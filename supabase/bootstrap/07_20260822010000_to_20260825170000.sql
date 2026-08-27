-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260822010000_harden_pos_rls_tenant_outlet.sql .. 20260825170000_dispute_center_approval_workflow.sql


-- ===== BEGIN SOURCE: 20260822010000_harden_pos_rls_tenant_outlet.sql =====
-- P1 security hardening: enforce tenant/outlet consistency and respect
-- granular POS outlet assignments at the database boundary.

-- Prevent rows from one tenant from pointing at another tenant's outlet.
CREATE OR REPLACE FUNCTION public.validate_pos_outlet_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.pos_outlets o
    WHERE o.id = NEW.outlet_id
      AND o.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS outlet does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'pos_stock',
    'pos_stock_mutations',
    'pos_sales',
    'pos_held_bills',
    'pos_sale_returns'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS validate_%I_outlet_tenant ON public.%I', table_name, table_name);
      EXECUTE format(
        'CREATE TRIGGER validate_%I_outlet_tenant BEFORE INSERT OR UPDATE OF tenant_id, outlet_id ON public.%I FOR EACH ROW EXECUTE FUNCTION public.validate_pos_outlet_tenant()',
        table_name, table_name
      );
    END IF;
  END LOOP;
END;
$$;

-- Ensure outlet-access records cannot cross tenant boundaries.
CREATE OR REPLACE FUNCTION public.validate_pos_user_outlet_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_outlets o
    WHERE o.id = NEW.outlet_id AND o.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS outlet does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pos_users u
    WHERE u.id = NEW.pos_user_id AND u.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS user does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.pos_user_outlet_access') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS validate_pos_user_outlet_access_tenant
      ON public.pos_user_outlet_access;
    CREATE TRIGGER validate_pos_user_outlet_access_tenant
      BEFORE INSERT OR UPDATE OF tenant_id, pos_user_id, outlet_id
      ON public.pos_user_outlet_access
      FOR EACH ROW
      EXECUTE FUNCTION public.validate_pos_user_outlet_access();
  END IF;
END;
$$;

-- Replace the broad tenant-wide outlet read policy with owner-or-assigned
-- outlet access. Owners retain visibility over every outlet in their tenant.
DROP POLICY IF EXISTS "tenant_users_select_outlets" ON public.pos_outlets;
DROP POLICY IF EXISTS "POS users can view assigned outlets" ON public.pos_outlets;
CREATE POLICY "POS users can view assigned outlets" ON public.pos_outlets
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.pos_user_outlet_access a
      JOIN public.pos_users u ON u.id = a.pos_user_id
      WHERE a.outlet_id = pos_outlets.id
        AND a.tenant_id = pos_outlets.tenant_id
        AND a.is_active = true
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  );

-- Only owners may manage outlet assignments; users may inspect their own
-- active assignments. This avoids exposing all staff assignments to any
-- active user in the tenant.
DROP POLICY IF EXISTS "tenant_owner_manage_access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "tenant_users_read_access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "POS owners manage outlet access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "POS users read own outlet access" ON public.pos_user_outlet_access;

CREATE POLICY "POS owners manage outlet access" ON public.pos_user_outlet_access
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_user_outlet_access.tenant_id AND t.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_user_outlet_access.tenant_id AND t.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "POS users read own outlet access" ON public.pos_user_outlet_access;
CREATE POLICY "POS users read own outlet access" ON public.pos_user_outlet_access
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_users u
      WHERE u.id = pos_user_outlet_access.pos_user_id
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  );

-- Explicit WITH CHECK clauses make the intended mutation boundary clear for
-- the core POS tables. Existing tenant-user SELECT policies remain read-only.
DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'pos_products', 'pos_stock', 'pos_stock_mutations', 'pos_sales',
    'pos_held_bills', 'pos_customers', 'pos_suppliers', 'pos_users'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    END IF;
  END LOOP;
END;
$$;

-- Reusable access predicate for outlet-scoped POS data.
CREATE OR REPLACE FUNCTION public.pos_user_can_access_outlet(
  p_tenant_id uuid,
  p_outlet_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pos_tenants t
    WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.pos_user_outlet_access a
    JOIN public.pos_users u ON u.id = a.pos_user_id
    WHERE a.tenant_id = p_tenant_id
      AND a.outlet_id = p_outlet_id
      AND a.is_active = true
      AND u.user_id = auth.uid()
      AND u.is_active = true
  );
$$;

-- Remove broad tenant-wide read policies for outlet-scoped data.
DROP POLICY IF EXISTS "tenant_users_select_stock" ON public.pos_stock;
DROP POLICY IF EXISTS "tenant_users_select_mutations" ON public.pos_stock_mutations;
DROP POLICY IF EXISTS "tenant_users_select_sales" ON public.pos_sales;
DROP POLICY IF EXISTS "tenant_users_select_held_bills" ON public.pos_held_bills;
DROP POLICY IF EXISTS "tenant_users_select_returns" ON public.pos_sale_returns;
DROP POLICY IF EXISTS "tenant_users_select_pos_users" ON public.pos_users;

DROP POLICY IF EXISTS "POS users can view assigned stock" ON public.pos_stock;
CREATE POLICY "POS users can view assigned stock" ON public.pos_stock
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

DROP POLICY IF EXISTS "POS users can view assigned stock mutations" ON public.pos_stock_mutations;
CREATE POLICY "POS users can view assigned stock mutations" ON public.pos_stock_mutations
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

DROP POLICY IF EXISTS "POS users can view assigned sales" ON public.pos_sales;
CREATE POLICY "POS users can view assigned sales" ON public.pos_sales
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

DROP POLICY IF EXISTS "POS users can view assigned held bills" ON public.pos_held_bills;
CREATE POLICY "POS users can view assigned held bills" ON public.pos_held_bills
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

DROP POLICY IF EXISTS "POS users can view assigned returns" ON public.pos_sale_returns;
CREATE POLICY "POS users can view assigned returns" ON public.pos_sale_returns
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

-- Staff can see their own POS identity; only tenant owners can see the full
-- tenant user directory.
DROP POLICY IF EXISTS "POS users can view own POS identity" ON public.pos_users;
CREATE POLICY "POS users can view own POS identity" ON public.pos_users
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Explicitly grant the helper only to API roles; the function itself does not
-- expose any data and is used solely inside RLS predicates.
REVOKE ALL ON FUNCTION public.pos_user_can_access_outlet(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pos_user_can_access_outlet(uuid, uuid) TO authenticated;

-- ===== END SOURCE: 20260822010000_harden_pos_rls_tenant_outlet.sql =====

-- ===== BEGIN SOURCE: 20260822020000_add_payment_webhook_idempotency.sql =====
-- Idempotency ledger for payment provider callbacks.
CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  event_key text NOT NULL,
  invoice_id text NOT NULL,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  status text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, event_key)
);

CREATE INDEX IF NOT EXISTS idx_payment_webhook_events_order
  ON public.payment_webhook_events(order_id, received_at DESC);

REVOKE ALL ON public.payment_webhook_events FROM anon, authenticated;
GRANT ALL ON public.payment_webhook_events TO service_role;
ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages payment webhook events"
  ON public.payment_webhook_events;
CREATE POLICY "Service role manages payment webhook events"
  ON public.payment_webhook_events FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ===== END SOURCE: 20260822020000_add_payment_webhook_idempotency.sql =====

-- ===== BEGIN SOURCE: 20260822030000_harden_storage_ownership.sql =====
-- Storage hardening for sensitive documents and merchant gallery.

-- The legacy merchants bucket contains KTP/certificate paths and must not be
-- publicly readable. Public storefront images use dedicated public buckets.
UPDATE storage.buckets
SET public = false
WHERE id = 'merchants';

DROP POLICY IF EXISTS "Public view merchants bucket" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to upload certificates" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to upload ktp" ON storage.objects;

DROP POLICY IF EXISTS "Owners and reviewers can read merchant documents" ON storage.objects;
CREATE POLICY "Owners and reviewers can read merchant documents"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'merchants'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR public.is_verifikator()
    OR (
      (storage.foldername(name))[1] IN ('ktp', 'certificate')
      AND (storage.foldername(name))[2] = auth.uid()::text
    )
  )
);

DROP POLICY IF EXISTS "Owners can upload merchant documents" ON storage.objects;
CREATE POLICY "Owners can upload merchant documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'merchants'
  AND (
    (
      (storage.foldername(name))[1] IN ('ktp', 'certificate')
      AND (storage.foldername(name))[2] = auth.uid()::text
    )
    OR public.is_admin()
    OR public.is_verifikator()
  )
  AND COALESCE(metadata->>'mimetype', '') IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')
);

DROP POLICY IF EXISTS "Owners can update merchant documents" ON storage.objects;
CREATE POLICY "Owners can update merchant documents"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
)
WITH CHECK (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
);

DROP POLICY IF EXISTS "Owners can delete merchant documents" ON storage.objects;
CREATE POLICY "Owners can delete merchant documents"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
);

-- Merchant gallery remains publicly readable, but writes are restricted to the
-- merchant owner, the related village administrator, or platform admin.
DROP POLICY IF EXISTS "Authenticated users can upload merchant gallery images" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own merchant gallery images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own merchant gallery images" ON storage.objects;

DROP POLICY IF EXISTS "Merchant owners can upload gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can upload gallery images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'merchant-gallery'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
  AND COALESCE(metadata->>'mimetype', '') IN ('image/jpeg', 'image/png', 'image/webp')
);

DROP POLICY IF EXISTS "Merchant owners can update gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can update gallery images"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchant-gallery'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
)
WITH CHECK (
  bucket_id = 'merchant-gallery'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
);

DROP POLICY IF EXISTS "Merchant owners can delete gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can delete gallery images"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchant-gallery'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
);

-- ===== END SOURCE: 20260822030000_harden_storage_ownership.sql =====

-- ===== BEGIN SOURCE: 20260822040000_harden_stock_decrement.sql =====
-- Prevent overselling: update only when enough stock exists and fail atomically.
CREATE OR REPLACE FUNCTION public.decrement_stock(p_product_id uuid, p_quantity integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_product_id IS NULL OR p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Invalid stock decrement request';
  END IF;

  UPDATE public.products
  SET stock = stock - p_quantity,
      updated_at = now()
  WHERE id = p_product_id
    AND stock >= p_quantity;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insufficient stock or product not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.decrement_stock(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decrement_stock(uuid, integer) TO authenticated;

-- ===== END SOURCE: 20260822040000_harden_stock_decrement.sql =====

-- ===== BEGIN SOURCE: 20260823050000_harden_payment_proof_insert.sql =====
-- Restrict payment-proof uploads to principals who own or fulfill the order.
-- Expected object path: orders/{order_id}/{filename}
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;

DROP POLICY IF EXISTS "Buyer merchant admin can upload payment proofs" ON storage.objects;
CREATE POLICY "Buyer merchant admin can upload payment proofs"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      LEFT JOIN public.merchants m ON m.id = o.merchant_id
      WHERE o.id::text = (storage.foldername(name))[2]
        AND (o.buyer_id = auth.uid() OR m.user_id = auth.uid())
    )
  )
  AND COALESCE(metadata->>'mimetype', '') IN (
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf'
  )
);

-- ===== END SOURCE: 20260823050000_harden_payment_proof_insert.sql =====

-- ===== BEGIN SOURCE: 20260823070000_atomic_pos_checkout.sql =====
-- Atomic POS checkout with request idempotency.
-- All core sale writes and stock mutations execute in one database transaction.

CREATE TABLE IF NOT EXISTS public.pos_sale_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  cashier_id uuid NOT NULL REFERENCES auth.users(id),
  request_key text NOT NULL,
  sale_id uuid REFERENCES public.pos_sales(id) ON DELETE SET NULL,
  response jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, outlet_id, request_key)
);

