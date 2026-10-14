-- 1. Setting kuota gratis
INSERT INTO app_settings (key, value, description, category)
VALUES ('free_tier_quota', '{"limit": 100}', 'Jumlah kuota gratis bulanan untuk merchant baru', 'merchant')
ON CONFLICT (key) DO NOTHING$bootstrap_sql_6aebc3672a53$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6aebc3672a53$;

DO $bootstrap_do_4651f8f5db3e$
BEGIN
  EXECUTE $bootstrap_sql_4651f8f5db3e$-- 2. Setting komisi kurir
INSERT INTO app_settings (key, value, description, category)
VALUES ('courier_commission', '{"percent": 80}', 'Persentase komisi kurir dari ongkir', 'courier')
ON CONFLICT (key) DO NOTHING$bootstrap_sql_4651f8f5db3e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4651f8f5db3e$;

DO $bootstrap_do_dd06165e7bd3$
BEGIN
  EXECUTE $bootstrap_sql_dd06165e7bd3$-- 3. Tabel withdrawal kurir
CREATE TABLE IF NOT EXISTS public.courier_withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID REFERENCES public.couriers(id) NOT NULL,
  amount NUMERIC NOT NULL,
  bank_name TEXT NOT NULL,
  account_number TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  status TEXT DEFAULT 'PENDING',
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
)$bootstrap_sql_dd06165e7bd3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dd06165e7bd3$;

DO $bootstrap_do_ef414169c103$
BEGIN
  EXECUTE $bootstrap_sql_ef414169c103$-- RLS for courier_withdrawal_requests
ALTER TABLE public.courier_withdrawal_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_ef414169c103$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef414169c103$;

DO $bootstrap_do_05fcc3e660aa$
BEGIN
  EXECUTE $bootstrap_sql_05fcc3e660aa$DROP POLICY IF EXISTS "Couriers can view own withdrawals" ON public.courier_withdrawal_requests$bootstrap_sql_05fcc3e660aa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_05fcc3e660aa$;

DO $bootstrap_do_0e79d39b3467$
BEGIN
  EXECUTE $bootstrap_sql_0e79d39b3467$CREATE POLICY "Couriers can view own withdrawals"
ON public.courier_withdrawal_requests FOR SELECT
USING (courier_id = public.get_user_courier_id())$bootstrap_sql_0e79d39b3467$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e79d39b3467$;

DO $bootstrap_do_7986f497c8b5$
BEGIN
  EXECUTE $bootstrap_sql_7986f497c8b5$DROP POLICY IF EXISTS "Couriers can create own withdrawals" ON public.courier_withdrawal_requests$bootstrap_sql_7986f497c8b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7986f497c8b5$;

DO $bootstrap_do_bdc28aa5023f$
BEGIN
  EXECUTE $bootstrap_sql_bdc28aa5023f$CREATE POLICY "Couriers can create own withdrawals"
ON public.courier_withdrawal_requests FOR INSERT
WITH CHECK (courier_id = public.get_user_courier_id())$bootstrap_sql_bdc28aa5023f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bdc28aa5023f$;

DO $bootstrap_do_10b09d6f5147$
BEGIN
  EXECUTE $bootstrap_sql_10b09d6f5147$DROP POLICY IF EXISTS "Admins full access courier withdrawals" ON public.courier_withdrawal_requests$bootstrap_sql_10b09d6f5147$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_10b09d6f5147$;

DO $bootstrap_do_5d8505602cbf$
BEGIN
  EXECUTE $bootstrap_sql_5d8505602cbf$CREATE POLICY "Admins full access courier withdrawals"
ON public.courier_withdrawal_requests FOR ALL
USING (public.is_admin())$bootstrap_sql_5d8505602cbf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d8505602cbf$;

DO $bootstrap_do_267a066dcc1c$
BEGIN
  EXECUTE $bootstrap_sql_267a066dcc1c$-- Trigger updated_at
DROP TRIGGER IF EXISTS update_courier_withdrawal_requests_updated_at ON public.courier_withdrawal_requests$bootstrap_sql_267a066dcc1c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_267a066dcc1c$;

DO $bootstrap_do_e543bdc51575$
BEGIN
  EXECUTE $bootstrap_sql_e543bdc51575$CREATE TRIGGER update_courier_withdrawal_requests_updated_at
BEFORE UPDATE ON public.courier_withdrawal_requests
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_e543bdc51575$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e543bdc51575$;

DO $bootstrap_do_2e2c164f9cdb$
BEGIN
  EXECUTE $bootstrap_sql_2e2c164f9cdb$-- 4. Kolom saldo di couriers
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS available_balance NUMERIC DEFAULT 0$bootstrap_sql_2e2c164f9cdb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2e2c164f9cdb$;

DO $bootstrap_do_fe6a1e3f7a6d$
BEGIN
  EXECUTE $bootstrap_sql_fe6a1e3f7a6d$ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS pending_balance NUMERIC DEFAULT 0$bootstrap_sql_fe6a1e3f7a6d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fe6a1e3f7a6d$;

DO $bootstrap_do_f4e48b6ddae7$
BEGIN
  EXECUTE $bootstrap_sql_f4e48b6ddae7$ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS total_withdrawn NUMERIC DEFAULT 0$bootstrap_sql_f4e48b6ddae7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4e48b6ddae7$;

DO $bootstrap_do_5a9edcef522c$
BEGIN
  EXECUTE $bootstrap_sql_5a9edcef522c$-- 5. Kolom bank di couriers
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS bank_name TEXT$bootstrap_sql_5a9edcef522c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a9edcef522c$;

DO $bootstrap_do_3ea9449a07f0$
BEGIN
  EXECUTE $bootstrap_sql_3ea9449a07f0$ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS bank_account_number TEXT$bootstrap_sql_3ea9449a07f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ea9449a07f0$;

DO $bootstrap_do_c23ccf4e0916$
BEGIN
  EXECUTE $bootstrap_sql_c23ccf4e0916$ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS bank_account_name TEXT$bootstrap_sql_c23ccf4e0916$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c23ccf4e0916$;

DO $bootstrap_do_cd0a39cab9f2$
BEGIN
  EXECUTE $bootstrap_sql_cd0a39cab9f2$
