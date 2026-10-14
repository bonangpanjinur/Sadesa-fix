-- ============================================================
-- FILE 01: FOUNDATION & AUTH
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"$bootstrap_sql_8776a97002c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8776a97002c5$;

DO $bootstrap_do_bc183146c6c5$
BEGIN
  EXECUTE $bootstrap_sql_bc183146c6c5$CREATE EXTENSION IF NOT EXISTS "pgcrypto"$bootstrap_sql_bc183146c6c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bc183146c6c5$;

DO $bootstrap_do_9991e98ca2d7$
BEGIN
  EXECUTE $bootstrap_sql_9991e98ca2d7$DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'buyer', 'verifikator', 'merchant', 'courier', 'admin_desa');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$$bootstrap_sql_9991e98ca2d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9991e98ca2d7$;

DO $bootstrap_do_3d0fccd20e52$
BEGIN
  EXECUTE $bootstrap_sql_3d0fccd20e52$CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$$bootstrap_sql_3d0fccd20e52$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3d0fccd20e52$;

DO $bootstrap_do_f810afd17045$
BEGIN
  EXECUTE $bootstrap_sql_f810afd17045$CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$$bootstrap_sql_f810afd17045$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f810afd17045$;

DO $bootstrap_do_195d0a82e119$
BEGIN
  EXECUTE $bootstrap_sql_195d0a82e119$CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  full_name text NOT NULL DEFAULT '',
  email text, phone text, address text, address_detail text, avatar_url text,
  village text, village_id text, village_name text,
  province_id text, province_name text, city_id text, city_name text,
  district_id text, district_name text,
  trust_score integer DEFAULT 100,
  cod_enabled boolean DEFAULT true,
  cod_fail_count integer DEFAULT 0,
  is_verified_buyer boolean DEFAULT false,
  is_blocked boolean DEFAULT false,
  blocked_by uuid, blocked_at timestamptz, block_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_195d0a82e119$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_195d0a82e119$;

DO $bootstrap_do_67ded035284a$
BEGIN
  EXECUTE $bootstrap_sql_67ded035284a$CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL DEFAULT 'buyer',
  UNIQUE (user_id, role)
)$bootstrap_sql_67ded035284a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_67ded035284a$;

DO $bootstrap_do_0c5f7ec73968$
BEGIN
  EXECUTE $bootstrap_sql_0c5f7ec73968$CREATE TABLE IF NOT EXISTS public.password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  token text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_0c5f7ec73968$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c5f7ec73968$;

DO $bootstrap_do_ae8af2d4b7bd$
BEGIN
  EXECUTE $bootstrap_sql_ae8af2d4b7bd$CREATE TABLE IF NOT EXISTS public.rate_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  identifier text NOT NULL,
  action text NOT NULL,
  count integer DEFAULT 1,
  window_start timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  UNIQUE (identifier, action, window_start)
)$bootstrap_sql_ae8af2d4b7bd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae8af2d4b7bd$;

DO $bootstrap_do_04621554f307$
BEGIN
  EXECUTE $bootstrap_sql_04621554f307$CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON public.profiles(user_id)$bootstrap_sql_04621554f307$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_04621554f307$;

DO $bootstrap_do_6a745f75e6a6$
BEGIN
  EXECUTE $bootstrap_sql_6a745f75e6a6$CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_email ON public.password_reset_tokens(email)$bootstrap_sql_6a745f75e6a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a745f75e6a6$;

DO $bootstrap_do_fda8e94c239e$
BEGIN
  EXECUTE $bootstrap_sql_fda8e94c239e$CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_token ON public.password_reset_tokens(token)$bootstrap_sql_fda8e94c239e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fda8e94c239e$;

DO $bootstrap_do_b66657d5e613$
BEGIN
  EXECUTE $bootstrap_sql_b66657d5e613$GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated$bootstrap_sql_b66657d5e613$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b66657d5e613$;

DO $bootstrap_do_60ce39f882ad$
BEGIN
  EXECUTE $bootstrap_sql_60ce39f882ad$GRANT ALL ON public.profiles TO service_role$bootstrap_sql_60ce39f882ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_60ce39f882ad$;

