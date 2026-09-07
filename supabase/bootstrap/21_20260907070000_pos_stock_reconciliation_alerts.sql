-- Phase 2: durable stock reconciliation and visible projection failures.

ALTER TABLE public.pos_marketplace_sync
  ADD COLUMN IF NOT EXISTS sync_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_error_at timestamptz,
  ADD COLUMN IF NOT EXISTS next_retry_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_pos_marketplace_sync_retry
  ON public.pos_marketplace_sync(tenant_id, sync_status, next_retry_at);

CREATE TABLE IF NOT EXISTS public.pos_stock_sync_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  sync_id uuid NOT NULL REFERENCES public.pos_marketplace_sync(id) ON DELETE CASCADE,
  alert_code text NOT NULL,
  severity text NOT NULL DEFAULT 'error' CHECK (severity IN ('warning', 'error')),
  message text NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  UNIQUE(sync_id, alert_code)
);

CREATE INDEX IF NOT EXISTS idx_pos_stock_sync_alerts_open
  ON public.pos_stock_sync_alerts(tenant_id, status, last_seen_at DESC);

ALTER TABLE public.pos_stock_sync_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "POS users view own stock sync alerts" ON public.pos_stock_sync_alerts;
CREATE POLICY "POS users view own stock sync alerts"
  ON public.pos_stock_sync_alerts
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.pos_tenants t
      WHERE t.id = tenant_id
        AND (t.user_id = auth.uid() OR public.is_admin())
    )
  );

CREATE OR REPLACE FUNCTION public.record_pos_stock_sync_failure(
  p_tenant_id uuid,
  p_pos_product_id uuid,
  p_message text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sync record;
  v_message text := left(COALESCE(NULLIF(trim(p_message), ''), 'Projection stok gagal'), 500);
  v_count integer := 0;
BEGIN
  FOR v_sync IN
    SELECT id, tenant_id
    FROM public.pos_marketplace_sync
    WHERE tenant_id = p_tenant_id
      AND (p_pos_product_id IS NULL OR pos_product_id = p_pos_product_id)
      AND sync_stock = true
  LOOP
    UPDATE public.pos_marketplace_sync
    SET sync_status = 'error',
        error_message = v_message,
        sync_attempts = COALESCE(sync_attempts, 0) + 1,
        last_error_at = now(),
        next_retry_at = now() + interval '5 minutes',
        updated_at = now()
    WHERE id = v_sync.id;

    INSERT INTO public.pos_stock_sync_alerts (
      tenant_id, sync_id, alert_code, severity, message, status,
      first_seen_at, last_seen_at, resolved_at
    )
    VALUES (
      v_sync.tenant_id, v_sync.id, 'STOCK_PROJECTION_FAILED', 'error', v_message,
      'open', now(), now(), NULL
    )
    ON CONFLICT (sync_id, alert_code) DO UPDATE
    SET severity = 'error',
        message = EXCLUDED.message,
        status = 'open',
        last_seen_at = now(),
        resolved_at = NULL;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_pos_stock_sync_alert(p_sync_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.pos_stock_sync_alerts
  SET status = 'resolved',
      resolved_at = now(),
      last_seen_at = now()
  WHERE sync_id = p_sync_id
    AND status = 'open';
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_safe(
  p_tenant_id uuid,
  p_pos_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  BEGIN
    v_result := public.sync_pos_stock_to_marketplace_internal(p_tenant_id, p_pos_product_id);
    RETURN v_result;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.record_pos_stock_sync_failure(p_tenant_id, p_pos_product_id, SQLERRM);
    RETURN jsonb_build_object(
      'tenant_id', p_tenant_id,
      'processed', 0,
      'updated', 0,
      'status', 'error',
      'error_message', SQLERRM
    );
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.pos_users u
      WHERE u.tenant_id = p_tenant_id
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'POS stock synchronization access denied' USING ERRCODE = '42501';
  END IF;

  RETURN public.sync_pos_stock_to_marketplace_safe(p_tenant_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_after_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;
  v_product_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.product_id ELSE NEW.product_id END;
BEGIN
  PERFORM public.sync_pos_stock_to_marketplace_safe(v_tenant_id, v_product_id);
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE OR REPLACE FUNCTION public.pos_stock_sync_alert_on_success()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.sync_status = 'synced' THEN
    PERFORM public.resolve_pos_stock_sync_alert(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pos_stock_sync_alert_on_success ON public.pos_marketplace_sync;
CREATE TRIGGER trg_pos_stock_sync_alert_on_success
AFTER UPDATE OF sync_status ON public.pos_marketplace_sync
FOR EACH ROW
WHEN (NEW.sync_status = 'synced')
EXECUTE FUNCTION public.pos_stock_sync_alert_on_success();

CREATE OR REPLACE FUNCTION public.get_pos_stock_reconciliation(p_tenant_id uuid)
RETURNS TABLE (
  pos_product_id uuid,
  product_name text,
  sku text,
  merchant_product_id uuid,
  outlet_total numeric,
  reserved numeric,
  pos_available numeric,
  marketplace_stock integer,
  delta numeric,
  status text,
  sync_status text,
  last_synced_at timestamptz,
  error_message text,
  last_error_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    pp.id,
    pp.name,
    pp.sku,
    pp.merchant_product_id,
    COALESCE(stock.outlet_total, 0),
    COALESCE(stock.reserved, 0),
    GREATEST(COALESCE(stock.outlet_total, 0) - COALESCE(stock.reserved, 0), 0),
    marketplace.stock,
    CASE
      WHEN pp.merchant_product_id IS NULL OR marketplace.id IS NULL THEN NULL
      ELSE GREATEST(COALESCE(stock.outlet_total, 0) - COALESCE(stock.reserved, 0), 0) - marketplace.stock
    END,
    CASE
      WHEN pp.merchant_product_id IS NULL THEN 'unlinked'
      WHEN marketplace.id IS NULL THEN 'missing'
      WHEN GREATEST(COALESCE(stock.outlet_total, 0) - COALESCE(stock.reserved, 0), 0) <> marketplace.stock THEN 'mismatch'
      ELSE 'ok'
    END,
    COALESCE(ms.sync_status, 'unlinked'),
    ms.last_synced_at,
    ms.error_message,
    ms.last_error_at
  FROM public.pos_products pp
  LEFT JOIN public.pos_marketplace_sync ms
    ON ms.tenant_id = pp.tenant_id
   AND ms.pos_product_id = pp.id
  LEFT JOIN public.products marketplace
    ON marketplace.id = COALESCE(ms.marketplace_product_id, pp.merchant_product_id)
  LEFT JOIN LATERAL (
    SELECT
      SUM(ps.quantity) AS outlet_total,
      SUM(COALESCE(ps.reserved_quantity, 0)) AS reserved
    FROM public.pos_stock ps
    WHERE ps.tenant_id = pp.tenant_id
      AND ps.product_id = pp.id
      AND ps.variant_id IS NULL
  ) stock ON true
  WHERE pp.tenant_id = p_tenant_id
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.pos_tenants t
        WHERE t.id = p_tenant_id
          AND t.user_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1
        FROM public.pos_users u
        WHERE u.tenant_id = p_tenant_id
          AND u.user_id = auth.uid()
          AND u.is_active = true
      )
    )
  ORDER BY pp.name;
$$;

REVOKE ALL ON FUNCTION public.record_pos_stock_sync_failure(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_pos_stock_sync_alert(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace_safe(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_pos_stock_reconciliation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_stock_reconciliation(uuid) TO authenticated;