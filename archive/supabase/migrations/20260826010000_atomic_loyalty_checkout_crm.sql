-- Atomic loyalty ledger and checkout/CRM integration.
-- The legacy pos_customers.loyalty_points remains a compatibility aggregate;
-- pos_loyalty_ledger is the immutable source of point movements.

CREATE TABLE IF NOT EXISTS public.pos_loyalty_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES public.pos_customers(id) ON DELETE CASCADE,
  sale_id uuid REFERENCES public.pos_sales(id) ON DELETE SET NULL,
  entry_type text NOT NULL CHECK (entry_type IN ('earn','redeem','adjust','expire','reverse')),
  points integer NOT NULL CHECK (points <> 0),
  balance_before integer NOT NULL CHECK (balance_before >= 0),
  balance_after integer NOT NULL CHECK (balance_after >= 0),
  rule_id uuid REFERENCES public.pos_loyalty_rules(id) ON DELETE SET NULL,
  idempotency_key text,
  description text,
  expires_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, idempotency_key)
)$bootstrap_sql_b97d9f711dec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b97d9f711dec$;

DO $bootstrap_do_da772cfa095e$
BEGIN
  EXECUTE $bootstrap_sql_da772cfa095e$CREATE INDEX IF NOT EXISTS idx_pos_loyalty_ledger_customer
  ON public.pos_loyalty_ledger(tenant_id, customer_id, created_at DESC)$bootstrap_sql_da772cfa095e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_da772cfa095e$;

DO $bootstrap_do_1c3ec290103c$
BEGIN
  EXECUTE $bootstrap_sql_1c3ec290103c$CREATE INDEX IF NOT EXISTS idx_pos_loyalty_ledger_sale
  ON public.pos_loyalty_ledger(sale_id) WHERE sale_id IS NOT NULL$bootstrap_sql_1c3ec290103c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c3ec290103c$;

DO $bootstrap_do_8fb7f677fb0a$
BEGIN
  EXECUTE $bootstrap_sql_8fb7f677fb0a$ALTER TABLE public.pos_loyalty_ledger ENABLE ROW LEVEL SECURITY$bootstrap_sql_8fb7f677fb0a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8fb7f677fb0a$;

DO $bootstrap_do_fc41fa41feab$
BEGIN
  EXECUTE $bootstrap_sql_fc41fa41feab$DROP POLICY IF EXISTS "Tenant users view loyalty ledger" ON public.pos_loyalty_ledger$bootstrap_sql_fc41fa41feab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc41fa41feab$;

DO $bootstrap_do_b915839f7d3f$
BEGIN
  EXECUTE $bootstrap_sql_b915839f7d3f$CREATE POLICY "Tenant users view loyalty ledger" ON public.pos_loyalty_ledger
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)
    OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
  )$bootstrap_sql_b915839f7d3f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b915839f7d3f$;

DO $bootstrap_do_440e73152118$
BEGIN
  EXECUTE $bootstrap_sql_440e73152118$DROP POLICY IF EXISTS "Tenant owners manage loyalty ledger" ON public.pos_loyalty_ledger$bootstrap_sql_440e73152118$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_440e73152118$;

DO $bootstrap_do_1b3a09ba9704$
BEGIN
  EXECUTE $bootstrap_sql_1b3a09ba9704$CREATE POLICY "Tenant owners manage loyalty ledger" ON public.pos_loyalty_ledger
  FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_1b3a09ba9704$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1b3a09ba9704$;

DO $bootstrap_do_de4419bb6e53$
BEGIN
  EXECUTE $bootstrap_sql_de4419bb6e53$-- Backfill the aggregate account once. This is safe to re-run.
INSERT INTO public.pos_loyalty_points(tenant_id, customer_id, total_points, used_points, expired_points, tier)
SELECT c.tenant_id, c.id, GREATEST(0, COALESCE(c.loyalty_points, 0)), 0, 0,
       COALESCE(NULLIF(c.loyalty_tier, ''), 'Bronze')
FROM public.pos_customers c
ON CONFLICT (tenant_id, customer_id) DO NOTHING$bootstrap_sql_de4419bb6e53$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de4419bb6e53$;

DO $bootstrap_do_72586ee49b26$
BEGIN
  EXECUTE $bootstrap_sql_72586ee49b26$CREATE OR REPLACE FUNCTION public.pos_loyalty_actor_can_access(p_tenant_id uuid, p_actor_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p_actor_id = auth.uid()
    AND (
      EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.pos_users u WHERE u.tenant_id = p_tenant_id AND u.user_id = auth.uid() AND u.is_active = true)
    );
$$$bootstrap_sql_72586ee49b26$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_72586ee49b26$;

