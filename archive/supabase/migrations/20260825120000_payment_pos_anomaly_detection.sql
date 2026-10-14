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
)$bootstrap_sql_d558dab27285$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d558dab27285$;

DO $bootstrap_do_46ba12a51723$
BEGIN
  EXECUTE $bootstrap_sql_46ba12a51723$CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_anomaly_open_subject
  ON public.pos_payment_anomalies(anomaly_type, subject_type, subject_id)
  WHERE status IN ('open','acknowledged')$bootstrap_sql_46ba12a51723$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46ba12a51723$;

DO $bootstrap_do_67b1fd99968a$
BEGIN
  EXECUTE $bootstrap_sql_67b1fd99968a$CREATE INDEX IF NOT EXISTS idx_pos_anomaly_tenant_status
  ON public.pos_payment_anomalies(tenant_id, status, detected_at DESC)$bootstrap_sql_67b1fd99968a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_67b1fd99968a$;

DO $bootstrap_do_40d26d4a901e$
BEGIN
  EXECUTE $bootstrap_sql_40d26d4a901e$ALTER TABLE public.pos_payment_anomalies ENABLE ROW LEVEL SECURITY$bootstrap_sql_40d26d4a901e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40d26d4a901e$;

DO $bootstrap_do_38e51b479f7f$
BEGIN
  EXECUTE $bootstrap_sql_38e51b479f7f$REVOKE ALL ON public.pos_payment_anomalies FROM anon, authenticated$bootstrap_sql_38e51b479f7f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_38e51b479f7f$;

DO $bootstrap_do_101e7bb884c4$
BEGIN
  EXECUTE $bootstrap_sql_101e7bb884c4$GRANT SELECT, UPDATE ON public.pos_payment_anomalies TO authenticated$bootstrap_sql_101e7bb884c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_101e7bb884c4$;

DO $bootstrap_do_1ddb1e5e525a$
BEGIN
  EXECUTE $bootstrap_sql_1ddb1e5e525a$GRANT ALL ON public.pos_payment_anomalies TO service_role$bootstrap_sql_1ddb1e5e525a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ddb1e5e525a$;

DO $bootstrap_do_93502eb0ceb0$
BEGIN
  EXECUTE $bootstrap_sql_93502eb0ceb0$DROP POLICY IF EXISTS "Admins view and manage anomalies" ON public.pos_payment_anomalies$bootstrap_sql_93502eb0ceb0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_93502eb0ceb0$;

DO $bootstrap_do_aef905774aeb$
BEGIN
  EXECUTE $bootstrap_sql_aef905774aeb$CREATE POLICY "Admins view and manage anomalies" ON public.pos_payment_anomalies FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_aef905774aeb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aef905774aeb$;

DO $bootstrap_do_f338186b96b8$
BEGIN
  EXECUTE $bootstrap_sql_f338186b96b8$DROP POLICY IF EXISTS "Tenant owners view anomalies" ON public.pos_payment_anomalies$bootstrap_sql_f338186b96b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f338186b96b8$;

DO $bootstrap_do_56ce037ab9c0$
BEGIN
  EXECUTE $bootstrap_sql_56ce037ab9c0$CREATE POLICY "Tenant owners view anomalies" ON public.pos_payment_anomalies FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_56ce037ab9c0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56ce037ab9c0$;

DO $bootstrap_do_e73be89b6d64$
BEGIN
  EXECUTE $bootstrap_sql_e73be89b6d64$CREATE OR REPLACE FUNCTION public.scan_pos_payment_anomalies(
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
$$$bootstrap_sql_e73be89b6d64$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e73be89b6d64$;

DO $bootstrap_do_aee68f42b509$
BEGIN
  EXECUTE $bootstrap_sql_aee68f42b509$REVOKE ALL ON FUNCTION public.scan_pos_payment_anomalies(uuid, timestamptz) FROM PUBLIC, anon, authenticated$bootstrap_sql_aee68f42b509$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aee68f42b509$;

DO $bootstrap_do_ca07a4ef6b8b$
BEGIN
  EXECUTE $bootstrap_sql_ca07a4ef6b8b$GRANT EXECUTE ON FUNCTION public.scan_pos_payment_anomalies(uuid, timestamptz) TO authenticated$bootstrap_sql_ca07a4ef6b8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca07a4ef6b8b$;

DO $bootstrap_do_9f92ac2d81b4$
BEGIN
  EXECUTE $bootstrap_sql_9f92ac2d81b4$
