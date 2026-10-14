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
)$bootstrap_sql_cadb7947d606$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cadb7947d606$;

DO $bootstrap_do_f7d03a3e2b16$
BEGIN
  EXECUTE $bootstrap_sql_f7d03a3e2b16$CREATE TABLE IF NOT EXISTS public.pos_journal_entries (
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
)$bootstrap_sql_f7d03a3e2b16$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f7d03a3e2b16$;

DO $bootstrap_do_532792d897d6$
BEGIN
  EXECUTE $bootstrap_sql_532792d897d6$CREATE TABLE IF NOT EXISTS public.pos_journal_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_entry_id uuid NOT NULL REFERENCES public.pos_journal_entries(id) ON DELETE CASCADE,
  account_code text NOT NULL,
  account_name text NOT NULL,
  debit numeric(15,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit numeric(15,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  tax_profile_id uuid REFERENCES public.pos_tax_profiles(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK ((debit = 0 AND credit > 0) OR (credit = 0 AND debit > 0))
)$bootstrap_sql_532792d897d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_532792d897d6$;

DO $bootstrap_do_9e6f2da8375a$
BEGIN
  EXECUTE $bootstrap_sql_9e6f2da8375a$CREATE INDEX IF NOT EXISTS idx_pos_journal_entries_export ON public.pos_journal_entries(tenant_id, entry_date, status)$bootstrap_sql_9e6f2da8375a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e6f2da8375a$;

DO $bootstrap_do_cb47c4923da8$
BEGIN
  EXECUTE $bootstrap_sql_cb47c4923da8$CREATE INDEX IF NOT EXISTS idx_pos_journal_lines_account ON public.pos_journal_lines(journal_entry_id, account_code)$bootstrap_sql_cb47c4923da8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb47c4923da8$;

DO $bootstrap_do_df5e3064bf50$
BEGIN
  EXECUTE $bootstrap_sql_df5e3064bf50$ALTER TABLE public.pos_tax_profiles ENABLE ROW LEVEL SECURITY$bootstrap_sql_df5e3064bf50$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df5e3064bf50$;

DO $bootstrap_do_2a11bb4013c1$
BEGIN
  EXECUTE $bootstrap_sql_2a11bb4013c1$ALTER TABLE public.pos_journal_entries ENABLE ROW LEVEL SECURITY$bootstrap_sql_2a11bb4013c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a11bb4013c1$;

DO $bootstrap_do_b67a8fb82bf8$
BEGIN
  EXECUTE $bootstrap_sql_b67a8fb82bf8$ALTER TABLE public.pos_journal_lines ENABLE ROW LEVEL SECURITY$bootstrap_sql_b67a8fb82bf8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b67a8fb82bf8$;

DO $bootstrap_do_3ae11a14b190$
BEGIN
  EXECUTE $bootstrap_sql_3ae11a14b190$DROP POLICY IF EXISTS "Tenant owners manage tax profiles" ON public.pos_tax_profiles$bootstrap_sql_3ae11a14b190$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ae11a14b190$;

DO $bootstrap_do_3c701dd31d09$
BEGIN
  EXECUTE $bootstrap_sql_3c701dd31d09$CREATE POLICY "Tenant owners manage tax profiles" ON public.pos_tax_profiles FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_3c701dd31d09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c701dd31d09$;

DO $bootstrap_do_9ad6a3e171ec$
BEGIN
  EXECUTE $bootstrap_sql_9ad6a3e171ec$DROP POLICY IF EXISTS "Tenant users view tax profiles" ON public.pos_tax_profiles$bootstrap_sql_9ad6a3e171ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ad6a3e171ec$;

DO $bootstrap_do_43ec95bad935$
BEGIN
  EXECUTE $bootstrap_sql_43ec95bad935$CREATE POLICY "Tenant users view tax profiles" ON public.pos_tax_profiles FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true))$bootstrap_sql_43ec95bad935$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_43ec95bad935$;

DO $bootstrap_do_539b8a09ff4f$
BEGIN
  EXECUTE $bootstrap_sql_539b8a09ff4f$DROP POLICY IF EXISTS "Tenant users view journals" ON public.pos_journal_entries$bootstrap_sql_539b8a09ff4f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_539b8a09ff4f$;

DO $bootstrap_do_6fb5b7975c0d$
BEGIN
  EXECUTE $bootstrap_sql_6fb5b7975c0d$CREATE POLICY "Tenant users view journals" ON public.pos_journal_entries FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_6fb5b7975c0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6fb5b7975c0d$;

DO $bootstrap_do_6fbb9edc8384$
BEGIN
  EXECUTE $bootstrap_sql_6fbb9edc8384$DROP POLICY IF EXISTS "Tenant users view journal lines" ON public.pos_journal_lines$bootstrap_sql_6fbb9edc8384$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6fbb9edc8384$;

DO $bootstrap_do_b6a4d7fb4c13$
BEGIN
  EXECUTE $bootstrap_sql_b6a4d7fb4c13$CREATE POLICY "Tenant users view journal lines" ON public.pos_journal_lines FOR SELECT TO authenticated USING (journal_entry_id IN (SELECT id FROM public.pos_journal_entries WHERE tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())))$bootstrap_sql_b6a4d7fb4c13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6a4d7fb4c13$;

DO $bootstrap_do_1272f9dd9128$
BEGIN
  EXECUTE $bootstrap_sql_1272f9dd9128$CREATE OR REPLACE FUNCTION public.post_pos_journal_entry(
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
END; $$$bootstrap_sql_1272f9dd9128$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1272f9dd9128$;

DO $bootstrap_do_4fd7ed32f538$
BEGIN
  EXECUTE $bootstrap_sql_4fd7ed32f538$REVOKE ALL ON FUNCTION public.post_pos_journal_entry(uuid, uuid, text, date, text, uuid, text, jsonb) FROM PUBLIC, anon$bootstrap_sql_4fd7ed32f538$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fd7ed32f538$;

DO $bootstrap_do_5c8d486fd7a2$
BEGIN
  EXECUTE $bootstrap_sql_5c8d486fd7a2$GRANT EXECUTE ON FUNCTION public.post_pos_journal_entry(uuid, uuid, text, date, text, uuid, text, jsonb) TO authenticated$bootstrap_sql_5c8d486fd7a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5c8d486fd7a2$;

DO $bootstrap_do_994f3e4d3822$
BEGIN
  EXECUTE $bootstrap_sql_994f3e4d3822$
