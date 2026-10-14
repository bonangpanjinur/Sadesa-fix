-- ====================================================================
-- MIGRASI: UPDATE LOGIKA PAKET TRANSAKSI (HARGA TETAP & KOMISI PERSEN)
-- ====================================================================

-- 1. Modifikasi tabel transaction_packages
-- Tambahkan kolom total_price dan ubah kas_fee menjadi numerik untuk persentase
ALTER TABLE public.transaction_packages
ADD COLUMN IF NOT EXISTS total_price INTEGER NOT NULL DEFAULT 0,
ALTER COLUMN kas_fee TYPE NUMERIC(5,2)$bootstrap_sql_a741e3720b4d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a741e3720b4d$;

DO $bootstrap_do_cf80aaa16329$
BEGIN
  EXECUTE $bootstrap_sql_cf80aaa16329$-- Update komentar kolom
COMMENT ON COLUMN public.transaction_packages.total_price IS 'Harga total paket yang dibayar oleh merchant'$bootstrap_sql_cf80aaa16329$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf80aaa16329$;

DO $bootstrap_do_0b4b2db7fef7$
BEGIN
  EXECUTE $bootstrap_sql_0b4b2db7fef7$COMMENT ON COLUMN public.transaction_packages.kas_fee IS 'Persentase komisi kelompok/kas (0-100)'$bootstrap_sql_0b4b2db7fef7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b4b2db7fef7$;

DO $bootstrap_do_4f0ec55dfaf8$
BEGIN
  EXECUTE $bootstrap_sql_4f0ec55dfaf8$-- 2. Bersihkan data lama dan masukkan data baru sesuai logika baru
-- Jangan membersihkan data lama: baris ini sengaja menjadi no-op supaya
-- subscription yang mereferensikan paket existing tetap valid saat rerun.
SELECT 1$bootstrap_sql_4f0ec55dfaf8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f0ec55dfaf8$;

DO $bootstrap_do_bbfc5e6a72a3$
BEGIN
  EXECUTE $bootstrap_sql_bbfc5e6a72a3$-- Masukkan data paket dengan harga total dan komisi persen
-- Kita asumsikan harga total adalah (price_per_transaction * quota) dari data sebelumnya
INSERT INTO public.transaction_packages (name, total_price, kas_fee, transaction_quota, validity_days, description, is_active) VALUES
('Paket Hemat', 25000, 10.00, 50, 30, 'Paket dasar untuk pemula dengan masa aktif 30 hari', true),
('Paket Reguler', 45000, 7.50, 100, 30, 'Paket standar untuk usaha menengah dengan masa aktif 30 hari', true),
('Paket Premium', 100000, 5.00, 250, 30, 'Paket terbaik dengan biaya transaksi termurah dengan masa aktif 30 hari', true)
ON CONFLICT DO NOTHING$bootstrap_sql_bbfc5e6a72a3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bbfc5e6a72a3$;

DO $bootstrap_do_3066a8dc2fcd$
BEGIN
  EXECUTE $bootstrap_sql_3066a8dc2fcd$-- 3. Update fungsi merchant_subscriptions jika perlu (biasanya payment_amount diambil dari total_price)
-- Tidak ada perubahan fungsi yang diperlukan di sini jika aplikasi mengambil total_price dari tabel packages saat checkout.
