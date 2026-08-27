-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260825200000_notification_delivery_queue.sql .. 20260829150000_pos_tenant_merchant_mapping.sql


-- ===== BEGIN SOURCE: 20260825200000_notification_delivery_queue.sql =====
CREATE TABLE IF NOT EXISTS public.notification_delivery_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel text NOT NULL CHECK (channel IN ('whatsapp','push','email','in_app')),
  template_key text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','sent','failed','dead_letter','cancelled','opted_out')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  max_attempts integer NOT NULL DEFAULT 5 CHECK (max_attempts > 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  provider_message_id text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  dead_letter_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_notification_jobs_due ON public.notification_delivery_jobs(status, next_attempt_at) WHERE status IN ('queued','failed');
CREATE INDEX IF NOT EXISTS idx_notification_jobs_recipient ON public.notification_delivery_jobs(recipient_id, created_at DESC);

ALTER TABLE public.notification_delivery_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own notification jobs" ON public.notification_delivery_jobs;
CREATE POLICY "Users view own notification jobs" ON public.notification_delivery_jobs FOR SELECT TO authenticated USING (recipient_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage notification jobs" ON public.notification_delivery_jobs;
CREATE POLICY "Admins manage notification jobs" ON public.notification_delivery_jobs FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Notification job claim requires admin access' USING ERRCODE = '42501'; END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Notification job completion requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id), last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at), sent_at = CASE WHEN p_success THEN now() ELSE sent_at END, dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$;
REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO authenticated;

-- ===== END SOURCE: 20260825200000_notification_delivery_queue.sql =====

-- ===== BEGIN SOURCE: 20260825210000_subscription_billing_controls.sql =====
ALTER TABLE public.merchant_subscriptions
  ADD COLUMN IF NOT EXISTS billing_period text NOT NULL DEFAULT 'monthly' CHECK (billing_period IN ('monthly','quarterly','yearly')),
  ADD COLUMN IF NOT EXISTS current_period_start timestamptz,
  ADD COLUMN IF NOT EXISTS current_period_end timestamptz,
  ADD COLUMN IF NOT EXISTS grace_period_until timestamptz,
  ADD COLUMN IF NOT EXISTS cancel_at_period_end boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS provider_subscription_id text;

CREATE TABLE IF NOT EXISTS public.subscription_billing_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_event_id text NOT NULL,
  event_type text NOT NULL,
  amount numeric(15,2),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'received' CHECK (status IN ('received','processed','ignored','failed')),
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  UNIQUE(provider, provider_event_id)
);
CREATE INDEX IF NOT EXISTS idx_subscription_events_subscription ON public.subscription_billing_events(subscription_id, created_at DESC);

ALTER TABLE public.subscription_billing_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Merchant views own subscription events" ON public.subscription_billing_events;
CREATE POLICY "Merchant views own subscription events" ON public.subscription_billing_events FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage subscription events" ON public.subscription_billing_events;
CREATE POLICY "Admins manage subscription events" ON public.subscription_billing_events FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.record_subscription_billing_event(
  p_subscription_id uuid, p_provider text, p_provider_event_id text, p_event_type text, p_amount numeric, p_payload jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_merchant_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Billing event ingestion requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT merchant_id INTO v_merchant_id FROM public.merchant_subscriptions WHERE id = p_subscription_id;
  IF v_merchant_id IS NULL THEN RAISE EXCEPTION 'Subscription not found' USING ERRCODE = 'P0002'; END IF;
  INSERT INTO public.subscription_billing_events(subscription_id, provider, provider_event_id, event_type, amount, payload)
  VALUES (p_subscription_id, p_provider, p_provider_event_id, p_event_type, p_amount, COALESCE(p_payload, '{}'::jsonb))
  ON CONFLICT (provider, provider_event_id) DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN jsonb_build_object('duplicate', true, 'provider_event_id', p_provider_event_id); END IF;
  RETURN jsonb_build_object('duplicate', false, 'event_id', v_id);
END; $$;
REVOKE ALL ON FUNCTION public.record_subscription_billing_event(uuid, text, text, text, numeric, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_subscription_billing_event(uuid, text, text, text, numeric, jsonb) TO service_role;

-- ===== END SOURCE: 20260825210000_subscription_billing_controls.sql =====

-- ===== BEGIN SOURCE: 20260825220000_tax_accounting_journal.sql =====
CREATE TABLE IF NOT EXISTS public.pos_tax_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  tax_code text NOT NULL,
  rate numeric(7,4) NOT NULL DEFAULT 0 CHECK (rate >= 0 AND rate <= 100),
  inclusive boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, tax_code)
);