DO $bootstrap_do_ac8e6f6b16dd$
BEGIN
  EXECUTE $bootstrap_sql_ac8e6f6b16dd$GRANT SELECT ON public.user_roles TO authenticated$bootstrap_sql_ac8e6f6b16dd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ac8e6f6b16dd$;

DO $bootstrap_do_54c0949460f0$
BEGIN
  EXECUTE $bootstrap_sql_54c0949460f0$GRANT ALL ON public.user_roles TO service_role$bootstrap_sql_54c0949460f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_54c0949460f0$;

DO $bootstrap_do_4a048cefcd01$
BEGIN
  EXECUTE $bootstrap_sql_4a048cefcd01$GRANT SELECT, INSERT, UPDATE ON public.password_reset_tokens TO anon, authenticated$bootstrap_sql_4a048cefcd01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a048cefcd01$;

DO $bootstrap_do_431ddbe57e06$
BEGIN
  EXECUTE $bootstrap_sql_431ddbe57e06$GRANT ALL ON public.password_reset_tokens TO service_role$bootstrap_sql_431ddbe57e06$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_431ddbe57e06$;

DO $bootstrap_do_6a0ced678e8b$
BEGIN
  EXECUTE $bootstrap_sql_6a0ced678e8b$GRANT SELECT, INSERT, UPDATE ON public.rate_limits TO authenticated$bootstrap_sql_6a0ced678e8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a0ced678e8b$;

DO $bootstrap_do_d374cb20e1de$
BEGIN
  EXECUTE $bootstrap_sql_d374cb20e1de$GRANT ALL ON public.rate_limits TO service_role$bootstrap_sql_d374cb20e1de$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d374cb20e1de$;

DO $bootstrap_do_4c232d6377ed$
BEGIN
  EXECUTE $bootstrap_sql_4c232d6377ed$ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY$bootstrap_sql_4c232d6377ed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c232d6377ed$;

DO $bootstrap_do_f44537086383$
BEGIN
  EXECUTE $bootstrap_sql_f44537086383$ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY$bootstrap_sql_f44537086383$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f44537086383$;

DO $bootstrap_do_142c809ac4ca$
BEGIN
  EXECUTE $bootstrap_sql_142c809ac4ca$ALTER TABLE public.password_reset_tokens ENABLE ROW LEVEL SECURITY$bootstrap_sql_142c809ac4ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_142c809ac4ca$;

DO $bootstrap_do_7b7561f2df26$
BEGIN
  EXECUTE $bootstrap_sql_7b7561f2df26$ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY$bootstrap_sql_7b7561f2df26$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b7561f2df26$;

DO $bootstrap_do_b1d6d425c016$
BEGIN
  EXECUTE $bootstrap_sql_b1d6d425c016$CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$$bootstrap_sql_b1d6d425c016$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b1d6d425c016$;

