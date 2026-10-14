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
)$bootstrap_sql_e807d34a5c5c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e807d34a5c5c$;

DO $bootstrap_do_45f9b02e3383$
BEGIN
  EXECUTE $bootstrap_sql_45f9b02e3383$CREATE INDEX IF NOT EXISTS idx_business_disputes_status ON public.business_disputes(status, priority, created_at DESC)$bootstrap_sql_45f9b02e3383$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_45f9b02e3383$;

DO $bootstrap_do_6952ac137252$
BEGIN
  EXECUTE $bootstrap_sql_6952ac137252$CREATE INDEX IF NOT EXISTS idx_business_disputes_subject ON public.business_disputes(subject_type, subject_id)$bootstrap_sql_6952ac137252$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6952ac137252$;

DO $bootstrap_do_e12af82f7ede$
BEGIN
  EXECUTE $bootstrap_sql_e12af82f7ede$CREATE TABLE IF NOT EXISTS public.approval_requests (
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
)$bootstrap_sql_e12af82f7ede$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e12af82f7ede$;

DO $bootstrap_do_d463916de661$
BEGIN
  EXECUTE $bootstrap_sql_d463916de661$CREATE INDEX IF NOT EXISTS idx_approval_requests_pending ON public.approval_requests(tenant_id, request_type, status, created_at DESC)$bootstrap_sql_d463916de661$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d463916de661$;

DO $bootstrap_do_0a2b3428e15a$
BEGIN
  EXECUTE $bootstrap_sql_0a2b3428e15a$ALTER TABLE public.business_disputes ENABLE ROW LEVEL SECURITY$bootstrap_sql_0a2b3428e15a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a2b3428e15a$;

DO $bootstrap_do_6983937aa824$
BEGIN
  EXECUTE $bootstrap_sql_6983937aa824$ALTER TABLE public.approval_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_6983937aa824$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6983937aa824$;

DO $bootstrap_do_fa133ab60c46$
BEGIN
  EXECUTE $bootstrap_sql_fa133ab60c46$DROP POLICY IF EXISTS "Users create disputes" ON public.business_disputes$bootstrap_sql_fa133ab60c46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa133ab60c46$;

DO $bootstrap_do_a697ed6703eb$
BEGIN
  EXECUTE $bootstrap_sql_a697ed6703eb$CREATE POLICY "Users create disputes" ON public.business_disputes FOR INSERT TO authenticated WITH CHECK (reporter_id = auth.uid())$bootstrap_sql_a697ed6703eb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a697ed6703eb$;

DO $bootstrap_do_396438b026ac$
BEGIN
  EXECUTE $bootstrap_sql_396438b026ac$DROP POLICY IF EXISTS "Participants view disputes" ON public.business_disputes$bootstrap_sql_396438b026ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_396438b026ac$;

DO $bootstrap_do_7558e5691ad7$
BEGIN
  EXECUTE $bootstrap_sql_7558e5691ad7$CREATE POLICY "Participants view disputes" ON public.business_disputes FOR SELECT TO authenticated USING (reporter_id = auth.uid() OR assigned_to = auth.uid() OR public.is_admin())$bootstrap_sql_7558e5691ad7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7558e5691ad7$;

DO $bootstrap_do_1fd96c61a782$
BEGIN
  EXECUTE $bootstrap_sql_1fd96c61a782$DROP POLICY IF EXISTS "Admins manage disputes" ON public.business_disputes$bootstrap_sql_1fd96c61a782$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1fd96c61a782$;

DO $bootstrap_do_2851a2342584$
BEGIN
  EXECUTE $bootstrap_sql_2851a2342584$CREATE POLICY "Admins manage disputes" ON public.business_disputes FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_2851a2342584$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2851a2342584$;

DO $bootstrap_do_0b5243b697d3$
BEGIN
  EXECUTE $bootstrap_sql_0b5243b697d3$DROP POLICY IF EXISTS "Tenant users view approvals" ON public.approval_requests$bootstrap_sql_0b5243b697d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b5243b697d3$;

DO $bootstrap_do_601ad2b15af1$
BEGIN
  EXECUTE $bootstrap_sql_601ad2b15af1$CREATE POLICY "Tenant users view approvals" ON public.approval_requests FOR SELECT TO authenticated USING (requester_id = auth.uid() OR public.is_admin() OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true))$bootstrap_sql_601ad2b15af1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_601ad2b15af1$;

DO $bootstrap_do_f45d2b55ea0d$
BEGIN
  EXECUTE $bootstrap_sql_f45d2b55ea0d$DROP POLICY IF EXISTS "Users create approvals" ON public.approval_requests$bootstrap_sql_f45d2b55ea0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f45d2b55ea0d$;

DO $bootstrap_do_025e2d655389$
BEGIN
  EXECUTE $bootstrap_sql_025e2d655389$CREATE POLICY "Users create approvals" ON public.approval_requests FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid())$bootstrap_sql_025e2d655389$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_025e2d655389$;

DO $bootstrap_do_230563e8533d$
BEGIN
  EXECUTE $bootstrap_sql_230563e8533d$DROP POLICY IF EXISTS "Admins manage approvals" ON public.approval_requests$bootstrap_sql_230563e8533d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_230563e8533d$;

DO $bootstrap_do_aa5eaa0cca85$
BEGIN
  EXECUTE $bootstrap_sql_aa5eaa0cca85$CREATE POLICY "Admins manage approvals" ON public.approval_requests FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_aa5eaa0cca85$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa5eaa0cca85$;

DO $bootstrap_do_e376eeb51468$
BEGIN
  EXECUTE $bootstrap_sql_e376eeb51468$CREATE OR REPLACE FUNCTION public.decide_approval_request(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
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
END; $$$bootstrap_sql_e376eeb51468$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e376eeb51468$;

DO $bootstrap_do_d2fb8f936a19$
BEGIN
  EXECUTE $bootstrap_sql_d2fb8f936a19$REVOKE ALL ON FUNCTION public.decide_approval_request(uuid, boolean, text) FROM PUBLIC, anon$bootstrap_sql_d2fb8f936a19$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d2fb8f936a19$;

DO $bootstrap_do_c3081d168aa9$
BEGIN
  EXECUTE $bootstrap_sql_c3081d168aa9$GRANT EXECUTE ON FUNCTION public.decide_approval_request(uuid, boolean, text) TO authenticated$bootstrap_sql_c3081d168aa9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c3081d168aa9$;

DO $bootstrap_do_d368ad88f3fe$
BEGIN
  EXECUTE $bootstrap_sql_d368ad88f3fe$
