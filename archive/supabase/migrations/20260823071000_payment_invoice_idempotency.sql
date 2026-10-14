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
)$bootstrap_sql_6eb0c648451e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6eb0c648451e$;

DO $bootstrap_do_6dad95334edf$
BEGIN
  EXECUTE $bootstrap_sql_6dad95334edf$CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_invoice_requests_key
  ON public.payment_invoice_requests(provider, request_key)$bootstrap_sql_6dad95334edf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6dad95334edf$;

DO $bootstrap_do_a9197d9fc50a$
BEGIN
  EXECUTE $bootstrap_sql_a9197d9fc50a$ALTER TABLE public.payment_invoice_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_a9197d9fc50a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a9197d9fc50a$;

DO $bootstrap_do_9dd2481d44d0$
BEGIN
  EXECUTE $bootstrap_sql_9dd2481d44d0$REVOKE ALL ON public.payment_invoice_requests FROM anon, authenticated$bootstrap_sql_9dd2481d44d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9dd2481d44d0$;

DO $bootstrap_do_d881f9ff7bec$
BEGIN
  EXECUTE $bootstrap_sql_d881f9ff7bec$GRANT ALL ON public.payment_invoice_requests TO service_role$bootstrap_sql_d881f9ff7bec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d881f9ff7bec$;

DO $bootstrap_do_86071855ff22$
BEGIN
  EXECUTE $bootstrap_sql_86071855ff22$CREATE OR REPLACE FUNCTION public.reserve_payment_invoice_request(
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
$$$bootstrap_sql_86071855ff22$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_86071855ff22$;

DO $bootstrap_do_d777625586d6$
BEGIN
  EXECUTE $bootstrap_sql_d777625586d6$REVOKE ALL ON FUNCTION public.reserve_payment_invoice_request(text, uuid, text) FROM PUBLIC, anon, authenticated$bootstrap_sql_d777625586d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d777625586d6$;

DO $bootstrap_do_49090d7103a0$
BEGIN
  EXECUTE $bootstrap_sql_49090d7103a0$GRANT EXECUTE ON FUNCTION public.reserve_payment_invoice_request(text, uuid, text) TO service_role$bootstrap_sql_49090d7103a0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49090d7103a0$;

DO $bootstrap_do_3c5e95bfc443$
BEGIN
  EXECUTE $bootstrap_sql_3c5e95bfc443$
