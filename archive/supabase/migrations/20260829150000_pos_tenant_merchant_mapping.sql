-- Explicit POS tenant to merchant billing identity mapping.
-- Ambiguous existing users are intentionally left unmapped for manual resolution.
ALTER TABLE public.pos_tenants
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_pos_tenants_merchant_id ON public.pos_tenants(merchant_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_tenants_one_per_merchant
  ON public.pos_tenants(merchant_id) WHERE merchant_id IS NOT NULL;

DO $$
BEGIN
  UPDATE public.pos_tenants t
  SET merchant_id = m.id
  FROM public.merchants m
  WHERE t.merchant_id IS NULL
    AND m.user_id = t.user_id
    AND (SELECT count(*) FROM public.merchants m2 WHERE m2.user_id = t.user_id) = 1;
END $$;

CREATE OR REPLACE FUNCTION public.set_pos_tenant_merchant(
  p_tenant_id uuid,
  p_merchant_id uuid
)
RETURNS public.pos_tenants
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_tenant FROM public.pos_tenants WHERE id = p_tenant_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR v_tenant.user_id = auth.uid()) THEN
    RAISE EXCEPTION 'POS tenant mapping access denied' USING ERRCODE = '42501';
  END IF;
  IF p_merchant_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = p_merchant_id AND (public.is_admin() OR m.user_id = v_tenant.user_id)
  ) THEN
    RAISE EXCEPTION 'Merchant must belong to the POS tenant owner' USING ERRCODE = '42501';
  END IF;
  UPDATE public.pos_tenants
  SET merchant_id = p_merchant_id, updated_at = now()
  WHERE id = p_tenant_id
  RETURNING * INTO v_tenant;
  RETURN v_tenant;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Merchant is already mapped to another POS tenant' USING ERRCODE = '23505';
END; $$;
REVOKE ALL ON FUNCTION public.set_pos_tenant_merchant(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pos_tenant_merchant(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.consume_whatsapp_delivery_usage(p_job_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_job public.notification_delivery_jobs%ROWTYPE;
  v_merchant_id uuid;
  v_period_start timestamptz := date_trunc('month', now());
  v_period_end timestamptz := date_trunc('month', now()) + interval '1 month';
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'WhatsApp usage enforcement requires worker access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.channel <> 'whatsapp' THEN
    RAISE EXCEPTION 'WhatsApp delivery job not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT t.merchant_id INTO v_merchant_id
  FROM public.pos_tenants t
  WHERE t.id = v_job.tenant_id;
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'WhatsApp delivery tenant has no explicit merchant mapping' USING ERRCODE = '23503';
  END IF;
  RETURN public.consume_subscription_usage(
    v_merchant_id,
    'whatsapp_messages',
    1,
    'notification_delivery_job',
    v_period_start,
    v_period_end,
    'notification_delivery_job:' || p_job_id::text,
    'whatsapp_delivery',
    jsonb_build_object('job_id', p_job_id, 'tenant_id', v_job.tenant_id, 'merchant_id', v_merchant_id, 'recipient_id', v_job.recipient_id)
  );
END; $$;
REVOKE ALL ON FUNCTION public.consume_whatsapp_delivery_usage(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_whatsapp_delivery_usage(uuid) TO service_role;