DO $bootstrap_do_7ec12ba9e793$
BEGIN
  EXECUTE $bootstrap_sql_7ec12ba9e793$CREATE OR REPLACE FUNCTION public.earn_pos_loyalty_points(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_sale_id uuid DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actor uuid := COALESCE(p_actor_id, auth.uid());
  v_customer public.pos_customers%ROWTYPE;
  v_account public.pos_loyalty_points%ROWTYPE;
  v_rule public.pos_loyalty_rules%ROWTYPE;
  v_points integer;
  v_before integer;
  v_after integer;
  v_entry_id uuid;
BEGIN
  IF NOT public.pos_loyalty_actor_can_access(p_tenant_id, v_actor) THEN
    RAISE EXCEPTION 'Loyalty access denied' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'Invalid loyalty amount' USING ERRCODE = '22023';
  END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id, balance_after INTO v_entry_id, v_after
    FROM public.pos_loyalty_ledger
    WHERE tenant_id = p_tenant_id AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('entry_id', v_entry_id, 'points', v_after, 'balance', v_after, 'duplicate', true);
    END IF;
  END IF;

  SELECT * INTO v_customer FROM public.pos_customers
  WHERE id = p_customer_id AND tenant_id = p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer does not belong to tenant' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_account FROM public.pos_loyalty_points
  WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.pos_loyalty_points(tenant_id, customer_id, total_points, tier)
    VALUES (p_tenant_id, p_customer_id, GREATEST(0, COALESCE(v_customer.loyalty_points, 0)), COALESCE(v_customer.loyalty_tier, 'Bronze'))
    RETURNING * INTO v_account;
  END IF;

  SELECT * INTO v_rule FROM public.pos_loyalty_rules
  WHERE tenant_id = p_tenant_id AND rule_type = 'earn' AND is_active = true AND min_spend <= p_amount
  ORDER BY priority DESC, points_per_currency DESC, created_at DESC LIMIT 1;
  v_points := CASE WHEN FOUND THEN floor(p_amount * v_rule.points_per_currency)::integer ELSE 0 END;
  v_before := GREATEST(0, COALESCE(v_account.total_points, 0) - COALESCE(v_account.used_points, 0) - COALESCE(v_account.expired_points, 0));
  v_after := v_before + v_points;
  IF v_points = 0 THEN
    RETURN jsonb_build_object('points', 0, 'balance', v_before, 'duplicate', false);
  END IF;

  INSERT INTO public.pos_loyalty_ledger(tenant_id, customer_id, sale_id, entry_type, points, balance_before, balance_after, rule_id, idempotency_key, description, created_by)
  VALUES (p_tenant_id, p_customer_id, p_sale_id, 'earn', v_points, v_before, v_after, v_rule.id, p_idempotency_key, 'Atomic loyalty earn', v_actor)
  RETURNING id INTO v_entry_id;
  UPDATE public.pos_loyalty_points SET total_points = total_points + v_points, updated_at = now() WHERE id = v_account.id;
  UPDATE public.pos_customers SET loyalty_points = v_after, updated_at = now() WHERE id = p_customer_id;
  RETURN jsonb_build_object('entry_id', v_entry_id, 'points', v_points, 'balance', v_after, 'duplicate', false);
END;
$$$bootstrap_sql_7ec12ba9e793$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ec12ba9e793$;

DO $bootstrap_do_bff236875914$
BEGIN
  EXECUTE $bootstrap_sql_bff236875914$CREATE OR REPLACE FUNCTION public.redeem_pos_loyalty_points(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_points integer,
  p_sale_id uuid DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actor uuid := COALESCE(p_actor_id, auth.uid());
  v_customer public.pos_customers%ROWTYPE;
  v_account public.pos_loyalty_points%ROWTYPE;
  v_rule public.pos_loyalty_rules%ROWTYPE;
  v_before integer;
  v_after integer;
  v_entry_id uuid;
BEGIN
  IF NOT public.pos_loyalty_actor_can_access(p_tenant_id, v_actor) THEN RAISE EXCEPTION 'Loyalty access denied' USING ERRCODE = '42501'; END IF;
  IF p_points IS NULL OR p_points <= 0 THEN RAISE EXCEPTION 'Invalid redeem points' USING ERRCODE = '22023'; END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id, balance_after INTO v_entry_id, v_after FROM public.pos_loyalty_ledger
    WHERE tenant_id = p_tenant_id AND idempotency_key = p_idempotency_key;
    IF FOUND THEN RETURN jsonb_build_object('entry_id', v_entry_id, 'points', p_points, 'balance', v_after, 'duplicate', true); END IF;
  END IF;
  SELECT * INTO v_customer FROM public.pos_customers WHERE id = p_customer_id AND tenant_id = p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer does not belong to tenant' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_account FROM public.pos_loyalty_points WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Loyalty account does not exist' USING ERRCODE = 'P0002'; END IF;
  v_before := GREATEST(0, COALESCE(v_account.total_points, 0) - COALESCE(v_account.used_points, 0) - COALESCE(v_account.expired_points, 0));
  IF p_points > v_before THEN RAISE EXCEPTION 'Insufficient loyalty points' USING ERRCODE = '23514'; END IF;
  SELECT * INTO v_rule FROM public.pos_loyalty_rules WHERE tenant_id = p_tenant_id AND rule_type = 'redeem' AND is_active = true ORDER BY priority DESC, created_at DESC LIMIT 1;
  v_after := v_before - p_points;
  INSERT INTO public.pos_loyalty_ledger(tenant_id, customer_id, sale_id, entry_type, points, balance_before, balance_after, rule_id, idempotency_key, description, created_by)
  VALUES (p_tenant_id, p_customer_id, p_sale_id, 'redeem', -p_points, v_before, v_after, v_rule.id, p_idempotency_key, 'Atomic loyalty redeem', v_actor)
  RETURNING id INTO v_entry_id;
  UPDATE public.pos_loyalty_points SET used_points = used_points + p_points, updated_at = now() WHERE id = v_account.id;
  UPDATE public.pos_customers SET loyalty_points = v_after, updated_at = now() WHERE id = p_customer_id;
  RETURN jsonb_build_object('entry_id', v_entry_id, 'points', p_points, 'balance', v_after, 'duplicate', false);
END;
$$$bootstrap_sql_bff236875914$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bff236875914$;

DO $bootstrap_do_7431eae34954$
BEGIN
  EXECUTE $bootstrap_sql_7431eae34954$REVOKE ALL ON FUNCTION public.pos_loyalty_actor_can_access(uuid, uuid) FROM PUBLIC, anon$bootstrap_sql_7431eae34954$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7431eae34954$;

DO $bootstrap_do_6d64e3a15c22$
BEGIN
  EXECUTE $bootstrap_sql_6d64e3a15c22$REVOKE ALL ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) FROM PUBLIC, anon$bootstrap_sql_6d64e3a15c22$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d64e3a15c22$;

DO $bootstrap_do_257e60665794$
BEGIN
  EXECUTE $bootstrap_sql_257e60665794$REVOKE ALL ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) FROM PUBLIC, anon$bootstrap_sql_257e60665794$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_257e60665794$;