DO $bootstrap_do_963eee639efc$
BEGIN
  EXECUTE $bootstrap_sql_963eee639efc$CREATE OR REPLACE FUNCTION public.has_any_role(_user_id uuid, _roles public.app_role[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = ANY(_roles))
$$$bootstrap_sql_963eee639efc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_963eee639efc$;

DO $bootstrap_do_d3134e8a2f9c$
BEGIN
  EXECUTE $bootstrap_sql_d3134e8a2f9c$CREATE OR REPLACE FUNCTION public.get_user_roles(_user_id uuid)
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(array_agg(role::text), ARRAY[]::text[]) FROM public.user_roles WHERE user_id = _user_id
$$$bootstrap_sql_d3134e8a2f9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3134e8a2f9c$;

DO $bootstrap_do_2bec652a40d4$
BEGIN
  EXECUTE $bootstrap_sql_2bec652a40d4$CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin')
$$$bootstrap_sql_2bec652a40d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2bec652a40d4$;

DO $bootstrap_do_fb5698351de1$
BEGIN
  EXECUTE $bootstrap_sql_fb5698351de1$CREATE OR REPLACE FUNCTION public.is_merchant()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$ SELECT public.has_role(auth.uid(), 'merchant') $$$bootstrap_sql_fb5698351de1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb5698351de1$;

DO $bootstrap_do_66701525833b$
BEGIN
  EXECUTE $bootstrap_sql_66701525833b$CREATE OR REPLACE FUNCTION public.is_courier()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$ SELECT public.has_role(auth.uid(), 'courier') $$$bootstrap_sql_66701525833b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_66701525833b$;

DO $bootstrap_do_be34d65a5296$
BEGIN
  EXECUTE $bootstrap_sql_be34d65a5296$CREATE OR REPLACE FUNCTION public.is_verifikator()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$ SELECT public.has_role(auth.uid(), 'verifikator') $$$bootstrap_sql_be34d65a5296$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be34d65a5296$;

DO $bootstrap_do_4b1c3072a1ca$
BEGIN
  EXECUTE $bootstrap_sql_4b1c3072a1ca$CREATE OR REPLACE FUNCTION public.is_admin_desa()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$ SELECT public.has_role(auth.uid(), 'admin_desa') $$$bootstrap_sql_4b1c3072a1ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4b1c3072a1ca$;

DO $bootstrap_do_eca80e9571d6$
BEGIN
  EXECUTE $bootstrap_sql_eca80e9571d6$CREATE OR REPLACE FUNCTION public.check_rate_limit(p_identifier text, p_action text, p_max_requests integer DEFAULT 10, p_window_seconds integer DEFAULT 60)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_window_start timestamptz; v_current_count integer;
BEGIN
  v_window_start := date_trunc('minute', now());
  SELECT count INTO v_current_count FROM public.rate_limits WHERE identifier = p_identifier AND action = p_action AND window_start = v_window_start;
  IF v_current_count IS NULL THEN
    INSERT INTO public.rate_limits (identifier, action, count, window_start) VALUES (p_identifier, p_action, 1, v_window_start)
    ON CONFLICT (identifier, action, window_start) DO UPDATE SET count = rate_limits.count + 1;
    RETURN jsonb_build_object('allowed', true, 'remaining', p_max_requests - 1);
  END IF;
  IF v_current_count >= p_max_requests THEN RETURN jsonb_build_object('allowed', false, 'remaining', 0, 'retry_after', p_window_seconds); END IF;
  UPDATE public.rate_limits SET count = count + 1 WHERE identifier = p_identifier AND action = p_action AND window_start = v_window_start;
  RETURN jsonb_build_object('allowed', true, 'remaining', p_max_requests - v_current_count - 1);
END; $$$bootstrap_sql_eca80e9571d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eca80e9571d6$;

DO $bootstrap_do_6f5e0ef92b09$
BEGIN
  EXECUTE $bootstrap_sql_6f5e0ef92b09$CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  INSERT INTO public.profiles (user_id, full_name, email)
  VALUES (NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    NEW.email)
  ON CONFLICT (user_id) DO UPDATE SET full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'buyer')
  ON CONFLICT (user_id, role) DO NOTHING;
  RETURN NEW;
END; $$$bootstrap_sql_6f5e0ef92b09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f5e0ef92b09$;

DO $bootstrap_do_7f190ea594ef$
BEGIN
  EXECUTE $bootstrap_sql_7f190ea594ef$DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users$bootstrap_sql_7f190ea594ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f190ea594ef$;

DO $bootstrap_do_b03352950c64$
BEGIN
  EXECUTE $bootstrap_sql_b03352950c64$CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user()$bootstrap_sql_b03352950c64$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b03352950c64$;

DO $bootstrap_do_da1b97c8b471$
BEGIN
  EXECUTE $bootstrap_sql_da1b97c8b471$DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles$bootstrap_sql_da1b97c8b471$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_da1b97c8b471$;

DO $bootstrap_do_7764ba2de5d1$
BEGIN
  EXECUTE $bootstrap_sql_7764ba2de5d1$CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_7764ba2de5d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7764ba2de5d1$;

DO $bootstrap_do_2c76a30bbf0a$
BEGIN
  EXECUTE $bootstrap_sql_2c76a30bbf0a$DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles$bootstrap_sql_2c76a30bbf0a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c76a30bbf0a$;

DO $bootstrap_do_e7207efbec26$
BEGIN
  EXECUTE $bootstrap_sql_e7207efbec26$CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = user_id OR public.is_admin())$bootstrap_sql_e7207efbec26$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7207efbec26$;

