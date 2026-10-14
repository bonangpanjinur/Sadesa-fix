-- 1. Trigger untuk otomatis mengisi user_id saat pendaftaran merchant (jika belum diisi)
-- Ini memastikan user_id selalu terhubung dengan user yang sedang login
CREATE OR REPLACE FUNCTION public.handle_merchant_user_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER$bootstrap_sql_823c282153de$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_823c282153de$;

DO $bootstrap_do_a8068ad77a93$
BEGIN
  EXECUTE $bootstrap_sql_a8068ad77a93$DROP TRIGGER IF EXISTS on_merchant_signup ON public.merchants$bootstrap_sql_a8068ad77a93$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a8068ad77a93$;

DO $bootstrap_do_7d86bd4ec194$
BEGIN
  EXECUTE $bootstrap_sql_7d86bd4ec194$CREATE TRIGGER on_merchant_signup
  BEFORE INSERT ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_merchant_user_id()$bootstrap_sql_7d86bd4ec194$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7d86bd4ec194$;

DO $bootstrap_do_36a1a855a3e4$
BEGIN
  EXECUTE $bootstrap_sql_36a1a855a3e4$-- 2. Trigger untuk otomatis mengubah role user menjadi 'merchant' saat disetujui
CREATE OR REPLACE FUNCTION public.handle_merchant_approval_role()
RETURNS TRIGGER AS $$
BEGIN
  -- Cek jika status berubah menjadi APPROVED
  IF (NEW.registration_status = 'APPROVED' AND OLD.registration_status != 'APPROVED') THEN
    -- Pastikan user_id ada
    IF NEW.user_id IS NOT NULL THEN
      -- Tambahkan role merchant ke tabel user_roles
      -- Menggunakan ON CONFLICT agar tidak error jika role sudah ada
      INSERT INTO public.user_roles (user_id, role)
      VALUES (NEW.user_id, 'merchant')
      ON CONFLICT (user_id, role) DO NOTHING;

      -- Opsional: Jika ingin menghapus role 'buyer' saat menjadi merchant
      -- DELETE FROM public.user_roles WHERE user_id = NEW.user_id AND role = 'buyer';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER$bootstrap_sql_36a1a855a3e4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_36a1a855a3e4$;

DO $bootstrap_do_c27f9154c03d$
BEGIN
  EXECUTE $bootstrap_sql_c27f9154c03d$DROP TRIGGER IF EXISTS on_merchant_approval ON public.merchants$bootstrap_sql_c27f9154c03d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c27f9154c03d$;

DO $bootstrap_do_f89ea29b15e3$
BEGIN
  EXECUTE $bootstrap_sql_f89ea29b15e3$CREATE TRIGGER on_merchant_approval
  AFTER UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_merchant_approval_role()$bootstrap_sql_f89ea29b15e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f89ea29b15e3$;

DO $bootstrap_do_400e10ebbb1d$
BEGIN
  EXECUTE $bootstrap_sql_400e10ebbb1d$-- 3. Perbaikan RLS Policy agar user bisa mendaftar dengan aman
DROP POLICY IF EXISTS "merchants_register" ON public.merchants$bootstrap_sql_400e10ebbb1d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_400e10ebbb1d$;

DO $bootstrap_do_adf8c92bb049$
BEGIN
  EXECUTE $bootstrap_sql_adf8c92bb049$CREATE POLICY "merchants_register" ON public.merchants
FOR INSERT
WITH CHECK (
  auth.role() = 'authenticated' AND
  (user_id = auth.uid() OR user_id IS NULL) -- Izinkan NULL karena akan diisi oleh trigger
)$bootstrap_sql_adf8c92bb049$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_adf8c92bb049$;

DO $bootstrap_do_87c2c24378c0$
BEGIN
  EXECUTE $bootstrap_sql_87c2c24378c0$