DO $bootstrap_do_57dbf8f3d020$
BEGIN
  EXECUTE $bootstrap_sql_57dbf8f3d020$GRANT EXECUTE ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) TO authenticated$bootstrap_sql_57dbf8f3d020$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_57dbf8f3d020$;

DO $bootstrap_do_14ffe5378f31$
BEGIN
  EXECUTE $bootstrap_sql_14ffe5378f31$GRANT EXECUTE ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) TO authenticated$bootstrap_sql_14ffe5378f31$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14ffe5378f31$;

DO $bootstrap_do_08a9fdd91f9a$
BEGIN
  EXECUTE $bootstrap_sql_08a9fdd91f9a$-- Mirror legacy checkout point mutations into the immutable ledger exactly once.
CREATE OR REPLACE FUNCTION public.record_pos_sale_loyalty_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_before integer;
  v_after integer;
  v_points integer;
BEGIN
  IF NEW.customer_id IS NULL OR (COALESCE(NEW.loyalty_points_earned, 0) = 0 AND COALESCE(NEW.loyalty_points_redeemed, 0) = 0) THEN RETURN NEW; END IF;
  INSERT INTO public.pos_loyalty_points(tenant_id, customer_id, total_points, tier)
  VALUES (NEW.tenant_id, NEW.customer_id, 0, 'Bronze') ON CONFLICT (tenant_id, customer_id) DO NOTHING;
  SELECT GREATEST(0, total_points - used_points - expired_points) INTO v_before FROM public.pos_loyalty_points
  WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id FOR UPDATE;
  v_points := COALESCE(NEW.loyalty_points_earned, 0) - COALESCE(NEW.loyalty_points_redeemed, 0);
  IF v_points = 0 THEN RETURN NEW; END IF;
  v_after := GREATEST(0, v_before + v_points);
  INSERT INTO public.pos_loyalty_ledger(tenant_id, customer_id, sale_id, entry_type, points, balance_before, balance_after, idempotency_key, description, created_by)
  VALUES (NEW.tenant_id, NEW.customer_id, NEW.id, CASE WHEN v_points >= 0 THEN 'earn' ELSE 'redeem' END, v_points, v_before, v_after, 'sale:' || NEW.id::text, 'POS sale loyalty sync', NEW.cashier_id)
  ON CONFLICT (tenant_id, idempotency_key) DO NOTHING;
  IF v_points > 0 THEN
    UPDATE public.pos_loyalty_points SET total_points = total_points + v_points, updated_at = now()
    WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id;
  ELSE
    UPDATE public.pos_loyalty_points SET used_points = used_points + abs(v_points), updated_at = now()
    WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id;
  END IF;
  RETURN NEW;
