-- Wallet top-up requests. Approval and credit happen in one database transaction.

CREATE TABLE IF NOT EXISTS public.commission_wallet_topup_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_type text NOT NULL CHECK (owner_type IN ('MERCHANT', 'COURIER')),
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE RESTRICT,
  courier_id uuid REFERENCES public.couriers(id) ON DELETE RESTRICT,
  amount_rupiah bigint NOT NULL CHECK (amount_rupiah BETWEEN 10000 AND 1000000000),
  proof_path text NOT NULL CHECK (length(proof_path) BETWEEN 8 AND 1000),
  note text,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
  admin_notes text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commission_wallet_topup_owner_matches_type CHECK (
    (owner_type = 'MERCHANT' AND merchant_id IS NOT NULL AND courier_id IS NULL)
    OR (owner_type = 'COURIER' AND courier_id IS NOT NULL AND merchant_id IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS commission_wallet_topup_status_created_idx
  ON public.commission_wallet_topup_requests (status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS commission_wallet_topup_one_pending_per_owner
  ON public.commission_wallet_topup_requests (owner_type, (COALESCE(merchant_id, courier_id)))
  WHERE status = 'PENDING';

-- Private proof storage. Paths are scoped to the authenticated user's UUID.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('commission-topup-proofs', 'commission-topup-proofs', false, 8388608,
  ARRAY['image/jpeg','image/png','image/webp','application/pdf'])
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS commission_topup_proof_owner_insert ON storage.objects;
CREATE POLICY commission_topup_proof_owner_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'commission-topup-proofs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
DROP POLICY IF EXISTS commission_topup_proof_owner_select ON storage.objects;
CREATE POLICY commission_topup_proof_owner_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'commission-topup-proofs'
    AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin())
  );
DROP POLICY IF EXISTS commission_topup_proof_owner_delete ON storage.objects;

ALTER TABLE public.commission_wallet_topup_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commission_wallet_topup_read_owner_or_admin ON public.commission_wallet_topup_requests;
CREATE POLICY commission_wallet_topup_read_owner_or_admin
  ON public.commission_wallet_topup_requests FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = commission_wallet_topup_requests.merchant_id AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.couriers c
      WHERE c.id = commission_wallet_topup_requests.courier_id AND c.user_id = auth.uid()
    )
  );
REVOKE ALL ON public.commission_wallet_topup_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.commission_wallet_topup_requests TO authenticated;
GRANT ALL ON public.commission_wallet_topup_requests TO service_role;

-- Public catalog gate: reveal only whether the merchant fee mode is active and
-- which requested merchant IDs have a positive, active wallet; never expose balances.
CREATE OR REPLACE FUNCTION public.get_merchant_wallet_gate(p_merchant_ids uuid[])
RETURNS TABLE(is_enabled boolean, merchant_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH mode AS (
    SELECT COALESCE((
      SELECT s.is_enabled
      FROM public.commission_fee_settings s
      WHERE s.owner_type = 'MERCHANT'
    ), false) AS is_enabled
  )
  SELECT mode.is_enabled, eligible.merchant_id
  FROM mode
  LEFT JOIN LATERAL (
    SELECT w.merchant_id
    FROM public.commission_wallets w
    JOIN public.merchants m ON m.id = w.merchant_id
    WHERE mode.is_enabled
      AND w.owner_type = 'MERCHANT'
      AND w.merchant_id = ANY(COALESCE(p_merchant_ids, '{}'::uuid[]))
      AND w.is_active = true
      AND w.balance_rupiah > 0
      AND m.status = 'ACTIVE'
      AND m.registration_status = 'APPROVED'
  ) eligible ON true;
$$;
REVOKE ALL ON FUNCTION public.get_merchant_wallet_gate(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_merchant_wallet_gate(uuid[]) TO anon, authenticated;

-- Explicit fee activation is the merchant cutover switch: stop new tier sales,
-- but keep historical subscription records and read policies intact.
DROP POLICY IF EXISTS "Merchants can create subscriptions" ON public.merchant_subscriptions;
CREATE POLICY "Merchants can create subscriptions"
  ON public.merchant_subscriptions FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_subscriptions.merchant_id AND m.user_id = auth.uid()
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.commission_fee_settings s
      WHERE s.owner_type = 'MERCHANT' AND s.is_enabled = true
    )
  );

-- An uploaded file can be removed only before it is attached to a payment request.
CREATE POLICY commission_topup_proof_owner_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'commission-topup-proofs'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND NOT EXISTS (
      SELECT 1 FROM public.commission_wallet_topup_requests r WHERE r.proof_path = name
    )
  );