DO $bootstrap_do_44772f5e936b$
BEGIN
  EXECUTE $bootstrap_sql_44772f5e936b$DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles$bootstrap_sql_44772f5e936b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44772f5e936b$;

DO $bootstrap_do_7bf1962e5f58$
BEGIN
  EXECUTE $bootstrap_sql_7bf1962e5f58$CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = user_id)$bootstrap_sql_7bf1962e5f58$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7bf1962e5f58$;

DO $bootstrap_do_19ca338b3f2d$
BEGIN
  EXECUTE $bootstrap_sql_19ca338b3f2d$DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles$bootstrap_sql_19ca338b3f2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19ca338b3f2d$;

DO $bootstrap_do_f3d155e3abce$
BEGIN
  EXECUTE $bootstrap_sql_f3d155e3abce$CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = user_id AND is_blocked = false)$bootstrap_sql_f3d155e3abce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3d155e3abce$;

DO $bootstrap_do_11937cc2d689$
BEGIN
  EXECUTE $bootstrap_sql_11937cc2d689$DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles$bootstrap_sql_11937cc2d689$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_11937cc2d689$;

DO $bootstrap_do_a9bcd444c3a7$
BEGIN
  EXECUTE $bootstrap_sql_a9bcd444c3a7$CREATE POLICY "Admins can update any profile" ON public.profiles FOR ALL USING (public.is_admin())$bootstrap_sql_a9bcd444c3a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a9bcd444c3a7$;

DO $bootstrap_do_3f90beb316fe$
BEGIN
  EXECUTE $bootstrap_sql_3f90beb316fe$DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles$bootstrap_sql_3f90beb316fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f90beb316fe$;

DO $bootstrap_do_251f82bbd2b3$
BEGIN
  EXECUTE $bootstrap_sql_251f82bbd2b3$CREATE POLICY "Users can view own roles" ON public.user_roles FOR SELECT USING (auth.uid() = user_id)$bootstrap_sql_251f82bbd2b3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_251f82bbd2b3$;

DO $bootstrap_do_0927986d79af$
BEGIN
  EXECUTE $bootstrap_sql_0927986d79af$DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles$bootstrap_sql_0927986d79af$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0927986d79af$;

DO $bootstrap_do_0a4f816fe647$
BEGIN
  EXECUTE $bootstrap_sql_0a4f816fe647$CREATE POLICY "Admins can view all roles" ON public.user_roles FOR SELECT USING (public.is_admin())$bootstrap_sql_0a4f816fe647$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a4f816fe647$;

DO $bootstrap_do_52c93527660c$
BEGIN
  EXECUTE $bootstrap_sql_52c93527660c$DROP POLICY IF EXISTS "Admins can insert user roles" ON public.user_roles$bootstrap_sql_52c93527660c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52c93527660c$;

DO $bootstrap_do_01dc8d0595d9$
BEGIN
  EXECUTE $bootstrap_sql_01dc8d0595d9$CREATE POLICY "Admins can insert user roles" ON public.user_roles FOR INSERT WITH CHECK (public.is_admin())$bootstrap_sql_01dc8d0595d9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_01dc8d0595d9$;

DO $bootstrap_do_c55a02f1cb47$
BEGIN
  EXECUTE $bootstrap_sql_c55a02f1cb47$DROP POLICY IF EXISTS "Admins can update user roles" ON public.user_roles$bootstrap_sql_c55a02f1cb47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c55a02f1cb47$;

DO $bootstrap_do_b4e1ec887474$
BEGIN
  EXECUTE $bootstrap_sql_b4e1ec887474$CREATE POLICY "Admins can update user roles" ON public.user_roles FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_b4e1ec887474$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b4e1ec887474$;

DO $bootstrap_do_9d02f3433358$
BEGIN
  EXECUTE $bootstrap_sql_9d02f3433358$DROP POLICY IF EXISTS "Admins can delete user roles" ON public.user_roles$bootstrap_sql_9d02f3433358$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9d02f3433358$;

