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
)$bootstrap_sql_b3e29ef0dee6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b3e29ef0dee6$;

DO $bootstrap_do_3513a2b7d99c$
BEGIN
  EXECUTE $bootstrap_sql_3513a2b7d99c$CREATE INDEX IF NOT EXISTS idx_merchant_product_import_jobs_merchant ON public.merchant_product_import_jobs(merchant_id, created_at DESC)$bootstrap_sql_3513a2b7d99c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3513a2b7d99c$;

DO $bootstrap_do_5a6ba2bf3746$
BEGIN
  EXECUTE $bootstrap_sql_5a6ba2bf3746$ALTER TABLE public.merchant_product_import_jobs ENABLE ROW LEVEL SECURITY$bootstrap_sql_5a6ba2bf3746$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a6ba2bf3746$;

DO $bootstrap_do_7dab8554bd3c$
BEGIN
  EXECUTE $bootstrap_sql_7dab8554bd3c$DROP POLICY IF EXISTS "Merchant manages own product import jobs" ON public.merchant_product_import_jobs$bootstrap_sql_7dab8554bd3c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7dab8554bd3c$;

DO $bootstrap_do_802baeeeb1cc$
BEGIN
  EXECUTE $bootstrap_sql_802baeeeb1cc$CREATE POLICY "Merchant manages own product import jobs" ON public.merchant_product_import_jobs FOR ALL TO authenticated USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin())$bootstrap_sql_802baeeeb1cc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_802baeeeb1cc$;

DO $bootstrap_do_e7cd070bb77b$
BEGIN
  EXECUTE $bootstrap_sql_e7cd070bb77b$CREATE OR REPLACE FUNCTION public.commit_merchant_product_import(p_merchant_id uuid, p_rows jsonb, p_validation_errors jsonb DEFAULT '[]'::jsonb)
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
END; $$$bootstrap_sql_e7cd070bb77b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7cd070bb77b$;

DO $bootstrap_do_717e3b792383$
BEGIN
  EXECUTE $bootstrap_sql_717e3b792383$CREATE OR REPLACE FUNCTION public.rollback_merchant_product_import(p_job_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.merchant_product_import_jobs%ROWTYPE; v_deleted integer := 0;
BEGIN
  SELECT * INTO v_job FROM public.merchant_product_import_jobs WHERE id = p_job_id AND (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'committed' THEN RAISE EXCEPTION 'Import rollback not available' USING ERRCODE = '55000'; END IF;
  DELETE FROM public.products WHERE id = ANY(v_job.inserted_product_ids) AND merchant_id = v_job.merchant_id AND created_at >= v_job.committed_at;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  UPDATE public.merchant_product_import_jobs SET status = 'rolled_back', rolled_back_at = now() WHERE id = v_job.id;
  RETURN jsonb_build_object('job_id', p_job_id, 'status', 'rolled_back', 'deleted_count', v_deleted);
END; $$$bootstrap_sql_717e3b792383$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_717e3b792383$;

DO $bootstrap_do_ffd242b10732$
BEGIN
  EXECUTE $bootstrap_sql_ffd242b10732$REVOKE ALL ON FUNCTION public.commit_merchant_product_import(uuid, jsonb, jsonb) FROM PUBLIC, anon$bootstrap_sql_ffd242b10732$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ffd242b10732$;

DO $bootstrap_do_d42ccd6a9055$
BEGIN
  EXECUTE $bootstrap_sql_d42ccd6a9055$REVOKE ALL ON FUNCTION public.rollback_merchant_product_import(uuid) FROM PUBLIC, anon$bootstrap_sql_d42ccd6a9055$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d42ccd6a9055$;

DO $bootstrap_do_a71f3012f2b7$
BEGIN
  EXECUTE $bootstrap_sql_a71f3012f2b7$GRANT EXECUTE ON FUNCTION public.commit_merchant_product_import(uuid, jsonb, jsonb) TO authenticated$bootstrap_sql_a71f3012f2b7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a71f3012f2b7$;

DO $bootstrap_do_780e1ce3e5b1$
BEGIN
  EXECUTE $bootstrap_sql_780e1ce3e5b1$GRANT EXECUTE ON FUNCTION public.rollback_merchant_product_import(uuid) TO authenticated$bootstrap_sql_780e1ce3e5b1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_780e1ce3e5b1$;

DO $bootstrap_do_29238c01ec37$
BEGIN
  EXECUTE $bootstrap_sql_29238c01ec37$
