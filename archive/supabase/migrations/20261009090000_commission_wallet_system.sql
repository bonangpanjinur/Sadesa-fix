-- Wallet saldo rupiah + persentase komisi Merchant/Courier.
-- Target: Supabase PostgreSQL. Migration untuk rollout bertahap; lihat MIGRATION NOTES.
-- Nilai amount memakai BIGINT rupiah bulat; fee dibulatkan ke rupiah terdekat.

-- 1) Satu wallet untuk tiap pedagang atau courier/ojek.
CREATE TABLE IF NOT EXISTS public.commission_wallets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_type text NOT NULL CHECK (owner_type IN ('MERCHANT', 'COURIER')),
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
  courier_id uuid REFERENCES public.couriers(id) ON DELETE CASCADE,
  balance_rupiah bigint NOT NULL DEFAULT 0 CHECK (balance_rupiah >= 0),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commission_wallets_owner_matches_type CHECK (
    (owner_type = 'MERCHANT' AND merchant_id IS NOT NULL AND courier_id IS NULL)
    OR
    (owner_type = 'COURIER' AND courier_id IS NOT NULL AND merchant_id IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS commission_wallets_merchant_uq
  ON public.commission_wallets (merchant_id) WHERE merchant_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS commission_wallets_courier_uq
  ON public.commission_wallets (courier_id) WHERE courier_id IS NOT NULL;

-- Tarif terpisah dan dapat diedit admin. Default 0% untuk mencegah charge sebelum konfigurasi.
CREATE TABLE IF NOT EXISTS public.commission_fee_settings (
  owner_type text PRIMARY KEY CHECK (owner_type IN ('MERCHANT', 'COURIER')),
  fee_percent numeric(7,4) NOT NULL DEFAULT 0
    CHECK (fee_percent >= 0 AND fee_percent <= 100),
  is_enabled boolean NOT NULL DEFAULT false,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.commission_fee_settings (owner_type, fee_percent, is_enabled)
VALUES ('MERCHANT', 0, false), ('COURIER', 0, false)
ON CONFLICT (owner_type) DO NOTHING;

-- Ledger append-only secara kebijakan aplikasi: setiap top up, komisi, refund, atau koreksi adalah satu baris.
-- amount_delta_rupiah positif = kredit; negatif = debit; fee_rate dan base_amount adalah snapshot saat transaksi.
CREATE TABLE IF NOT EXISTS public.commission_wallet_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id uuid NOT NULL REFERENCES public.commission_wallets(id) ON DELETE RESTRICT,
  entry_type text NOT NULL CHECK (entry_type IN ('TOPUP', 'COMMISSION', 'REFUND', 'ADJUSTMENT')),
  source_type text NOT NULL CHECK (source_type IN ('ORDER', 'RIDE', 'PAYMENT', 'ADMIN')),
  source_id uuid,
  idempotency_key text NOT NULL UNIQUE,
  amount_delta_rupiah bigint NOT NULL,
  base_amount_rupiah bigint CHECK (base_amount_rupiah IS NULL OR base_amount_rupiah >= 0),
  fee_percent numeric(7,4) CHECK (fee_percent IS NULL OR (fee_percent >= 0 AND fee_percent <= 100)),
  note text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commission_ledger_type_sign CHECK (
    (entry_type IN ('TOPUP', 'REFUND') AND amount_delta_rupiah > 0)
    OR (entry_type = 'COMMISSION' AND amount_delta_rupiah <= 0)
    OR (entry_type = 'ADJUSTMENT' AND amount_delta_rupiah <> 0)
  )
);

CREATE INDEX IF NOT EXISTS commission_wallet_ledger_wallet_created_idx
  ON public.commission_wallet_ledger (wallet_id, created_at DESC);
CREATE INDEX IF NOT EXISTS commission_wallet_ledger_source_idx
  ON public.commission_wallet_ledger (source_type, source_id);

-- Satu potongan komisi per order/ride, terlepas dari retry dengan idempotency key berbeda.
CREATE UNIQUE INDEX IF NOT EXISTS commission_wallet_ledger_one_fee_per_source
  ON public.commission_wallet_ledger (source_type, source_id)
  WHERE entry_type = 'COMMISSION' AND source_id IS NOT NULL;

-- Buat wallet saat entitas dibuat. Fungsi SECURITY DEFINER memiliki search_path terkunci.
CREATE OR REPLACE FUNCTION public.provision_commission_wallet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_TABLE_NAME = 'merchants' THEN
    INSERT INTO public.commission_wallets (owner_type, merchant_id)
    VALUES ('MERCHANT', NEW.id)
    ON CONFLICT DO NOTHING;
  ELSIF TG_TABLE_NAME = 'couriers' THEN
    INSERT INTO public.commission_wallets (owner_type, courier_id)
    VALUES ('COURIER', NEW.id)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS merchants_provision_commission_wallet ON public.merchants;
CREATE TRIGGER merchants_provision_commission_wallet
AFTER INSERT ON public.merchants
FOR EACH ROW EXECUTE FUNCTION public.provision_commission_wallet();

DROP TRIGGER IF EXISTS couriers_provision_commission_wallet ON public.couriers;
CREATE TRIGGER couriers_provision_commission_wallet
AFTER INSERT ON public.couriers
FOR EACH ROW EXECUTE FUNCTION public.provision_commission_wallet();

-- Provision wallet untuk entitas yang sudah ada.
INSERT INTO public.commission_wallets (owner_type, merchant_id)
SELECT 'MERCHANT', m.id FROM public.merchants m
ON CONFLICT DO NOTHING;
INSERT INTO public.commission_wallets (owner_type, courier_id)
SELECT 'COURIER', c.id FROM public.couriers c
ON CONFLICT DO NOTHING;

-- RPC otoritatif: tidak menerima nilai transaksi atau persentase dari client.
-- Basis merchant = orders.subtotal (bukan shipping_cost).
-- Basis ojek = ride_requests.final_fare.
-- Merchant hanya order DONE/DELIVERED/COMPLETED; ojek hanya ride COMPLETED.
-- Panggil dari trusted backend saat state transaksi menjadi final.
CREATE OR REPLACE FUNCTION public.apply_transaction_commission(
  p_owner_type text,
  p_source_id uuid
)
RETURNS TABLE (
  success boolean,
  already_applied boolean,
  fee_rupiah bigint,
  balance_after_rupiah bigint,
  message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_type text := upper(trim(p_owner_type));
  v_source_type text;
  v_owner_id uuid;
  v_base_amount bigint;
  v_status text;
  v_rate numeric(7,4);
  v_enabled boolean := false;
  v_fee bigint;
  v_wallet_id uuid;
  v_balance bigint;
  v_ledger_id uuid;
BEGIN
  IF p_source_id IS NULL OR v_owner_type NOT IN ('MERCHANT', 'COURIER') THEN
    RAISE EXCEPTION 'owner type atau source id tidak valid';
  END IF;

  -- Mengunci record sumber agar pembatalan/perubahan status tidak beradu dengan fee settlement.
  IF v_owner_type = 'MERCHANT' THEN
    v_source_type := 'ORDER';
    SELECT o.merchant_id, o.subtotal::bigint, o.status
      INTO v_owner_id, v_base_amount, v_status
    FROM public.orders o
    WHERE o.id = p_source_id
    FOR UPDATE;

    IF NOT FOUND OR v_owner_id IS NULL THEN
      RAISE EXCEPTION 'order tidak ditemukan atau tidak memiliki merchant';
    END IF;
    IF upper(v_status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
      RAISE EXCEPTION 'komisi pedagang hanya dapat dipotong dari order selesai';
    END IF;
  ELSE
    v_source_type := 'RIDE';
    SELECT r.driver_id, r.final_fare::bigint, r.status
      INTO v_owner_id, v_base_amount, v_status
    FROM public.ride_requests r
    WHERE r.id = p_source_id
    FOR UPDATE;

    IF NOT FOUND OR v_owner_id IS NULL THEN
      RAISE EXCEPTION 'ride tidak ditemukan atau belum memiliki courier';
    END IF;
    IF v_status <> 'COMPLETED' THEN
      RAISE EXCEPTION 'komisi ojek hanya dapat dipotong dari ride selesai';
    END IF;
  END IF;

  IF v_base_amount IS NULL OR v_base_amount <= 0 THEN
    RAISE EXCEPTION 'nilai dasar komisi harus lebih besar dari nol';
  END IF;

  SELECT s.fee_percent, s.is_enabled
    INTO v_rate, v_enabled
  FROM public.commission_fee_settings s
  WHERE s.owner_type = v_owner_type
  FOR SHARE;

  -- Fee nonaktif tidak menghambat transaksi legacy selama rollout bertahap.
  IF NOT FOUND OR NOT v_enabled THEN
    RETURN QUERY SELECT true, false, 0::bigint, NULL::bigint, 'Komisi sedang nonaktif';
    RETURN;
  END IF;

  -- Pastikan wallet tersedia, termasuk untuk entitas yang dibuat sebelum trigger dipasang.
  IF v_owner_type = 'MERCHANT' THEN
    INSERT INTO public.commission_wallets (owner_type, merchant_id)
    VALUES ('MERCHANT', v_owner_id)
    ON CONFLICT DO NOTHING;
    SELECT w.id INTO v_wallet_id
    FROM public.commission_wallets w
    WHERE w.owner_type = 'MERCHANT' AND w.merchant_id = v_owner_id
    FOR UPDATE;
  ELSE
    INSERT INTO public.commission_wallets (owner_type, courier_id)
    VALUES ('COURIER', v_owner_id)
    ON CONFLICT DO NOTHING;
    SELECT w.id INTO v_wallet_id
    FROM public.commission_wallets w
    WHERE w.owner_type = 'COURIER' AND w.courier_id = v_owner_id
    FOR UPDATE;
  END IF;

  IF v_wallet_id IS NULL THEN
    RAISE EXCEPTION 'wallet tidak ditemukan';
  END IF;

  -- Idempotensi: setelah lock wallet, retry atas sumber yang sama tidak memotong lagi.
  SELECT l.id, w.balance_rupiah
    INTO v_ledger_id, v_balance
  FROM public.commission_wallet_ledger l
  JOIN public.commission_wallets w ON w.id = l.wallet_id
  WHERE l.source_type = v_source_type
    AND l.source_id = p_source_id
    AND l.entry_type = 'COMMISSION';

  IF FOUND THEN
    RETURN QUERY SELECT true, true, -(
      SELECT l.amount_delta_rupiah
      FROM public.commission_wallet_ledger l WHERE l.id = v_ledger_id
    ), v_balance, 'Potongan komisi sudah pernah diterapkan';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.commission_wallets w
    WHERE w.id = v_wallet_id AND w.is_active = true
  ) THEN
    RAISE EXCEPTION 'wallet tidak aktif';
  END IF;

  v_fee := round(v_base_amount::numeric * v_rate / 100)::bigint;
  IF v_fee < 0 THEN
    RAISE EXCEPTION 'hasil komisi tidak valid';
  END IF;

  -- Satu UPDATE bersyarat mengunci dan memeriksa saldo dalam operasi atomik.
  UPDATE public.commission_wallets w
  SET balance_rupiah = w.balance_rupiah - v_fee,
      updated_at = now()
  WHERE w.id = v_wallet_id
    AND w.is_active = true
    AND w.balance_rupiah >= v_fee
  RETURNING w.balance_rupiah INTO v_balance;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, false, v_fee, NULL::bigint,
      'Saldo tidak cukup atau wallet tidak aktif';
    RETURN;
  END IF;

  INSERT INTO public.commission_wallet_ledger (
    wallet_id, entry_type, source_type, source_id, idempotency_key,
    amount_delta_rupiah, base_amount_rupiah, fee_percent, note, created_by
  ) VALUES (
    v_wallet_id, 'COMMISSION', v_source_type, p_source_id,
    'commission:' || v_source_type || ':' || p_source_id::text,
    -v_fee, v_base_amount, v_rate,
    'Komisi ' || v_owner_type || ' atas ' || v_source_type || ' ' || p_source_id::text,
    auth.uid()
  );

  RETURN QUERY SELECT true, false, v_fee, v_balance, 'Komisi berhasil dipotong';
EXCEPTION
  WHEN unique_violation THEN
    -- Unique source key juga mencegah double charge jika ada retry lintas koneksi.
    IF NOT EXISTS (
      SELECT 1 FROM public.commission_wallet_ledger l
      WHERE l.source_type = v_source_type
        AND l.source_id = p_source_id
        AND l.entry_type = 'COMMISSION'
    ) THEN
      RAISE;
    END IF;
    SELECT w.balance_rupiah INTO v_balance
    FROM public.commission_wallets w
    WHERE (v_owner_type = 'MERCHANT' AND w.owner_type = 'MERCHANT' AND w.merchant_id = v_owner_id)
       OR (v_owner_type = 'COURIER' AND w.owner_type = 'COURIER' AND w.courier_id = v_owner_id);
    RETURN QUERY SELECT true, true, NULL::bigint, v_balance,
      'Potongan komisi sudah pernah diterapkan';
END;
$$;

-- Trigger berjalan dalam transaksi perubahan status yang sama. Jika saldo kurang,
-- exception membatalkan perubahan status order/ride juga.
CREATE OR REPLACE FUNCTION public.charge_commission_on_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_type text;
  v_result record;
BEGIN
  IF TG_TABLE_NAME = 'orders' THEN
    IF upper(NEW.status) IN ('DONE', 'DELIVERED', 'COMPLETED')
       AND upper(OLD.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
      v_owner_type := 'MERCHANT';
    END IF;
  ELSIF TG_TABLE_NAME = 'ride_requests' THEN
    IF upper(NEW.status) = 'COMPLETED' AND upper(OLD.status) <> 'COMPLETED' THEN
      v_owner_type := 'COURIER';
    END IF;
  END IF;

  IF v_owner_type IS NOT NULL THEN
    SELECT * INTO v_result
    FROM public.apply_transaction_commission(v_owner_type, NEW.id);
    IF NOT v_result.success THEN
      RAISE EXCEPTION '%', v_result.message USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_charge_commission_after_completion ON public.orders;
CREATE TRIGGER orders_charge_commission_after_completion
AFTER UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.charge_commission_on_completion();

DROP TRIGGER IF EXISTS rides_charge_commission_after_completion ON public.ride_requests;
CREATE TRIGGER rides_charge_commission_after_completion
AFTER UPDATE OF status ON public.ride_requests
FOR EACH ROW EXECUTE FUNCTION public.charge_commission_on_completion();

-- Admin-only wallet credit for verified top-ups / opening balances. Caller must provide
-- a unique external payment reference or adjustment idempotency key.
CREATE OR REPLACE FUNCTION public.admin_credit_commission_wallet(
  p_owner_type text, p_owner_id uuid, p_amount_rupiah bigint,
  p_idempotency_key text, p_note text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_type text := upper(trim(p_owner_type));
  v_wallet_id uuid;
  v_balance bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501'; END IF;
  IF v_owner_type NOT IN ('MERCHANT', 'COURIER') OR p_amount_rupiah <= 0
     OR length(trim(coalesce(p_idempotency_key, ''))) < 8 THEN
    RAISE EXCEPTION 'data top-up tidak valid';
  END IF;

  IF v_owner_type = 'MERCHANT' THEN
    INSERT INTO public.commission_wallets (owner_type, merchant_id)
    VALUES ('MERCHANT', p_owner_id) ON CONFLICT DO NOTHING;
    SELECT id INTO v_wallet_id FROM public.commission_wallets
    WHERE owner_type = 'MERCHANT' AND merchant_id = p_owner_id FOR UPDATE;
  ELSE
    INSERT INTO public.commission_wallets (owner_type, courier_id)
    VALUES ('COURIER', p_owner_id) ON CONFLICT DO NOTHING;
    SELECT id INTO v_wallet_id FROM public.commission_wallets
    WHERE owner_type = 'COURIER' AND courier_id = p_owner_id FOR UPDATE;
  END IF;
  IF v_wallet_id IS NULL THEN RAISE EXCEPTION 'pemilik wallet tidak ditemukan'; END IF;

  SELECT w.balance_rupiah INTO v_balance FROM public.commission_wallets w WHERE w.id = v_wallet_id;
  IF EXISTS (
    SELECT 1 FROM public.commission_wallet_ledger
    WHERE idempotency_key = p_idempotency_key AND wallet_id = v_wallet_id
      AND amount_delta_rupiah = p_amount_rupiah
  ) THEN
    RETURN v_balance;
  ELSIF EXISTS (
    SELECT 1 FROM public.commission_wallet_ledger WHERE idempotency_key = p_idempotency_key
  ) THEN
    RAISE EXCEPTION 'idempotency key sudah digunakan untuk mutasi lain';
  END IF;

  UPDATE public.commission_wallets
  SET balance_rupiah = balance_rupiah + p_amount_rupiah, updated_at = now()
  WHERE id = v_wallet_id
  RETURNING balance_rupiah INTO v_balance;
  INSERT INTO public.commission_wallet_ledger (wallet_id, entry_type, source_type, source_id,
    idempotency_key, amount_delta_rupiah, note, created_by)
  VALUES (v_wallet_id, 'TOPUP', 'PAYMENT', NULL, p_idempotency_key, p_amount_rupiah, p_note, auth.uid());
  RETURN v_balance;
END;
$$;

-- Atur izin konfigurasi: authenticated dapat membaca tarif, hanya admin dapat mengubah.
ALTER TABLE public.commission_fee_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commission_fee_settings_read_authenticated ON public.commission_fee_settings;
CREATE POLICY commission_fee_settings_read_authenticated
  ON public.commission_fee_settings FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS commission_fee_settings_admin_write ON public.commission_fee_settings;
CREATE POLICY commission_fee_settings_admin_write
  ON public.commission_fee_settings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Owner hanya dapat membaca saldo dan ledger miliknya; tidak ada kebijakan UPDATE/INSERT untuk client.
ALTER TABLE public.commission_wallets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commission_wallets_read_owner_or_admin ON public.commission_wallets;
CREATE POLICY commission_wallets_read_owner_or_admin
  ON public.commission_wallets FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR (merchant_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = commission_wallets.merchant_id AND m.user_id = auth.uid()
    ))
    OR (courier_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.couriers c
      WHERE c.id = commission_wallets.courier_id AND c.user_id = auth.uid()
    ))
  );

ALTER TABLE public.commission_wallet_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commission_wallet_ledger_read_owner_or_admin ON public.commission_wallet_ledger;
CREATE POLICY commission_wallet_ledger_read_owner_or_admin
  ON public.commission_wallet_ledger FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.commission_wallets w
      LEFT JOIN public.merchants m ON m.id = w.merchant_id
      LEFT JOIN public.couriers c ON c.id = w.courier_id
      WHERE w.id = commission_wallet_ledger.wallet_id
        AND (m.user_id = auth.uid() OR c.user_id = auth.uid())
    )
  );