-- Caller cannot choose the beneficiary: it is resolved from auth.uid().
CREATE OR REPLACE FUNCTION public.create_commission_wallet_topup_request(
  p_owner_type text,
  p_amount_rupiah bigint,
  p_proof_path text,
  p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage, pg_temp
AS $$
DECLARE
  v_owner_type text := upper(trim(p_owner_type));
  v_owner_id uuid;
  v_request_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login required' USING ERRCODE = '42501';
  END IF;
  IF v_owner_type IS NULL OR v_owner_type NOT IN ('MERCHANT', 'COURIER')
     OR p_amount_rupiah NOT BETWEEN 10000 AND 1000000000
     OR length(trim(COALESCE(p_proof_path, ''))) NOT BETWEEN 8 AND 1000
     OR length(COALESCE(p_note, '')) > 500
     OR split_part(p_proof_path, '/', 1) <> auth.uid()::text THEN
    RAISE EXCEPTION 'permintaan top-up tidak valid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects o
    WHERE o.bucket_id = 'commission-topup-proofs' AND o.name = p_proof_path
  ) THEN
    RAISE EXCEPTION 'bukti pembayaran tidak ditemukan';
  END IF;

  IF v_owner_type = 'MERCHANT' THEN
    SELECT m.id INTO v_owner_id FROM public.merchants m
    WHERE m.user_id = auth.uid() AND m.status = 'ACTIVE' AND m.registration_status = 'APPROVED'
    FOR SHARE;
  ELSE
    SELECT c.id INTO v_owner_id FROM public.couriers c
    WHERE c.user_id = auth.uid() AND c.registration_status = 'APPROVED'
    FOR SHARE;
  END IF;
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'akun pedagang/ojek aktif tidak ditemukan' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.commission_wallet_topup_requests (
    owner_type, merchant_id, courier_id, amount_rupiah, proof_path, note
  ) VALUES (
    v_owner_type,
    CASE WHEN v_owner_type = 'MERCHANT' THEN v_owner_id END,
    CASE WHEN v_owner_type = 'COURIER' THEN v_owner_id END,
    p_amount_rupiah, p_proof_path, NULLIF(trim(p_note), '')
  ) RETURNING id INTO v_request_id;
  RETURN v_request_id;
END;
$$;

-- Locks the request and wallet; approval, balance credit, and ledger entry are atomic.
CREATE OR REPLACE FUNCTION public.process_commission_wallet_topup(
  p_request_id uuid,
  p_approve boolean,
  p_admin_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_request public.commission_wallet_topup_requests%ROWTYPE;
  v_wallet_id uuid;
  v_balance bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'id permintaan top-up wajib diisi';
  END IF;
  IF length(COALESCE(p_admin_notes, '')) > 500 THEN
    RAISE EXCEPTION 'catatan admin maksimal 500 karakter';
  END IF;
  SELECT * INTO v_request
  FROM public.commission_wallet_topup_requests
  WHERE id = p_request_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'permintaan top-up tidak ditemukan'; END IF;

  IF v_request.status <> 'PENDING' THEN
    SELECT w.balance_rupiah INTO v_balance
    FROM public.commission_wallets w
    WHERE (v_request.owner_type = 'MERCHANT' AND w.merchant_id = v_request.merchant_id)
       OR (v_request.owner_type = 'COURIER' AND w.courier_id = v_request.courier_id);
    RETURN jsonb_build_object('status', v_request.status, 'balance_rupiah', v_balance, 'already_processed', true);
  END IF;

  IF p_approve THEN
    IF v_request.owner_type = 'MERCHANT' THEN
      INSERT INTO public.commission_wallets (owner_type, merchant_id)
      VALUES ('MERCHANT', v_request.merchant_id) ON CONFLICT DO NOTHING;
      SELECT id INTO v_wallet_id FROM public.commission_wallets
      WHERE owner_type = 'MERCHANT' AND merchant_id = v_request.merchant_id FOR UPDATE;
    ELSE
      INSERT INTO public.commission_wallets (owner_type, courier_id)
      VALUES ('COURIER', v_request.courier_id) ON CONFLICT DO NOTHING;
      SELECT id INTO v_wallet_id FROM public.commission_wallets
      WHERE owner_type = 'COURIER' AND courier_id = v_request.courier_id FOR UPDATE;
    END IF;
    IF v_wallet_id IS NULL THEN RAISE EXCEPTION 'wallet penerima tidak ditemukan'; END IF;

    UPDATE public.commission_wallets
    SET balance_rupiah = balance_rupiah + v_request.amount_rupiah, updated_at = now()
    WHERE id = v_wallet_id
    RETURNING balance_rupiah INTO v_balance;

    INSERT INTO public.commission_wallet_ledger (
      wallet_id, entry_type, source_type, source_id, idempotency_key,
      amount_delta_rupiah, note, created_by
    ) VALUES (
      v_wallet_id, 'TOPUP', 'PAYMENT', v_request.id,
      'topup-request:' || v_request.id::text,
      v_request.amount_rupiah,
      'Top-up request ' || v_request.id::text,
      auth.uid()
    );
  END IF;

  UPDATE public.commission_wallet_topup_requests
  SET status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
      admin_notes = NULLIF(trim(p_admin_notes), ''),
      reviewed_by = auth.uid(), reviewed_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'status', CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
    'balance_rupiah', v_balance,
    'already_processed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_commission_wallet_topup_request(text, bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_commission_wallet_topup_request(text, bigint, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) TO authenticated;

-- Repeatability marker required by the bootstrap bundle validator.
DO $bootstrap_do_commission_wallet_topups$
BEGIN
  NULL;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_commission_wallet_topups$;
