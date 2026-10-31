-- Fase 5: operational telemetry for GDC QRIS pilot rollout.
-- Only aggregate operational fields are stored; provider payloads remain in the attempt table.

CREATE TABLE IF NOT EXISTS public.gdc_qris_observability_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id uuid REFERENCES public.gdc_qris_payment_attempts(id) ON DELETE SET NULL,
  event_type text NOT NULL CHECK (event_type IN ('GENERATE_STARTED', 'GENERATE_SUCCEEDED', 'GENERATE_FAILED', 'QUERY_SUCCEEDED', 'QUERY_FAILED', 'CALLBACK_PROCESSED', 'CALLBACK_REJECTED')),
  internal_status text,
  provider_http_status integer,
  duration_ms integer CHECK (duration_ms IS NULL OR duration_ms >= 0),
  error_code text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gdc_qris_observability_created_idx
  ON public.gdc_qris_observability_events(created_at DESC, event_type);
CREATE INDEX IF NOT EXISTS gdc_qris_observability_attempt_idx
  ON public.gdc_qris_observability_events(attempt_id, created_at DESC);

ALTER TABLE public.gdc_qris_observability_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins read GDC observability" ON public.gdc_qris_observability_events;
CREATE POLICY "Admins read GDC observability" ON public.gdc_qris_observability_events
  FOR SELECT TO authenticated USING (public.is_admin());
REVOKE ALL ON public.gdc_qris_observability_events FROM anon, authenticated;
GRANT SELECT ON public.gdc_qris_observability_events TO authenticated;
GRANT ALL ON public.gdc_qris_observability_events TO service_role;

CREATE OR REPLACE FUNCTION public.record_gdc_qris_observability(
  p_attempt_id uuid,
  p_event_type text,
  p_internal_status text DEFAULT NULL,
  p_provider_http_status integer DEFAULT NULL,
  p_duration_ms integer DEFAULT NULL,
  p_error_code text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF p_event_type NOT IN ('GENERATE_STARTED', 'GENERATE_SUCCEEDED', 'GENERATE_FAILED', 'QUERY_SUCCEEDED', 'QUERY_FAILED', 'CALLBACK_PROCESSED', 'CALLBACK_REJECTED') THEN
    RAISE EXCEPTION 'Invalid GDC event type' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.gdc_qris_observability_events(attempt_id, event_type, internal_status, provider_http_status, duration_ms, error_code)
  VALUES (p_attempt_id, p_event_type, NULLIF(left(p_internal_status, 32), ''), p_provider_http_status, p_duration_ms, NULLIF(left(p_error_code, 64), ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_gdc_qris_observability(uuid,text,text,integer,integer,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_gdc_qris_observability(uuid,text,text,integer,integer,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_gdc_qris_rollout_metrics(p_since timestamptz DEFAULT now() - interval '24 hours')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan' USING ERRCODE = '42501'; END IF;
  SELECT jsonb_build_object(
    'since', p_since,
    'generate_started', count(*) FILTER (WHERE event_type = 'GENERATE_STARTED'),
    'generate_succeeded', count(*) FILTER (WHERE event_type = 'GENERATE_SUCCEEDED'),
    'generate_failed', count(*) FILTER (WHERE event_type = 'GENERATE_FAILED'),
    'query_succeeded', count(*) FILTER (WHERE event_type = 'QUERY_SUCCEEDED'),
    'query_failed', count(*) FILTER (WHERE event_type = 'QUERY_FAILED'),
    'callback_processed', count(*) FILTER (WHERE event_type = 'CALLBACK_PROCESSED'),
    'callback_rejected', count(*) FILTER (WHERE event_type = 'CALLBACK_REJECTED'),
    'unique_attempts', count(DISTINCT attempt_id),
    'avg_duration_ms', round(avg(duration_ms) FILTER (WHERE duration_ms IS NOT NULL), 2)
  ) INTO v_result
  FROM public.gdc_qris_observability_events WHERE created_at >= p_since;
  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.get_gdc_qris_rollout_metrics(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_gdc_qris_rollout_metrics(timestamptz) TO authenticated;
