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