END; $$$bootstrap_sql_08a9fdd91f9a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08a9fdd91f9a$;

DO $bootstrap_do_daa226bffa4a$
BEGIN
  EXECUTE $bootstrap_sql_daa226bffa4a$CREATE OR REPLACE FUNCTION public.apply_pos_sale_loyalty_rules()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rule public.pos_loyalty_rules%ROWTYPE;
  v_available integer;
  v_requested_redeem integer := GREATEST(0, COALESCE(NEW.loyalty_points_redeemed, 0));
BEGIN
  IF NEW.customer_id IS NULL THEN
    NEW.loyalty_points_earned := 0;
    NEW.loyalty_points_redeemed := 0;
    NEW.loyalty_discount := 0;
    RETURN NEW;
  END IF;
  SELECT * INTO v_rule FROM public.pos_loyalty_rules
  WHERE tenant_id = NEW.tenant_id AND rule_type = 'earn' AND is_active = true AND min_spend <= NEW.total
  ORDER BY priority DESC, points_per_currency DESC, created_at DESC LIMIT 1;
  NEW.loyalty_points_earned := CASE WHEN FOUND THEN floor(NEW.total * v_rule.points_per_currency)::integer ELSE 0 END;
  SELECT GREATEST(0, total_points - used_points - expired_points) INTO v_available
  FROM public.pos_loyalty_points WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id FOR UPDATE;
  IF v_available IS NULL THEN
    SELECT GREATEST(0, COALESCE(loyalty_points, 0)) INTO v_available FROM public.pos_customers
    WHERE tenant_id = NEW.tenant_id AND id = NEW.customer_id FOR UPDATE;
  END IF;
  IF v_requested_redeem > COALESCE(v_available, 0) THEN
    RAISE EXCEPTION 'Insufficient loyalty points' USING ERRCODE = '23514';
  END IF;
  NEW.loyalty_points_redeemed := v_requested_redeem;
  RETURN NEW;
END; $$$bootstrap_sql_daa226bffa4a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_daa226bffa4a$;

DO $bootstrap_do_2602b3eb8520$
BEGIN
  EXECUTE $bootstrap_sql_2602b3eb8520$DROP TRIGGER IF EXISTS trg_apply_pos_sale_loyalty_rules ON public.pos_sales$bootstrap_sql_2602b3eb8520$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2602b3eb8520$;

DO $bootstrap_do_e45e6ba0c67b$
BEGIN
  EXECUTE $bootstrap_sql_e45e6ba0c67b$CREATE TRIGGER trg_apply_pos_sale_loyalty_rules
BEFORE INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.apply_pos_sale_loyalty_rules()$bootstrap_sql_e45e6ba0c67b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e45e6ba0c67b$;

DO $bootstrap_do_c5622aa118a5$
BEGIN
  EXECUTE $bootstrap_sql_c5622aa118a5$DROP TRIGGER IF EXISTS trg_record_pos_sale_loyalty_ledger ON public.pos_sales$bootstrap_sql_c5622aa118a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5622aa118a5$;

DO $bootstrap_do_5ed534a839dd$
BEGIN
  EXECUTE $bootstrap_sql_5ed534a839dd$CREATE TRIGGER trg_record_pos_sale_loyalty_ledger
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.record_pos_sale_loyalty_ledger()$bootstrap_sql_5ed534a839dd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ed534a839dd$;

DO $bootstrap_do_6c2842da2731$
BEGIN
  EXECUTE $bootstrap_sql_6c2842da2731$-- Reusing a cart after a completed sale marks matching active carts as recovered.
CREATE OR REPLACE FUNCTION public.mark_crm_cart_recovered_after_pos_sale()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    UPDATE public.crm_abandoned_carts
    SET recovered_at = now()
    WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id AND recovered_at IS NULL;
  END IF;
  RETURN NEW;
END; $$$bootstrap_sql_6c2842da2731$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c2842da2731$;

DO $bootstrap_do_8293a5cc88cd$
BEGIN
  EXECUTE $bootstrap_sql_8293a5cc88cd$DROP TRIGGER IF EXISTS trg_mark_crm_cart_recovered ON public.pos_sales$bootstrap_sql_8293a5cc88cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8293a5cc88cd$;

DO $bootstrap_do_2f3839e312f4$
BEGIN
  EXECUTE $bootstrap_sql_2f3839e312f4$CREATE TRIGGER trg_mark_crm_cart_recovered
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.mark_crm_cart_recovered_after_pos_sale()$bootstrap_sql_2f3839e312f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2f3839e312f4$;

DO $bootstrap_do_6d22400cabd4$
BEGIN
  EXECUTE $bootstrap_sql_6d22400cabd4$
