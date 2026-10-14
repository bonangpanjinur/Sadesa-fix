-- 1. Perbarui tabel refund_requests dengan kolom baru
ALTER TABLE public.refund_requests
ADD COLUMN IF NOT EXISTS evidence_urls text[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS refund_type text DEFAULT 'FULL'$bootstrap_sql_8962511c5a0c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8962511c5a0c$;

DO $bootstrap_do_4838163b4e07$
BEGIN
  EXECUTE $bootstrap_sql_4838163b4e07$-- 2. Isi data merchant_id untuk data refund yang sudah ada (jika ada)
UPDATE public.refund_requests rr
SET merchant_id = o.merchant_id
FROM public.orders o
WHERE rr.order_id = o.id AND rr.merchant_id IS NULL$bootstrap_sql_4838163b4e07$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4838163b4e07$;

DO $bootstrap_do_9266ef7524a7$
BEGIN
  EXECUTE $bootstrap_sql_9266ef7524a7$-- 3. Tambahkan index untuk performa pencarian merchant
CREATE INDEX IF NOT EXISTS idx_refund_requests_merchant ON public.refund_requests(merchant_id)$bootstrap_sql_9266ef7524a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9266ef7524a7$;

DO $bootstrap_do_d9b774769e59$
BEGIN
  EXECUTE $bootstrap_sql_d9b774769e59$-- 4. Tambahkan kebijakan keamanan (RLS) agar Merchant bisa melihat refund mereka sendiri
DROP POLICY IF EXISTS "Merchants can view own refunds" ON public.refund_requests$bootstrap_sql_d9b774769e59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d9b774769e59$;

DO $bootstrap_do_3422e62e38b1$
BEGIN
  EXECUTE $bootstrap_sql_3422e62e38b1$CREATE POLICY "Merchants can view own refunds" ON public.refund_requests
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = refund_requests.merchant_id
    AND m.user_id = auth.uid()
  )
)$bootstrap_sql_3422e62e38b1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3422e62e38b1$;

DO $bootstrap_do_531f991da00d$
BEGIN
  EXECUTE $bootstrap_sql_531f991da00d$-- 5. Pastikan bucket storage tersedia untuk bukti refund (Opsional jika belum ada)
-- Jalankan ini jika Anda ingin memastikan folder storage bisa diakses
-- INSERT INTO storage.buckets (id, name, public) VALUES ('public_assets', 'public_assets', true) ON CONFLICT (id) DO NOTHING;
