-- Guard the refund dispute state machine.
-- Admin mediation updates must go through this RPC so terminal refund decisions
-- cannot be overwritten by a direct table update from the UI.

CREATE OR REPLACE FUNCTION public.update_refund_dispute_status(
  p_refund_id uuid,
  p_dispute_status text,
  p_admin_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_refund public.refund_requests%ROWTYPE;
  v_next_status text := upper(trim(COALESCE(p_dispute_status, '')));
  v_notes text := NULLIF(left(trim(COALESCE(p_admin_notes, '')), 2000), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF v_next_status NOT IN ('OPEN', 'IN_MEDIATION', 'CLOSED') THEN
    RAISE EXCEPTION 'Invalid dispute status transition' USING ERRCODE = '22023';
  END IF;
  IF v_next_status = 'CLOSED' AND v_notes IS NULL THEN
    RAISE EXCEPTION 'Closing a dispute requires admin notes' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_refund
  FROM public.refund_requests
  WHERE id = p_refund_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_next_status = 'CLOSED' AND v_refund.status = 'APPROVED'
     AND v_refund.settlement_status <> 'COMPLETED' THEN
    RAISE EXCEPTION 'Refund dispute cannot be closed before settlement completes' USING ERRCODE = '55000';
  END IF;
  IF v_next_status = 'CLOSED'
     AND v_refund.status NOT IN ('APPROVED', 'REJECTED') THEN
    RAISE EXCEPTION 'Only a decided refund dispute can be closed' USING ERRCODE = '55000';
  END IF;
  IF v_next_status <> 'CLOSED'
     AND (v_refund.status IN ('APPROVED', 'REJECTED')
       OR v_refund.dispute_status IN ('RESOLVED_REFUND', 'RESOLVED_REJECTED', 'CLOSED')) THEN
    RAISE EXCEPTION 'Resolved refund dispute cannot be reopened' USING ERRCODE = '55000';
  END IF;
  IF v_refund.dispute_status = 'CLOSED' AND v_next_status = 'CLOSED' THEN
    RETURN jsonb_build_object('id', v_refund.id, 'dispute_status', 'CLOSED');
  END IF;

  UPDATE public.refund_requests
  SET dispute_status = v_next_status,
      admin_notes = COALESCE(v_notes, admin_notes),
      updated_at = now()
  WHERE id = v_refund.id;

  RETURN jsonb_build_object('id', v_refund.id, 'dispute_status', v_next_status);
END;
$$;

REVOKE ALL ON FUNCTION public.update_refund_dispute_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_refund_dispute_status(uuid, text, text) TO authenticated;
