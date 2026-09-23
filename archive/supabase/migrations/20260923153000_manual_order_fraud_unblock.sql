-- Manual unblock must be explicit, admin-only, and auditable.
CREATE OR REPLACE FUNCTION public.unblock_order_fraud_block(
  p_block_id uuid,
  p_reason text
)
RETURNS public.order_fraud_blocks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_block public.order_fraud_blocks%ROWTYPE;
  v_reason text := NULLIF(trim(p_reason), '');
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can unblock fraud blocks' USING ERRCODE = '42501';
  END IF;
  IF v_reason IS NULL OR length(v_reason) < 10 OR length(v_reason) > 500 THEN
    RAISE EXCEPTION 'Unblock reason must be between 10 and 500 characters' USING ERRCODE = '22023';
  END IF;

  UPDATE public.order_fraud_blocks
  SET blocked_until = now(),
      metadata = metadata || jsonb_build_object(
        'manual_unblock_reason', v_reason,
        'manual_unblocked_by', auth.uid(),
        'manual_unblocked_at', now()
      ),
      updated_at = now()
  WHERE id = p_block_id
  RETURNING * INTO v_block;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fraud block not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_block;
END;
$$;

REVOKE ALL ON FUNCTION public.unblock_order_fraud_block(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_order_fraud_block(uuid, text) TO authenticated;
COMMENT ON FUNCTION public.unblock_order_fraud_block(uuid, text) IS
  'Admin-only manual unblock with mandatory audit reason.';