DO $bootstrap_do_170ac3e131cb$
BEGIN
  EXECUTE $bootstrap_sql_170ac3e131cb$CREATE POLICY "Admins can delete user roles" ON public.user_roles FOR DELETE USING (public.is_admin())$bootstrap_sql_170ac3e131cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_170ac3e131cb$;

DO $bootstrap_do_b944e3eba9ef$
BEGIN
  EXECUTE $bootstrap_sql_b944e3eba9ef$DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens$bootstrap_sql_b944e3eba9ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b944e3eba9ef$;

DO $bootstrap_do_587eadeee637$
BEGIN
  EXECUTE $bootstrap_sql_587eadeee637$CREATE POLICY "Users can verify their tokens" ON public.password_reset_tokens FOR SELECT TO anon, authenticated USING (true)$bootstrap_sql_587eadeee637$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_587eadeee637$;

DO $bootstrap_do_56d000d5137d$
BEGIN
  EXECUTE $bootstrap_sql_56d000d5137d$DROP POLICY IF EXISTS "Password reset token insert" ON public.password_reset_tokens$bootstrap_sql_56d000d5137d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56d000d5137d$;

DO $bootstrap_do_c7b344fe859a$
BEGIN
  EXECUTE $bootstrap_sql_c7b344fe859a$CREATE POLICY "Password reset token insert" ON public.password_reset_tokens FOR INSERT TO anon, authenticated WITH CHECK (email IS NOT NULL AND token IS NOT NULL AND expires_at > now())$bootstrap_sql_c7b344fe859a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7b344fe859a$;

DO $bootstrap_do_523e3b6407b7$
BEGIN
  EXECUTE $bootstrap_sql_523e3b6407b7$DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens$bootstrap_sql_523e3b6407b7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_523e3b6407b7$;

DO $bootstrap_do_a327382eb097$
BEGIN
  EXECUTE $bootstrap_sql_a327382eb097$CREATE POLICY "Tokens can be marked as used" ON public.password_reset_tokens FOR UPDATE TO anon, authenticated USING (used_at IS NULL AND expires_at > now())$bootstrap_sql_a327382eb097$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a327382eb097$;

DO $bootstrap_do_c371ef1bae6b$
BEGIN
  EXECUTE $bootstrap_sql_c371ef1bae6b$DROP POLICY IF EXISTS "Rate limits managed by functions" ON public.rate_limits$bootstrap_sql_c371ef1bae6b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c371ef1bae6b$;

DO $bootstrap_do_6e0d21bd9de2$
BEGIN
  EXECUTE $bootstrap_sql_6e0d21bd9de2$CREATE POLICY "Rate limits managed by functions" ON public.rate_limits FOR SELECT USING (identifier = auth.uid()::text OR public.is_admin())$bootstrap_sql_6e0d21bd9de2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e0d21bd9de2$;

DO $bootstrap_do_4fec9ed1d032$
BEGIN
  EXECUTE $bootstrap_sql_4fec9ed1d032$DROP POLICY IF EXISTS "Users can insert own rate limits" ON public.rate_limits$bootstrap_sql_4fec9ed1d032$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fec9ed1d032$;

DO $bootstrap_do_0d43d3e4c51f$
BEGIN
  EXECUTE $bootstrap_sql_0d43d3e4c51f$CREATE POLICY "Users can insert own rate limits" ON public.rate_limits FOR INSERT TO authenticated WITH CHECK (identifier = auth.uid()::text)$bootstrap_sql_0d43d3e4c51f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d43d3e4c51f$;

DO $bootstrap_do_b626860897c2$
BEGIN
  EXECUTE $bootstrap_sql_b626860897c2$DROP POLICY IF EXISTS "Users can update own rate limits" ON public.rate_limits$bootstrap_sql_b626860897c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b626860897c2$;

DO $bootstrap_do_5b7a237a2970$
BEGIN
  EXECUTE $bootstrap_sql_5b7a237a2970$CREATE POLICY "Users can update own rate limits" ON public.rate_limits FOR UPDATE TO authenticated USING (identifier = auth.uid()::text)$bootstrap_sql_5b7a237a2970$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5b7a237a2970$;

DO $bootstrap_do_fa8ea2e2e17d$
BEGIN
  EXECUTE $bootstrap_sql_fa8ea2e2e17d$