CREATE INDEX IF NOT EXISTS idx_pos_sale_requests_created_at
  ON public.pos_sale_requests(created_at DESC);

ALTER TABLE public.pos_sale_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pos_sale_requests FROM anon, authenticated;
GRANT ALL ON public.pos_sale_requests TO service_role;

CREATE OR REPLACE FUNCTION public.process_pos_sale(
  p_request_key text,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_cashier_id uuid,
  p_sale jsonb,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.pos_sale_requests%ROWTYPE;
  v_request_id uuid;
  v_sale_id uuid;
  v_item jsonb;
  v_stock public.pos_stock%ROWTYPE;
  v_qty numeric;
  v_before numeric;
  v_after numeric;
  v_sale_number text;
  v_payment_method text;
  v_total numeric;
  v_response jsonb;
  v_recipe record;
  v_raw public.pos_raw_materials%ROWTYPE;
  v_usage numeric;
  v_customer_segment text;
  v_input_price numeric;
  v_effective_price numeric;
  v_computed_subtotal numeric := 0;
  v_price_override_count integer := 0;
  v_sale_earned integer := 0;
  v_sale_redeemed integer := 0;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
    RAISE EXCEPTION 'Cashier identity mismatch' USING ERRCODE = '42501';
  END IF;

  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  IF p_request_key IS NULL OR length(trim(p_request_key)) < 16 OR length(p_request_key) > 128 THEN
    RAISE EXCEPTION 'Invalid POS request key' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'POS sale requires at least one item' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.pos_sale_requests(tenant_id, outlet_id, cashier_id, request_key)
  VALUES (p_tenant_id, p_outlet_id, p_cashier_id, trim(p_request_key))
  ON CONFLICT (tenant_id, outlet_id, request_key) DO NOTHING
  RETURNING id INTO v_request_id;

  IF v_request_id IS NULL THEN
    SELECT * INTO v_existing
    FROM public.pos_sale_requests
    WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id AND request_key = trim(p_request_key);
    IF v_existing.response IS NULL THEN
      RAISE EXCEPTION 'POS request is already being processed' USING ERRCODE = '55P03';
    END IF;
    RETURN v_existing.response || jsonb_build_object('duplicate', true);
  END IF;

  v_sale_number := NULLIF(trim(p_sale->>'sale_number'), '');
  IF v_sale_number IS NULL THEN
    RAISE EXCEPTION 'Sale number is required' USING ERRCODE = '22023';
  END IF;

  v_payment_method := lower(COALESCE(p_sale->>'payment_method', 'cash'));
  -- The UI historically uses qr_pay; persist it as the schema-supported qris value.
  IF v_payment_method = 'qr_pay' THEN v_payment_method := 'qris'; END IF;
  IF v_payment_method NOT IN ('cash', 'qris', 'transfer', 'debit', 'credit', 'split') THEN
    RAISE EXCEPTION 'Unsupported payment method' USING ERRCODE = '22023';
  END IF;

  v_total := COALESCE((p_sale->>'total')::numeric, 0);
  v_customer_segment := lower(COALESCE(NULLIF(p_sale->>'customer_segment', ''), 'retail'));
  IF v_customer_segment NOT IN ('retail', 'wholesale', 'reseller', 'member', 'outlet') THEN
    RAISE EXCEPTION 'Unsupported customer segment' USING ERRCODE = '22023';
  END IF;
  IF v_total < 0 THEN
    RAISE EXCEPTION 'Invalid sale total' USING ERRCODE = '22023';
  END IF;

  -- Resolve price-book prices before inserting the sale. This makes the
  -- server authoritative for both line prices and the final total.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := COALESCE((v_item->>'qty')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid item quantity' USING ERRCODE = '22023'; END IF;
    v_input_price := COALESCE((v_item->>'price')::numeric, 0);
    v_effective_price := COALESCE(public.get_effective_pos_price(
      p_tenant_id, p_outlet_id, (v_item->>'product_id')::uuid,
      NULLIF(v_item->>'variant_id', '')::uuid, v_customer_segment
    ), v_input_price);
    IF v_effective_price <> v_input_price THEN
      IF COALESCE((p_sale->>'offline_sync')::boolean, false) THEN
        RAISE EXCEPTION 'Price conflict for product %: server price is %, queued price is %', v_item->>'product_id', v_effective_price, v_input_price USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('conflict_type', 'PRICE_CHANGED', 'product_id', v_item->>'product_id', 'queued_price', v_input_price, 'server_price', v_effective_price)::text;
      END IF;
      v_price_override_count := v_price_override_count + 1;
    END IF;
    v_computed_subtotal := v_computed_subtotal + GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0));
  END LOOP;
  v_total := GREATEST(0, v_computed_subtotal - COALESCE((p_sale->>'discount_amount')::numeric, 0) + COALESCE((p_sale->>'tax_amount')::numeric, 0));

  INSERT INTO public.pos_sales(
    tenant_id, outlet_id, sale_number, cashier_id, cashier_name,
    customer_id, customer_name, subtotal, discount_amount, tax_amount, total,
    payment_method, payment_amount, change_amount, status, notes,
    promotion_id, voucher_id, voucher_code, promotion_discount, voucher_discount,
    loyalty_points_earned, loyalty_points_redeemed, loyalty_discount
  ) VALUES (
    p_tenant_id, p_outlet_id, v_sale_number, p_cashier_id,
    NULLIF(p_sale->>'cashier_name', ''), NULLIF(p_sale->>'customer_id', '')::uuid,
    NULLIF(p_sale->>'customer_name', ''), v_computed_subtotal,
    COALESCE((p_sale->>'discount_amount')::numeric, 0), COALESCE((p_sale->>'tax_amount')::numeric, 0), v_total,
    v_payment_method, COALESCE((p_sale->>'payment_amount')::numeric, v_total),
    COALESCE((p_sale->>'change_amount')::numeric, 0), 'completed', NULLIF(p_sale->>'notes', ''),
    NULLIF(p_sale->>'promotion_id', '')::uuid, NULLIF(p_sale->>'voucher_id', '')::uuid,
    NULLIF(p_sale->>'voucher_code', ''), COALESCE((p_sale->>'promotion_discount')::numeric, 0),
    COALESCE((p_sale->>'voucher_discount')::numeric, 0), COALESCE((p_sale->>'loyalty_points_earned')::integer, 0),
    COALESCE((p_sale->>'loyalty_points_redeemed')::integer, 0), COALESCE((p_sale->>'loyalty_discount')::numeric, 0)
  ) RETURNING id INTO v_sale_id;
  SELECT loyalty_points_earned, loyalty_points_redeemed INTO v_sale_earned, v_sale_redeemed
  FROM public.pos_sales WHERE id = v_sale_id;

  v_computed_subtotal := 0;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := COALESCE((v_item->>'qty')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid item quantity' USING ERRCODE = '22023'; END IF;

    v_input_price := COALESCE((v_item->>'price')::numeric, 0);
    v_effective_price := COALESCE(public.get_effective_pos_price(
      p_tenant_id, p_outlet_id, (v_item->>'product_id')::uuid,
      NULLIF(v_item->>'variant_id', '')::uuid, v_customer_segment
    ), v_input_price);
    IF v_effective_price <> v_input_price THEN
      v_price_override_count := v_price_override_count + 1;
    END IF;
    v_computed_subtotal := v_computed_subtotal + GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0));

    INSERT INTO public.pos_sale_items(
      sale_id, product_id, variant_id, product_name, variant_name, sku,
      qty, price, cost_price, discount, tax_amount, subtotal, notes
    ) VALUES (
      v_sale_id, (v_item->>'product_id')::uuid, NULLIF(v_item->>'variant_id', '')::uuid,
      COALESCE(v_item->>'name', 'Produk'), NULLIF(v_item->>'variant_name', ''), NULLIF(v_item->>'sku', ''),
      v_qty, v_effective_price, COALESCE((v_item->>'cost_price')::numeric, 0),
      COALESCE((v_item->>'discount')::numeric, 0), COALESCE((v_item->>'tax_amount')::numeric, 0),
      GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0) + COALESCE((v_item->>'tax_amount')::numeric, 0)), NULLIF(v_item->>'notes', '')
    );

    SELECT * INTO v_stock
    FROM public.pos_stock
    WHERE tenant_id = p_tenant_id
      AND outlet_id = p_outlet_id
      AND product_id = (v_item->>'product_id')::uuid
      AND variant_id IS NOT DISTINCT FROM NULLIF(v_item->>'variant_id', '')::uuid
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stock row not found for product %', v_item->>'product_id' USING ERRCODE = 'P0002';
    END IF;
    v_before := v_stock.quantity;
    v_after := v_before - v_qty;
    IF v_after < 0 THEN
      RAISE EXCEPTION 'Insufficient stock for product %', v_item->>'product_id' USING ERRCODE = '23514';
    END IF;

    UPDATE public.pos_stock
    SET quantity = v_after, updated_at = now()
    WHERE id = v_stock.id;

    INSERT INTO public.pos_stock_mutations(
      tenant_id, product_id, variant_id, outlet_id, type, quantity,
      quantity_before, quantity_after, reference_id, reference_type, notes, created_by
    ) VALUES (
      p_tenant_id, (v_item->>'product_id')::uuid, NULLIF(v_item->>'variant_id', '')::uuid,
      p_outlet_id, 'sale', -v_qty, v_before, v_after, v_sale_id, 'pos_sale',
      'Atomic POS sale', p_cashier_id
    );
  END LOOP;

  IF v_price_override_count > 0 THEN
    UPDATE public.pos_sales
    SET subtotal = v_computed_subtotal,
        total = GREATEST(0, v_computed_subtotal - COALESCE(discount_amount, 0) + COALESCE(tax_amount, 0)),
        notes = concat_ws(' | ', NULLIF(notes, ''), 'Price book: ' || v_customer_segment)
    WHERE id = v_sale_id;
    SELECT total INTO v_total FROM public.pos_sales WHERE id = v_sale_id;
  END IF;

  -- Consume recipe ingredients under row locks in the same transaction.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    FOR v_recipe IN
      SELECT r.raw_material_id, r.qty_needed
      FROM public.pos_recipes r
      WHERE r.tenant_id = p_tenant_id
        AND r.product_id = (v_item->>'product_id')::uuid
    LOOP
      SELECT * INTO v_raw
      FROM public.pos_raw_materials
      WHERE id = v_recipe.raw_material_id
        AND tenant_id = p_tenant_id
        AND (outlet_id = p_outlet_id OR outlet_id IS NULL)
      ORDER BY (outlet_id IS NULL)
      LIMIT 1
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Raw material is unavailable for product %', v_item->>'product_id' USING ERRCODE = 'P0002';
      END IF;
      v_usage := v_recipe.qty_needed * COALESCE((v_item->>'qty')::numeric, 0);
      IF v_raw.current_stock - v_usage < 0 THEN
        RAISE EXCEPTION 'Insufficient raw material stock for product %', v_item->>'product_id' USING ERRCODE = '23514';
      END IF;

      UPDATE public.pos_raw_materials
      SET current_stock = current_stock - v_usage, updated_at = now()
      WHERE id = v_raw.id;
      INSERT INTO public.pos_raw_material_mutations(
        tenant_id, outlet_id, raw_material_id, type, qty,
        qty_before, qty_after, reference_id, reference_type, notes, created_by
      ) VALUES (
        p_tenant_id, p_outlet_id, v_raw.id, 'usage', -v_usage,
        v_raw.current_stock, v_raw.current_stock - v_usage, v_sale_id, 'pos_sale',
        'Atomic POS sale recipe usage', p_cashier_id
      );
    END LOOP;
  END LOOP;

  -- Keep the customer aggregate in the same transaction when a customer is selected.
  IF NULLIF(p_sale->>'customer_id', '') IS NOT NULL THEN
    UPDATE public.pos_customers
    SET total_purchase = COALESCE(total_purchase, 0) + v_total,
        transaction_count = COALESCE(transaction_count, 0) + 1,
        last_purchase_at = now(),
        loyalty_points = GREATEST(0, COALESCE(loyalty_points, 0)
          - v_sale_redeemed + v_sale_earned),
        updated_at = now()
    WHERE id = (p_sale->>'customer_id')::uuid AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Customer does not belong to tenant' USING ERRCODE = '42501'; END IF;
  END IF;

  IF NULLIF(p_sale->>'voucher_id', '') IS NOT NULL THEN
    UPDATE public.pos_vouchers
    SET used_count = used_count + 1, updated_at = now()
    WHERE id = (p_sale->>'voucher_id')::uuid AND tenant_id = p_tenant_id
      AND is_active = true AND (usage_limit IS NULL OR used_count < usage_limit);
    IF NOT FOUND THEN RAISE EXCEPTION 'Voucher is no longer available' USING ERRCODE = '23514'; END IF;
    INSERT INTO public.pos_voucher_usages(voucher_id, sale_id, customer_id, customer_name, discount_given)
    VALUES ((p_sale->>'voucher_id')::uuid, v_sale_id, NULLIF(p_sale->>'customer_id', '')::uuid,
      NULLIF(p_sale->>'customer_name', ''), COALESCE((p_sale->>'voucher_discount')::numeric, 0));
  END IF;

  v_response := jsonb_build_object(
    'sale_id', v_sale_id, 'sale_number', v_sale_number, 'total', v_total,
    'payment_method', v_payment_method, 'duplicate', false
  );
  UPDATE public.pos_sale_requests SET sale_id = v_sale_id, response = v_response WHERE id = v_request_id;
  RETURN v_response;