CREATE TABLE IF NOT EXISTS public.pos_journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  entry_number text NOT NULL,
  entry_date date NOT NULL DEFAULT CURRENT_DATE,
  source_type text NOT NULL CHECK (source_type IN ('sale','payment','refund','purchase','payout','adjustment','tax','settlement')),
  source_id uuid,
  memo text NOT NULL,
  status text NOT NULL DEFAULT 'posted' CHECK (status IN ('draft','posted','reversed')),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, entry_number)
);
CREATE TABLE IF NOT EXISTS public.pos_journal_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_entry_id uuid NOT NULL REFERENCES public.pos_journal_entries(id) ON DELETE CASCADE,
  account_code text NOT NULL,
  account_name text NOT NULL,
  debit numeric(15,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit numeric(15,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  tax_profile_id uuid REFERENCES public.pos_tax_profiles(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK ((debit = 0 AND credit > 0) OR (credit = 0 AND debit > 0))
);
CREATE INDEX IF NOT EXISTS idx_pos_journal_entries_export ON public.pos_journal_entries(tenant_id, entry_date, status);
CREATE INDEX IF NOT EXISTS idx_pos_journal_lines_account ON public.pos_journal_lines(journal_entry_id, account_code);

ALTER TABLE public.pos_tax_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_journal_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tenant owners manage tax profiles" ON public.pos_tax_profiles;
CREATE POLICY "Tenant owners manage tax profiles" ON public.pos_tax_profiles FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant users view tax profiles" ON public.pos_tax_profiles;
CREATE POLICY "Tenant users view tax profiles" ON public.pos_tax_profiles FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Tenant users view journals" ON public.pos_journal_entries;
CREATE POLICY "Tenant users view journals" ON public.pos_journal_entries FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant users view journal lines" ON public.pos_journal_lines;
CREATE POLICY "Tenant users view journal lines" ON public.pos_journal_lines FOR SELECT TO authenticated USING (journal_entry_id IN (SELECT id FROM public.pos_journal_entries WHERE tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.post_pos_journal_entry(
  p_tenant_id uuid, p_outlet_id uuid, p_entry_number text, p_entry_date date, p_source_type text, p_source_id uuid, p_memo text, p_lines jsonb
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_line jsonb; v_debit numeric; v_credit numeric; v_total_debit numeric := 0; v_total_credit numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) < 2 THEN
    RAISE EXCEPTION 'Invalid journal entry' USING ERRCODE = '42501';
  END IF;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_debit := COALESCE((v_line->>'debit')::numeric, 0); v_credit := COALESCE((v_line->>'credit')::numeric, 0);
    IF (v_debit > 0 AND v_credit > 0) OR (v_debit = 0 AND v_credit = 0) THEN RAISE EXCEPTION 'Journal line must contain debit or credit only' USING ERRCODE = '23514'; END IF;
    v_total_debit := v_total_debit + v_debit; v_total_credit := v_total_credit + v_credit;
  END LOOP;
  IF v_total_debit <> v_total_credit THEN RAISE EXCEPTION 'Journal entry is not balanced' USING ERRCODE = '23514'; END IF;
  INSERT INTO public.pos_journal_entries(tenant_id, outlet_id, entry_number, entry_date, source_type, source_id, memo, created_by)
  VALUES (p_tenant_id, p_outlet_id, p_entry_number, COALESCE(p_entry_date, CURRENT_DATE), p_source_type, p_source_id, p_memo, auth.uid()) RETURNING id INTO v_entry_id;
  INSERT INTO public.pos_journal_lines(journal_entry_id, account_code, account_name, debit, credit, tax_profile_id, metadata)
  SELECT v_entry_id, value->>'account_code', value->>'account_name', COALESCE((value->>'debit')::numeric,0), COALESCE((value->>'credit')::numeric,0), NULLIF(value->>'tax_profile_id','')::uuid, COALESCE(value->'metadata','{}'::jsonb)
  FROM jsonb_array_elements(p_lines);
  RETURN v_entry_id;
END; $$;
REVOKE ALL ON FUNCTION public.post_pos_journal_entry(uuid, uuid, text, date, text, uuid, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_pos_journal_entry(uuid, uuid, text, date, text, uuid, text, jsonb) TO authenticated;

-- ===== END SOURCE: 20260825220000_tax_accounting_journal.sql =====

-- ===== BEGIN SOURCE: 20260825230000_worker_claim_and_subscription_processor.sql =====
CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job completion requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id), last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at), sent_at = CASE WHEN p_success THEN now() ELSE sent_at END, dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$;
REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.process_one_subscription_billing_event()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_event public.subscription_billing_events%ROWTYPE; v_payload jsonb; v_status text; v_period_start timestamptz; v_period_end timestamptz; v_grace timestamptz;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Subscription event processing requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_event FROM public.subscription_billing_events WHERE status IN ('received','failed') ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('processed', false, 'reason', 'empty'); END IF;
  v_payload := COALESCE(v_event.payload, '{}'::jsonb);
  v_period_start := NULLIF(COALESCE(v_payload->>'period_start', v_payload->>'current_period_start'), '')::timestamptz;
  v_period_end := NULLIF(COALESCE(v_payload->>'period_end', v_payload->>'current_period_end'), '')::timestamptz;
  v_grace := NULLIF(v_payload->>'grace_period_until', '')::timestamptz;
  IF v_event.event_type IN ('payment_succeeded','invoice_paid','subscription_renewed') THEN
    UPDATE public.merchant_subscriptions SET payment_status = 'PAID', status = 'ACTIVE', paid_at = COALESCE(paid_at, now()), current_period_start = COALESCE(v_period_start, current_period_start), current_period_end = COALESCE(v_period_end, current_period_end), grace_period_until = NULL, updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSIF v_event.event_type IN ('payment_failed','invoice_failed') THEN
    UPDATE public.merchant_subscriptions SET payment_status = 'UNPAID', status = CASE WHEN v_grace IS NULL OR v_grace > now() THEN 'PAST_DUE' ELSE 'EXPIRED' END, grace_period_until = COALESCE(v_grace, now() + interval '7 days'), updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSIF v_event.event_type IN ('subscription_cancelled','cancelled') THEN
    UPDATE public.merchant_subscriptions SET status = 'CANCELLED', updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSE
    v_status := 'ignored';
  END IF;
  UPDATE public.subscription_billing_events SET status = v_status, processed_at = now(), error_message = NULL WHERE id = v_event.id;
  RETURN jsonb_build_object('processed', true, 'event_id', v_event.id, 'status', v_status);
EXCEPTION WHEN OTHERS THEN
  IF v_event.id IS NOT NULL THEN UPDATE public.subscription_billing_events SET status = 'failed', error_message = SQLERRM WHERE id = v_event.id; END IF;
  RETURN jsonb_build_object('processed', true, 'event_id', v_event.id, 'status', 'failed', 'error', SQLERRM);
END; $$;
REVOKE ALL ON FUNCTION public.process_one_subscription_billing_event() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_one_subscription_billing_event() TO authenticated, service_role;

-- ===== END SOURCE: 20260825230000_worker_claim_and_subscription_processor.sql =====

-- ===== BEGIN SOURCE: 20260825235000_price_override_approval_rpc.sql =====
CREATE OR REPLACE FUNCTION public.decide_pos_price_override(p_request_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.pos_price_override_requests%ROWTYPE; v_sale public.pos_sales%ROWTYPE; v_item public.pos_sale_items%ROWTYPE; v_subtotal numeric;
BEGIN
  SELECT * INTO v_request FROM public.pos_price_override_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_request.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Price override approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_request.status <> 'pending' THEN RAISE EXCEPTION 'Price override request already decided' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_price_override_requests SET status = 'rejected', approved_by = auth.uid(), decided_at = now(), reason = COALESCE(NULLIF(trim(p_reason), ''), reason) WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  IF v_request.sale_item_id IS NULL THEN RAISE EXCEPTION 'Price override item is required' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_item FROM public.pos_sale_items WHERE id = v_request.sale_item_id FOR UPDATE;
  IF NOT FOUND OR (v_request.sale_id IS NOT NULL AND v_item.sale_id <> v_request.sale_id) THEN RAISE EXCEPTION 'Sale item not found' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = v_item.sale_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Only completed POS sales can be price-adjusted' USING ERRCODE = '55000'; END IF;
  IF v_sale.tenant_id <> v_request.tenant_id OR v_sale.outlet_id <> v_request.outlet_id THEN RAISE EXCEPTION 'Price override scope mismatch' USING ERRCODE = '42501'; END IF;
  UPDATE public.pos_sale_items SET price = v_request.requested_price, subtotal = GREATEST(0, (v_request.requested_price * qty) - COALESCE(discount, 0)) WHERE id = v_item.id;
  SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal FROM public.pos_sale_items WHERE sale_id = v_sale.id;
  UPDATE public.pos_sales SET subtotal = v_subtotal, total = GREATEST(0, v_subtotal - COALESCE(discount_amount, 0) + COALESCE(tax_amount, 0)), notes = concat_ws(E'\n', notes, 'Approved price override: ', v_request.id::text) WHERE id = v_sale.id;
  UPDATE public.pos_price_override_requests SET status = 'approved', approved_by = auth.uid(), decided_at = now() WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'sale_id', v_sale.id, 'new_price', v_request.requested_price, 'new_subtotal', v_subtotal);
END; $$;
REVOKE ALL ON FUNCTION public.decide_pos_price_override(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_pos_price_override(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260825235000_price_override_approval_rpc.sql =====

-- ===== BEGIN SOURCE: 20260826000000_atomic_warehouse_transfer.sql =====
CREATE TABLE IF NOT EXISTS public.pos_warehouse_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  from_warehouse_id uuid NOT NULL REFERENCES public.pos_warehouses(id) ON DELETE RESTRICT,
  to_warehouse_id uuid NOT NULL REFERENCES public.pos_warehouses(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'completed' CHECK (status IN ('completed','cancelled')),
  notes text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz NOT NULL DEFAULT now(),
  CHECK (from_warehouse_id <> to_warehouse_id)
);
CREATE TABLE IF NOT EXISTS public.pos_warehouse_transfer_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid NOT NULL REFERENCES public.pos_warehouse_transfers(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE RESTRICT,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0)
);
CREATE INDEX IF NOT EXISTS idx_pos_warehouse_transfers_tenant ON public.pos_warehouse_transfers(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_warehouse_transfer_items_transfer ON public.pos_warehouse_transfer_items(transfer_id);
ALTER TABLE public.pos_warehouse_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_warehouse_transfer_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view warehouse transfers" ON public.pos_warehouse_transfers;
CREATE POLICY "POS users view warehouse transfers" ON public.pos_warehouse_transfers FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()) OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Tenant owners insert warehouse transfers" ON public.pos_warehouse_transfers;
CREATE POLICY "Tenant owners insert warehouse transfers" ON public.pos_warehouse_transfers FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "POS users view warehouse transfer items" ON public.pos_warehouse_transfer_items;
CREATE POLICY "POS users view warehouse transfer items" ON public.pos_warehouse_transfer_items FOR SELECT TO authenticated
  USING (transfer_id IN (SELECT id FROM public.pos_warehouse_transfers WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()) OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)));

CREATE OR REPLACE FUNCTION public.transfer_stock_between_warehouses(
  p_tenant_id uuid,
  p_from_warehouse_id uuid,
  p_to_warehouse_id uuid,
  p_items jsonb,
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_from public.pos_warehouses%ROWTYPE; v_to public.pos_warehouses%ROWTYPE; v_transfer_id uuid; v_item jsonb; v_source public.pos_stock%ROWTYPE; v_dest public.pos_stock%ROWTYPE; v_product_id uuid; v_variant_id uuid; v_qty numeric; v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 OR p_from_warehouse_id = p_to_warehouse_id THEN
    RAISE EXCEPTION 'Invalid warehouse transfer' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_from FROM public.pos_warehouses WHERE id = p_from_warehouse_id AND tenant_id = p_tenant_id AND is_active FOR UPDATE;
  SELECT * INTO v_to FROM public.pos_warehouses WHERE id = p_to_warehouse_id AND tenant_id = p_tenant_id AND is_active FOR UPDATE;
  IF NOT FOUND OR v_from.outlet_id IS NULL OR v_to.outlet_id IS NULL THEN RAISE EXCEPTION 'Warehouse must be active and linked to an outlet' USING ERRCODE = '55000'; END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, v_from.outlet_id) OR NOT public.pos_user_can_access_outlet(p_tenant_id, v_to.outlet_id) THEN RAISE EXCEPTION 'Warehouse transfer access denied' USING ERRCODE = '42501'; END IF;
  INSERT INTO public.pos_warehouse_transfers(tenant_id, from_warehouse_id, to_warehouse_id, notes, created_by)
  VALUES (p_tenant_id, p_from_warehouse_id, p_to_warehouse_id, NULLIF(trim(p_notes), ''), auth.uid()) RETURNING id INTO v_transfer_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_item->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_item->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_item->>'quantity')::numeric, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid warehouse transfer item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_source FROM public.pos_stock WHERE tenant_id = p_tenant_id AND outlet_id = v_from.outlet_id AND warehouse_id = p_from_warehouse_id AND product_id = v_product_id AND variant_id IS NOT DISTINCT FROM v_variant_id FOR UPDATE;
    IF NOT FOUND OR v_source.quantity - v_source.reserved_quantity < v_qty THEN RAISE EXCEPTION 'Insufficient available warehouse stock' USING ERRCODE = '23514'; END IF;
    v_after := v_source.quantity - v_qty;
    UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_source.id;
    INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
    VALUES (p_tenant_id, v_product_id, v_variant_id, v_from.outlet_id, 'transfer_out', -v_qty, v_source.quantity, v_after, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer out', auth.uid());
    SELECT * INTO v_dest FROM public.pos_stock WHERE tenant_id = p_tenant_id AND outlet_id = v_to.outlet_id AND warehouse_id = p_to_warehouse_id AND product_id = v_product_id AND variant_id IS NOT DISTINCT FROM v_variant_id FOR UPDATE;
    IF FOUND THEN
      UPDATE public.pos_stock SET quantity = quantity + v_qty, updated_at = now() WHERE id = v_dest.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (p_tenant_id, v_product_id, v_variant_id, v_to.outlet_id, 'transfer_in', v_qty, v_dest.quantity, v_dest.quantity + v_qty, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer in', auth.uid());
    ELSE
      INSERT INTO public.pos_stock(tenant_id, outlet_id, warehouse_id, product_id, variant_id, quantity, reserved_quantity, min_stock)
      VALUES (p_tenant_id, v_to.outlet_id, p_to_warehouse_id, v_product_id, v_variant_id, v_qty, 0, 0);
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (p_tenant_id, v_product_id, v_variant_id, v_to.outlet_id, 'transfer_in', v_qty, 0, v_qty, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer in', auth.uid());
    END IF;
    INSERT INTO public.pos_warehouse_transfer_items(transfer_id, product_id, variant_id, quantity) VALUES (v_transfer_id, v_product_id, v_variant_id, v_qty);
  END LOOP;
  RETURN jsonb_build_object('transfer_id', v_transfer_id, 'status', 'completed');
END; $$;
REVOKE ALL ON FUNCTION public.transfer_stock_between_warehouses(uuid, uuid, uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_stock_between_warehouses(uuid, uuid, uuid, jsonb, text) TO authenticated;

-- ===== END SOURCE: 20260826000000_atomic_warehouse_transfer.sql =====

-- ===== BEGIN SOURCE: 20260826010000_atomic_loyalty_checkout_crm.sql =====
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
);

CREATE INDEX IF NOT EXISTS idx_pos_loyalty_ledger_customer
  ON public.pos_loyalty_ledger(tenant_id, customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_loyalty_ledger_sale
  ON public.pos_loyalty_ledger(sale_id) WHERE sale_id IS NOT NULL;

ALTER TABLE public.pos_loyalty_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tenant users view loyalty ledger" ON public.pos_loyalty_ledger;
CREATE POLICY "Tenant users view loyalty ledger" ON public.pos_loyalty_ledger
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)
    OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
  );
DROP POLICY IF EXISTS "Tenant owners manage loyalty ledger" ON public.pos_loyalty_ledger;
CREATE POLICY "Tenant owners manage loyalty ledger" ON public.pos_loyalty_ledger
  FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- Backfill the aggregate account once. This is safe to re-run.
INSERT INTO public.pos_loyalty_points(tenant_id, customer_id, total_points, used_points, expired_points, tier)
SELECT c.tenant_id, c.id, GREATEST(0, COALESCE(c.loyalty_points, 0)), 0, 0,
       COALESCE(NULLIF(c.loyalty_tier, ''), 'Bronze')
FROM public.pos_customers c
ON CONFLICT (tenant_id, customer_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.pos_loyalty_actor_can_access(p_tenant_id uuid, p_actor_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p_actor_id = auth.uid()
    AND (
      EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.pos_users u WHERE u.tenant_id = p_tenant_id AND u.user_id = auth.uid() AND u.is_active = true)
    );
$$;

CREATE OR REPLACE FUNCTION public.earn_pos_loyalty_points(
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
$$;

CREATE OR REPLACE FUNCTION public.redeem_pos_loyalty_points(
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
$$;

REVOKE ALL ON FUNCTION public.pos_loyalty_actor_can_access(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) TO authenticated;

-- Mirror legacy checkout point mutations into the immutable ledger exactly once.
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
END; $$;

CREATE OR REPLACE FUNCTION public.apply_pos_sale_loyalty_rules()
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
END; $$;

DROP TRIGGER IF EXISTS trg_apply_pos_sale_loyalty_rules ON public.pos_sales;
CREATE TRIGGER trg_apply_pos_sale_loyalty_rules
BEFORE INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.apply_pos_sale_loyalty_rules();
DROP TRIGGER IF EXISTS trg_record_pos_sale_loyalty_ledger ON public.pos_sales;
CREATE TRIGGER trg_record_pos_sale_loyalty_ledger
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.record_pos_sale_loyalty_ledger();

-- Reusing a cart after a completed sale marks matching active carts as recovered.
CREATE OR REPLACE FUNCTION public.mark_crm_cart_recovered_after_pos_sale()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    UPDATE public.crm_abandoned_carts
    SET recovered_at = now()
    WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id AND recovered_at IS NULL;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_mark_crm_cart_recovered ON public.pos_sales;
CREATE TRIGGER trg_mark_crm_cart_recovered
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.mark_crm_cart_recovered_after_pos_sale();

-- ===== END SOURCE: 20260826010000_atomic_loyalty_checkout_crm.sql =====

-- ===== BEGIN SOURCE: 20260826010000_marketplace_stock_reservation_lifecycle.sql =====
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS reserved_stock integer NOT NULL DEFAULT 0 CHECK (reserved_stock >= 0);

CREATE TABLE IF NOT EXISTS public.marketplace_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','released','consumed','expired')),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes',
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  consumed_at timestamptz,
  UNIQUE(order_id)
);
CREATE TABLE IF NOT EXISTS public.marketplace_stock_reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.marketplace_stock_reservations(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.product_variants(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK (quantity > 0),
  UNIQUE(reservation_id, product_id, variant_id)
);
CREATE INDEX IF NOT EXISTS idx_marketplace_reservations_expiry ON public.marketplace_stock_reservations(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_marketplace_reservation_items_product ON public.marketplace_stock_reservation_items(product_id);
ALTER TABLE public.marketplace_stock_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_stock_reservation_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Buyers view own stock reservations" ON public.marketplace_stock_reservations;
CREATE POLICY "Buyers view own stock reservations" ON public.marketplace_stock_reservations FOR SELECT TO authenticated USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Merchants view order reservations" ON public.marketplace_stock_reservations;
CREATE POLICY "Merchants view order reservations" ON public.marketplace_stock_reservations FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = order_id AND m.user_id = auth.uid()));
DROP POLICY IF EXISTS "Users view own reservation items" ON public.marketplace_stock_reservation_items;
CREATE POLICY "Users view own reservation items" ON public.marketplace_stock_reservation_items FOR SELECT TO authenticated USING (reservation_id IN (SELECT id FROM public.marketplace_stock_reservations WHERE buyer_id = auth.uid() OR EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = marketplace_stock_reservations.order_id AND m.user_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.reserve_marketplace_stock(
  p_order_id uuid,
  p_items jsonb,
  p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_reservation_id uuid; v_input jsonb; v_product public.products%ROWTYPE; v_product_id uuid; v_variant_id uuid; v_qty integer; v_total integer := 0; v_existing public.marketplace_stock_reservations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_order_id IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'Invalid marketplace reservation' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR v_order.status IN ('CANCELLED','CANCELED','REJECTED','REFUNDED') THEN RAISE EXCEPTION 'Order reservation access denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_existing FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF FOUND THEN RETURN jsonb_build_object('reservation_id', v_existing.id, 'status', v_existing.status, 'duplicate', true); END IF;
  INSERT INTO public.marketplace_stock_reservations(order_id, buyer_id, expires_at) VALUES (p_order_id, auth.uid(), GREATEST(p_expires_at, now() + interval '1 minute')) RETURNING id INTO v_reservation_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_input->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_input->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_input->>'quantity')::integer, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid marketplace reservation item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_product FROM public.products WHERE id = v_product_id FOR UPDATE;
    IF NOT FOUND OR v_product.stock - v_product.reserved_stock < v_qty THEN RAISE EXCEPTION 'Insufficient marketplace stock' USING ERRCODE = '23514'; END IF;
    UPDATE public.products SET reserved_stock = reserved_stock + v_qty, updated_at = now() WHERE id = v_product_id;
    INSERT INTO public.marketplace_stock_reservation_items(reservation_id, product_id, variant_id, quantity) VALUES (v_reservation_id, v_product_id, v_variant_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('reservation_id', v_reservation_id, 'status', 'active', 'quantity', v_total, 'expires_at', p_expires_at);
END; $$;

CREATE OR REPLACE FUNCTION public.release_marketplace_stock_reservation(p_order_id uuid, p_status text DEFAULT 'released')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.marketplace_stock_reservations%ROWTYPE; v_item record; v_user_is_buyer boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  SELECT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid()) INTO v_user_is_buyer;
  IF NOT v_user_is_buyer AND NOT EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = p_order_id AND m.user_id = auth.uid()) AND NOT public.is_admin() THEN RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501'; END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.marketplace_stock_reservation_items WHERE reservation_id = v_res.id LOOP
    UPDATE public.products SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now() WHERE id = v_item.product_id;
  END LOOP;
  UPDATE public.marketplace_stock_reservations SET status = CASE WHEN p_status IN ('expired','released') THEN p_status ELSE 'released' END, released_at = now() WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', p_status);
END; $$;

CREATE OR REPLACE FUNCTION public.consume_marketplace_stock_reservation(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.marketplace_stock_reservations%ROWTYPE; v_item record; v_product public.products%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  IF v_res.status = 'consumed' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed', 'duplicate', true); END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.marketplace_stock_reservation_items WHERE reservation_id = v_res.id LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id FOR UPDATE;
    IF NOT FOUND OR v_product.reserved_stock < v_item.quantity OR v_product.stock < v_item.quantity THEN RAISE EXCEPTION 'Reserved marketplace stock is no longer available' USING ERRCODE = '23514'; END IF;
    UPDATE public.products SET stock = stock - v_item.quantity, reserved_stock = reserved_stock - v_item.quantity, sold_count = COALESCE(sold_count, 0) + v_item.quantity, updated_at = now() WHERE id = v_item.product_id;
  END LOOP;
  UPDATE public.marketplace_stock_reservations SET status = 'consumed', consumed_at = now() WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed');
END; $$;

CREATE OR REPLACE FUNCTION public.expire_marketplace_stock_reservations(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order_id uuid; v_count integer := 0;
BEGIN
  FOR v_order_id IN SELECT order_id FROM public.marketplace_stock_reservations WHERE status = 'active' AND expires_at <= now() ORDER BY expires_at FOR UPDATE SKIP LOCKED LIMIT GREATEST(1, LEAST(p_limit, 1000)) LOOP
    PERFORM public.release_marketplace_stock_reservation(v_order_id, 'expired'); v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION public.marketplace_reservation_order_status_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF lower(COALESCE(NEW.status, '')) IN ('cancelled','canceled','rejected','refunded') AND lower(COALESCE(OLD.status, '')) <> lower(COALESCE(NEW.status, '')) THEN PERFORM public.release_marketplace_stock_reservation(NEW.id, 'released');
  ELSIF lower(COALESCE(NEW.status, '')) IN ('shipped','delivered','completed','done') AND lower(COALESCE(OLD.status, '')) <> lower(COALESCE(NEW.status, '')) THEN PERFORM public.consume_marketplace_stock_reservation(NEW.id);
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_marketplace_reservation_order_status ON public.orders;
CREATE TRIGGER trg_marketplace_reservation_order_status AFTER UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.marketplace_reservation_order_status_trigger();

REVOKE ALL ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.consume_marketplace_stock_reservation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.expire_marketplace_stock_reservations(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_marketplace_stock_reservation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_marketplace_stock_reservations(integer) TO service_role;

-- ===== END SOURCE: 20260826010000_marketplace_stock_reservation_lifecycle.sql =====

-- ===== BEGIN SOURCE: 20260826020000_crm_notification_dispatch.sql =====
-- CRM campaign dispatch into the durable notification queue.
ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS dedupe_key text;
CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_jobs_tenant_dedupe
  ON public.notification_delivery_jobs(tenant_id, dedupe_key)
  WHERE dedupe_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.enqueue_due_crm_campaign_jobs(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_campaign record;
  v_member record;
  v_delivery_id uuid;
  v_job_id uuid;
  v_queued integer := 0;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
  v_phone text;
  v_message text;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'CRM dispatcher requires admin or service role' USING ERRCODE = '42501';
  END IF;
  FOR v_campaign IN
    SELECT c.* FROM public.crm_campaigns c
    WHERE c.status = 'scheduled' AND COALESCE(c.scheduled_at, now()) <= now()
    ORDER BY COALESCE(c.scheduled_at, c.created_at)
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    FOR v_member IN
      SELECT sm.customer_id
      FROM public.crm_segment_members sm
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id
    LOOP
      INSERT INTO public.crm_campaign_deliveries(campaign_id, customer_id, status)
      VALUES (v_campaign.id, v_member.customer_id, 'queued')
      ON CONFLICT (campaign_id, customer_id) DO NOTHING
      RETURNING id INTO v_delivery_id;
      IF v_delivery_id IS NULL THEN CONTINUE; END IF;

      SELECT COALESCE(u.raw_user_meta_data->>'phone', u.phone) INTO v_phone
      FROM auth.users u WHERE u.id = v_member.customer_id;
      v_message := replace(replace(v_campaign.template, '{{customer_id}}', v_member.customer_id::text), '{{campaign_name}}', v_campaign.name);
      INSERT INTO public.notification_delivery_jobs(
        tenant_id, recipient_id, channel, template_key, payload, dedupe_key
      ) VALUES (
        v_campaign.tenant_id, v_member.customer_id, v_campaign.channel, 'crm_campaign',
        jsonb_build_object('campaign_id', v_campaign.id, 'delivery_id', v_delivery_id, 'to', v_phone, 'message', v_message),
        'crm:' || v_campaign.id::text || ':' || v_member.customer_id::text
      )
      ON CONFLICT (tenant_id, dedupe_key) DO NOTHING
      RETURNING id INTO v_job_id;
      IF v_job_id IS NOT NULL THEN v_queued := v_queued + 1; END IF;
    END LOOP;
    UPDATE public.crm_campaigns SET status = 'sending' WHERE id = v_campaign.id;
  END LOOP;
  RETURN jsonb_build_object('queued', v_queued);
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) TO service_role;

-- ===== END SOURCE: 20260826020000_crm_notification_dispatch.sql =====

-- ===== BEGIN SOURCE: 20260826020000_marketplace_partial_fulfillment.sql =====
CREATE TABLE IF NOT EXISTS public.marketplace_shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  shipment_number text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','packed','shipped','delivered','cancelled')),
  tracking_number text,
  courier_id uuid REFERENCES public.couriers(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  shipped_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(merchant_id, shipment_number)
);
CREATE TABLE IF NOT EXISTS public.marketplace_shipment_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES public.marketplace_shipments(id) ON DELETE CASCADE,
  order_item_id uuid NOT NULL REFERENCES public.order_items(id) ON DELETE RESTRICT,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  UNIQUE(shipment_id, order_item_id)
);
CREATE INDEX IF NOT EXISTS idx_marketplace_shipments_order ON public.marketplace_shipments(order_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_marketplace_shipment_items_order_item ON public.marketplace_shipment_items(order_item_id);
ALTER TABLE public.marketplace_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_shipment_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Buyer views own marketplace shipments" ON public.marketplace_shipments;
CREATE POLICY "Buyer views own marketplace shipments" ON public.marketplace_shipments FOR SELECT TO authenticated USING (order_id IN (SELECT id FROM public.orders WHERE buyer_id = auth.uid()));
DROP POLICY IF EXISTS "Merchant views own marketplace shipments" ON public.marketplace_shipments;
CREATE POLICY "Merchant views own marketplace shipments" ON public.marketplace_shipments FOR SELECT TO authenticated USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Buyer views own shipment items" ON public.marketplace_shipment_items;
CREATE POLICY "Buyer views own shipment items" ON public.marketplace_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.marketplace_shipments WHERE order_id IN (SELECT id FROM public.orders WHERE buyer_id = auth.uid())));
DROP POLICY IF EXISTS "Merchant views own shipment items" ON public.marketplace_shipment_items;
CREATE POLICY "Merchant views own shipment items" ON public.marketplace_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.marketplace_shipments WHERE merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.create_marketplace_shipment(p_order_id uuid, p_items jsonb, p_tracking_number text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_merchant_id uuid; v_shipment_id uuid; v_input jsonb; v_item public.order_items%ROWTYPE; v_product_id uuid; v_order_item_id uuid; v_qty integer; v_shipped integer; v_total integer := 0; v_number text;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'Invalid shipment request' USING ERRCODE = '22023'; END IF;
  SELECT o.* INTO v_order
  FROM public.orders o
  JOIN public.merchants m ON m.id = o.merchant_id
  WHERE o.id = p_order_id AND m.user_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Shipment access denied' USING ERRCODE = '42501'; END IF;
  v_merchant_id := v_order.merchant_id;
  v_number := 'SHP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  INSERT INTO public.marketplace_shipments(order_id, merchant_id, shipment_number, tracking_number) VALUES (p_order_id, v_merchant_id, v_number, NULLIF(trim(p_tracking_number), '')) RETURNING id INTO v_shipment_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_order_item_id := NULLIF(v_input->>'order_item_id', '')::uuid; v_qty := COALESCE((v_input->>'quantity')::integer, 0);
    IF v_order_item_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid shipment item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_item FROM public.order_items WHERE id = v_order_item_id AND order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order item not found' USING ERRCODE = 'P0002'; END IF;
    SELECT COALESCE(sum(quantity), 0) INTO v_shipped FROM public.marketplace_shipment_items si JOIN public.marketplace_shipments s ON s.id = si.shipment_id WHERE si.order_item_id = v_order_item_id AND s.status <> 'cancelled';
    IF v_shipped + v_qty > v_item.quantity THEN RAISE EXCEPTION 'Shipment quantity exceeds order quantity' USING ERRCODE = '23514'; END IF;
    v_product_id := NULLIF(v_item.product_id::text, '')::uuid;
    INSERT INTO public.marketplace_shipment_items(shipment_id, order_item_id, product_id, quantity) VALUES (v_shipment_id, v_order_item_id, v_product_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('id', v_shipment_id, 'shipment_number', v_number, 'quantity', v_total, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.update_marketplace_shipment_status(p_shipment_id uuid, p_status text, p_tracking_number text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_shipment public.marketplace_shipments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_status NOT IN ('pending','processing','packed','shipped','delivered','cancelled') THEN RAISE EXCEPTION 'Invalid shipment status' USING ERRCODE = '22023'; END IF;
  SELECT s.* INTO v_shipment FROM public.marketplace_shipments s WHERE s.id = p_shipment_id AND (s.merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Shipment access denied' USING ERRCODE = '42501'; END IF;
  UPDATE public.marketplace_shipments SET status = p_status, tracking_number = COALESCE(NULLIF(trim(p_tracking_number), ''), tracking_number), shipped_at = CASE WHEN p_status = 'shipped' AND shipped_at IS NULL THEN now() ELSE shipped_at END, delivered_at = CASE WHEN p_status = 'delivered' AND delivered_at IS NULL THEN now() ELSE delivered_at END WHERE id = p_shipment_id;
  RETURN jsonb_build_object('id', p_shipment_id, 'status', p_status);
END; $$;
REVOKE ALL ON FUNCTION public.create_marketplace_shipment(uuid, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_marketplace_shipment_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_shipment(uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_marketplace_shipment_status(uuid, text, text) TO authenticated;

-- ===== END SOURCE: 20260826020000_marketplace_partial_fulfillment.sql =====

-- ===== BEGIN SOURCE: 20260826030000_merchant_import_commit_rollback.sql =====
CREATE TABLE IF NOT EXISTS public.merchant_product_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'preview' CHECK (status IN ('preview','validated','committed','rolled_back','failed')),
  row_count integer NOT NULL DEFAULT 0 CHECK (row_count >= 0),
  valid_count integer NOT NULL DEFAULT 0 CHECK (valid_count >= 0),
  error_count integer NOT NULL DEFAULT 0 CHECK (error_count >= 0),
  inserted_product_ids uuid[] NOT NULL DEFAULT '{}',
  validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  rolled_back_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_merchant_product_import_jobs_merchant ON public.merchant_product_import_jobs(merchant_id, created_at DESC);
ALTER TABLE public.merchant_product_import_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Merchant manages own product import jobs" ON public.merchant_product_import_jobs;
CREATE POLICY "Merchant manages own product import jobs" ON public.merchant_product_import_jobs FOR ALL TO authenticated USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin());

CREATE OR REPLACE FUNCTION public.commit_merchant_product_import(p_merchant_id uuid, p_rows jsonb, p_validation_errors jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job_id uuid; v_ids uuid[] := '{}'; v_row jsonb; v_product_id uuid; v_count integer := 0; v_errors integer := jsonb_array_length(COALESCE(p_validation_errors, '[]'::jsonb));
BEGIN
  IF auth.uid() IS NULL OR NOT (p_merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN RAISE EXCEPTION 'Import access denied or invalid rows' USING ERRCODE = '42501'; END IF;
  INSERT INTO public.merchant_product_import_jobs(merchant_id, created_by, status, row_count, valid_count, error_count, validation_errors) VALUES (p_merchant_id, auth.uid(), 'validated', jsonb_array_length(p_rows) + v_errors, jsonb_array_length(p_rows), v_errors, COALESCE(p_validation_errors, '[]'::jsonb)) RETURNING id INTO v_job_id;
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
    IF NULLIF(trim(v_row->>'name'), '') IS NULL OR COALESCE((v_row->>'price')::numeric, 0) <= 0 OR COALESCE((v_row->>'stock')::integer, -1) < 0 THEN RAISE EXCEPTION 'Invalid product import row' USING ERRCODE = '22023'; END IF;
    INSERT INTO public.products(merchant_id, name, description, price, stock, category, is_active, is_promo) VALUES (p_merchant_id, trim(v_row->>'name'), NULLIF(v_row->>'description', ''), (v_row->>'price')::numeric, (v_row->>'stock')::integer, trim(v_row->>'category'), COALESCE((v_row->>'is_active')::boolean, true), COALESCE((v_row->>'is_promo')::boolean, false)) RETURNING id INTO v_product_id;
    v_ids := array_append(v_ids, v_product_id); v_count := v_count + 1;
  END LOOP;
  UPDATE public.merchant_product_import_jobs SET status = 'committed', inserted_product_ids = v_ids, committed_at = now() WHERE id = v_job_id;
  RETURN jsonb_build_object('job_id', v_job_id, 'status', 'committed', 'inserted_count', v_count);
EXCEPTION WHEN OTHERS THEN
  IF v_job_id IS NOT NULL THEN UPDATE public.merchant_product_import_jobs SET status = 'failed' WHERE id = v_job_id; END IF;
  RAISE;
END; $$;

CREATE OR REPLACE FUNCTION public.rollback_merchant_product_import(p_job_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.merchant_product_import_jobs%ROWTYPE; v_deleted integer := 0;
BEGIN
  SELECT * INTO v_job FROM public.merchant_product_import_jobs WHERE id = p_job_id AND (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'committed' THEN RAISE EXCEPTION 'Import rollback not available' USING ERRCODE = '55000'; END IF;
  DELETE FROM public.products WHERE id = ANY(v_job.inserted_product_ids) AND merchant_id = v_job.merchant_id AND created_at >= v_job.committed_at;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  UPDATE public.merchant_product_import_jobs SET status = 'rolled_back', rolled_back_at = now() WHERE id = v_job.id;
  RETURN jsonb_build_object('job_id', p_job_id, 'status', 'rolled_back', 'deleted_count', v_deleted);
END; $$;
REVOKE ALL ON FUNCTION public.commit_merchant_product_import(uuid, jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rollback_merchant_product_import(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.commit_merchant_product_import(uuid, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_merchant_product_import(uuid) TO authenticated;

-- ===== END SOURCE: 20260826030000_merchant_import_commit_rollback.sql =====

-- ===== BEGIN SOURCE: 20260826030000_pos_customer_crm_identity.sql =====
-- Unify POS customers with CRM while keeping legacy auth-user references compatible.
ALTER TABLE public.pos_customers
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_customers_tenant_auth_user
  ON public.pos_customers(tenant_id, auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pos_customers_tenant_phone
  ON public.pos_customers(tenant_id, phone) WHERE phone IS NOT NULL;

ALTER TABLE public.crm_segment_members DROP CONSTRAINT IF EXISTS crm_segment_members_pkey;
ALTER TABLE public.crm_segment_members
  ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE public.crm_segment_members
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_segment_members_auth
  ON public.crm_segment_members(segment_id, customer_id) WHERE customer_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_segment_members_pos
  ON public.crm_segment_members(segment_id, pos_customer_id) WHERE pos_customer_id IS NOT NULL;
ALTER TABLE public.crm_segment_members
  DROP CONSTRAINT IF EXISTS crm_segment_members_target_check;
ALTER TABLE public.crm_segment_members
  ADD CONSTRAINT crm_segment_members_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL);

ALTER TABLE public.crm_campaign_deliveries
  ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE public.crm_campaign_deliveries
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_campaign_deliveries_pos
  ON public.crm_campaign_deliveries(campaign_id, pos_customer_id) WHERE pos_customer_id IS NOT NULL;
ALTER TABLE public.crm_campaign_deliveries
  DROP CONSTRAINT IF EXISTS crm_campaign_deliveries_target_check;
ALTER TABLE public.crm_campaign_deliveries
  ADD CONSTRAINT crm_campaign_deliveries_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL);

ALTER TABLE public.crm_abandoned_carts
  ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE public.crm_abandoned_carts
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE;
ALTER TABLE public.crm_abandoned_carts
  DROP CONSTRAINT IF EXISTS crm_abandoned_carts_target_check;
ALTER TABLE public.crm_abandoned_carts
  ADD CONSTRAINT crm_abandoned_carts_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL);

ALTER TABLE public.notification_delivery_jobs
  ALTER COLUMN recipient_id DROP NOT NULL;
ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS recipient_pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE;
ALTER TABLE public.notification_delivery_jobs
  DROP CONSTRAINT IF EXISTS notification_delivery_jobs_recipient_check;
ALTER TABLE public.notification_delivery_jobs
  ADD CONSTRAINT notification_delivery_jobs_recipient_check CHECK (recipient_id IS NOT NULL OR recipient_pos_customer_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_notification_jobs_pos_recipient
  ON public.notification_delivery_jobs(recipient_pos_customer_id, created_at DESC);

DROP POLICY IF EXISTS "Users view own notification jobs" ON public.notification_delivery_jobs;
CREATE POLICY "Users view own notification jobs" ON public.notification_delivery_jobs FOR SELECT TO authenticated
  USING (
    recipient_id = auth.uid()
    OR recipient_pos_customer_id IN (SELECT id FROM public.pos_customers WHERE auth_user_id = auth.uid())
    OR public.is_admin()
  );

CREATE OR REPLACE FUNCTION public.enqueue_due_crm_campaign_jobs(p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campaign record;
  v_target record;
  v_delivery_id uuid;
  v_job_id uuid;
  v_queued integer := 0;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'CRM dispatcher requires admin or service role' USING ERRCODE = '42501';
  END IF;
  FOR v_campaign IN
    SELECT c.* FROM public.crm_campaigns c
    WHERE c.status = 'scheduled' AND COALESCE(c.scheduled_at, now()) <= now()
    ORDER BY COALESCE(c.scheduled_at, c.created_at)
    LIMIT v_limit FOR UPDATE SKIP LOCKED
  LOOP
    FOR v_target IN
      SELECT sm.customer_id, NULL::uuid AS pos_customer_id, COALESCE(u.raw_user_meta_data->>'phone', u.phone) AS phone
      FROM public.crm_segment_members sm JOIN auth.users u ON u.id = sm.customer_id
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id
      UNION ALL
      SELECT NULL::uuid, sm.pos_customer_id, pc.phone
      FROM public.crm_segment_members sm JOIN public.pos_customers pc ON pc.id = sm.pos_customer_id
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id AND pc.is_active = true
    LOOP
      INSERT INTO public.crm_campaign_deliveries(campaign_id, customer_id, pos_customer_id, status)
      VALUES (v_campaign.id, v_target.customer_id, v_target.pos_customer_id, 'queued')
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_delivery_id;
      IF v_delivery_id IS NULL THEN CONTINUE; END IF;
      INSERT INTO public.notification_delivery_jobs(
        tenant_id, recipient_id, recipient_pos_customer_id, channel, template_key, payload, dedupe_key
      ) VALUES (
        v_campaign.tenant_id, v_target.customer_id, v_target.pos_customer_id, v_campaign.channel, 'crm_campaign',
        jsonb_build_object('campaign_id', v_campaign.id, 'delivery_id', v_delivery_id, 'to', v_target.phone, 'message', v_campaign.template),
        'crm:' || v_campaign.id::text || ':' || COALESCE(v_target.customer_id, v_target.pos_customer_id)::text
      )
      ON CONFLICT (tenant_id, dedupe_key) DO NOTHING
      RETURNING id INTO v_job_id;
      IF v_job_id IS NOT NULL THEN v_queued := v_queued + 1; END IF;
    END LOOP;
    UPDATE public.crm_campaigns SET status = 'sending' WHERE id = v_campaign.id;
  END LOOP;
  RETURN jsonb_build_object('queued', v_queued);
END; $$;

CREATE OR REPLACE FUNCTION public.mark_crm_cart_recovered_after_pos_sale()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    UPDATE public.crm_abandoned_carts
    SET recovered_at = now()
    WHERE tenant_id = NEW.tenant_id
      AND (customer_id = NEW.customer_id OR pos_customer_id = NEW.customer_id)
      AND recovered_at IS NULL;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_mark_crm_cart_recovered ON public.pos_sales;
CREATE TRIGGER trg_mark_crm_cart_recovered
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.mark_crm_cart_recovered_after_pos_sale();

-- Best-effort deterministic backfill for existing customers. Ambiguous emails remain unmapped.
UPDATE public.pos_customers pc
SET auth_user_id = u.id
FROM auth.users u
WHERE pc.auth_user_id IS NULL
  AND pc.email IS NOT NULL
  AND lower(trim(pc.email)) = lower(trim(u.email))
  AND NOT EXISTS (
    SELECT 1 FROM public.pos_customers occupied
    WHERE occupied.tenant_id = pc.tenant_id AND occupied.auth_user_id = u.id
  );

-- ===== END SOURCE: 20260826030000_pos_customer_crm_identity.sql =====

-- ===== BEGIN SOURCE: 20260827090000_atomic_pricebook_admin_rpc.sql =====
-- Atomic admin operation for price-book header plus its first item.
CREATE OR REPLACE FUNCTION public.create_pos_price_book(
  p_tenant_id uuid,
  p_name text,
  p_customer_segment text,
  p_outlet_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_priority integer,
  p_product_id uuid,
  p_variant_id uuid,
  p_price numeric
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_book_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.pos_tenants WHERE id = p_tenant_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Price book administration denied' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_name), '') IS NULL OR p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'Invalid price book input' USING ERRCODE = '22023';
  END IF;
  IF p_customer_segment NOT IN ('retail','wholesale','reseller','member','outlet') THEN
    RAISE EXCEPTION 'Invalid customer segment' USING ERRCODE = '22023';
  END IF;
  IF p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL AND p_ends_at < p_starts_at THEN
    RAISE EXCEPTION 'Price book end date precedes start date' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pos_products WHERE id = p_product_id AND tenant_id = p_tenant_id AND is_active = true) THEN
    RAISE EXCEPTION 'Product does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  IF p_outlet_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_outlet_id AND tenant_id = p_tenant_id) THEN
    RAISE EXCEPTION 'Outlet does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_price_books(tenant_id, name, customer_segment, outlet_id, starts_at, ends_at, priority, created_by)
  VALUES (p_tenant_id, trim(p_name), p_customer_segment, p_outlet_id, p_starts_at, p_ends_at, COALESCE(p_priority, 0), auth.uid())
  RETURNING id INTO v_book_id;
  INSERT INTO public.pos_price_book_items(price_book_id, product_id, variant_id, price)
  VALUES (v_book_id, p_product_id, p_variant_id, p_price);
  RETURN v_book_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_pos_price_book(uuid, text, text, uuid, timestamptz, timestamptz, integer, uuid, uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_price_book(uuid, text, text, uuid, timestamptz, timestamptz, integer, uuid, uuid, numeric) TO authenticated;

-- ===== END SOURCE: 20260827090000_atomic_pricebook_admin_rpc.sql =====

-- ===== BEGIN SOURCE: 20260827100000_refund_approval_workflow_rpc.sql =====
CREATE OR REPLACE FUNCTION public.decide_refund_request(
  p_request_id uuid,
  p_approve boolean,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_request public.refund_requests%ROWTYPE;
  v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Refund approval denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_request FROM public.refund_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Refund request not found' USING ERRCODE = 'P0002'; END IF;
  IF upper(COALESCE(v_request.status, '')) <> 'PENDING' THEN
    RAISE EXCEPTION 'Refund request is no longer pending' USING ERRCODE = '55000';
  END IF;
  v_status := CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END;
  UPDATE public.refund_requests
  SET status = v_status,
      admin_notes = NULLIF(trim(p_notes), ''),
      processed_at = now()
  WHERE id = p_request_id;
  RETURN jsonb_build_object('id', p_request_id, 'status', v_status, 'processed_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.decide_refund_request(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_refund_request(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260827100000_refund_approval_workflow_rpc.sql =====

-- ===== BEGIN SOURCE: 20260827110000_atomic_stock_transfer_approval.sql =====
CREATE OR REPLACE FUNCTION public.create_pos_stock_transfer(
  p_tenant_id uuid,
  p_transfer_number text,
  p_from_outlet_id uuid,
  p_to_outlet_id uuid,
  p_notes text,
  p_items jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_transfer_id uuid;
  v_item jsonb;
  v_product public.pos_products%ROWTYPE;
  v_qty numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true
    UNION ALL SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  ) THEN RAISE EXCEPTION 'Transfer creation denied' USING ERRCODE = '42501'; END IF;
  IF p_from_outlet_id = p_to_outlet_id OR NULLIF(trim(p_transfer_number), '') IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid stock transfer' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_from_outlet_id AND tenant_id = p_tenant_id)
     OR NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_to_outlet_id AND tenant_id = p_tenant_id) THEN
    RAISE EXCEPTION 'Transfer outlet does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_stock_transfers(tenant_id, transfer_number, from_outlet_id, to_outlet_id, status, notes, requested_by)
  VALUES (p_tenant_id, trim(p_transfer_number), p_from_outlet_id, p_to_outlet_id, 'pending', NULLIF(trim(p_notes), ''), auth.uid())
  RETURNING id INTO v_transfer_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'qty_requested')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid transfer quantity' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_product FROM public.pos_products WHERE id = (v_item->>'product_id')::uuid AND tenant_id = p_tenant_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer product does not belong to tenant' USING ERRCODE = '42501'; END IF;
    INSERT INTO public.pos_stock_transfer_items(transfer_id, product_id, variant_id, product_name, sku, unit, qty_requested, qty_sent, qty_received)
    VALUES (v_transfer_id, v_product.id, NULLIF(v_item->>'variant_id', '')::uuid, v_product.name, v_product.sku, COALESCE(v_product.unit, 'pcs'), v_qty, 0, 0);
  END LOOP;
  RETURN jsonb_build_object('transfer_id', v_transfer_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_stock_transfer(p_transfer_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_transfer public.pos_stock_transfers%ROWTYPE;
BEGIN
  SELECT * INTO v_transfer FROM public.pos_stock_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_transfer.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Transfer approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_transfer.status <> 'pending' THEN RAISE EXCEPTION 'Transfer is no longer pending' USING ERRCODE = '55000'; END IF;
  IF p_approve THEN
    UPDATE public.pos_stock_transfers SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = p_transfer_id;
  ELSE
    UPDATE public.pos_stock_transfers SET status = 'rejected', rejection_reason = COALESCE(NULLIF(trim(p_reason), ''), 'Ditolak supervisor') WHERE id = p_transfer_id;
  END IF;
  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'status', CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END);
END; $$;

CREATE OR REPLACE FUNCTION public.complete_pos_stock_transfer(p_transfer_id uuid, p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_transfer public.pos_stock_transfers%ROWTYPE;
  v_transfer_item public.pos_stock_transfer_items%ROWTYPE;
  v_input jsonb;
  v_source public.pos_stock%ROWTYPE;
  v_destination public.pos_stock%ROWTYPE;
  v_sent numeric;
  v_received numeric;
  v_after numeric;
BEGIN
  SELECT * INTO v_transfer FROM public.pos_stock_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_transfer.tenant_id AND t.user_id = auth.uid()) OR (public.pos_user_can_access_outlet(v_transfer.tenant_id, v_transfer.from_outlet_id) AND public.pos_user_can_access_outlet(v_transfer.tenant_id, v_transfer.to_outlet_id))) THEN
    RAISE EXCEPTION 'Transfer completion denied' USING ERRCODE = '42501';
  END IF;
  IF v_transfer.status <> 'approved' OR jsonb_typeof(p_items) <> 'array' THEN RAISE EXCEPTION 'Transfer is not ready for completion' USING ERRCODE = '55000'; END IF;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_transfer_item FROM public.pos_stock_transfer_items WHERE id = (v_input->>'item_id')::uuid AND transfer_id = p_transfer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer item not found' USING ERRCODE = 'P0002'; END IF;
    v_sent := COALESCE((v_input->>'qty_sent')::numeric, v_transfer_item.qty_requested);
    v_received := COALESCE((v_input->>'qty_received')::numeric, v_sent);
    IF v_sent <= 0 OR v_received < 0 OR v_received > v_sent OR v_sent > v_transfer_item.qty_requested THEN RAISE EXCEPTION 'Invalid transfer receive quantity' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_source FROM public.pos_stock WHERE tenant_id = v_transfer.tenant_id AND outlet_id = v_transfer.from_outlet_id AND product_id = v_transfer_item.product_id AND variant_id IS NOT DISTINCT FROM v_transfer_item.variant_id FOR UPDATE;
    IF NOT FOUND OR v_source.quantity - v_source.reserved_quantity < v_sent THEN RAISE EXCEPTION 'Insufficient source stock for transfer' USING ERRCODE = '23514'; END IF;
    v_after := v_source.quantity - v_sent;
    UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_source.id;
    INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
    VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.from_outlet_id, 'transfer_out', -v_sent, v_source.quantity, v_after, v_transfer.id, 'stock_transfer', 'Atomic transfer keluar', auth.uid());
    SELECT * INTO v_destination FROM public.pos_stock WHERE tenant_id = v_transfer.tenant_id AND outlet_id = v_transfer.to_outlet_id AND product_id = v_transfer_item.product_id AND variant_id IS NOT DISTINCT FROM v_transfer_item.variant_id FOR UPDATE;
    IF FOUND THEN
      v_after := v_destination.quantity + v_received;
      UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_destination.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.to_outlet_id, 'transfer_in', v_received, v_destination.quantity, v_after, v_transfer.id, 'stock_transfer', 'Atomic transfer masuk', auth.uid());
    ELSE
      INSERT INTO public.pos_stock(tenant_id, product_id, variant_id, outlet_id, quantity, min_stock) VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.to_outlet_id, v_received, 0);
    END IF;
    UPDATE public.pos_stock_transfer_items SET qty_sent = v_sent, qty_received = v_received WHERE id = v_transfer_item.id;
  END LOOP;
  UPDATE public.pos_stock_transfers SET status = 'completed', completed_by = auth.uid(), completed_at = now() WHERE id = p_transfer_id;
  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'status', 'completed');
END; $$;

REVOKE ALL ON FUNCTION public.create_pos_stock_transfer(uuid, text, uuid, uuid, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_stock_transfer(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_pos_stock_transfer(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_stock_transfer(uuid, text, uuid, uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_stock_transfer(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_pos_stock_transfer(uuid, jsonb) TO authenticated;

-- ===== END SOURCE: 20260827110000_atomic_stock_transfer_approval.sql =====

-- ===== BEGIN SOURCE: 20260827120000_stock_adjustment_approval_rpc.sql =====
ALTER TABLE public.approval_requests ADD COLUMN IF NOT EXISTS request_context jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.request_pos_stock_adjustment(
  p_stock_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_quantity numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_stock public.pos_stock%ROWTYPE; v_request_id uuid; v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR p_quantity IS NULL OR p_quantity < 0 OR p_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid stock adjustment request' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_stock FROM public.pos_stock WHERE id = p_stock_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;
  v_after := CASE WHEN p_type = 'adjustment' THEN p_quantity ELSE CASE WHEN p_type IN ('initial','purchase','return_sale','transfer_in') THEN v_stock.quantity + p_quantity ELSE v_stock.quantity - p_quantity END END;
  IF v_after < v_stock.reserved_quantity THEN RAISE EXCEPTION 'Adjustment cannot reduce stock below reserved quantity' USING ERRCODE = '23514'; END IF;
  INSERT INTO public.approval_requests(tenant_id, requester_id, request_type, subject_id, requested_amount, reason, request_context)
  VALUES (p_tenant_id, auth.uid(), 'stock_adjustment', p_stock_id, p_quantity, COALESCE(NULLIF(trim(p_notes), ''), 'Stock adjustment requires approval'), jsonb_build_object('type', p_type, 'notes', NULLIF(trim(p_notes), ''), 'outlet_id', p_outlet_id, 'quantity_before', v_stock.quantity, 'quantity_after_requested', v_after))
  RETURNING id INTO v_request_id;
  RETURN jsonb_build_object('request_id', v_request_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_stock_adjustment(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.approval_requests%ROWTYPE; v_stock public.pos_stock%ROWTYPE; v_type text; v_after numeric; v_delta numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Stock adjustment approval denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_request FROM public.approval_requests WHERE id = p_request_id AND request_type = 'stock_adjustment' FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'pending' THEN RAISE EXCEPTION 'Stock adjustment approval is not pending' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.approval_requests SET status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  v_type := v_request.request_context->>'type';
  SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_request.subject_id AND tenant_id = v_request.tenant_id FOR UPDATE;
  IF NOT FOUND OR v_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') THEN RAISE EXCEPTION 'Stock adjustment target is invalid' USING ERRCODE = 'P0002'; END IF;
  v_after := CASE WHEN v_type = 'adjustment' THEN v_request.requested_amount ELSE CASE WHEN v_type IN ('initial','purchase','return_sale','transfer_in') THEN v_stock.quantity + v_request.requested_amount ELSE v_stock.quantity - v_request.requested_amount END END;
  IF v_after < v_stock.reserved_quantity THEN RAISE EXCEPTION 'Adjustment would reduce stock below reserved quantity' USING ERRCODE = '23514'; END IF;
  v_delta := v_after - v_stock.quantity;
  UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
  INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, notes, created_by, reference_id, reference_type)
  VALUES (v_request.tenant_id, v_stock.product_id, v_stock.variant_id, (v_request.request_context->>'outlet_id')::uuid, v_type, v_delta, v_stock.quantity, v_after, COALESCE(NULLIF(trim(p_notes), ''), v_request.reason), auth.uid(), p_request_id, 'stock_adjustment_approval');
  UPDATE public.approval_requests SET status = 'approved', approved_level = required_level, decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'stock_id', v_stock.id, 'quantity_before', v_stock.quantity, 'quantity_after', v_after, 'delta', v_delta);
END; $$;

REVOKE ALL ON FUNCTION public.request_pos_stock_adjustment(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_stock_adjustment(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pos_stock_adjustment(uuid, uuid, uuid, text, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_stock_adjustment(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260827120000_stock_adjustment_approval_rpc.sql =====

-- ===== BEGIN SOURCE: 20260828100000_pwa_device_management.sql =====
CREATE TABLE IF NOT EXISTS public.pwa_device_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  device_name text NOT NULL DEFAULT 'Perangkat PWA',
  device_type text NOT NULL DEFAULT 'browser' CHECK (device_type IN ('browser','pwa','kiosk')),
  platform text,
  user_agent text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','idle','revoked')),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  last_sync_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES auth.users(id),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_pwa_device_sessions_user ON public.pwa_device_sessions(user_id, status, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_pwa_device_sessions_tenant ON public.pwa_device_sessions(tenant_id, status, last_seen_at DESC);
ALTER TABLE public.pwa_device_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own PWA devices" ON public.pwa_device_sessions;
CREATE POLICY "Users view own PWA devices" ON public.pwa_device_sessions FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage PWA devices" ON public.pwa_device_sessions;
CREATE POLICY "Admins manage PWA devices" ON public.pwa_device_sessions FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.register_pwa_device(
  p_device_id text,
  p_device_name text DEFAULT 'Perangkat PWA',
  p_device_type text DEFAULT 'browser',
  p_platform text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_device public.pwa_device_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_device_id), '') IS NULL OR p_device_type NOT IN ('browser','pwa','kiosk') THEN
    RAISE EXCEPTION 'Invalid PWA device registration' USING ERRCODE = '22023';
  END IF;
  IF p_tenant_id IS NOT NULL AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true) OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Device tenant access denied' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pwa_device_sessions(user_id, tenant_id, device_id, device_name, device_type, platform, user_agent, status, last_seen_at, revoked_at, revoked_by)
  VALUES (auth.uid(), p_tenant_id, trim(p_device_id), COALESCE(NULLIF(trim(p_device_name), ''), 'Perangkat PWA'), p_device_type, NULLIF(trim(p_platform), ''), NULLIF(left(p_user_agent, 500), ''), 'active', now(), NULL, NULL)
  ON CONFLICT (user_id, device_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type, platform = EXCLUDED.platform, user_agent = EXCLUDED.user_agent, status = 'active', last_seen_at = now(), revoked_at = NULL, revoked_by = NULL, updated_at = now()
  RETURNING * INTO v_device;
  RETURN v_device;
END; $$;

CREATE OR REPLACE FUNCTION public.heartbeat_pwa_device(p_device_id text, p_sync_at timestamptz DEFAULT NULL)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_device public.pwa_device_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_device FROM public.pwa_device_sessions WHERE user_id = auth.uid() AND device_id = trim(p_device_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'PWA device is not registered' USING ERRCODE = 'P0002'; END IF;
  IF v_device.status <> 'revoked' THEN
    UPDATE public.pwa_device_sessions SET status = 'active', last_seen_at = now(), last_sync_at = COALESCE(p_sync_at, last_sync_at), updated_at = now() WHERE id = v_device.id RETURNING * INTO v_device;
  END IF;
  RETURN v_device;
END; $$;

CREATE OR REPLACE FUNCTION public.revoke_pwa_device(p_device_session_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Device revoke requires admin access' USING ERRCODE = '42501'; END IF;
  UPDATE public.pwa_device_sessions SET status = 'revoked', revoked_at = now(), revoked_by = auth.uid(), updated_at = now() WHERE id = p_device_session_id AND status <> 'revoked';
  IF NOT FOUND THEN RAISE EXCEPTION 'Device not found or already revoked' USING ERRCODE = 'P0002'; END IF;
  RETURN jsonb_build_object('device_id', p_device_session_id, 'status', 'revoked');
END; $$;

REVOKE ALL ON FUNCTION public.register_pwa_device(text, text, text, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.heartbeat_pwa_device(text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_pwa_device(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_pwa_device(text, text, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.heartbeat_pwa_device(text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_pwa_device(uuid) TO authenticated;

-- ===== END SOURCE: 20260828100000_pwa_device_management.sql =====

-- ===== BEGIN SOURCE: 20260829100000_security_privilege_hardening.sql =====
-- SECURITY DEFINER trigger/helper functions must not be callable by browser roles.
-- Their execution is reserved for database triggers or server-side worker paths.
REVOKE ALL ON FUNCTION public.mark_crm_cart_recovered_after_pos_sale() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) FROM PUBLIC, anon, authenticated;

-- Keep the critical transaction functions callable only by authenticated users
-- after their own tenant/outlet checks; service_role retains ownership access.
REVOKE ALL ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) FROM PUBLIC, anon;

-- ===== END SOURCE: 20260829100000_security_privilege_hardening.sql =====

-- ===== BEGIN SOURCE: 20260829110000_legacy_security_definer_hardening.sql =====
-- Harden legacy SECURITY DEFINER functions created before explicit search_path
-- conventions were applied. Trigger functions are not browser APIs.
ALTER FUNCTION public.check_low_quota_alert() SET search_path = public;
ALTER FUNCTION public.increment_product_view(uuid) SET search_path = public;
ALTER FUNCTION public.auto_assign_merchant_to_group() SET search_path = public;
ALTER FUNCTION public.auto_assign_village_admin_role() SET search_path = public;
ALTER FUNCTION public.handle_merchant_approval_role() SET search_path = public;

REVOKE ALL ON FUNCTION public.check_low_quota_alert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_assign_merchant_to_group() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_assign_village_admin_role() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_merchant_approval_role() FROM PUBLIC, anon, authenticated;

-- ===== END SOURCE: 20260829110000_legacy_security_definer_hardening.sql =====

-- ===== BEGIN SOURCE: 20260829120000_subscription_entitlements_usage.sql =====
-- Subscription plans, entitlements, invoices, and usage ledger.
-- Safe to replay: all schema objects and policies are guarded.

CREATE TABLE IF NOT EXISTS public.subscription_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,
  price numeric(15,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  currency text NOT NULL DEFAULT 'IDR' CHECK (char_length(currency) = 3),
  billing_interval text NOT NULL DEFAULT 'monthly' CHECK (billing_interval IN ('monthly', 'quarterly', 'yearly')),
  trial_days integer NOT NULL DEFAULT 0 CHECK (trial_days >= 0 AND trial_days <= 365),
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.merchant_subscriptions
  ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES public.subscription_plans(id),
  ADD COLUMN IF NOT EXISTS cancel_reason text,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_plan ON public.merchant_subscriptions(plan_id);
CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_active_merchant
  ON public.merchant_subscriptions(merchant_id, status, expired_at DESC);

CREATE TABLE IF NOT EXISTS public.subscription_plan_entitlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES public.subscription_plans(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  entitlement_type text NOT NULL DEFAULT 'limit' CHECK (entitlement_type IN ('boolean', 'limit', 'metered')),
  enabled boolean NOT NULL DEFAULT true,
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  unit text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (plan_id, feature_key)
);

CREATE TABLE IF NOT EXISTS public.merchant_subscription_entitlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  unit text,
  source text NOT NULL DEFAULT 'override' CHECK (source IN ('override', 'support', 'migration')),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key),
  CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_merchant_entitlements_active
  ON public.merchant_subscription_entitlements(subscription_id, feature_key, starts_at, ends_at);

CREATE TABLE IF NOT EXISTS public.subscription_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  provider text,
  provider_invoice_id text,
  invoice_number text,
  amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  currency text NOT NULL DEFAULT 'IDR' CHECK (char_length(currency) = 3),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'open', 'paid', 'void', 'uncollectible', 'failed')),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  due_at timestamptz,
  paid_at timestamptz,
  hosted_invoice_url text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_invoice_id),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_subscription_invoices_subscription
  ON public.subscription_invoices(subscription_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.subscription_usage_counters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  used_quantity numeric(20,4) NOT NULL DEFAULT 0 CHECK (used_quantity >= 0),
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key, period_start, period_end),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_usage_counters_merchant_period
  ON public.subscription_usage_counters(merchant_id, feature_key, period_start, period_end);

CREATE TABLE IF NOT EXISTS public.subscription_usage_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  quantity numeric(20,4) NOT NULL CHECK (quantity > 0),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  idempotency_key text NOT NULL,
  source_type text NOT NULL DEFAULT 'application',
  source_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key, idempotency_key),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_usage_ledger_merchant_created
  ON public.subscription_usage_ledger(merchant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_ledger_feature_period
  ON public.subscription_usage_ledger(subscription_id, feature_key, period_start, period_end, created_at DESC);

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plan_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_subscription_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_usage_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_usage_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users view active subscription plans" ON public.subscription_plans;
CREATE POLICY "Authenticated users view active subscription plans"
  ON public.subscription_plans FOR SELECT TO authenticated
  USING (is_active OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage subscription plans" ON public.subscription_plans;
CREATE POLICY "Admins manage subscription plans"
  ON public.subscription_plans FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Authenticated users view plan entitlements" ON public.subscription_plan_entitlements;
CREATE POLICY "Authenticated users view plan entitlements"
  ON public.subscription_plan_entitlements FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.subscription_plans p WHERE p.id = plan_id AND (p.is_active OR public.is_admin())));
DROP POLICY IF EXISTS "Admins manage plan entitlements" ON public.subscription_plan_entitlements;
CREATE POLICY "Admins manage plan entitlements"
  ON public.subscription_plan_entitlements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own subscription entitlements" ON public.merchant_subscription_entitlements;
CREATE POLICY "Merchants view own subscription entitlements"
  ON public.merchant_subscription_entitlements FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage merchant subscription entitlements" ON public.merchant_subscription_entitlements;
CREATE POLICY "Admins manage merchant subscription entitlements"
  ON public.merchant_subscription_entitlements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own subscription invoices" ON public.subscription_invoices;
CREATE POLICY "Merchants view own subscription invoices"
  ON public.subscription_invoices FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage subscription invoices" ON public.subscription_invoices;
CREATE POLICY "Admins manage subscription invoices"
  ON public.subscription_invoices FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own usage counters" ON public.subscription_usage_counters;
CREATE POLICY "Merchants view own usage counters"
  ON public.subscription_usage_counters FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage usage counters" ON public.subscription_usage_counters;
CREATE POLICY "Admins manage usage counters"
  ON public.subscription_usage_counters FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own usage ledger" ON public.subscription_usage_ledger;
CREATE POLICY "Merchants view own usage ledger"
  ON public.subscription_usage_ledger FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage usage ledger" ON public.subscription_usage_ledger;
CREATE POLICY "Admins manage usage ledger"
  ON public.subscription_usage_ledger FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.consume_subscription_usage(
  p_merchant_id uuid,
  p_feature_key text,
  p_quantity numeric,
  p_idempotency_key text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_source_type text DEFAULT 'application',
  p_source_id text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.merchant_subscriptions%ROWTYPE;
  v_plan_limit bigint;
  v_override_limit bigint;
  v_enabled boolean;
  v_used numeric(20,4);
  v_counter public.subscription_usage_counters%ROWTYPE;
  v_ledger_id uuid;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(trim(p_feature_key), '') IS NULL OR p_quantity IS NULL OR p_quantity <= 0 OR NULLIF(trim(p_idempotency_key), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid subscription usage request' USING ERRCODE = '22023';
  END IF;
  IF p_period_end <= p_period_start THEN
    RAISE EXCEPTION 'Usage period is invalid' USING ERRCODE = '22023';
  END IF;
  IF auth.role() <> 'service_role' AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Subscription usage access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_subscription
  FROM public.merchant_subscriptions ms
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status IN ('ACTIVE', 'PAST_DUE')
    AND (ms.status = 'ACTIVE' OR ms.grace_period_until IS NULL OR ms.grace_period_until > now())
    AND (ms.expired_at IS NULL OR ms.expired_at > now())
  ORDER BY ms.current_period_end DESC NULLS LAST, ms.expired_at DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active subscription found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_subscription.id::text || ':' || p_feature_key || ':' || p_idempotency_key, 0));
  SELECT id, quantity INTO v_ledger_id, v_used
  FROM public.subscription_usage_ledger
  WHERE subscription_id = v_subscription.id AND feature_key = p_feature_key AND idempotency_key = p_idempotency_key;
  IF v_ledger_id IS NOT NULL THEN
    RETURN jsonb_build_object('accepted', true, 'idempotent', true, 'ledger_id', v_ledger_id, 'quantity', v_used);
  END IF;

  SELECT spe.enabled, spe.limit_value INTO v_enabled, v_override_limit
  FROM public.merchant_subscription_entitlements spe
  WHERE spe.subscription_id = v_subscription.id
    AND spe.feature_key = p_feature_key
    AND spe.starts_at <= now()
    AND (spe.ends_at IS NULL OR spe.ends_at > now());
  IF NOT FOUND THEN
    SELECT spe.enabled, spe.limit_value INTO v_enabled, v_plan_limit
    FROM public.subscription_plan_entitlements spe
    WHERE spe.plan_id = v_subscription.plan_id AND spe.feature_key = p_feature_key;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Feature is not included in subscription' USING ERRCODE = '42501';
    END IF;
  END IF;
  IF COALESCE(v_enabled, false) = false THEN
    RAISE EXCEPTION 'Feature is disabled for subscription' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.subscription_usage_counters(subscription_id, merchant_id, feature_key, period_start, period_end, limit_value)
  VALUES (v_subscription.id, p_merchant_id, p_feature_key, p_period_start, p_period_end, COALESCE(v_override_limit, v_plan_limit))
  ON CONFLICT (subscription_id, feature_key, period_start, period_end) DO NOTHING;
  SELECT * INTO v_counter
  FROM public.subscription_usage_counters
  WHERE subscription_id = v_subscription.id AND feature_key = p_feature_key AND period_start = p_period_start AND period_end = p_period_end
  FOR UPDATE;

  IF v_counter.limit_value IS NOT NULL AND v_counter.used_quantity + p_quantity > v_counter.limit_value THEN
    RAISE EXCEPTION 'Subscription usage limit exceeded' USING ERRCODE = '54000';
  END IF;

  UPDATE public.subscription_usage_counters
  SET used_quantity = used_quantity + p_quantity, updated_at = now()
  WHERE id = v_counter.id;
  INSERT INTO public.subscription_usage_ledger(subscription_id, merchant_id, feature_key, quantity, period_start, period_end, idempotency_key, source_type, source_id, metadata)
  VALUES (v_subscription.id, p_merchant_id, p_feature_key, p_quantity, p_period_start, p_period_end, p_idempotency_key, COALESCE(NULLIF(trim(p_source_type), ''), 'application'), p_source_id, COALESCE(p_metadata, '{}'::jsonb))
  RETURNING id INTO v_ledger_id;

  RETURN jsonb_build_object('accepted', true, 'idempotent', false, 'ledger_id', v_ledger_id, 'used_quantity', v_counter.used_quantity + p_quantity, 'limit_value', v_counter.limit_value);
END;
$$;

REVOKE ALL ON FUNCTION public.consume_subscription_usage(uuid, text, numeric, text, timestamptz, timestamptz, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_subscription_usage(uuid, text, numeric, text, timestamptz, timestamptz, text, text, jsonb) TO authenticated, service_role;

-- Seed only the plan catalog; entitlements are intentionally explicit and can be managed by admin UI.
INSERT INTO public.subscription_plans (code, name, description, price, billing_interval, trial_days, sort_order)
VALUES
  ('free', 'Free', 'Operasi marketplace dasar', 0, 'monthly', 0, 10),
  ('starter', 'Starter', 'POS dan laporan operasional', 49000, 'monthly', 14, 20),
  ('growth', 'Growth', 'Inventaris, CRM, dan automation', 149000, 'monthly', 14, 30),
  ('pro', 'Pro', 'Multi-outlet, API, dan analytics lanjutan', 399000, 'monthly', 14, 40)
ON CONFLICT (code) DO NOTHING;

DROP TRIGGER IF EXISTS set_subscription_plans_updated_at ON public.subscription_plans;
CREATE TRIGGER set_subscription_plans_updated_at BEFORE UPDATE ON public.subscription_plans
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_plan_entitlements_updated_at ON public.subscription_plan_entitlements;
CREATE TRIGGER set_subscription_plan_entitlements_updated_at BEFORE UPDATE ON public.subscription_plan_entitlements
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_merchant_subscription_entitlements_updated_at ON public.merchant_subscription_entitlements;
CREATE TRIGGER set_merchant_subscription_entitlements_updated_at BEFORE UPDATE ON public.merchant_subscription_entitlements
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_invoices_updated_at ON public.subscription_invoices;
CREATE TRIGGER set_subscription_invoices_updated_at BEFORE UPDATE ON public.subscription_invoices
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_usage_counters_updated_at ON public.subscription_usage_counters;
CREATE TRIGGER set_subscription_usage_counters_updated_at BEFORE UPDATE ON public.subscription_usage_counters
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260829120000_subscription_entitlements_usage.sql =====

-- ===== BEGIN SOURCE: 20260829130000_subscription_entitlement_enforcement.sql =====
-- Subscription entitlement catalog and server-side resolution.
-- Idempotent and safe to replay. Existing merchant overrides always win.

INSERT INTO public.subscription_plan_entitlements (plan_id, feature_key, entitlement_type, enabled, limit_value, unit)
SELECT p.id, v.feature_key, v.entitlement_type, v.enabled, v.limit_value, v.unit
FROM public.subscription_plans p
JOIN (VALUES
  ('free', 'active_products', 'limit', true, 50::bigint, 'items'),
  ('free', 'pos_devices', 'limit', true, 1::bigint, 'devices'),
  ('free', 'whatsapp_messages', 'metered', true, 0::bigint, 'messages/month'),
  ('free', 'warehouses', 'limit', true, 1::bigint, 'warehouses'),
  ('free', 'customer_segments', 'limit', true, 0::bigint, 'segments'),
  ('free', 'api_requests', 'metered', true, 0::bigint, 'requests/month'),
  ('free', 'offline_queue', 'limit', true, 20::bigint, 'transactions'),
  ('free', 'reports_history_days', 'limit', true, 30::bigint, 'days'),
  ('free', 'loyalty_rules', 'limit', true, 1::bigint, 'rules'),
  ('starter', 'active_products', 'limit', true, 300::bigint, 'items'),
  ('starter', 'pos_devices', 'limit', true, 2::bigint, 'devices'),
  ('starter', 'whatsapp_messages', 'metered', true, 500::bigint, 'messages/month'),
  ('starter', 'warehouses', 'limit', true, 1::bigint, 'warehouses'),
  ('starter', 'customer_segments', 'limit', true, 1::bigint, 'segments'),
  ('starter', 'api_requests', 'metered', true, 0::bigint, 'requests/month'),
  ('starter', 'offline_queue', 'limit', true, 100::bigint, 'transactions'),
  ('starter', 'reports_history_days', 'limit', true, 365::bigint, 'days'),
  ('starter', 'loyalty_rules', 'limit', true, 3::bigint, 'rules'),
  ('growth', 'active_products', 'limit', true, 2000::bigint, 'items'),
  ('growth', 'pos_devices', 'limit', true, 5::bigint, 'devices'),
  ('growth', 'whatsapp_messages', 'metered', true, 3000::bigint, 'messages/month'),
  ('growth', 'warehouses', 'limit', true, 2::bigint, 'warehouses'),
  ('growth', 'customer_segments', 'limit', true, 10::bigint, 'segments'),
  ('growth', 'api_requests', 'metered', true, 10000::bigint, 'requests/month'),
  ('growth', 'offline_queue', 'limit', true, 500::bigint, 'transactions'),
  ('growth', 'reports_history_days', 'limit', true, NULL::bigint, 'days'),
  ('growth', 'loyalty_rules', 'limit', true, 10::bigint, 'rules'),
  ('pro', 'active_products', 'limit', true, NULL::bigint, 'items'),
  ('pro', 'pos_devices', 'limit', true, NULL::bigint, 'devices'),
  ('pro', 'whatsapp_messages', 'metered', true, 15000::bigint, 'messages/month'),
  ('pro', 'warehouses', 'limit', true, NULL::bigint, 'warehouses'),
  ('pro', 'customer_segments', 'limit', true, NULL::bigint, 'segments'),
  ('pro', 'api_requests', 'metered', true, 100000::bigint, 'requests/month'),
  ('pro', 'offline_queue', 'limit', true, 2000::bigint, 'transactions'),
  ('pro', 'reports_history_days', 'limit', true, NULL::bigint, 'days'),
  ('pro', 'loyalty_rules', 'limit', true, NULL::bigint, 'rules')
) AS v(plan_code, feature_key, entitlement_type, enabled, limit_value, unit) ON v.plan_code = p.code
ON CONFLICT (plan_id, feature_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_subscription_entitlement(
  p_merchant_id uuid,
  p_feature_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.merchant_subscriptions%ROWTYPE;
  v_enabled boolean;
  v_limit bigint;
  v_unit text;
  v_source text;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(trim(p_feature_key), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid entitlement request' USING ERRCODE = '22023';
  END IF;
  IF auth.role() <> 'service_role' AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Entitlement access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_subscription
  FROM public.merchant_subscriptions ms
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status IN ('ACTIVE', 'PAST_DUE')
    AND (ms.status = 'ACTIVE' OR ms.grace_period_until IS NULL OR ms.grace_period_until > now())
    AND (ms.expired_at IS NULL OR ms.expired_at > now())
  ORDER BY ms.current_period_end DESC NULLS LAST, ms.expired_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('enabled', false, 'limit_value', 0, 'source', 'none');
  END IF;

  SELECT mse.enabled, mse.limit_value, mse.unit, 'override'
  INTO v_enabled, v_limit, v_unit, v_source
  FROM public.merchant_subscription_entitlements mse
  WHERE mse.subscription_id = v_subscription.id
    AND mse.feature_key = p_feature_key
    AND mse.starts_at <= now()
    AND (mse.ends_at IS NULL OR mse.ends_at > now());

  IF NOT FOUND THEN
    SELECT spe.enabled, spe.limit_value, spe.unit, 'plan'
    INTO v_enabled, v_limit, v_unit, v_source
    FROM public.subscription_plan_entitlements spe
    WHERE spe.plan_id = v_subscription.plan_id
      AND spe.feature_key = p_feature_key;
  END IF;

  RETURN jsonb_build_object(
    'enabled', COALESCE(v_enabled, false),
    'limit_value', v_limit,
    'unit', v_unit,
    'source', COALESCE(v_source, 'none'),
    'subscription_id', v_subscription.id,
    'plan_id', v_subscription.plan_id,
    'status', v_subscription.status,
    'grace_period_until', v_subscription.grace_period_until
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_subscription_entitlement(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_subscription_entitlement(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.require_subscription_feature(
  p_merchant_id uuid,
  p_feature_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entitlement jsonb;
BEGIN
  v_entitlement := public.get_subscription_entitlement(p_merchant_id, p_feature_key);
  IF COALESCE((v_entitlement->>'enabled')::boolean, false) = false THEN
    RAISE EXCEPTION 'Feature is not included in active subscription' USING ERRCODE = '42501';
  END IF;
  RETURN v_entitlement;
END;
$$;

REVOKE ALL ON FUNCTION public.require_subscription_feature(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_subscription_feature(uuid, text) TO authenticated, service_role;

-- ===== END SOURCE: 20260829130000_subscription_entitlement_enforcement.sql =====

-- ===== BEGIN SOURCE: 20260829140000_subscription_runtime_enforcement.sql =====
-- Runtime subscription enforcement for PWA devices and WhatsApp delivery.
-- Safe to replay: functions are replaced and grants are deterministic.

CREATE OR REPLACE FUNCTION public.register_pwa_device(
  p_device_id text,
  p_device_name text DEFAULT 'Perangkat PWA',
  p_device_type text DEFAULT 'browser',
  p_platform text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_device public.pwa_device_sessions%ROWTYPE;
  v_merchant_id uuid;
  v_entitlement jsonb;
  v_limit bigint;
  v_active_devices bigint;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_device_id), '') IS NULL OR p_device_type NOT IN ('browser','pwa','kiosk') THEN
    RAISE EXCEPTION 'Invalid PWA device registration' USING ERRCODE = '22023';
  END IF;
  IF p_tenant_id IS NOT NULL AND NOT (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true)
    OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Device tenant access denied' USING ERRCODE = '42501';
  END IF;

  -- Serialize registrations per account so two tabs cannot bypass the device limit.
  PERFORM pg_advisory_xact_lock(hashtextextended('pwa-device:' || auth.uid()::text, 0));
  SELECT * INTO v_device
  FROM public.pwa_device_sessions
  WHERE user_id = auth.uid() AND device_id = trim(p_device_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    SELECT m.id INTO v_merchant_id FROM public.merchants m WHERE m.user_id = auth.uid() LIMIT 1;
    SELECT count(*) INTO v_active_devices
    FROM public.pwa_device_sessions
    WHERE user_id = auth.uid() AND status <> 'revoked';

    -- Accounts without an active subscription retain one basic device.
    v_limit := 1;
    IF v_merchant_id IS NOT NULL THEN
      v_entitlement := public.get_subscription_entitlement(v_merchant_id, 'pos_devices');
      IF COALESCE((v_entitlement->>'subscription_id') IS NOT NULL, false) THEN
        IF COALESCE((v_entitlement->>'enabled')::boolean, false) = false THEN
          RAISE EXCEPTION 'POS device feature is not included in active subscription' USING ERRCODE = '42501';
        END IF;
        v_limit := NULLIF((v_entitlement->>'limit_value')::bigint, 0);
      END IF;
    END IF;
    IF v_limit IS NOT NULL AND v_active_devices >= v_limit THEN
      RAISE EXCEPTION 'POS device limit exceeded' USING ERRCODE = '54000';
    END IF;
  END IF;

  INSERT INTO public.pwa_device_sessions(user_id, tenant_id, device_id, device_name, device_type, platform, user_agent, status, last_seen_at, revoked_at, revoked_by)
  VALUES (auth.uid(), p_tenant_id, trim(p_device_id), COALESCE(NULLIF(trim(p_device_name), ''), 'Perangkat PWA'), p_device_type, NULLIF(trim(p_platform), ''), NULLIF(left(p_user_agent, 500), ''), 'active', now(), NULL, NULL)
  ON CONFLICT (user_id, device_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type, platform = EXCLUDED.platform, user_agent = EXCLUDED.user_agent, status = 'active', last_seen_at = now(), revoked_at = NULL, revoked_by = NULL, updated_at = now()
  RETURNING * INTO v_device;
  RETURN v_device;
END; $$;

-- Worker-only bridge: resolve the POS tenant owner to merchant billing identity,
-- then consume exactly once per delivery job.
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
  SELECT m.id INTO v_merchant_id
  FROM public.pos_tenants t
  JOIN public.merchants m ON m.user_id = t.user_id
  WHERE t.id = v_job.tenant_id
  LIMIT 1;
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'WhatsApp delivery merchant mapping is missing' USING ERRCODE = '23503';
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
    jsonb_build_object('job_id', p_job_id, 'tenant_id', v_job.tenant_id, 'recipient_id', v_job.recipient_id)
  );
END; $$;
REVOKE ALL ON FUNCTION public.consume_whatsapp_delivery_usage(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_whatsapp_delivery_usage(uuid) TO service_role;

-- Service-role worker access is explicit; browser clients remain admin-only.
CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job completion requires admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id), last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at), sent_at = CASE WHEN p_success THEN now() ELSE sent_at END, dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$;

REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO service_role, authenticated;

-- ===== END SOURCE: 20260829140000_subscription_runtime_enforcement.sql =====

-- ===== BEGIN SOURCE: 20260829150000_pos_tenant_merchant_mapping.sql =====
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

-- ===== END SOURCE: 20260829150000_pos_tenant_merchant_mapping.sql =====