GRANT SELECT ON public.commission_fee_settings,
  public.commission_wallets,
  public.commission_wallet_ledger TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.commission_fee_settings TO authenticated;
GRANT ALL ON public.commission_fee_settings,
  public.commission_wallets,
  public.commission_wallet_ledger TO service_role;

-- Hanya trusted backend/service_role boleh mengeksekusi RPC pemotongan.
REVOKE ALL ON FUNCTION public.apply_transaction_commission(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_transaction_commission(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.provision_commission_wallet() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.charge_commission_on_completion() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_credit_commission_wallet(text, uuid, bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_credit_commission_wallet(text, uuid, bigint, text, text) TO authenticated, service_role;


/*
MIGRATION NOTES (wajib diputuskan sebelum production):
1. Draft ini TIDAK mengonversi merchant_subscriptions.transaction_quota/used_quota menjadi uang.
   Tentukan nominal konversi saldo tersisa per akun, lakukan dry-run, simpan saldo pembuka sebagai
   baris ledger ADJUSTMENT dengan idempotency key unik, dan rekonsiliasi totalnya sebelum cutover.
2. Kebijakan basis merchant ditetapkan ke orders.subtotal (tidak termasuk ongkir). Pastikan subtotal
   adalah angka server-validated dan cocok dengan jumlah yang benar-benar dibayar setelah diskon/refund.
3. Courier memakai ride_requests.final_fare dan hanya status COMPLETED. Jika ada fee untuk kurir
   barang (bukan ojek penumpang), tambahkan sumber/entitas bisnis tersendiri; jangan pakai enum RIDE.
4. Fungsi ini hanya melakukan potongan wallet. Panggil di dalam RPC trusted yang mengubah transaksi
   menjadi DONE/COMPLETED dalam transaksi database yang sama. Bila wallet tidak cukup, RPC pemanggil
   harus gagal/rollback penyelesaian atau menerapkan kebijakan saldo negatif yang disepakati.
5. Top-up wajib ditulis lewat alur pembayaran terverifikasi server-side dan mengkredit wallet serta
   memasukkan ledger dalam satu transaksi. Jangan memberi hak INSERT/UPDATE saldo atau ledger ke client.
6. Angka default fee adalah 0% dan is_enabled=false. Admin perlu mengatur serta mengaktifkan tarif
   MERCHANT dan COURIER secara eksplisit sebelum potongan berjalan.
7. Jalankan di staging, uji dua sesi paralel, retry RPC, saldo pas/kurang, order/ride batal, refund,
   perubahan fee bersamaan, RLS, dan pemanggilan non-service_role. Pertimbangkan menambah audit log
   perubahan settings serta proses reversal ledger sebelum peluncuran.
*/