EXCEPTION WHEN OTHERS THEN
  -- The surrounding transaction rolls back sale, items, stock, and request row together.
  RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) TO authenticated;

-- ===== END SOURCE: 20260823070000_atomic_pos_checkout.sql =====

-- ===== BEGIN SOURCE: 20260823071000_payment_invoice_idempotency.sql =====
-- Reserve one invoice creation attempt per order/provider before calling the
-- external payment provider. This closes the concurrent-create race that a
-- read-before-insert check cannot prevent.
CREATE TABLE IF NOT EXISTS public.payment_invoice_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  request_key text NOT NULL,
  status text NOT NULL DEFAULT 'processing'
    CHECK (status IN ('processing', 'completed', 'failed')),
  invoice_id text,
  invoice_url text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, order_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_invoice_requests_key
  ON public.payment_invoice_requests(provider, request_key);

ALTER TABLE public.payment_invoice_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_invoice_requests FROM anon, authenticated;
GRANT ALL ON public.payment_invoice_requests TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_payment_invoice_request(
  p_provider text,
  p_order_id uuid,
  p_request_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payment_invoice_requests%ROWTYPE;
  v_inserted boolean := false;
BEGIN
  IF p_provider IS NULL OR p_provider = '' OR p_order_id IS NULL
     OR p_request_key IS NULL OR length(trim(p_request_key)) < 16
     OR length(p_request_key) > 128 THEN
    RAISE EXCEPTION 'Invalid payment invoice request' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.payment_invoice_requests(provider, order_id, request_key)
  VALUES (lower(trim(p_provider)), p_order_id, trim(p_request_key))
  ON CONFLICT (provider, order_id) DO NOTHING
  RETURNING true INTO v_inserted;

  SELECT * INTO v_row
  FROM public.payment_invoice_requests
  WHERE provider = lower(trim(p_provider)) AND order_id = p_order_id;

  -- A failed attempt can be retried with the same logical request key. An
  -- in-progress or completed attempt remains exclusively owned by its first
  -- caller to prevent concurrent provider calls.
  IF NOT COALESCE(v_inserted, false) AND v_row.status = 'failed' THEN
    UPDATE public.payment_invoice_requests
    SET status = 'processing', request_key = trim(p_request_key), last_error = NULL, updated_at = now()
    WHERE id = v_row.id AND status = 'failed';
    v_inserted := true;
    SELECT * INTO v_row FROM public.payment_invoice_requests WHERE id = v_row.id;
  END IF;

  RETURN jsonb_build_object(
    'can_process', COALESCE(v_inserted, false),
    'status', v_row.status,
    'request_key', v_row.request_key,
    'invoice_id', v_row.invoice_id,
    'invoice_url', v_row.invoice_url,
    'last_error', v_row.last_error,
    'created_at', v_row.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_payment_invoice_request(text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_payment_invoice_request(text, uuid, text) TO service_role;

-- ===== END SOURCE: 20260823071000_payment_invoice_idempotency.sql =====

-- ===== BEGIN SOURCE: 20260823080000_p1_inventory_shift_atomic.sql =====
-- P1 inventory ledger and cashier-session hardening.

ALTER TABLE public.pos_sales
  ADD COLUMN IF NOT EXISTS cash_session_id uuid REFERENCES public.pos_cash_sessions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_pos_sales_cash_session
  ON public.pos_sales(cash_session_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_cash_session_per_cashier_outlet
  ON public.pos_cash_sessions(tenant_id, outlet_id, cashier_id)
  WHERE status = 'open' AND cashier_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.assign_pos_sale_cash_session()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.cash_session_id IS NULL THEN
    SELECT id INTO NEW.cash_session_id
    FROM public.pos_cash_sessions
    WHERE tenant_id = NEW.tenant_id
      AND outlet_id = NEW.outlet_id
      AND cashier_id = NEW.cashier_id
      AND status = 'open'
    ORDER BY opened_at DESC
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_pos_sale_cash_session ON public.pos_sales;
CREATE TRIGGER assign_pos_sale_cash_session
  BEFORE INSERT ON public.pos_sales
  FOR EACH ROW EXECUTE FUNCTION public.assign_pos_sale_cash_session();

CREATE OR REPLACE FUNCTION public.open_cash_session(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_cashier_id uuid,
  p_cashier_name text,
  p_opening_balance numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_session public.pos_cash_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
    RAISE EXCEPTION 'Cashier identity mismatch' USING ERRCODE = '42501';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;
  IF p_opening_balance IS NULL OR p_opening_balance < 0 THEN
    RAISE EXCEPTION 'Invalid opening balance' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.pos_cash_sessions(
    tenant_id, outlet_id, cashier_id, cashier_name, session_number,
    status, opening_balance, cash_sales_total, non_cash_sales_total,
    cash_in_total, cash_out_total, notes_open
  ) VALUES (
    p_tenant_id, p_outlet_id, p_cashier_id, COALESCE(NULLIF(trim(p_cashier_name), ''), 'Kasir'),
    'KAS-' || to_char(now(), 'YYMMDD-HH24MISS') || '-' || substr(p_cashier_id::text, 1, 6),
    'open', p_opening_balance, 0, 0, 0, 0, NULLIF(trim(p_notes), '')
  ) RETURNING * INTO v_session;

  RETURN jsonb_build_object('session_id', v_session.id, 'session_number', v_session.session_number, 'status', v_session.status);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Cashier already has an open session for this outlet' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.record_cash_mutation(
  p_session_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_category text,
  p_amount numeric,
  p_description text,
  p_reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.pos_cash_sessions%ROWTYPE;
  v_mutation_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_amount IS NULL OR p_amount <= 0
     OR p_type NOT IN ('in', 'out') OR NULLIF(trim(p_description), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid cash mutation' USING ERRCODE = '22023';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session FROM public.pos_cash_sessions
  WHERE id = p_session_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Cash session is not open' USING ERRCODE = '55000';
  END IF;
  IF v_session.cashier_id <> auth.uid() AND NOT EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Cash session access denied' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.pos_cash_mutations(
    tenant_id, outlet_id, cash_session_id, type, category, amount, description, reference, created_by
  ) VALUES (
    p_tenant_id, p_outlet_id, p_session_id, p_type, COALESCE(NULLIF(trim(p_category), ''), 'other'),
    p_amount, trim(p_description), NULLIF(trim(p_reference), ''), auth.uid()
  ) RETURNING id INTO v_mutation_id;

  IF p_type = 'in' THEN
    UPDATE public.pos_cash_sessions SET cash_in_total = COALESCE(cash_in_total, 0) + p_amount WHERE id = p_session_id;
  ELSE
    UPDATE public.pos_cash_sessions SET cash_out_total = COALESCE(cash_out_total, 0) + p_amount WHERE id = p_session_id;
  END IF;
  RETURN jsonb_build_object('mutation_id', v_mutation_id, 'session_id', p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.close_cash_session(
  p_session_id uuid,
  p_closing_balance numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.pos_cash_sessions%ROWTYPE;
  v_cash_sales numeric := 0;
  v_non_cash_sales numeric := 0;
  v_cash_in numeric := 0;
  v_cash_out numeric := 0;
  v_expected numeric;
  v_difference numeric;
BEGIN
  IF auth.uid() IS NULL OR p_closing_balance IS NULL OR p_closing_balance < 0 THEN
    RAISE EXCEPTION 'Invalid closing balance' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_session FROM public.pos_cash_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Cash session is not open' USING ERRCODE = '55000';
  END IF;
  IF v_session.cashier_id <> auth.uid() AND NOT EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = v_session.tenant_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Cash session access denied' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(CASE WHEN payment_method = 'cash' THEN total ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN payment_method <> 'cash' THEN total ELSE 0 END), 0)
  INTO v_cash_sales, v_non_cash_sales
  FROM public.pos_sales
  WHERE cash_session_id = p_session_id AND status = 'completed';

  SELECT COALESCE(SUM(CASE WHEN type = 'in' THEN amount ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN type = 'out' THEN amount ELSE 0 END), 0)
  INTO v_cash_in, v_cash_out
  FROM public.pos_cash_mutations
  WHERE cash_session_id = p_session_id;

  v_expected := v_session.opening_balance + v_cash_sales + v_cash_in - v_cash_out;
  v_difference := p_closing_balance - v_expected;

  UPDATE public.pos_cash_sessions
  SET status = 'closed', closing_balance = p_closing_balance, expected_balance = v_expected,
      difference = v_difference, cash_sales_total = v_cash_sales,
      non_cash_sales_total = v_non_cash_sales, cash_in_total = v_cash_in,
      cash_out_total = v_cash_out, notes_close = NULLIF(trim(p_notes), ''), closed_at = now()
  WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'session_id', p_session_id, 'expected_balance', v_expected,
    'closing_balance', p_closing_balance, 'difference', v_difference,
    'cash_sales_total', v_cash_sales, 'non_cash_sales_total', v_non_cash_sales,
    'cash_in_total', v_cash_in, 'cash_out_total', v_cash_out
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_pos_stock(
  p_stock_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_quantity numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock public.pos_stock%ROWTYPE;
  v_after numeric;
  v_delta numeric;
BEGIN
  IF p_quantity IS NULL OR p_quantity < 0 OR p_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') THEN
    RAISE EXCEPTION 'Invalid stock adjustment' USING ERRCODE = '22023';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_stock FROM public.pos_stock
  WHERE id = p_stock_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;

  v_after := CASE WHEN p_type = 'adjustment' THEN p_quantity ELSE
    CASE WHEN p_type IN ('purchase','return_sale','transfer_in','initial')
      THEN v_stock.quantity + p_quantity ELSE v_stock.quantity - p_quantity END END;
  IF v_after < 0 THEN RAISE EXCEPTION 'Insufficient stock' USING ERRCODE = '23514'; END IF;
  v_delta := v_after - v_stock.quantity;

  UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
  INSERT INTO public.pos_stock_mutations(
    tenant_id, product_id, variant_id, outlet_id, type, quantity,
    quantity_before, quantity_after, notes, created_by
  ) VALUES (
    p_tenant_id, v_stock.product_id, v_stock.variant_id, p_outlet_id, p_type,
    v_delta, v_stock.quantity, v_after, NULLIF(trim(p_notes), ''), auth.uid()
  );
  RETURN jsonb_build_object('stock_id', v_stock.id, 'quantity_before', v_stock.quantity, 'quantity_after', v_after, 'delta', v_delta);
END;
$$;

REVOKE ALL ON FUNCTION public.open_cash_session(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_cash_mutation(uuid, uuid, uuid, text, text, numeric, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.close_cash_session(uuid, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.adjust_pos_stock(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_cash_session(uuid, uuid, uuid, text, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_cash_mutation(uuid, uuid, uuid, text, text, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_cash_session(uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_pos_stock(uuid, uuid, uuid, text, numeric, text) TO authenticated;

-- ===== END SOURCE: 20260823080000_p1_inventory_shift_atomic.sql =====

-- ===== BEGIN SOURCE: 20260823090000_harden_payment_settings_access.sql =====
-- Payment security hardening:
-- do not expose provider credentials through the generic app_settings read path.

DROP POLICY IF EXISTS "Anyone can view settings" ON public.app_settings;

DROP POLICY IF EXISTS "Public can view non-sensitive settings" ON public.app_settings;
CREATE POLICY "Public can view non-sensitive settings"
  ON public.app_settings
  FOR SELECT
  USING (
    key !~* '(secret|token|credential|api[_-]?key|private|password)'
    AND key NOT IN (
      'payment_xendit',
      'payment_midtrans',
      'whatsapp_settings',
      'push_notification_settings'
    )
  );

CREATE OR REPLACE FUNCTION public.is_payment_provider_enabled(p_provider text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE lower(trim(p_provider))
    WHEN 'xendit' THEN COALESCE((
      SELECT (value->>'enabled')::boolean
      FROM public.app_settings
      WHERE key = 'payment_xendit'
    ), false)
    WHEN 'midtrans' THEN COALESCE((
      SELECT (value->>'enabled')::boolean
      FROM public.app_settings
      WHERE key = 'payment_midtrans'
    ), false)
    ELSE false
  END;
$$;

REVOKE ALL ON FUNCTION public.is_payment_provider_enabled(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_payment_provider_enabled(text) TO anon, authenticated;

-- ===== END SOURCE: 20260823090000_harden_payment_settings_access.sql =====

-- ===== BEGIN SOURCE: 20260823091000_harden_pos_sale_amounts.sql =====
-- Server-side price and line arithmetic guard for all POS sale writes.
-- The checkout RPC remains the atomic boundary; this trigger protects direct
-- inserts and prevents a compromised client from inflating line prices.

CREATE OR REPLACE FUNCTION public.validate_pos_sale_item_amounts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale record;
  v_product_price numeric;
  v_variant_price numeric;
BEGIN
  SELECT tenant_id, outlet_id
  INTO v_sale
  FROM public.pos_sales
  WHERE id = NEW.sale_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale does not exist' USING ERRCODE = '23503';
  END IF;

  IF NEW.qty <= 0 OR NEW.price < 0 OR NEW.discount < 0 OR NEW.tax_amount < 0 THEN
    RAISE EXCEPTION 'Invalid POS sale item amount' USING ERRCODE = '22023';
  END IF;

  IF NEW.discount > NEW.price * NEW.qty THEN
    RAISE EXCEPTION 'Line discount exceeds line amount' USING ERRCODE = '22023';
  END IF;

  IF abs(NEW.subtotal - (NEW.price * NEW.qty - NEW.discount)) > 0.01 THEN
    RAISE EXCEPTION 'Line subtotal mismatch' USING ERRCODE = '22023';
  END IF;

  SELECT price
  INTO v_variant_price
  FROM public.pos_product_variants
  WHERE id = NEW.variant_id
    AND product_id = NEW.product_id
    AND tenant_id = v_sale.tenant_id
    AND is_active = true;

  IF NEW.variant_id IS NOT NULL AND NOT FOUND THEN
    RAISE EXCEPTION 'Product variant does not belong to tenant or product' USING ERRCODE = '42501';
  END IF;

  SELECT price
  INTO v_product_price
  FROM public.pos_products
  WHERE id = NEW.product_id
    AND tenant_id = v_sale.tenant_id
    AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product does not belong to tenant or is inactive' USING ERRCODE = '42501';
  END IF;

  IF NEW.price > COALESCE(v_variant_price, v_product_price) THEN
    RAISE EXCEPTION 'Sale price exceeds catalog price' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_pos_sale_item_amounts ON public.pos_sale_items;
CREATE TRIGGER validate_pos_sale_item_amounts
BEFORE INSERT OR UPDATE ON public.pos_sale_items
FOR EACH ROW
EXECUTE FUNCTION public.validate_pos_sale_item_amounts();

REVOKE ALL ON FUNCTION public.validate_pos_sale_item_amounts() FROM PUBLIC;

-- ===== END SOURCE: 20260823091000_harden_pos_sale_amounts.sql =====

-- ===== BEGIN SOURCE: 20260823092000_harden_pos_sale_totals.sql =====
-- Validate POS header arithmetic after all sale items have been inserted.
-- A deferred constraint trigger lets the atomic checkout RPC insert the header
-- first and items afterward while still enforcing the invariant at COMMIT.

CREATE OR REPLACE FUNCTION public.validate_pos_sale_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item_tax numeric;
  v_item_subtotal numeric;
BEGIN
  IF NEW.subtotal < 0 OR NEW.tax_amount < 0 OR NEW.total < 0 THEN
    RAISE EXCEPTION 'Invalid POS sale totals' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(sum(tax_amount), 0), COALESCE(sum(subtotal), 0)
  INTO v_item_tax, v_item_subtotal
  FROM public.pos_sale_items
  WHERE sale_id = NEW.id;

  IF abs(NEW.tax_amount - v_item_tax) > 0.01 THEN
    RAISE EXCEPTION 'Sale tax does not match item tax' USING ERRCODE = '22023';
  END IF;

  -- Header discounts may include promotions, vouchers, or loyalty discounts,
  -- so the valid total may be lower than the item subtotal but never higher
  -- than the subtotal plus tax.
  IF NEW.total > NEW.subtotal + NEW.tax_amount + 0.01 THEN
    RAISE EXCEPTION 'Sale total exceeds subtotal and tax' USING ERRCODE = '22023';
  END IF;

  IF v_item_subtotal > NEW.subtotal + 0.01 THEN
    RAISE EXCEPTION 'Item subtotal exceeds sale subtotal' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_pos_sale_totals ON public.pos_sales;
CREATE CONSTRAINT TRIGGER validate_pos_sale_totals
AFTER INSERT OR UPDATE OF subtotal, tax_amount, total, discount_amount,
  promotion_discount, voucher_discount, loyalty_discount
ON public.pos_sales
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.validate_pos_sale_totals();

REVOKE ALL ON FUNCTION public.validate_pos_sale_totals() FROM PUBLIC;

-- ===== END SOURCE: 20260823092000_harden_pos_sale_totals.sql =====

-- ===== BEGIN SOURCE: 20260823093000_harden_manual_payment_verification.sql =====
-- Manual payment verification must be an authorized, auditable business action.
-- It is intentionally separate from provider webhooks: merchant verification
-- requires ownership and an uploaded proof, while provider callbacks require
-- the provider secret and matching invoice.

CREATE OR REPLACE FUNCTION public.merchant_verify_order_payment(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
  v_now timestamptz := now();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT id, merchant_id, status, payment_status, payment_proof_url
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_admin()
     AND NOT EXISTS (
       SELECT 1 FROM public.merchants m
       WHERE m.id = v_order.merchant_id AND m.user_id = auth.uid()
     ) THEN
    RAISE EXCEPTION 'Order verification access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.payment_status = 'PAID' THEN
    RETURN jsonb_build_object('success', true, 'already_paid', true, 'order_id', v_order.id);
  END IF;

  IF v_order.payment_proof_url IS NULL OR length(trim(v_order.payment_proof_url)) = 0 THEN
    RAISE EXCEPTION 'Payment proof is required' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET payment_status = 'PAID',
      payment_paid_at = v_now,
      status = CASE WHEN status IN ('PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'NEW') THEN 'PROCESSED' ELSE status END,
      confirmed_at = COALESCE(confirmed_at, v_now),
      updated_at = v_now
  WHERE id = v_order.id;

  RETURN jsonb_build_object('success', true, 'already_paid', false, 'order_id', v_order.id, 'payment_status', 'PAID');
END;
$$;

REVOKE ALL ON FUNCTION public.merchant_verify_order_payment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merchant_verify_order_payment(uuid) TO authenticated;

-- ===== END SOURCE: 20260823093000_harden_manual_payment_verification.sql =====

-- ===== BEGIN SOURCE: 20260823094000_atomic_payment_webhook_processing.sql =====
-- Process a provider callback and its idempotency ledger in one transaction.
-- The order row is locked before the event is recorded, preventing concurrent
-- callbacks from racing through terminal-state checks.
CREATE OR REPLACE FUNCTION public.process_payment_webhook_event(
  p_provider text,
  p_event_key text,
  p_invoice_id text,
  p_order_id uuid,
  p_status text,
  p_paid_at timestamptz DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL,
  p_paid_amount numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_inserted boolean := false;
  v_current_status text;
  v_order_total numeric;
BEGIN
  IF NULLIF(trim(p_provider), '') IS NULL
     OR NULLIF(trim(p_event_key), '') IS NULL
     OR NULLIF(trim(p_invoice_id), '') IS NULL
     OR p_order_id IS NULL
     OR p_status NOT IN ('PAID', 'EXPIRED', 'PENDING') THEN
    RAISE EXCEPTION 'Invalid payment webhook event' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_order.payment_invoice_id IS NULL OR v_order.payment_invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'Invoice mismatch' USING ERRCODE = '23P01';
  END IF;

  v_order_total := v_order.total;
  IF v_order_total IS NULL OR v_order_total <= 0 OR v_order_total <> trunc(v_order_total) THEN
    RAISE EXCEPTION 'Invalid order total' USING ERRCODE = '22023';
  END IF;

  IF p_status = 'PAID' AND (p_paid_amount IS NULL OR p_paid_amount <> v_order_total) THEN
    RAISE EXCEPTION 'Payment amount mismatch' USING ERRCODE = '22003';
  END IF;

  INSERT INTO public.payment_webhook_events(provider, event_key, invoice_id, order_id, status)
  VALUES (lower(trim(p_provider)), trim(p_event_key), p_invoice_id, p_order_id, p_status)
  ON CONFLICT (provider, event_key) DO NOTHING
  RETURNING true INTO v_inserted;

  IF NOT COALESCE(v_inserted, false) THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true);
  END IF;

  v_current_status := COALESCE(v_order.payment_status, 'UNPAID');
  IF v_current_status = 'PAID'
     OR (v_current_status = 'EXPIRED' AND p_status = 'PENDING') THEN
    RETURN jsonb_build_object('success', true, 'ignored', true);
  END IF;

  UPDATE public.orders
  SET payment_status = p_status,
      payment_paid_at = CASE WHEN p_status = 'PAID' THEN COALESCE(p_paid_at, now()) ELSE NULL END,
      payment_method = NULLIF(trim(p_payment_method), ''),
      payment_channel = NULLIF(trim(p_payment_channel), ''),
      status = CASE
        WHEN p_status = 'PAID' THEN 'CONFIRMED'
        WHEN p_status = 'EXPIRED' AND v_current_status <> 'PAID' THEN 'CANCELLED'
        ELSE status
      END
  WHERE id = p_order_id;

  RETURN jsonb_build_object('success', true, 'processed', true, 'status', p_status);
END;
$$;

REVOKE ALL ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  TO service_role;

COMMENT ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  IS 'Atomically validates, deduplicates, and applies payment provider callbacks.';

-- Prevent direct SQL updates from downgrading a paid order payment status.
CREATE OR REPLACE FUNCTION public.prevent_paid_payment_downgrade()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.payment_status = 'PAID' AND NEW.payment_status IS DISTINCT FROM 'PAID' THEN
    RAISE EXCEPTION 'Paid order payment status is terminal' USING ERRCODE = '27000';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_paid_payment_downgrade ON public.orders;
CREATE TRIGGER trg_prevent_paid_payment_downgrade
  BEFORE UPDATE OF payment_status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.prevent_paid_payment_downgrade();

REVOKE ALL ON FUNCTION public.prevent_paid_payment_downgrade() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prevent_paid_payment_downgrade() TO service_role;
-- Rollback note: drop the trigger/function only after restoring the previous
-- webhook implementation; the function is intentionally retained for staged rollout.


-- ===== END SOURCE: 20260823094000_atomic_payment_webhook_processing.sql =====

-- ===== BEGIN SOURCE: 20260825090000_production_refund_return_controls.sql =====
-- Production return/refund controls.
ALTER TABLE public.pos_sale_returns
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'approved'
    CHECK (status IN ('pending', 'approved', 'rejected', 'processed')),
  ADD COLUMN IF NOT EXISTS refund_fee numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS processed_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text;

CREATE INDEX IF NOT EXISTS idx_pos_sale_returns_status
  ON public.pos_sale_returns(tenant_id, outlet_id, status, created_at DESC);

CREATE OR REPLACE FUNCTION public.request_pos_sale_return(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_sale_id uuid,
  p_reason text,
  p_refund_method text,
  p_restock boolean,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale public.pos_sales%ROWTYPE;
  v_return_id uuid;
  v_return_number text;
  v_item jsonb;
  v_sale_item public.pos_sale_items%ROWTYPE;
  v_qty numeric;
  v_refunded numeric;
  v_total numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id)
     OR p_sale_id IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0
     OR p_refund_method NOT IN ('cash', 'store_credit') THEN
    RAISE EXCEPTION 'Invalid return request' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_sale FROM public.pos_sales
  WHERE id = p_sale_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN
    RAISE EXCEPTION 'Sale is not eligible for return' USING ERRCODE = '55000';
  END IF;

  v_return_number := 'RTN-' || to_char(clock_timestamp(), 'YYMMDDHH24MISSMS');
  INSERT INTO public.pos_sale_returns(
    tenant_id, sale_id, outlet_id, return_number, reason, refund_method,
    total_refund, restock, created_by, status
  ) VALUES (
    p_tenant_id, p_sale_id, p_outlet_id, v_return_number, NULLIF(trim(p_reason), ''),
    p_refund_method, 0, COALESCE(p_restock, true), auth.uid(), 'pending'
  ) RETURNING id INTO v_return_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF NULLIF(v_item->>'sale_item_id', '') IS NULL
       OR (v_item->>'qty')::numeric <= 0 THEN
      RAISE EXCEPTION 'Invalid return item' USING ERRCODE = '22023';
    END IF;
    v_qty := (v_item->>'qty')::numeric;
    SELECT * INTO v_sale_item FROM public.pos_sale_items
    WHERE id = (v_item->>'sale_item_id')::uuid AND sale_id = p_sale_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Sale item not found' USING ERRCODE = 'P0002'; END IF;
    SELECT COALESCE(SUM(qty), 0) INTO v_refunded
    FROM public.pos_sale_return_items ri
    JOIN public.pos_sale_returns r ON r.id = ri.return_id
    WHERE ri.sale_item_id = v_sale_item.id AND r.status IN ('pending', 'approved', 'processed');
    IF v_refunded + v_qty > v_sale_item.qty THEN
      RAISE EXCEPTION 'Return quantity exceeds sold quantity' USING ERRCODE = '23514';
    END IF;
    INSERT INTO public.pos_sale_return_items(return_id, sale_item_id, product_id, product_name, qty, price, subtotal)
    VALUES (v_return_id, v_sale_item.id, v_sale_item.product_id, v_sale_item.product_name, v_qty, v_sale_item.price, v_qty * v_sale_item.price);
    v_total := v_total + v_qty * v_sale_item.price;
  END LOOP;

  UPDATE public.pos_sale_returns SET total_refund = v_total WHERE id = v_return_id;
  RETURN jsonb_build_object('return_id', v_return_id, 'return_number', v_return_number, 'status', 'pending', 'total_refund', v_total);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_pos_sale_return(
  p_return_id uuid,
  p_approve boolean,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_return public.pos_sale_returns%ROWTYPE;
  v_item record;
  v_stock public.pos_stock%ROWTYPE;
  v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR p_return_id IS NULL THEN
    RAISE EXCEPTION 'Invalid return approval' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_return FROM public.pos_sale_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND OR NOT public.pos_user_can_access_outlet(v_return.tenant_id, v_return.outlet_id) THEN
    RAISE EXCEPTION 'Return access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = v_return.tenant_id AND t.user_id = auth.uid()
  )) THEN
    RAISE EXCEPTION 'Return approval requires supervisor access' USING ERRCODE = '42501';
  END IF;
  IF v_return.status <> 'pending' THEN
    RAISE EXCEPTION 'Return is already processed' USING ERRCODE = '55000';
  END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_sale_returns
    SET status = 'rejected', approved_by = auth.uid(), approved_at = now(), rejection_reason = NULLIF(trim(p_rejection_reason), '')
    WHERE id = p_return_id;
    RETURN jsonb_build_object('return_id', p_return_id, 'status', 'rejected');
  END IF;

  IF v_return.restock THEN
    FOR v_item IN SELECT * FROM public.pos_sale_return_items WHERE return_id = p_return_id LOOP
      SELECT * INTO v_stock FROM public.pos_stock
      WHERE tenant_id = v_return.tenant_id AND outlet_id = v_return.outlet_id
        AND product_id = v_item.product_id
        AND variant_id IS NOT DISTINCT FROM v_item.variant_id
      FOR UPDATE;
      IF FOUND THEN
        v_after := v_stock.quantity + v_item.qty;
        UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
        INSERT INTO public.pos_stock_mutations(
          tenant_id, product_id, variant_id, outlet_id, type, quantity,
          quantity_before, quantity_after, reference_id, reference_type, notes, created_by
        ) VALUES (
          v_return.tenant_id, v_item.product_id, v_stock.variant_id, v_return.outlet_id, 'return_sale',
          v_item.qty, v_stock.quantity, v_after, p_return_id, 'pos_sale_return', 'Approved sale return', auth.uid()
        );
      END IF;
    END LOOP;
  END IF;

  UPDATE public.pos_sale_returns
  SET status = 'processed', approved_by = auth.uid(), approved_at = now(), processed_at = now()
  WHERE id = p_return_id;
  RETURN jsonb_build_object('return_id', p_return_id, 'status', 'processed', 'total_refund', v_return.total_refund);
END;
$$;

REVOKE ALL ON FUNCTION public.request_pos_sale_return(uuid, uuid, uuid, text, text, boolean, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_pos_sale_return(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pos_sale_return(uuid, uuid, uuid, text, text, boolean, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_pos_sale_return(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260825090000_production_refund_return_controls.sql =====

-- ===== BEGIN SOURCE: 20260825093000_payment_reconciliation_ledger.sql =====
-- Payment reconciliation ledger. Provider imports/callback processors write here;
-- business users only read the resulting reconciliation state.
CREATE TABLE IF NOT EXISTS public.payment_reconciliation_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  provider_event_id text,
  invoice_id text NOT NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE SET NULL,
  expected_amount numeric(15,2) NOT NULL DEFAULT 0,
  provider_amount numeric(15,2),
  provider_fee numeric(15,2) NOT NULL DEFAULT 0,
  net_amount numeric(15,2),
  currency text NOT NULL DEFAULT 'IDR',
  provider_status text NOT NULL,
  reconciliation_status text NOT NULL DEFAULT 'unmatched'
    CHECK (reconciliation_status IN ('unmatched', 'matched', 'mismatch', 'refunded', 'settled')),
  settlement_reference text,
  settlement_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(provider, invoice_id),
  UNIQUE(provider, provider_event_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_reconciliation_order
  ON public.payment_reconciliation_records(order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_reconciliation_status
  ON public.payment_reconciliation_records(reconciliation_status, created_at DESC);

ALTER TABLE public.payment_reconciliation_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_reconciliation_records FROM anon, authenticated;
GRANT SELECT ON public.payment_reconciliation_records TO authenticated;
GRANT ALL ON public.payment_reconciliation_records TO service_role;

DROP POLICY IF EXISTS "Admins can view payment reconciliation" ON public.payment_reconciliation_records;
CREATE POLICY "Admins can view payment reconciliation"
  ON public.payment_reconciliation_records FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Merchants can view own payment reconciliation" ON public.payment_reconciliation_records;
CREATE POLICY "Merchants can view own payment reconciliation"
  ON public.payment_reconciliation_records FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.record_payment_reconciliation(
  p_provider text,
  p_provider_event_id text,
  p_invoice_id text,
  p_order_id uuid,
  p_expected_amount numeric,
  p_provider_amount numeric,
  p_provider_fee numeric,
  p_provider_status text,
  p_settlement_reference text DEFAULT NULL,
  p_settlement_at timestamptz DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_status text;
  v_id uuid;
BEGIN
  IF NULLIF(trim(p_provider), '') IS NULL
     OR NULLIF(trim(p_invoice_id), '') IS NULL
     OR p_expected_amount IS NULL OR p_expected_amount < 0
     OR p_provider_amount IS NOT NULL AND p_provider_amount < 0
     OR p_provider_fee IS NULL OR p_provider_fee < 0
     OR NULLIF(trim(p_provider_status), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid reconciliation record' USING ERRCODE = '22023';
  END IF;

  IF p_order_id IS NOT NULL THEN
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002'; END IF;
  END IF;

  v_status := CASE
    WHEN lower(p_provider_status) IN ('refunded', 'refund') THEN 'refunded'
    WHEN p_provider_amount IS NULL THEN 'unmatched'
    WHEN p_provider_amount <> p_expected_amount THEN 'mismatch'
    WHEN p_settlement_reference IS NOT NULL THEN 'settled'
    ELSE 'matched'
  END;

  INSERT INTO public.payment_reconciliation_records(
    provider, provider_event_id, invoice_id, order_id, merchant_id,
    expected_amount, provider_amount, provider_fee, net_amount, provider_status,
    reconciliation_status, settlement_reference, settlement_at, metadata, updated_at
  ) VALUES (
    lower(trim(p_provider)), NULLIF(trim(p_provider_event_id), ''), p_invoice_id,
    p_order_id, v_order.merchant_id, p_expected_amount, p_provider_amount,
    p_provider_fee, CASE WHEN p_provider_amount IS NULL THEN NULL ELSE p_provider_amount - p_provider_fee END,
    trim(p_provider_status), v_status, NULLIF(trim(p_settlement_reference), ''), p_settlement_at,
    COALESCE(p_metadata, '{}'::jsonb), now()
  )
  ON CONFLICT (provider, invoice_id) DO UPDATE SET
    provider_event_id = COALESCE(EXCLUDED.provider_event_id, payment_reconciliation_records.provider_event_id),
    provider_amount = EXCLUDED.provider_amount,
    provider_fee = EXCLUDED.provider_fee,
    net_amount = EXCLUDED.net_amount,
    provider_status = EXCLUDED.provider_status,
    reconciliation_status = EXCLUDED.reconciliation_status,
    settlement_reference = COALESCE(EXCLUDED.settlement_reference, payment_reconciliation_records.settlement_reference),
    settlement_at = COALESCE(EXCLUDED.settlement_at, payment_reconciliation_records.settlement_at),
    metadata = payment_reconciliation_records.metadata || EXCLUDED.metadata,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'status', v_status, 'provider', lower(trim(p_provider)), 'invoice_id', p_invoice_id);
END;
$$;

REVOKE ALL ON FUNCTION public.record_payment_reconciliation(text, text, text, uuid, numeric, numeric, numeric, text, text, timestamptz, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_payment_reconciliation(text, text, text, uuid, numeric, numeric, numeric, text, text, timestamptz, jsonb)
  TO service_role;

-- ===== END SOURCE: 20260825093000_payment_reconciliation_ledger.sql =====

-- ===== BEGIN SOURCE: 20260825100000_cashier_approval_and_stock_opname.sql =====
-- Cashier approval controls ------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_void_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  sale_id uuid NOT NULL REFERENCES public.pos_sales(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_void_pending_sale ON public.pos_void_requests(sale_id) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS public.pos_price_override_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  sale_id uuid REFERENCES public.pos_sales(id) ON DELETE CASCADE,
  sale_item_id uuid REFERENCES public.pos_sale_items(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  original_price numeric(15,2) NOT NULL,
  requested_price numeric(15,2) NOT NULL,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  CHECK (original_price >= 0 AND requested_price >= 0)
);
CREATE INDEX IF NOT EXISTS idx_pos_price_override_pending ON public.pos_price_override_requests(tenant_id, outlet_id, status, created_at DESC);

ALTER TABLE public.pos_void_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_price_override_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view own void requests" ON public.pos_void_requests;
CREATE POLICY "POS users view own void requests" ON public.pos_void_requests FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create void requests" ON public.pos_void_requests;
CREATE POLICY "POS users create void requests" ON public.pos_void_requests FOR INSERT TO authenticated
  WITH CHECK (requested_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view price overrides" ON public.pos_price_override_requests;
CREATE POLICY "POS users view price overrides" ON public.pos_price_override_requests FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create price overrides" ON public.pos_price_override_requests;
CREATE POLICY "POS users create price overrides" ON public.pos_price_override_requests FOR INSERT TO authenticated
  WITH CHECK (requested_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.request_pos_void(
  p_tenant_id uuid, p_outlet_id uuid, p_sale_id uuid, p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sale public.pos_sales%ROWTYPE; v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_reason), '') IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid void request' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = p_sale_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Sale is not eligible for void' USING ERRCODE = '55000'; END IF;
  INSERT INTO public.pos_void_requests(tenant_id, outlet_id, sale_id, requested_by, reason)
  VALUES (p_tenant_id, p_outlet_id, p_sale_id, auth.uid(), trim(p_reason)) RETURNING id INTO v_id;
  RETURN jsonb_build_object('request_id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_void(p_request_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_req public.pos_void_requests%ROWTYPE; v_sale public.pos_sales%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE; v_after numeric;
BEGIN
  SELECT * INTO v_req FROM public.pos_void_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_req.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Void approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'Void request already decided' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_void_requests SET status = 'rejected', approved_by = auth.uid(), decided_at = now(), reason = COALESCE(NULLIF(trim(p_reason), ''), reason) WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = v_req.sale_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Sale is not eligible for void' USING ERRCODE = '55000'; END IF;
  UPDATE public.pos_sales SET status = 'void', voided_by = auth.uid(), voided_at = now(), void_reason = v_req.reason WHERE id = v_sale.id;
  FOR v_item IN SELECT * FROM public.pos_sale_items WHERE sale_id = v_sale.id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE tenant_id = v_sale.tenant_id AND outlet_id = v_sale.outlet_id AND product_id = v_item.product_id AND variant_id IS NOT DISTINCT FROM v_item.variant_id FOR UPDATE;
    IF FOUND THEN
      v_after := v_stock.quantity + v_item.qty;
      UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_sale.tenant_id, v_item.product_id, v_item.variant_id, v_sale.outlet_id, 'return_sale', v_item.qty, v_stock.quantity, v_after, v_sale.id, 'pos_sale_void', 'Approved POS void', auth.uid());
    END IF;
  END LOOP;
  UPDATE public.pos_void_requests SET status = 'approved', approved_by = auth.uid(), decided_at = now() WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'sale_id', v_sale.id);
END; $$;

-- Stock opname -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_stock_opnames (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  opname_number text NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','counting','approved','cancelled')),
  reason text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.pos_stock_opname_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opname_id uuid NOT NULL REFERENCES public.pos_stock_opnames(id) ON DELETE CASCADE,
  stock_id uuid NOT NULL REFERENCES public.pos_stock(id) ON DELETE CASCADE,
  system_quantity numeric(15,3) NOT NULL,
  counted_quantity numeric(15,3) NOT NULL CHECK (counted_quantity >= 0),
  difference numeric(15,3) NOT NULL,
  notes text
);
ALTER TABLE public.pos_stock_opnames ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_stock_opname_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view stock opnames" ON public.pos_stock_opnames;
CREATE POLICY "POS users view stock opnames" ON public.pos_stock_opnames FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create stock opnames" ON public.pos_stock_opnames;
CREATE POLICY "POS users create stock opnames" ON public.pos_stock_opnames FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view stock opname items" ON public.pos_stock_opname_items;
CREATE POLICY "POS users view stock opname items" ON public.pos_stock_opname_items FOR SELECT TO authenticated USING (opname_id IN (SELECT id FROM public.pos_stock_opnames WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));
DROP POLICY IF EXISTS "POS users create stock opname items" ON public.pos_stock_opname_items;
CREATE POLICY "POS users create stock opname items" ON public.pos_stock_opname_items FOR INSERT TO authenticated WITH CHECK (opname_id IN (SELECT id FROM public.pos_stock_opnames WHERE created_by = auth.uid() AND status IN ('draft','counting')));

CREATE OR REPLACE FUNCTION public.approve_pos_stock_opname(p_opname_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_opname public.pos_stock_opnames%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE; v_delta numeric;
BEGIN
  SELECT * INTO v_opname FROM public.pos_stock_opnames WHERE id = p_opname_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_opname.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Stock opname approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_opname.status NOT IN ('draft','counting') THEN RAISE EXCEPTION 'Stock opname already decided' USING ERRCODE = '55000'; END IF;
  FOR v_item IN SELECT * FROM public.pos_stock_opname_items WHERE opname_id = p_opname_id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_item.stock_id AND tenant_id = v_opname.tenant_id AND outlet_id = v_opname.outlet_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;
    v_delta := v_item.counted_quantity - v_stock.quantity;
    IF v_delta <> 0 THEN
      UPDATE public.pos_stock SET quantity = v_item.counted_quantity, updated_at = now() WHERE id = v_stock.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_opname.tenant_id, v_stock.product_id, v_stock.variant_id, v_opname.outlet_id, 'opname', v_delta, v_stock.quantity, v_item.counted_quantity, p_opname_id, 'stock_opname', COALESCE(v_item.notes, v_opname.reason), auth.uid());
    END IF;
  END LOOP;
  UPDATE public.pos_stock_opnames SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = p_opname_id;
  RETURN jsonb_build_object('opname_id', p_opname_id, 'status', 'approved');
END; $$;

REVOKE ALL ON FUNCTION public.request_pos_void(uuid, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_void(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_pos_stock_opname(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pos_void(uuid, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_void(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_pos_stock_opname(uuid) TO authenticated;

-- ===== END SOURCE: 20260825100000_cashier_approval_and_stock_opname.sql =====

-- ===== BEGIN SOURCE: 20260825110000_atomic_purchase_receiving.sql =====
CREATE OR REPLACE FUNCTION public.receive_pos_purchase_order(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_purchase_order_id uuid,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_po public.pos_purchase_orders%ROWTYPE;
  v_input jsonb;
  v_item public.pos_purchase_order_items%ROWTYPE;
  v_stock public.pos_stock%ROWTYPE;
  v_qty numeric;
  v_after numeric;
  v_any boolean := false;
  v_all_received boolean := true;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id)
     OR p_purchase_order_id IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Invalid purchase receiving request' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_po FROM public.pos_purchase_orders
  WHERE id = p_purchase_order_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_po.status IN ('cancelled', 'received') THEN
    RAISE EXCEPTION 'Purchase order is not receivable' USING ERRCODE = '55000';
  END IF;

  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_input->>'quantity')::numeric, 0);
    IF NULLIF(v_input->>'item_id', '') IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Invalid received item' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_item FROM public.pos_purchase_order_items
    WHERE id = (v_input->>'item_id')::uuid AND purchase_order_id = p_purchase_order_id
    FOR UPDATE;
    IF NOT FOUND OR v_item.qty_received + v_qty > v_item.qty_ordered THEN
      RAISE EXCEPTION 'Received quantity exceeds ordered quantity' USING ERRCODE = '23514';
    END IF;
    v_any := true;
    UPDATE public.pos_purchase_order_items SET qty_received = qty_received + v_qty WHERE id = v_item.id;
    IF v_item.product_id IS NOT NULL THEN
      SELECT * INTO v_stock FROM public.pos_stock
      WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id
        AND product_id = v_item.product_id AND variant_id IS NOT DISTINCT FROM v_item.variant_id
      FOR UPDATE;
      IF FOUND THEN
        v_after := v_stock.quantity + v_qty;
        UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
      ELSE
        v_after := v_qty;
        INSERT INTO public.pos_stock(tenant_id, product_id, variant_id, outlet_id, quantity, min_stock)
        VALUES (p_tenant_id, v_item.product_id, v_item.variant_id, p_outlet_id, v_after, 0)
        RETURNING * INTO v_stock;
      END IF;
      INSERT INTO public.pos_stock_mutations(
        tenant_id, product_id, variant_id, outlet_id, type, quantity,
        quantity_before, quantity_after, reference_id, reference_type, notes, created_by
      ) VALUES (
        p_tenant_id, v_item.product_id, v_item.variant_id, p_outlet_id, 'purchase', v_qty,
        v_after - v_qty, v_after, p_purchase_order_id, 'purchase_order',
        'Atomic purchase receiving ' || v_po.po_number, auth.uid()
      );
    END IF;
  END LOOP;
  IF NOT v_any THEN RAISE EXCEPTION 'No items received' USING ERRCODE = '22023'; END IF;

  SELECT NOT EXISTS (
    SELECT 1 FROM public.pos_purchase_order_items
    WHERE purchase_order_id = p_purchase_order_id AND qty_received < qty_ordered
  ) INTO v_all_received;
  UPDATE public.pos_purchase_orders
  SET status = CASE WHEN v_all_received THEN 'received' ELSE 'partial' END,
      received_date = CURRENT_DATE, updated_by = auth.uid(), updated_at = now()
  WHERE id = p_purchase_order_id;
  RETURN jsonb_build_object('purchase_order_id', p_purchase_order_id, 'status', CASE WHEN v_all_received THEN 'received' ELSE 'partial' END);
END;
$$;

REVOKE ALL ON FUNCTION public.receive_pos_purchase_order(uuid, uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.receive_pos_purchase_order(uuid, uuid, uuid, jsonb) TO authenticated;

-- ===== END SOURCE: 20260825110000_atomic_purchase_receiving.sql =====

-- ===== BEGIN SOURCE: 20260825120000_payment_pos_anomaly_detection.sql =====
CREATE TABLE IF NOT EXISTS public.pos_payment_anomalies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  anomaly_type text NOT NULL CHECK (anomaly_type IN (
    'payment_mismatch', 'duplicate_refund', 'repeated_void', 'offline_retry_spike', 'manual_adjustment_spike'
  )),
  severity text NOT NULL DEFAULT 'medium' CHECK (severity IN ('low','medium','high','critical')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved','false_positive')),
  subject_type text NOT NULL,
  subject_id uuid,
  observed_count integer NOT NULL DEFAULT 1,
  threshold integer NOT NULL DEFAULT 1,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  detected_at timestamptz NOT NULL DEFAULT now(),
  acknowledged_by uuid REFERENCES auth.users(id),
  acknowledged_at timestamptz,
  resolved_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_anomaly_open_subject
  ON public.pos_payment_anomalies(anomaly_type, subject_type, subject_id)
  WHERE status IN ('open','acknowledged');
CREATE INDEX IF NOT EXISTS idx_pos_anomaly_tenant_status
  ON public.pos_payment_anomalies(tenant_id, status, detected_at DESC);

ALTER TABLE public.pos_payment_anomalies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pos_payment_anomalies FROM anon, authenticated;
GRANT SELECT, UPDATE ON public.pos_payment_anomalies TO authenticated;
GRANT ALL ON public.pos_payment_anomalies TO service_role;
DROP POLICY IF EXISTS "Admins view and manage anomalies" ON public.pos_payment_anomalies;
CREATE POLICY "Admins view and manage anomalies" ON public.pos_payment_anomalies FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Tenant owners view anomalies" ON public.pos_payment_anomalies;
CREATE POLICY "Tenant owners view anomalies" ON public.pos_payment_anomalies FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.scan_pos_payment_anomalies(
  p_tenant_id uuid DEFAULT NULL,
  p_since timestamptz DEFAULT now() - interval '24 hours'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer := 0;
  v_row record;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Anomaly scan requires admin access' USING ERRCODE = '42501';
  END IF;

  FOR v_row IN
    SELECT NULL::uuid AS tenant_id, r.order_id AS subject_id, r.id AS record_id, r.expected_amount, r.provider_amount
    FROM public.payment_reconciliation_records r
    WHERE r.created_at >= COALESCE(p_since, now() - interval '24 hours')
      AND r.reconciliation_status = 'mismatch'
  LOOP
    INSERT INTO public.pos_payment_anomalies(
      tenant_id, anomaly_type, severity, subject_type, subject_id, threshold, details
    ) VALUES (
      v_row.tenant_id, 'payment_mismatch', 'high', 'payment_reconciliation', v_row.record_id, 1,
      jsonb_build_object('order_id', v_row.subject_id, 'expected_amount', v_row.expected_amount, 'provider_amount', v_row.provider_amount)
    ) ON CONFLICT (anomaly_type, subject_type, subject_id) WHERE status IN ('open','acknowledged') DO UPDATE
      SET observed_count = pos_payment_anomalies.observed_count + 1, details = EXCLUDED.details;
    v_count := v_count + 1;
  END LOOP;

  FOR v_row IN
    SELECT r.tenant_id, r.sale_id AS subject_id, count(*)::integer AS observed_count
    FROM public.pos_sale_returns r
    WHERE r.created_at >= COALESCE(p_since, now() - interval '24 hours')
      AND r.status IN ('pending','approved','processed')
      AND (p_tenant_id IS NULL OR r.tenant_id = p_tenant_id)
    GROUP BY r.tenant_id, r.sale_id HAVING count(*) > 1
  LOOP
    INSERT INTO public.pos_payment_anomalies(
      tenant_id, anomaly_type, severity, subject_type, subject_id, observed_count, threshold, details
    ) VALUES (
      v_row.tenant_id, 'duplicate_refund', 'high', 'pos_sale', v_row.subject_id, v_row.observed_count, 1,
      jsonb_build_object('return_count', v_row.observed_count)
    ) ON CONFLICT (anomaly_type, subject_type, subject_id) WHERE status IN ('open','acknowledged') DO UPDATE
      SET observed_count = EXCLUDED.observed_count, details = EXCLUDED.details;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.scan_pos_payment_anomalies(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.scan_pos_payment_anomalies(uuid, timestamptz) TO authenticated;

-- ===== END SOURCE: 20260825120000_payment_pos_anomaly_detection.sql =====

-- ===== BEGIN SOURCE: 20260825130000_supplier_payables_and_terms.sql =====
ALTER TABLE public.pos_purchase_orders
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid','partial','paid','overdue')),
  ADD COLUMN IF NOT EXISTS payment_terms_days integer NOT NULL DEFAULT 0 CHECK (payment_terms_days >= 0),
  ADD COLUMN IF NOT EXISTS due_date date,
  ADD COLUMN IF NOT EXISTS amount_due numeric(15,2) NOT NULL DEFAULT 0;

UPDATE public.pos_purchase_orders
SET amount_due = GREATEST(0, total - amount_paid),
    due_date = COALESCE(due_date, order_date + payment_terms_days),
    payment_status = CASE WHEN amount_paid >= total AND total > 0 THEN 'paid' WHEN amount_paid > 0 THEN 'partial' ELSE 'unpaid' END
WHERE amount_due = 0 OR due_date IS NULL;

CREATE TABLE IF NOT EXISTS public.pos_supplier_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  purchase_order_id uuid NOT NULL REFERENCES public.pos_purchase_orders(id) ON DELETE RESTRICT,
  supplier_id uuid REFERENCES public.pos_suppliers(id) ON DELETE SET NULL,
  amount numeric(15,2) NOT NULL CHECK (amount > 0),
  payment_method text NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash','transfer','debit','credit','other')),
  reference text,
  notes text,
  paid_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pos_supplier_payments_po ON public.pos_supplier_payments(purchase_order_id, paid_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_supplier_payments_supplier ON public.pos_supplier_payments(tenant_id, supplier_id, paid_at DESC);

ALTER TABLE public.pos_supplier_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view supplier payments" ON public.pos_supplier_payments;
CREATE POLICY "POS users view supplier payments" ON public.pos_supplier_payments FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create supplier payments" ON public.pos_supplier_payments;
CREATE POLICY "POS users create supplier payments" ON public.pos_supplier_payments FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.record_supplier_payment(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_purchase_order_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.pos_purchase_orders%ROWTYPE;
  v_payment_id uuid;
  v_new_paid numeric;
  v_status text;
BEGIN
  IF auth.uid() IS NULL OR p_amount IS NULL OR p_amount <= 0
     OR p_payment_method NOT IN ('cash','transfer','debit','credit','other')
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid supplier payment' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_po FROM public.pos_purchase_orders
  WHERE id = p_purchase_order_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
  IF NOT FOUND OR v_po.status = 'cancelled' THEN RAISE EXCEPTION 'Purchase order is not payable' USING ERRCODE = '55000'; END IF;
  IF p_amount > GREATEST(0, v_po.total - v_po.amount_paid) THEN RAISE EXCEPTION 'Payment exceeds outstanding balance' USING ERRCODE = '23514'; END IF;
  INSERT INTO public.pos_supplier_payments(tenant_id, outlet_id, purchase_order_id, supplier_id, amount, payment_method, reference, notes, created_by)
  VALUES (p_tenant_id, p_outlet_id, p_purchase_order_id, v_po.supplier_id, p_amount, p_payment_method, NULLIF(trim(p_reference), ''), NULLIF(trim(p_notes), ''), auth.uid())
  RETURNING id INTO v_payment_id;
  v_new_paid := v_po.amount_paid + p_amount;
  v_status := CASE WHEN v_new_paid >= v_po.total THEN 'paid' WHEN v_new_paid > 0 THEN 'partial' ELSE 'unpaid' END;
  UPDATE public.pos_purchase_orders
  SET amount_paid = v_new_paid, amount_due = GREATEST(0, total - v_new_paid), payment_status = v_status, updated_by = auth.uid(), updated_at = now()
  WHERE id = v_po.id;
  RETURN jsonb_build_object('payment_id', v_payment_id, 'purchase_order_id', v_po.id, 'amount_paid', v_new_paid, 'amount_due', GREATEST(0, v_po.total - v_new_paid), 'payment_status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.record_supplier_payment(uuid, uuid, uuid, numeric, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_supplier_payment(uuid, uuid, uuid, numeric, text, text, text) TO authenticated;

-- ===== END SOURCE: 20260825130000_supplier_payables_and_terms.sql =====

-- ===== BEGIN SOURCE: 20260825140000_stock_batches_fefo_multiwarehouse.sql =====
CREATE TABLE IF NOT EXISTS public.pos_warehouses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  name text NOT NULL,
  code text NOT NULL,
  warehouse_type text NOT NULL DEFAULT 'warehouse' CHECK (warehouse_type IN ('warehouse','outlet','vehicle','transit')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, code)
);
ALTER TABLE public.pos_stock ADD COLUMN IF NOT EXISTS warehouse_id uuid REFERENCES public.pos_warehouses(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.pos_stock_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  warehouse_id uuid REFERENCES public.pos_warehouses(id) ON DELETE SET NULL,
  stock_id uuid REFERENCES public.pos_stock(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE CASCADE,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE SET NULL,
  batch_number text NOT NULL,
  expiry_date date,
  quantity numeric(15,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  unit_cost numeric(15,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
  received_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, outlet_id, product_id, variant_id, batch_number)
);
CREATE INDEX IF NOT EXISTS idx_pos_stock_batches_fefo
  ON public.pos_stock_batches(tenant_id, outlet_id, product_id, variant_id, expiry_date NULLS LAST, received_at);

ALTER TABLE public.pos_warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_stock_batches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view warehouses" ON public.pos_warehouses;
CREATE POLICY "POS users view warehouses" ON public.pos_warehouses FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant owners manage warehouses" ON public.pos_warehouses;
CREATE POLICY "Tenant owners manage warehouses" ON public.pos_warehouses FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "POS users view stock batches" ON public.pos_stock_batches;
CREATE POLICY "POS users view stock batches" ON public.pos_stock_batches FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "Tenant owners manage stock batches" ON public.pos_stock_batches;
CREATE POLICY "Tenant owners manage stock batches" ON public.pos_stock_batches FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.consume_pos_stock_fefo(
  p_tenant_id uuid, p_outlet_id uuid, p_product_id uuid, p_variant_id uuid, p_quantity numeric, p_reference_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_remaining numeric := p_quantity; v_batch record; v_take numeric; v_consumed numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR p_quantity IS NULL OR p_quantity <= 0 OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid FEFO consumption request' USING ERRCODE = '42501';
  END IF;
  FOR v_batch IN SELECT * FROM public.pos_stock_batches
    WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id AND product_id = p_product_id
      AND variant_id IS NOT DISTINCT FROM p_variant_id AND quantity > 0
    ORDER BY expiry_date NULLS LAST, received_at, id FOR UPDATE LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := LEAST(v_remaining, v_batch.quantity);
    UPDATE public.pos_stock_batches SET quantity = quantity - v_take WHERE id = v_batch.id;
    v_remaining := v_remaining - v_take;
    v_consumed := v_consumed + v_take;
  END LOOP;
  IF v_remaining > 0 THEN RAISE EXCEPTION 'Insufficient FEFO batch stock' USING ERRCODE = '23514'; END IF;
  RETURN jsonb_build_object('product_id', p_product_id, 'consumed', v_consumed, 'remaining', v_remaining, 'reference_id', p_reference_id);
END; $$;
REVOKE ALL ON FUNCTION public.consume_pos_stock_fefo(uuid, uuid, uuid, uuid, numeric, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_pos_stock_fefo(uuid, uuid, uuid, uuid, numeric, uuid) TO authenticated;

-- ===== END SOURCE: 20260825140000_stock_batches_fefo_multiwarehouse.sql =====

-- ===== BEGIN SOURCE: 20260825150000_stock_reservation_partial_fulfillment.sql =====
ALTER TABLE public.pos_stock ADD COLUMN IF NOT EXISTS reserved_quantity numeric(15,3) NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0);

CREATE TABLE IF NOT EXISTS public.pos_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','released','consumed','expired')),
  expires_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.pos_stock_reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.pos_stock_reservations(id) ON DELETE CASCADE,
  stock_id uuid NOT NULL REFERENCES public.pos_stock(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.pos_product_variants(id),
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0),
  UNIQUE(reservation_id, stock_id)
);
CREATE INDEX IF NOT EXISTS idx_pos_reservations_order ON public.pos_stock_reservations(order_id, status);
CREATE INDEX IF NOT EXISTS idx_pos_reservations_expiry ON public.pos_stock_reservations(status, expires_at);

CREATE TABLE IF NOT EXISTS public.pos_fulfillment_shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  shipment_number text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','packed','shipped','delivered','cancelled')),
  courier_id uuid REFERENCES auth.users(id),
  tracking_number text,
  created_at timestamptz NOT NULL DEFAULT now(),
  shipped_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(tenant_id, shipment_number)
);
CREATE TABLE IF NOT EXISTS public.pos_fulfillment_shipment_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES public.pos_fulfillment_shipments(id) ON DELETE CASCADE,
  order_item_id uuid REFERENCES public.order_items(id) ON DELETE SET NULL,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0)
);

ALTER TABLE public.pos_stock_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_stock_reservation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_fulfillment_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_fulfillment_shipment_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view reservations" ON public.pos_stock_reservations;
CREATE POLICY "POS users view reservations" ON public.pos_stock_reservations FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view reservation items" ON public.pos_stock_reservation_items;
CREATE POLICY "POS users view reservation items" ON public.pos_stock_reservation_items FOR SELECT TO authenticated USING (reservation_id IN (SELECT id FROM public.pos_stock_reservations WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));
DROP POLICY IF EXISTS "POS users view shipments" ON public.pos_fulfillment_shipments;
CREATE POLICY "POS users view shipments" ON public.pos_fulfillment_shipments FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view shipment items" ON public.pos_fulfillment_shipment_items;
CREATE POLICY "POS users view shipment items" ON public.pos_fulfillment_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.pos_fulfillment_shipments WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));

CREATE OR REPLACE FUNCTION public.reserve_pos_stock(
  p_tenant_id uuid, p_outlet_id uuid, p_order_id uuid, p_items jsonb, p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_reservation_id uuid; v_input jsonb; v_stock public.pos_stock%ROWTYPE; v_qty numeric; v_total numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid stock reservation' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_stock_reservations(tenant_id, outlet_id, order_id, expires_at, created_by)
  VALUES (p_tenant_id, p_outlet_id, p_order_id, p_expires_at, auth.uid()) RETURNING id INTO v_reservation_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_input->>'quantity')::numeric, 0);
    IF NULLIF(v_input->>'stock_id', '') IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid reservation item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = (v_input->>'stock_id')::uuid AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
    IF NOT FOUND OR v_stock.quantity - v_stock.reserved_quantity < v_qty THEN RAISE EXCEPTION 'Insufficient available stock for reservation' USING ERRCODE = '23514'; END IF;
    UPDATE public.pos_stock SET reserved_quantity = reserved_quantity + v_qty, updated_at = now() WHERE id = v_stock.id;
    INSERT INTO public.pos_stock_reservation_items(reservation_id, stock_id, product_id, variant_id, quantity)
    VALUES (v_reservation_id, v_stock.id, v_stock.product_id, v_stock.variant_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('reservation_id', v_reservation_id, 'quantity', v_total, 'status', 'active');
END; $$;

CREATE OR REPLACE FUNCTION public.release_pos_stock_reservation(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.pos_stock_reservations%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM public.pos_stock_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND OR NOT public.pos_user_can_access_outlet(v_res.tenant_id, v_res.outlet_id) THEN RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501'; END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('reservation_id', p_reservation_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.pos_stock_reservation_items WHERE reservation_id = p_reservation_id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_item.stock_id FOR UPDATE;
    IF FOUND THEN UPDATE public.pos_stock SET reserved_quantity = GREATEST(0, reserved_quantity - v_item.quantity), updated_at = now() WHERE id = v_stock.id; END IF;
  END LOOP;
  UPDATE public.pos_stock_reservations SET status = 'released', released_at = now() WHERE id = p_reservation_id;
  RETURN jsonb_build_object('reservation_id', p_reservation_id, 'status', 'released');
END; $$;

REVOKE ALL ON FUNCTION public.reserve_pos_stock(uuid, uuid, uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_pos_stock_reservation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_pos_stock(uuid, uuid, uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_pos_stock_reservation(uuid) TO authenticated;

-- ===== END SOURCE: 20260825150000_stock_reservation_partial_fulfillment.sql =====

-- ===== BEGIN SOURCE: 20260825160000_courier_payroll_cod_reconciliation.sql =====
CREATE TABLE IF NOT EXISTS public.courier_commission_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  base_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (base_amount >= 0),
  per_km_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (per_km_amount >= 0),
  bonus_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (bonus_amount >= 0),
  penalty_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (penalty_amount >= 0),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS distance_km numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS base_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bonus_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS penalty_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rule_id uuid REFERENCES public.courier_commission_rules(id),
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;

CREATE TABLE IF NOT EXISTS public.courier_cod_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  expected_cash numeric(15,2) NOT NULL CHECK (expected_cash >= 0),
  collected_cash numeric(15,2) NOT NULL CHECK (collected_cash >= 0),
  variance numeric(15,2) NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','matched','shortage','overage','approved','disputed')),
  proof_url text,
  notes text,
  submitted_by uuid REFERENCES auth.users(id),
  reviewed_by uuid REFERENCES auth.users(id),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  UNIQUE(courier_id, order_id)
);
CREATE INDEX IF NOT EXISTS idx_courier_cod_status ON public.courier_cod_reconciliations(courier_id, status, submitted_at DESC);

ALTER TABLE public.courier_commission_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_cod_reconciliations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins manage courier commission rules" ON public.courier_commission_rules;
CREATE POLICY "Admins manage courier commission rules" ON public.courier_commission_rules FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Couriers view own COD reconciliation" ON public.courier_cod_reconciliations;
CREATE POLICY "Couriers view own COD reconciliation" ON public.courier_cod_reconciliations FOR SELECT TO authenticated
  USING (courier_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Couriers submit own COD reconciliation" ON public.courier_cod_reconciliations;
CREATE POLICY "Couriers submit own COD reconciliation" ON public.courier_cod_reconciliations FOR INSERT TO authenticated
  WITH CHECK (submitted_by = auth.uid() AND courier_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Admins manage COD reconciliation" ON public.courier_cod_reconciliations;
CREATE POLICY "Admins manage COD reconciliation" ON public.courier_cod_reconciliations FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.submit_courier_cod_reconciliation(
  p_courier_id uuid, p_order_id uuid, p_collected_cash numeric, p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_id uuid; v_expected numeric; v_variance numeric; v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_courier_owner(auth.uid(), p_courier_id) OR p_collected_cash IS NULL OR p_collected_cash < 0 THEN
    RAISE EXCEPTION 'COD reconciliation access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND courier_id = p_courier_id FOR SHARE;
  IF NOT FOUND OR v_order.payment_method <> 'COD' OR v_order.status NOT IN ('DONE','DELIVERED') THEN
    RAISE EXCEPTION 'Order is not eligible for COD reconciliation' USING ERRCODE = '55000';
  END IF;
  v_expected := v_order.total + COALESCE(v_order.shipping_cost, 0);
  v_variance := p_collected_cash - v_expected;
  v_status := CASE WHEN v_variance = 0 THEN 'matched' WHEN v_variance < 0 THEN 'shortage' ELSE 'overage' END;
  INSERT INTO public.courier_cod_reconciliations(courier_id, order_id, expected_cash, collected_cash, variance, status, notes, submitted_by)
  VALUES (p_courier_id, p_order_id, v_expected, p_collected_cash, v_variance, v_status, NULLIF(trim(p_notes), ''), auth.uid())
  ON CONFLICT (courier_id, order_id) DO UPDATE SET
    collected_cash = EXCLUDED.collected_cash, variance = EXCLUDED.variance, status = EXCLUDED.status,
    notes = EXCLUDED.notes, submitted_by = auth.uid(), submitted_at = now(), reviewed_by = NULL, reviewed_at = NULL
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'expected_cash', v_expected, 'collected_cash', p_collected_cash, 'variance', v_variance, 'status', v_status);
END; $$;

CREATE OR REPLACE FUNCTION public.review_courier_cod_reconciliation(p_id uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() OR p_status NOT IN ('approved','disputed') THEN
    RAISE EXCEPTION 'COD review denied' USING ERRCODE = '42501';
  END IF;
  UPDATE public.courier_cod_reconciliations SET status = p_status, notes = COALESCE(NULLIF(trim(p_notes), ''), notes), reviewed_by = auth.uid(), reviewed_at = now() WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'COD reconciliation not found' USING ERRCODE = 'P0002'; END IF;
  RETURN jsonb_build_object('id', p_id, 'status', p_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_courier_cod_reconciliation(uuid, uuid, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_courier_cod_reconciliation(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_courier_cod_reconciliation(uuid, uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_courier_cod_reconciliation(uuid, text, text) TO authenticated;

-- ===== END SOURCE: 20260825160000_courier_payroll_cod_reconciliation.sql =====

-- ===== BEGIN SOURCE: 20260825170000_dispute_center_approval_workflow.sql =====
CREATE TABLE IF NOT EXISTS public.business_disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  reporter_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  subject_type text NOT NULL CHECK (subject_type IN ('order','payment','refund','delivery','product','account','payout')),
  subject_id uuid,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','investigating','resolved','rejected','closed')),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  amount numeric(15,2) CHECK (amount IS NULL OR amount >= 0),
  evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
  resolution text,
  assigned_to uuid REFERENCES auth.users(id),
  resolved_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_business_disputes_status ON public.business_disputes(status, priority, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_business_disputes_subject ON public.business_disputes(subject_type, subject_id);

CREATE TABLE IF NOT EXISTS public.approval_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES auth.users(id),
  request_type text NOT NULL CHECK (request_type IN ('refund','discount','void','negative_stock','payout','bank_account','stock_adjustment','price_override')),
  subject_id uuid,
  requested_amount numeric(15,2) CHECK (requested_amount IS NULL OR requested_amount >= 0),
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  required_level integer NOT NULL DEFAULT 1 CHECK (required_level > 0),
  approved_level integer NOT NULL DEFAULT 0 CHECK (approved_level >= 0),
  decided_by uuid REFERENCES auth.users(id),
  decided_at timestamptz,
  decision_notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_approval_requests_pending ON public.approval_requests(tenant_id, request_type, status, created_at DESC);

ALTER TABLE public.business_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users create disputes" ON public.business_disputes;
CREATE POLICY "Users create disputes" ON public.business_disputes FOR INSERT TO authenticated WITH CHECK (reporter_id = auth.uid());
DROP POLICY IF EXISTS "Participants view disputes" ON public.business_disputes;
CREATE POLICY "Participants view disputes" ON public.business_disputes FOR SELECT TO authenticated USING (reporter_id = auth.uid() OR assigned_to = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage disputes" ON public.business_disputes;
CREATE POLICY "Admins manage disputes" ON public.business_disputes FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Tenant users view approvals" ON public.approval_requests;
CREATE POLICY "Tenant users view approvals" ON public.approval_requests FOR SELECT TO authenticated USING (requester_id = auth.uid() OR public.is_admin() OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Users create approvals" ON public.approval_requests;
CREATE POLICY "Users create approvals" ON public.approval_requests FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid());
DROP POLICY IF EXISTS "Admins manage approvals" ON public.approval_requests;
CREATE POLICY "Admins manage approvals" ON public.approval_requests FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.decide_approval_request(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.approval_requests%ROWTYPE; v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Approval requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_request FROM public.approval_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'pending' THEN RAISE EXCEPTION 'Approval request is not pending' USING ERRCODE = '55000'; END IF;
  v_status := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
  UPDATE public.approval_requests SET status = v_status, approved_level = CASE WHEN p_approve THEN required_level ELSE approved_level END,
    decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', v_status);
END; $$;
REVOKE ALL ON FUNCTION public.decide_approval_request(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_approval_request(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260825170000_dispute_center_approval_workflow.sql =====
