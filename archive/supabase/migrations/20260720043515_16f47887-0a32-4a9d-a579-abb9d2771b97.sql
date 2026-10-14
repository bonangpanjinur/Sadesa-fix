CREATE TABLE IF NOT EXISTS public.villages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid, name text NOT NULL, province text,
  district text NOT NULL, regency text NOT NULL, subdistrict text,
  description text, image_url text,
  is_active boolean NOT NULL DEFAULT true,
  location_lat numeric, location_lng numeric,
  contact_name text, contact_phone text, contact_email text,
  registration_status text NOT NULL DEFAULT 'PENDING',
  registered_at timestamptz DEFAULT now(),
  approved_at timestamptz, approved_by uuid, rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_63094f7fb85a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63094f7fb85a$;

DO $bootstrap_do_a81f0dbd441c$
BEGIN
  EXECUTE $bootstrap_sql_a81f0dbd441c$CREATE TABLE IF NOT EXISTS public.user_villages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  role text DEFAULT 'admin_desa',
  created_at timestamptz DEFAULT now(),
  UNIQUE (user_id, village_id)
)$bootstrap_sql_a81f0dbd441c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a81f0dbd441c$;

DO $bootstrap_do_8cae031a5758$
BEGIN
  EXECUTE $bootstrap_sql_8cae031a5758$CREATE TABLE IF NOT EXISTS public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL, slug text NOT NULL UNIQUE,
  description text, icon text,
  is_active boolean DEFAULT true, sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now()
)$bootstrap_sql_8cae031a5758$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8cae031a5758$;

DO $bootstrap_do_b503a361e7ad$
BEGIN
  EXECUTE $bootstrap_sql_b503a361e7ad$CREATE TABLE IF NOT EXISTS public.trade_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  village_id uuid REFERENCES public.villages(id) ON DELETE SET NULL,
  verifikator_id uuid NOT NULL,
  monthly_fee integer NOT NULL DEFAULT 10000,
  description text, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_b503a361e7ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b503a361e7ad$;

DO $bootstrap_do_77c546b36bd2$
BEGIN
  EXECUTE $bootstrap_sql_77c546b36bd2$CREATE TABLE IF NOT EXISTS public.transaction_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  classification_price text NOT NULL DEFAULT '',
  price_per_transaction integer NOT NULL DEFAULT 0,
  total_price integer NOT NULL DEFAULT 0,
  group_commission_percent numeric NOT NULL DEFAULT 5,
  kas_fee numeric(5,2) DEFAULT 0,
  transaction_quota integer NOT NULL DEFAULT 100,
  total_credits integer NOT NULL DEFAULT 100,
  validity_days integer NOT NULL DEFAULT 30,
  description text, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_77c546b36bd2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77c546b36bd2$;

DO $bootstrap_do_edb79babc53c$
BEGIN
  EXECUTE $bootstrap_sql_edb79babc53c$CREATE TABLE IF NOT EXISTS public.quota_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  min_price integer NOT NULL DEFAULT 0, max_price integer,
  credit_cost integer NOT NULL DEFAULT 1,
  description text, is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_edb79babc53c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_edb79babc53c$;

DO $bootstrap_do_7122366eebe1$
BEGIN
  EXECUTE $bootstrap_sql_7122366eebe1$CREATE TABLE IF NOT EXISTS public.tourism (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  name text NOT NULL, description text, image_url text,
  location_lat numeric, location_lng numeric,
  wa_link text, sosmed_link text,
  facilities text[] DEFAULT '{}',
  is_active boolean NOT NULL DEFAULT true,
  view_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_7122366eebe1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7122366eebe1$;

DO $bootstrap_do_922944aa3079$
BEGIN
  EXECUTE $bootstrap_sql_922944aa3079$CREATE TABLE IF NOT EXISTS public.merchants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid, name text NOT NULL, address text, phone text,
  province text, city text, district text, subdistrict text,
  village_id uuid REFERENCES public.villages(id) ON DELETE SET NULL,
  image_url text, cover_image_url text, ktp_url text, slug text,
  business_category text DEFAULT 'kuliner',
  business_description text, classification_price text,
  trade_group text, verifikator_code text,
  open_time time, close_time time,
  is_open boolean NOT NULL DEFAULT true,
  order_mode text NOT NULL DEFAULT 'ADMIN_ASSISTED',
  status text NOT NULL DEFAULT 'ACTIVE',
  registration_status text NOT NULL DEFAULT 'PENDING',
  registered_at timestamptz DEFAULT now(),
  approved_at timestamptz, approved_by uuid, rejection_reason text,
  badge text, rating_avg numeric DEFAULT 0, rating_count integer DEFAULT 0,
  is_verified boolean DEFAULT false, verified_at timestamptz, verified_by uuid,
  verifikator_id uuid,
  group_id uuid REFERENCES public.trade_groups(id) ON DELETE SET NULL,
  current_subscription_id uuid,
  location_lat numeric, location_lng numeric,
  qris_image_url text,
  payment_cod_enabled boolean DEFAULT true,
  payment_transfer_enabled boolean DEFAULT true,
  cod_max_amount integer DEFAULT 75000,
  cod_max_distance_km numeric DEFAULT 3,
  bank_name text, bank_account_number text, bank_account_name text,
  available_balance integer DEFAULT 0, pending_balance integer DEFAULT 0,
  total_withdrawn integer DEFAULT 0,
  halal_certificate_url text, halal_status text DEFAULT 'NONE',
  notification_sound_enabled boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_922944aa3079$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_922944aa3079$;

DO $bootstrap_do_4332d98f653f$
BEGIN
  EXECUTE $bootstrap_sql_4332d98f653f$CREATE UNIQUE INDEX IF NOT EXISTS idx_merchants_slug ON public.merchants(slug) WHERE slug IS NOT NULL$bootstrap_sql_4332d98f653f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4332d98f653f$;

DO $bootstrap_do_b9cf2ffb39f1$
BEGIN
  EXECUTE $bootstrap_sql_b9cf2ffb39f1$CREATE TABLE IF NOT EXISTS public.merchant_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id uuid NOT NULL REFERENCES public.transaction_packages(id),
  transaction_quota integer NOT NULL DEFAULT 0,
  used_quota integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'ACTIVE',
  payment_status text NOT NULL DEFAULT 'UNPAID',
  payment_amount integer NOT NULL DEFAULT 0,
  paid_at timestamptz,
  started_at timestamptz NOT NULL DEFAULT now(),
  expired_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_b9cf2ffb39f1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9cf2ffb39f1$;

DO $bootstrap_do_475dbc7162ad$
BEGIN
  EXECUTE $bootstrap_sql_475dbc7162ad$DO $$ BEGIN
  ALTER TABLE public.merchants
    ADD CONSTRAINT merchants_current_subscription_id_fkey
    FOREIGN KEY (current_subscription_id) REFERENCES public.merchant_subscriptions(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$$bootstrap_sql_475dbc7162ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_475dbc7162ad$;

DO $bootstrap_do_ebca2d44af0f$
BEGIN
  EXECUTE $bootstrap_sql_ebca2d44af0f$CREATE TABLE IF NOT EXISTS public.merchant_gallery (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  image_url text NOT NULL, caption text, sort_order integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_ebca2d44af0f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ebca2d44af0f$;

DO $bootstrap_do_f966c6035750$
BEGIN
  EXECUTE $bootstrap_sql_f966c6035750$CREATE TABLE IF NOT EXISTS public.merchant_favorites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, merchant_id)
)$bootstrap_sql_f966c6035750$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f966c6035750$;

DO $bootstrap_do_5fd7b99623ac$
BEGIN
  EXECUTE $bootstrap_sql_5fd7b99623ac$CREATE TABLE IF NOT EXISTS public.group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'ACTIVE',
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, merchant_id)
)$bootstrap_sql_5fd7b99623ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5fd7b99623ac$;

DO $bootstrap_do_0f2d8aeb84ed$
BEGIN
  EXECUTE $bootstrap_sql_0f2d8aeb84ed$CREATE TABLE IF NOT EXISTS public.kas_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  amount integer NOT NULL,
  payment_month integer NOT NULL, payment_year integer NOT NULL,
  status text NOT NULL DEFAULT 'UNPAID',
  payment_date timestamptz, collected_by uuid,
  notes text, invoice_note text, sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, merchant_id, payment_month, payment_year)
)$bootstrap_sql_0f2d8aeb84ed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f2d8aeb84ed$;

DO $bootstrap_do_948de7829440$
BEGIN
  EXECUTE $bootstrap_sql_948de7829440$CREATE TABLE IF NOT EXISTS public.group_announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES public.trade_groups(id),
  verifikator_id uuid, title text NOT NULL, message text NOT NULL,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_948de7829440$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_948de7829440$;

DO $bootstrap_do_3c77bdb13348$
BEGIN
  EXECUTE $bootstrap_sql_3c77bdb13348$CREATE TABLE IF NOT EXISTS public.verifikator_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verifikator_id uuid NOT NULL,
  code text NOT NULL UNIQUE,
  trade_group text NOT NULL, description text,
  is_active boolean NOT NULL DEFAULT true,
  usage_count integer NOT NULL DEFAULT 0, max_usage integer,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_3c77bdb13348$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c77bdb13348$;

DO $bootstrap_do_5e94b332c307$
BEGIN
  EXECUTE $bootstrap_sql_5e94b332c307$CREATE TABLE IF NOT EXISTS public.verifikator_earnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verifikator_id uuid NOT NULL,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id),
  package_id uuid NOT NULL REFERENCES public.transaction_packages(id),
  package_amount integer NOT NULL,
  commission_percent numeric NOT NULL,
  commission_amount integer NOT NULL,
  status text NOT NULL DEFAULT 'PENDING',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_5e94b332c307$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5e94b332c307$;

DO $bootstrap_do_e34a21b618ce$
BEGIN
  EXECUTE $bootstrap_sql_e34a21b618ce$CREATE TABLE IF NOT EXISTS public.verifikator_withdrawals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verifikator_id uuid NOT NULL,
  amount integer NOT NULL,
  bank_name text NOT NULL, account_number text NOT NULL, account_holder text NOT NULL,
  status text NOT NULL DEFAULT 'PENDING',
  admin_notes text, proof_image_url text,
  processed_by uuid, processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_e34a21b618ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e34a21b618ce$;

DO $bootstrap_do_a3d03f487c56$
BEGIN
  EXECUTE $bootstrap_sql_a3d03f487c56$CREATE TABLE IF NOT EXISTS public.couriers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid, name text NOT NULL, phone text NOT NULL, email text,
  province text NOT NULL, city text NOT NULL, district text NOT NULL,
  subdistrict text NOT NULL, address text NOT NULL,
  ktp_number text NOT NULL, ktp_image_url text NOT NULL, photo_url text NOT NULL,
  vehicle_type text NOT NULL DEFAULT 'motor',
  vehicle_plate text, vehicle_image_url text NOT NULL,
  village_id uuid REFERENCES public.villages(id),
  status text NOT NULL DEFAULT 'INACTIVE',
  registration_status text NOT NULL DEFAULT 'PENDING',
  is_available boolean NOT NULL DEFAULT false,
  current_lat numeric, current_lng numeric, last_location_update timestamptz,
  registered_at timestamptz DEFAULT now(),
  approved_at timestamptz, approved_by uuid, rejection_reason text,
  bank_name text, bank_account_name text, bank_account_number text,
  available_balance numeric DEFAULT 0, pending_balance numeric DEFAULT 0,
  total_withdrawn numeric DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_a3d03f487c56$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3d03f487c56$;

DO $bootstrap_do_f3212e30000b$
BEGIN
  EXECUTE $bootstrap_sql_f3212e30000b$CREATE TABLE IF NOT EXISTS public.courier_earnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id uuid, amount integer NOT NULL DEFAULT 0,
  type text NOT NULL DEFAULT 'DELIVERY',
  status text NOT NULL DEFAULT 'PENDING',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_f3212e30000b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3212e30000b$;

DO $bootstrap_do_1b80d14012c1$
BEGIN
  EXECUTE $bootstrap_sql_1b80d14012c1$CREATE TABLE IF NOT EXISTS public.courier_withdrawal_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id),
  amount numeric NOT NULL,
  bank_name text NOT NULL, account_number text NOT NULL, account_holder text NOT NULL,
  status text DEFAULT 'PENDING', admin_notes text,
  processed_by uuid, processed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_1b80d14012c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1b80d14012c1$;

DO $bootstrap_do_51c7da6fe1ad$
BEGIN
  EXECUTE $bootstrap_sql_51c7da6fe1ad$CREATE TABLE IF NOT EXISTS public.courier_deposits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  amount numeric NOT NULL DEFAULT 0, proof_url text,
  status text NOT NULL DEFAULT 'PENDING',
  admin_notes text, approved_by uuid, processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_51c7da6fe1ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51c7da6fe1ad$;

DO $bootstrap_do_e6a242f4826a$
BEGIN
  EXECUTE $bootstrap_sql_e6a242f4826a$CREATE TABLE IF NOT EXISTS public.courier_balance_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id uuid, type text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  balance_before numeric NOT NULL DEFAULT 0,
  balance_after numeric NOT NULL DEFAULT 0,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_e6a242f4826a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6a242f4826a$;

DO $bootstrap_do_4fb39adb84a7$
BEGIN
  EXECUTE $bootstrap_sql_4fb39adb84a7$CREATE INDEX IF NOT EXISTS idx_merchants_location ON public.merchants(location_lat, location_lng)$bootstrap_sql_4fb39adb84a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fb39adb84a7$;

DO $bootstrap_do_1bc7e9f03ecc$
BEGIN
  EXECUTE $bootstrap_sql_1bc7e9f03ecc$CREATE INDEX IF NOT EXISTS idx_merchants_verifikator_code ON public.merchants(verifikator_code)$bootstrap_sql_1bc7e9f03ecc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1bc7e9f03ecc$;

DO $bootstrap_do_6088e265fb40$
BEGIN
  EXECUTE $bootstrap_sql_6088e265fb40$CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_merchant ON public.merchant_subscriptions(merchant_id)$bootstrap_sql_6088e265fb40$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6088e265fb40$;

DO $bootstrap_do_7a94283d3cb6$
BEGIN
  EXECUTE $bootstrap_sql_7a94283d3cb6$CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_status ON public.merchant_subscriptions(status)$bootstrap_sql_7a94283d3cb6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7a94283d3cb6$;

DO $bootstrap_do_c7ac8c836f89$
BEGIN
  EXECUTE $bootstrap_sql_c7ac8c836f89$CREATE INDEX IF NOT EXISTS idx_merchant_gallery_merchant ON public.merchant_gallery(merchant_id)$bootstrap_sql_c7ac8c836f89$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7ac8c836f89$;

DO $bootstrap_do_8b20bdb5924a$
BEGIN
  EXECUTE $bootstrap_sql_8b20bdb5924a$CREATE INDEX IF NOT EXISTS idx_merchant_favorites_user ON public.merchant_favorites(user_id)$bootstrap_sql_8b20bdb5924a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b20bdb5924a$;

DO $bootstrap_do_0104e1094b11$
BEGIN
  EXECUTE $bootstrap_sql_0104e1094b11$CREATE INDEX IF NOT EXISTS idx_merchant_favorites_merchant ON public.merchant_favorites(merchant_id)$bootstrap_sql_0104e1094b11$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0104e1094b11$;

DO $bootstrap_do_76f923bd16c3$
BEGIN
  EXECUTE $bootstrap_sql_76f923bd16c3$CREATE INDEX IF NOT EXISTS idx_courier_deposits_courier ON public.courier_deposits(courier_id)$bootstrap_sql_76f923bd16c3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_76f923bd16c3$;

DO $bootstrap_do_f8c873b2bc6c$
BEGIN
  EXECUTE $bootstrap_sql_f8c873b2bc6c$CREATE INDEX IF NOT EXISTS idx_courier_balance_logs_courier ON public.courier_balance_logs(courier_id)$bootstrap_sql_f8c873b2bc6c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8c873b2bc6c$;

DO $bootstrap_do_d7ac09bde36c$
BEGIN
  EXECUTE $bootstrap_sql_d7ac09bde36c$GRANT SELECT ON public.villages TO anon$bootstrap_sql_d7ac09bde36c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7ac09bde36c$;

DO $bootstrap_do_4b3c3708374e$
BEGIN
  EXECUTE $bootstrap_sql_4b3c3708374e$GRANT SELECT, INSERT, UPDATE ON public.villages TO authenticated$bootstrap_sql_4b3c3708374e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4b3c3708374e$;

DO $bootstrap_do_6b29f45c2ca2$
BEGIN
  EXECUTE $bootstrap_sql_6b29f45c2ca2$GRANT ALL ON public.villages TO service_role$bootstrap_sql_6b29f45c2ca2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b29f45c2ca2$;

DO $bootstrap_do_6ad47cc1402b$
BEGIN
  EXECUTE $bootstrap_sql_6ad47cc1402b$GRANT SELECT, INSERT ON public.user_villages TO authenticated$bootstrap_sql_6ad47cc1402b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6ad47cc1402b$;

DO $bootstrap_do_8c876e8c12d7$
BEGIN
  EXECUTE $bootstrap_sql_8c876e8c12d7$GRANT ALL ON public.user_villages TO service_role$bootstrap_sql_8c876e8c12d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8c876e8c12d7$;

DO $bootstrap_do_3ae3fe8f9b70$
BEGIN
  EXECUTE $bootstrap_sql_3ae3fe8f9b70$GRANT SELECT ON public.categories TO anon, authenticated$bootstrap_sql_3ae3fe8f9b70$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ae3fe8f9b70$;

DO $bootstrap_do_80d992d8e1c0$
BEGIN
  EXECUTE $bootstrap_sql_80d992d8e1c0$GRANT ALL ON public.categories TO service_role$bootstrap_sql_80d992d8e1c0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_80d992d8e1c0$;

DO $bootstrap_do_51034fd0ffd9$
BEGIN
  EXECUTE $bootstrap_sql_51034fd0ffd9$GRANT SELECT, INSERT, UPDATE ON public.trade_groups TO authenticated$bootstrap_sql_51034fd0ffd9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51034fd0ffd9$;

DO $bootstrap_do_c0e292ec680b$
BEGIN
  EXECUTE $bootstrap_sql_c0e292ec680b$GRANT ALL ON public.trade_groups TO service_role$bootstrap_sql_c0e292ec680b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0e292ec680b$;

DO $bootstrap_do_ffac97af1d90$
BEGIN
  EXECUTE $bootstrap_sql_ffac97af1d90$GRANT SELECT ON public.transaction_packages TO anon, authenticated$bootstrap_sql_ffac97af1d90$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ffac97af1d90$;

DO $bootstrap_do_ea90e4a8ffac$
BEGIN
  EXECUTE $bootstrap_sql_ea90e4a8ffac$GRANT ALL ON public.transaction_packages TO service_role$bootstrap_sql_ea90e4a8ffac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea90e4a8ffac$;

DO $bootstrap_do_e5da8401ecd2$
BEGIN
  EXECUTE $bootstrap_sql_e5da8401ecd2$GRANT SELECT ON public.quota_tiers TO anon, authenticated$bootstrap_sql_e5da8401ecd2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e5da8401ecd2$;

DO $bootstrap_do_3b69a822c990$
BEGIN
  EXECUTE $bootstrap_sql_3b69a822c990$GRANT ALL ON public.quota_tiers TO service_role$bootstrap_sql_3b69a822c990$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b69a822c990$;

DO $bootstrap_do_792274897142$
BEGIN
  EXECUTE $bootstrap_sql_792274897142$GRANT SELECT ON public.tourism TO anon$bootstrap_sql_792274897142$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_792274897142$;

DO $bootstrap_do_bdf3eb721969$
BEGIN
  EXECUTE $bootstrap_sql_bdf3eb721969$GRANT SELECT, INSERT, UPDATE, DELETE ON public.tourism TO authenticated$bootstrap_sql_bdf3eb721969$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bdf3eb721969$;

DO $bootstrap_do_8871932a5c36$
BEGIN
  EXECUTE $bootstrap_sql_8871932a5c36$GRANT ALL ON public.tourism TO service_role$bootstrap_sql_8871932a5c36$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8871932a5c36$;

DO $bootstrap_do_0aee114d8a17$
BEGIN
  EXECUTE $bootstrap_sql_0aee114d8a17$GRANT SELECT ON public.merchants TO anon$bootstrap_sql_0aee114d8a17$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0aee114d8a17$;

DO $bootstrap_do_033ade6c0f4c$
BEGIN
  EXECUTE $bootstrap_sql_033ade6c0f4c$GRANT SELECT, INSERT, UPDATE ON public.merchants TO authenticated$bootstrap_sql_033ade6c0f4c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_033ade6c0f4c$;

DO $bootstrap_do_deb632e11070$
BEGIN
  EXECUTE $bootstrap_sql_deb632e11070$GRANT ALL ON public.merchants TO service_role$bootstrap_sql_deb632e11070$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_deb632e11070$;

DO $bootstrap_do_4561b2d12309$
BEGIN
  EXECUTE $bootstrap_sql_4561b2d12309$GRANT SELECT, INSERT, UPDATE ON public.merchant_subscriptions TO authenticated$bootstrap_sql_4561b2d12309$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4561b2d12309$;

DO $bootstrap_do_4c916a2077ea$
BEGIN
  EXECUTE $bootstrap_sql_4c916a2077ea$GRANT ALL ON public.merchant_subscriptions TO service_role$bootstrap_sql_4c916a2077ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c916a2077ea$;

DO $bootstrap_do_0661ccda63fb$
BEGIN
  EXECUTE $bootstrap_sql_0661ccda63fb$GRANT SELECT ON public.merchant_gallery TO anon, authenticated$bootstrap_sql_0661ccda63fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0661ccda63fb$;

DO $bootstrap_do_a9c8f0558cbc$
BEGIN
  EXECUTE $bootstrap_sql_a9c8f0558cbc$GRANT INSERT, UPDATE, DELETE ON public.merchant_gallery TO authenticated$bootstrap_sql_a9c8f0558cbc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a9c8f0558cbc$;

DO $bootstrap_do_5d0347620d1f$
BEGIN
  EXECUTE $bootstrap_sql_5d0347620d1f$GRANT ALL ON public.merchant_gallery TO service_role$bootstrap_sql_5d0347620d1f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d0347620d1f$;

DO $bootstrap_do_083f0d5647e8$
BEGIN
  EXECUTE $bootstrap_sql_083f0d5647e8$GRANT SELECT, INSERT, DELETE ON public.merchant_favorites TO authenticated$bootstrap_sql_083f0d5647e8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_083f0d5647e8$;

DO $bootstrap_do_12a76e455517$
BEGIN
  EXECUTE $bootstrap_sql_12a76e455517$GRANT ALL ON public.merchant_favorites TO service_role$bootstrap_sql_12a76e455517$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_12a76e455517$;

DO $bootstrap_do_747d4f11e9cd$
BEGIN
  EXECUTE $bootstrap_sql_747d4f11e9cd$GRANT SELECT, INSERT, UPDATE ON public.group_members TO authenticated$bootstrap_sql_747d4f11e9cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_747d4f11e9cd$;

DO $bootstrap_do_6cfe1453e34f$
BEGIN
  EXECUTE $bootstrap_sql_6cfe1453e34f$GRANT ALL ON public.group_members TO service_role$bootstrap_sql_6cfe1453e34f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6cfe1453e34f$;

DO $bootstrap_do_1b22e44512a7$
BEGIN
  EXECUTE $bootstrap_sql_1b22e44512a7$GRANT SELECT, INSERT, UPDATE ON public.kas_payments TO authenticated$bootstrap_sql_1b22e44512a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1b22e44512a7$;

DO $bootstrap_do_413cd6ceb863$
BEGIN
  EXECUTE $bootstrap_sql_413cd6ceb863$GRANT ALL ON public.kas_payments TO service_role$bootstrap_sql_413cd6ceb863$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_413cd6ceb863$;

DO $bootstrap_do_9cf97cc26e07$
BEGIN
  EXECUTE $bootstrap_sql_9cf97cc26e07$GRANT SELECT, INSERT, UPDATE, DELETE ON public.group_announcements TO authenticated$bootstrap_sql_9cf97cc26e07$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cf97cc26e07$;

DO $bootstrap_do_86b08a2adfa5$
BEGIN
  EXECUTE $bootstrap_sql_86b08a2adfa5$GRANT ALL ON public.group_announcements TO service_role$bootstrap_sql_86b08a2adfa5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_86b08a2adfa5$;

DO $bootstrap_do_c485905ea4c0$
BEGIN
  EXECUTE $bootstrap_sql_c485905ea4c0$GRANT SELECT, INSERT, UPDATE ON public.verifikator_codes TO authenticated$bootstrap_sql_c485905ea4c0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c485905ea4c0$;

DO $bootstrap_do_90eb27ac6521$
BEGIN
  EXECUTE $bootstrap_sql_90eb27ac6521$GRANT ALL ON public.verifikator_codes TO service_role$bootstrap_sql_90eb27ac6521$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90eb27ac6521$;

DO $bootstrap_do_68a7df040106$
BEGIN
  EXECUTE $bootstrap_sql_68a7df040106$GRANT SELECT, INSERT, UPDATE ON public.verifikator_earnings TO authenticated$bootstrap_sql_68a7df040106$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68a7df040106$;

DO $bootstrap_do_9c422c7c86f2$
BEGIN
  EXECUTE $bootstrap_sql_9c422c7c86f2$GRANT ALL ON public.verifikator_earnings TO service_role$bootstrap_sql_9c422c7c86f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c422c7c86f2$;

DO $bootstrap_do_c66e3a6118b3$
BEGIN
  EXECUTE $bootstrap_sql_c66e3a6118b3$GRANT SELECT, INSERT, UPDATE ON public.verifikator_withdrawals TO authenticated$bootstrap_sql_c66e3a6118b3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c66e3a6118b3$;

DO $bootstrap_do_c389fc6f1237$
BEGIN
  EXECUTE $bootstrap_sql_c389fc6f1237$GRANT ALL ON public.verifikator_withdrawals TO service_role$bootstrap_sql_c389fc6f1237$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c389fc6f1237$;

DO $bootstrap_do_718cb682d560$
BEGIN
  EXECUTE $bootstrap_sql_718cb682d560$GRANT SELECT ON public.couriers TO anon, authenticated$bootstrap_sql_718cb682d560$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_718cb682d560$;

DO $bootstrap_do_33b96a68c7b4$
BEGIN
  EXECUTE $bootstrap_sql_33b96a68c7b4$GRANT INSERT, UPDATE ON public.couriers TO authenticated$bootstrap_sql_33b96a68c7b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33b96a68c7b4$;

DO $bootstrap_do_f5329b5355ac$
BEGIN
  EXECUTE $bootstrap_sql_f5329b5355ac$GRANT ALL ON public.couriers TO service_role$bootstrap_sql_f5329b5355ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f5329b5355ac$;

DO $bootstrap_do_40067ed7f332$
BEGIN
  EXECUTE $bootstrap_sql_40067ed7f332$GRANT SELECT, INSERT, UPDATE ON public.courier_earnings TO authenticated$bootstrap_sql_40067ed7f332$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40067ed7f332$;

DO $bootstrap_do_2a862e877bb9$
BEGIN
  EXECUTE $bootstrap_sql_2a862e877bb9$GRANT ALL ON public.courier_earnings TO service_role$bootstrap_sql_2a862e877bb9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a862e877bb9$;

DO $bootstrap_do_6701b7b3847e$
BEGIN
  EXECUTE $bootstrap_sql_6701b7b3847e$GRANT SELECT, INSERT ON public.courier_withdrawal_requests TO authenticated$bootstrap_sql_6701b7b3847e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6701b7b3847e$;

DO $bootstrap_do_b23b38557dfe$
BEGIN
  EXECUTE $bootstrap_sql_b23b38557dfe$GRANT ALL ON public.courier_withdrawal_requests TO service_role$bootstrap_sql_b23b38557dfe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b23b38557dfe$;

DO $bootstrap_do_b2bf8d7f2a01$
BEGIN
  EXECUTE $bootstrap_sql_b2bf8d7f2a01$GRANT SELECT, INSERT ON public.courier_deposits TO authenticated$bootstrap_sql_b2bf8d7f2a01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b2bf8d7f2a01$;

DO $bootstrap_do_79c2a8f07c51$
BEGIN
  EXECUTE $bootstrap_sql_79c2a8f07c51$GRANT ALL ON public.courier_deposits TO service_role$bootstrap_sql_79c2a8f07c51$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_79c2a8f07c51$;

DO $bootstrap_do_4c683722166d$
BEGIN
  EXECUTE $bootstrap_sql_4c683722166d$GRANT SELECT ON public.courier_balance_logs TO authenticated$bootstrap_sql_4c683722166d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c683722166d$;

DO $bootstrap_do_088d95a592e7$
BEGIN
  EXECUTE $bootstrap_sql_088d95a592e7$GRANT ALL ON public.courier_balance_logs TO service_role$bootstrap_sql_088d95a592e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_088d95a592e7$;

DO $bootstrap_do_c0ced0a42d0e$
BEGIN
  EXECUTE $bootstrap_sql_c0ced0a42d0e$ALTER TABLE public.villages ENABLE ROW LEVEL SECURITY$bootstrap_sql_c0ced0a42d0e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0ced0a42d0e$;

DO $bootstrap_do_b1c686aeab96$
BEGIN
  EXECUTE $bootstrap_sql_b1c686aeab96$ALTER TABLE public.user_villages ENABLE ROW LEVEL SECURITY$bootstrap_sql_b1c686aeab96$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b1c686aeab96$;

DO $bootstrap_do_02d6d170d5de$
BEGIN
  EXECUTE $bootstrap_sql_02d6d170d5de$ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY$bootstrap_sql_02d6d170d5de$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_02d6d170d5de$;

DO $bootstrap_do_685710f871ae$
BEGIN
  EXECUTE $bootstrap_sql_685710f871ae$ALTER TABLE public.trade_groups ENABLE ROW LEVEL SECURITY$bootstrap_sql_685710f871ae$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_685710f871ae$;

DO $bootstrap_do_c09380f4539c$
BEGIN
  EXECUTE $bootstrap_sql_c09380f4539c$ALTER TABLE public.transaction_packages ENABLE ROW LEVEL SECURITY$bootstrap_sql_c09380f4539c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c09380f4539c$;

DO $bootstrap_do_632fba06c994$
BEGIN
  EXECUTE $bootstrap_sql_632fba06c994$ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY$bootstrap_sql_632fba06c994$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_632fba06c994$;

DO $bootstrap_do_9a257fc9ef21$
BEGIN
  EXECUTE $bootstrap_sql_9a257fc9ef21$ALTER TABLE public.tourism ENABLE ROW LEVEL SECURITY$bootstrap_sql_9a257fc9ef21$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9a257fc9ef21$;

DO $bootstrap_do_a830abe3d49e$
BEGIN
  EXECUTE $bootstrap_sql_a830abe3d49e$ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY$bootstrap_sql_a830abe3d49e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a830abe3d49e$;

DO $bootstrap_do_8c0cdf185d0a$
BEGIN
  EXECUTE $bootstrap_sql_8c0cdf185d0a$ALTER TABLE public.merchant_subscriptions ENABLE ROW LEVEL SECURITY$bootstrap_sql_8c0cdf185d0a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8c0cdf185d0a$;

DO $bootstrap_do_ae0cc1d3d493$
BEGIN
  EXECUTE $bootstrap_sql_ae0cc1d3d493$ALTER TABLE public.merchant_gallery ENABLE ROW LEVEL SECURITY$bootstrap_sql_ae0cc1d3d493$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae0cc1d3d493$;

DO $bootstrap_do_5adf17b0c7a3$
BEGIN
  EXECUTE $bootstrap_sql_5adf17b0c7a3$ALTER TABLE public.merchant_favorites ENABLE ROW LEVEL SECURITY$bootstrap_sql_5adf17b0c7a3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5adf17b0c7a3$;

DO $bootstrap_do_9b779d0437c6$
BEGIN
  EXECUTE $bootstrap_sql_9b779d0437c6$ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY$bootstrap_sql_9b779d0437c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b779d0437c6$;

DO $bootstrap_do_1f1aa4f352d1$
BEGIN
  EXECUTE $bootstrap_sql_1f1aa4f352d1$ALTER TABLE public.kas_payments ENABLE ROW LEVEL SECURITY$bootstrap_sql_1f1aa4f352d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f1aa4f352d1$;

DO $bootstrap_do_dad95bcb5694$
BEGIN
  EXECUTE $bootstrap_sql_dad95bcb5694$ALTER TABLE public.group_announcements ENABLE ROW LEVEL SECURITY$bootstrap_sql_dad95bcb5694$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dad95bcb5694$;

DO $bootstrap_do_436f8989dbf6$
BEGIN
  EXECUTE $bootstrap_sql_436f8989dbf6$ALTER TABLE public.verifikator_codes ENABLE ROW LEVEL SECURITY$bootstrap_sql_436f8989dbf6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_436f8989dbf6$;

DO $bootstrap_do_6ec622bb885c$
BEGIN
  EXECUTE $bootstrap_sql_6ec622bb885c$ALTER TABLE public.verifikator_earnings ENABLE ROW LEVEL SECURITY$bootstrap_sql_6ec622bb885c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6ec622bb885c$;

DO $bootstrap_do_3a53c0066429$
BEGIN
  EXECUTE $bootstrap_sql_3a53c0066429$ALTER TABLE public.verifikator_withdrawals ENABLE ROW LEVEL SECURITY$bootstrap_sql_3a53c0066429$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3a53c0066429$;

DO $bootstrap_do_c540230772ec$
BEGIN
  EXECUTE $bootstrap_sql_c540230772ec$ALTER TABLE public.couriers ENABLE ROW LEVEL SECURITY$bootstrap_sql_c540230772ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c540230772ec$;

DO $bootstrap_do_5223e963af8e$
BEGIN
  EXECUTE $bootstrap_sql_5223e963af8e$ALTER TABLE public.courier_earnings ENABLE ROW LEVEL SECURITY$bootstrap_sql_5223e963af8e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5223e963af8e$;

DO $bootstrap_do_eed8cddc20c5$
BEGIN
  EXECUTE $bootstrap_sql_eed8cddc20c5$ALTER TABLE public.courier_withdrawal_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_eed8cddc20c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eed8cddc20c5$;

DO $bootstrap_do_1474fae3ff23$
BEGIN
  EXECUTE $bootstrap_sql_1474fae3ff23$ALTER TABLE public.courier_deposits ENABLE ROW LEVEL SECURITY$bootstrap_sql_1474fae3ff23$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1474fae3ff23$;

DO $bootstrap_do_6d8a7c5aecd7$
BEGIN
  EXECUTE $bootstrap_sql_6d8a7c5aecd7$ALTER TABLE public.courier_balance_logs ENABLE ROW LEVEL SECURITY$bootstrap_sql_6d8a7c5aecd7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d8a7c5aecd7$;

DO $bootstrap_do_78986fe50299$
BEGIN
  EXECUTE $bootstrap_sql_78986fe50299$CREATE OR REPLACE FUNCTION public.is_courier_owner(_user_id uuid, _courier_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.couriers WHERE id = _courier_id AND user_id = _user_id)
$$$bootstrap_sql_78986fe50299$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_78986fe50299$;

DO $bootstrap_do_1798e9e3d2c4$
BEGIN
  EXECUTE $bootstrap_sql_1798e9e3d2c4$CREATE OR REPLACE FUNCTION public.generate_merchant_slug(merchant_name text)
RETURNS text LANGUAGE plpgsql SET search_path = public AS $$
DECLARE base_slug text; final_slug text; counter integer := 0;
BEGIN
  base_slug := lower(regexp_replace(merchant_name, '[^a-zA-Z0-9]+', '-', 'g'));
  base_slug := trim(both '-' from base_slug);
  final_slug := base_slug;
  WHILE EXISTS (SELECT 1 FROM public.merchants WHERE slug = final_slug) LOOP
    counter := counter + 1;
    final_slug := base_slug || '-' || counter;
  END LOOP;
  RETURN final_slug;
END; $$$bootstrap_sql_1798e9e3d2c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1798e9e3d2c4$;

DO $bootstrap_do_92e31b6cfbca$
BEGIN
  EXECUTE $bootstrap_sql_92e31b6cfbca$CREATE OR REPLACE FUNCTION public.get_quota_cost(product_price integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(
    (SELECT credit_cost FROM public.quota_tiers
     WHERE is_active = true AND product_price >= min_price
       AND (max_price IS NULL OR product_price <= max_price)
     ORDER BY min_price DESC LIMIT 1), 1)
$$$bootstrap_sql_92e31b6cfbca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_92e31b6cfbca$;

DO $bootstrap_do_4771a01f5abb$
BEGIN
  EXECUTE $bootstrap_sql_4771a01f5abb$CREATE OR REPLACE FUNCTION public.calculate_quota_cost(p_product_price integer)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE v_cost integer;
BEGIN
  SELECT credit_cost INTO v_cost FROM public.quota_tiers
  WHERE p_product_price >= min_price
    AND (max_price IS NULL OR p_product_price <= max_price)
    AND is_active = true
  ORDER BY min_price DESC LIMIT 1;
  RETURN COALESCE(v_cost, 1);
END; $$$bootstrap_sql_4771a01f5abb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4771a01f5abb$;

DO $bootstrap_do_b0f0caf0f023$
BEGIN
  EXECUTE $bootstrap_sql_b0f0caf0f023$CREATE OR REPLACE FUNCTION public.check_merchant_quota(p_merchant_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_subscription RECORD;
BEGIN
  SELECT * INTO v_subscription FROM public.merchant_subscriptions
  WHERE merchant_id = p_merchant_id AND status = 'ACTIVE' AND expired_at > now() AND used_quota < transaction_quota
  ORDER BY expired_at DESC LIMIT 1;
  IF v_subscription IS NULL THEN
    RETURN jsonb_build_object('can_transact', false, 'reason', 'Tidak ada kuota transaksi aktif.', 'remaining_quota', 0);
  END IF;
  RETURN jsonb_build_object('can_transact', true,
    'remaining_quota', v_subscription.transaction_quota - v_subscription.used_quota,
    'subscription_id', v_subscription.id);
END; $$$bootstrap_sql_b0f0caf0f023$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b0f0caf0f023$;

DO $bootstrap_do_322302da25ed$
BEGIN
  EXECUTE $bootstrap_sql_322302da25ed$CREATE OR REPLACE FUNCTION public.use_merchant_quota(p_merchant_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.merchant_subscriptions SET used_quota = used_quota + 1, updated_at = now()
  WHERE merchant_id = p_merchant_id AND status = 'ACTIVE' AND expired_at > now() AND used_quota < transaction_quota;
  RETURN FOUND;
END; $$$bootstrap_sql_322302da25ed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_322302da25ed$;

DO $bootstrap_do_4f34a244f079$
BEGIN
  EXECUTE $bootstrap_sql_4f34a244f079$CREATE OR REPLACE FUNCTION public.deduct_merchant_quota(p_merchant_id uuid, p_credits integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_sub_id uuid;
BEGIN
  SELECT id INTO v_sub_id FROM public.merchant_subscriptions
  WHERE merchant_id = p_merchant_id AND status = 'ACTIVE' AND expired_at > now()
    AND (transaction_quota - used_quota) >= p_credits
  ORDER BY expired_at ASC LIMIT 1;
  IF v_sub_id IS NULL THEN RETURN FALSE; END IF;
  UPDATE public.merchant_subscriptions SET used_quota = used_quota + p_credits, updated_at = now() WHERE id = v_sub_id;
  RETURN TRUE;
END; $$$bootstrap_sql_4f34a244f079$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f34a244f079$;

DO $bootstrap_do_0eb2277b2715$
BEGIN
  EXECUTE $bootstrap_sql_0eb2277b2715$CREATE OR REPLACE FUNCTION public.auto_assign_merchant_to_group()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_code RECORD; v_group RECORD;
BEGIN
  IF NEW.verifikator_code IS NOT NULL AND NEW.group_id IS NULL THEN
    SELECT * INTO v_code FROM public.verifikator_codes WHERE code = NEW.verifikator_code AND is_active = true LIMIT 1;
    IF v_code IS NOT NULL THEN
      SELECT * INTO v_group FROM public.trade_groups WHERE verifikator_id = v_code.verifikator_id AND is_active = true LIMIT 1;
      IF v_group IS NOT NULL THEN
        NEW.group_id := v_group.id;
        INSERT INTO public.group_members (group_id, merchant_id, status)
        VALUES (v_group.id, NEW.id, 'ACTIVE') ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END; $$$bootstrap_sql_0eb2277b2715$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0eb2277b2715$;

DO $bootstrap_do_8c8263610c72$
BEGIN
  EXECUTE $bootstrap_sql_8c8263610c72$CREATE OR REPLACE FUNCTION public.generate_monthly_kas(p_group_id uuid, p_month integer, p_year integer)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_group RECORD; v_member RECORD; v_count integer := 0;
BEGIN
  SELECT * INTO v_group FROM public.trade_groups WHERE id = p_group_id;
  IF v_group IS NULL THEN RETURN 0; END IF;
  FOR v_member IN SELECT * FROM public.group_members WHERE group_id = p_group_id AND status = 'ACTIVE' LOOP
    INSERT INTO public.kas_payments (group_id, merchant_id, amount, payment_month, payment_year, status)
    VALUES (p_group_id, v_member.merchant_id, v_group.monthly_fee, p_month, p_year, 'UNPAID')
    ON CONFLICT (group_id, merchant_id, payment_month, payment_year) DO NOTHING;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END; $$$bootstrap_sql_8c8263610c72$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8c8263610c72$;

DO $bootstrap_do_65836569875a$
BEGIN
  EXECUTE $bootstrap_sql_65836569875a$CREATE OR REPLACE FUNCTION public.record_verifikator_commission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_merchant RECORD; v_package RECORD; v_commission integer;
BEGIN
  IF NEW.payment_status = 'PAID' AND (OLD.payment_status IS NULL OR OLD.payment_status != 'PAID') THEN
    SELECT * INTO v_merchant FROM public.merchants WHERE id = NEW.merchant_id;
    IF v_merchant.verifikator_id IS NOT NULL THEN
      SELECT * INTO v_package FROM public.transaction_packages WHERE id = NEW.package_id;
      v_commission := FLOOR(NEW.payment_amount * v_package.group_commission_percent / 100);
      IF v_commission > 0 THEN
        INSERT INTO public.verifikator_earnings (verifikator_id, merchant_id, subscription_id, package_id,
          package_amount, commission_percent, commission_amount, status)
        VALUES (v_merchant.verifikator_id, NEW.merchant_id, NEW.id, NEW.package_id,
          NEW.payment_amount, v_package.group_commission_percent, v_commission, 'PENDING');
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END; $$$bootstrap_sql_65836569875a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_65836569875a$;

DO $bootstrap_do_a4928c0a78c4$
BEGIN
  EXECUTE $bootstrap_sql_a4928c0a78c4$CREATE OR REPLACE FUNCTION public.process_verifikator_withdrawal(p_withdrawal_id uuid, p_status text, p_admin_notes text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_withdrawal RECORD; v_total_pending integer;
BEGIN
  SELECT * INTO v_withdrawal FROM public.verifikator_withdrawals WHERE id = p_withdrawal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Withdrawal not found'; END IF;
  IF v_withdrawal.status != 'PENDING' THEN RAISE EXCEPTION 'Already processed'; END IF;
  IF p_status = 'APPROVED' THEN
    SELECT COALESCE(SUM(commission_amount), 0) INTO v_total_pending
    FROM public.verifikator_earnings WHERE verifikator_id = v_withdrawal.verifikator_id AND status = 'PENDING';
    IF v_total_pending < v_withdrawal.amount THEN RAISE EXCEPTION 'Insufficient balance'; END IF;
    WITH earnings_to_pay AS (
      SELECT id, commission_amount, SUM(commission_amount) OVER (ORDER BY created_at) AS running_total
      FROM public.verifikator_earnings WHERE verifikator_id = v_withdrawal.verifikator_id AND status = 'PENDING'
      ORDER BY created_at
    ) UPDATE public.verifikator_earnings SET status = 'PAID', paid_at = now()
      WHERE id IN (SELECT id FROM earnings_to_pay WHERE running_total <= v_withdrawal.amount);
  END IF;
  UPDATE public.verifikator_withdrawals
  SET status = p_status, admin_notes = p_admin_notes, processed_by = auth.uid(), processed_at = now(), updated_at = now()
  WHERE id = p_withdrawal_id;
  RETURN TRUE;
END; $$$bootstrap_sql_a4928c0a78c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a4928c0a78c4$;

DO $bootstrap_do_17df4f87a46d$
BEGIN
  EXECUTE $bootstrap_sql_17df4f87a46d$CREATE OR REPLACE FUNCTION public.approve_quota_subscription(p_subscription_id uuid, p_admin_notes text DEFAULT NULL)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sub RECORD;
BEGIN
  SELECT * INTO v_sub FROM public.merchant_subscriptions WHERE id = p_subscription_id;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'message', 'Subscription tidak ditemukan'); END IF;
  IF v_sub.payment_status = 'PAID' AND v_sub.status = 'ACTIVE' THEN
    RETURN json_build_object('success', false, 'message', 'Subscription sudah aktif');
  END IF;
  UPDATE public.merchant_subscriptions SET status='ACTIVE', payment_status='PAID', paid_at=now(), updated_at=now() WHERE id = p_subscription_id;
  UPDATE public.merchants SET current_subscription_id = p_subscription_id, updated_at=now() WHERE id = v_sub.merchant_id;
  RETURN json_build_object('success', true, 'message', 'Subscription berhasil disetujui dan diaktifkan');
END; $$$bootstrap_sql_17df4f87a46d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17df4f87a46d$;

DO $bootstrap_do_66beb86e2f55$
BEGIN
  EXECUTE $bootstrap_sql_66beb86e2f55$CREATE OR REPLACE FUNCTION public.reject_quota_subscription(p_subscription_id uuid, p_admin_notes text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_admin_notes IS NULL OR p_admin_notes = '' THEN
    RETURN json_build_object('success', false, 'message', 'Catatan admin wajib diisi saat menolak');
  END IF;
  UPDATE public.merchant_subscriptions SET status='INACTIVE', payment_status='REJECTED', updated_at=now() WHERE id = p_subscription_id;
  RETURN json_build_object('success', true, 'message', 'Subscription berhasil ditolak');
END; $$$bootstrap_sql_66beb86e2f55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_66beb86e2f55$;

DO $bootstrap_do_8e02ad80083f$
BEGIN
  EXECUTE $bootstrap_sql_8e02ad80083f$DROP TRIGGER IF EXISTS update_villages_updated_at ON public.villages$bootstrap_sql_8e02ad80083f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e02ad80083f$;

DO $bootstrap_do_08ca6ae65fe9$
BEGIN
  EXECUTE $bootstrap_sql_08ca6ae65fe9$CREATE TRIGGER update_villages_updated_at BEFORE UPDATE ON public.villages FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_08ca6ae65fe9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08ca6ae65fe9$;

DO $bootstrap_do_985ae32b18e3$
BEGIN
  EXECUTE $bootstrap_sql_985ae32b18e3$DROP TRIGGER IF EXISTS update_merchants_updated_at ON public.merchants$bootstrap_sql_985ae32b18e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_985ae32b18e3$;

DO $bootstrap_do_efe7df8e38d6$
BEGIN
  EXECUTE $bootstrap_sql_efe7df8e38d6$CREATE TRIGGER update_merchants_updated_at BEFORE UPDATE ON public.merchants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_efe7df8e38d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_efe7df8e38d6$;

DO $bootstrap_do_d38fbdc2a608$
BEGIN
  EXECUTE $bootstrap_sql_d38fbdc2a608$DROP TRIGGER IF EXISTS update_merchant_subscriptions_updated_at ON public.merchant_subscriptions$bootstrap_sql_d38fbdc2a608$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d38fbdc2a608$;

DO $bootstrap_do_0e9165c0f55a$
BEGIN
  EXECUTE $bootstrap_sql_0e9165c0f55a$CREATE TRIGGER update_merchant_subscriptions_updated_at BEFORE UPDATE ON public.merchant_subscriptions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_0e9165c0f55a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e9165c0f55a$;

DO $bootstrap_do_1e9126f1f3b4$
BEGIN
  EXECUTE $bootstrap_sql_1e9126f1f3b4$DROP TRIGGER IF EXISTS update_couriers_updated_at ON public.couriers$bootstrap_sql_1e9126f1f3b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1e9126f1f3b4$;

DO $bootstrap_do_944551fe1b55$
BEGIN
  EXECUTE $bootstrap_sql_944551fe1b55$CREATE TRIGGER update_couriers_updated_at BEFORE UPDATE ON public.couriers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_944551fe1b55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_944551fe1b55$;

DO $bootstrap_do_0b7acc2c4f8d$
BEGIN
  EXECUTE $bootstrap_sql_0b7acc2c4f8d$DROP TRIGGER IF EXISTS update_trade_groups_updated_at ON public.trade_groups$bootstrap_sql_0b7acc2c4f8d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b7acc2c4f8d$;

DO $bootstrap_do_5147eff34611$
BEGIN
  EXECUTE $bootstrap_sql_5147eff34611$CREATE TRIGGER update_trade_groups_updated_at BEFORE UPDATE ON public.trade_groups FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_5147eff34611$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5147eff34611$;

DO $bootstrap_do_d65afe60ebc1$
BEGIN
  EXECUTE $bootstrap_sql_d65afe60ebc1$DROP TRIGGER IF EXISTS update_transaction_packages_updated_at ON public.transaction_packages$bootstrap_sql_d65afe60ebc1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d65afe60ebc1$;

DO $bootstrap_do_a33c009824a2$
BEGIN
  EXECUTE $bootstrap_sql_a33c009824a2$CREATE TRIGGER update_transaction_packages_updated_at BEFORE UPDATE ON public.transaction_packages FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_a33c009824a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a33c009824a2$;

DO $bootstrap_do_44adc8d5a1d2$
BEGIN
  EXECUTE $bootstrap_sql_44adc8d5a1d2$DROP TRIGGER IF EXISTS update_quota_tiers_updated_at ON public.quota_tiers$bootstrap_sql_44adc8d5a1d2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44adc8d5a1d2$;

DO $bootstrap_do_b14eaeaae2d7$
BEGIN
  EXECUTE $bootstrap_sql_b14eaeaae2d7$CREATE TRIGGER update_quota_tiers_updated_at BEFORE UPDATE ON public.quota_tiers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_b14eaeaae2d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b14eaeaae2d7$;

DO $bootstrap_do_70a69cbd809e$
BEGIN
  EXECUTE $bootstrap_sql_70a69cbd809e$DROP TRIGGER IF EXISTS update_kas_payments_updated_at ON public.kas_payments$bootstrap_sql_70a69cbd809e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70a69cbd809e$;

DO $bootstrap_do_738fc0cda686$
BEGIN
  EXECUTE $bootstrap_sql_738fc0cda686$CREATE TRIGGER update_kas_payments_updated_at BEFORE UPDATE ON public.kas_payments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_738fc0cda686$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_738fc0cda686$;

DO $bootstrap_do_f2c9962bd974$
BEGIN
  EXECUTE $bootstrap_sql_f2c9962bd974$DROP TRIGGER IF EXISTS trigger_auto_assign_merchant_group ON public.merchants$bootstrap_sql_f2c9962bd974$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2c9962bd974$;

DO $bootstrap_do_6e06c9bed059$
BEGIN
  EXECUTE $bootstrap_sql_6e06c9bed059$CREATE TRIGGER trigger_auto_assign_merchant_group BEFORE INSERT OR UPDATE ON public.merchants FOR EACH ROW EXECUTE FUNCTION public.auto_assign_merchant_to_group()$bootstrap_sql_6e06c9bed059$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e06c9bed059$;

DO $bootstrap_do_41b6d8b51ada$
BEGIN
  EXECUTE $bootstrap_sql_41b6d8b51ada$DROP TRIGGER IF EXISTS trigger_record_verifikator_commission ON public.merchant_subscriptions$bootstrap_sql_41b6d8b51ada$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_41b6d8b51ada$;

DO $bootstrap_do_5fa87cc11ab6$
BEGIN
  EXECUTE $bootstrap_sql_5fa87cc11ab6$CREATE TRIGGER trigger_record_verifikator_commission AFTER INSERT OR UPDATE ON public.merchant_subscriptions FOR EACH ROW EXECUTE FUNCTION public.record_verifikator_commission()$bootstrap_sql_5fa87cc11ab6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5fa87cc11ab6$;

DO $bootstrap_do_31d99a8ef01f$
BEGIN
  EXECUTE $bootstrap_sql_31d99a8ef01f$DROP VIEW IF EXISTS public.public_merchants CASCADE$bootstrap_sql_31d99a8ef01f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31d99a8ef01f$;

DO $bootstrap_do_1039098d428c$
BEGIN
  EXECUTE $bootstrap_sql_1039098d428c$CREATE VIEW public.public_merchants WITH (security_invoker=on) AS
SELECT id, name, image_url, business_category, business_description, village_id,
  CASE WHEN phone IS NOT NULL THEN CONCAT('****', RIGHT(phone, 4)) END AS phone_masked,
  city, district, province,
  CASE WHEN location_lat IS NOT NULL THEN ROUND(location_lat::numeric, 2) END AS location_lat_approx,
  CASE WHEN location_lng IS NOT NULL THEN ROUND(location_lng::numeric, 2) END AS location_lng_approx,
  is_open, open_time, close_time, rating_avg, rating_count, is_verified, badge, order_mode
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_1039098d428c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1039098d428c$;

DO $bootstrap_do_59633d33fab0$
BEGIN
  EXECUTE $bootstrap_sql_59633d33fab0$DROP VIEW IF EXISTS public.public_couriers CASCADE$bootstrap_sql_59633d33fab0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59633d33fab0$;

DO $bootstrap_do_4d627088d485$
BEGIN
  EXECUTE $bootstrap_sql_4d627088d485$CREATE VIEW public.public_couriers WITH (security_invoker=on) AS
SELECT id, name,
  CASE WHEN phone IS NOT NULL THEN CONCAT('****', RIGHT(phone, 4)) END AS phone_masked,
  photo_url, vehicle_type,
  CASE WHEN current_lat IS NOT NULL THEN ROUND(current_lat, 3) END AS current_lat_approx,
  CASE WHEN current_lng IS NOT NULL THEN ROUND(current_lng, 3) END AS current_lng_approx,
  is_available, status, village_id
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_4d627088d485$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d627088d485$;

DO $bootstrap_do_8d60a3888f98$
BEGIN
  EXECUTE $bootstrap_sql_8d60a3888f98$GRANT SELECT ON public.public_merchants TO anon, authenticated$bootstrap_sql_8d60a3888f98$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8d60a3888f98$;

DO $bootstrap_do_42098a6c1726$
BEGIN
  EXECUTE $bootstrap_sql_42098a6c1726$GRANT SELECT ON public.public_couriers TO anon, authenticated$bootstrap_sql_42098a6c1726$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42098a6c1726$;

DO $bootstrap_do_fd55515475e9$
BEGIN
  EXECUTE $bootstrap_sql_fd55515475e9$DROP POLICY IF EXISTS "Anyone can view active villages" ON public.villages$bootstrap_sql_fd55515475e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd55515475e9$;

DO $bootstrap_do_9c6c4f5b0752$
BEGIN
  EXECUTE $bootstrap_sql_9c6c4f5b0752$CREATE POLICY "Anyone can view active villages" ON public.villages FOR SELECT USING (is_active = true)$bootstrap_sql_9c6c4f5b0752$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c6c4f5b0752$;

DO $bootstrap_do_0c2c0645b99f$
BEGIN
  EXECUTE $bootstrap_sql_0c2c0645b99f$DROP POLICY IF EXISTS "Authenticated users can register village" ON public.villages$bootstrap_sql_0c2c0645b99f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c2c0645b99f$;

DO $bootstrap_do_ea92cd99ceaa$
BEGIN
  EXECUTE $bootstrap_sql_ea92cd99ceaa$CREATE POLICY "Authenticated users can register village" ON public.villages FOR INSERT TO authenticated WITH CHECK (registration_status = 'PENDING' AND is_active = false)$bootstrap_sql_ea92cd99ceaa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea92cd99ceaa$;

DO $bootstrap_do_952302c3a68a$
BEGIN
  EXECUTE $bootstrap_sql_952302c3a68a$DROP POLICY IF EXISTS "Admins can manage villages" ON public.villages$bootstrap_sql_952302c3a68a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_952302c3a68a$;

DO $bootstrap_do_47bd5f714990$
BEGIN
  EXECUTE $bootstrap_sql_47bd5f714990$CREATE POLICY "Admins can manage villages" ON public.villages FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_47bd5f714990$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47bd5f714990$;

DO $bootstrap_do_9cca94ed4db1$
BEGIN
  EXECUTE $bootstrap_sql_9cca94ed4db1$DROP POLICY IF EXISTS "Village owners can update own village" ON public.villages$bootstrap_sql_9cca94ed4db1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cca94ed4db1$;

DO $bootstrap_do_cc62e2a35e31$
BEGIN
  EXECUTE $bootstrap_sql_cc62e2a35e31$CREATE POLICY "Village owners can update own village" ON public.villages FOR UPDATE USING (user_id = auth.uid())$bootstrap_sql_cc62e2a35e31$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc62e2a35e31$;

DO $bootstrap_do_c73cca547fa4$
BEGIN
  EXECUTE $bootstrap_sql_c73cca547fa4$DROP POLICY IF EXISTS "Admin desa can update own village" ON public.villages$bootstrap_sql_c73cca547fa4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c73cca547fa4$;

DO $bootstrap_do_ef5db05bb141$
BEGIN
  EXECUTE $bootstrap_sql_ef5db05bb141$CREATE POLICY "Admin desa can update own village" ON public.villages FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = villages.id AND uv.user_id = auth.uid()))$bootstrap_sql_ef5db05bb141$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef5db05bb141$;

DO $bootstrap_do_5a8b5690f81f$
BEGIN
  EXECUTE $bootstrap_sql_5a8b5690f81f$DROP POLICY IF EXISTS "Admins manage village assignments" ON public.user_villages$bootstrap_sql_5a8b5690f81f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a8b5690f81f$;

DO $bootstrap_do_ea9fa73a6ea3$
BEGIN
  EXECUTE $bootstrap_sql_ea9fa73a6ea3$CREATE POLICY "Admins manage village assignments" ON public.user_villages FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_ea9fa73a6ea3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea9fa73a6ea3$;

DO $bootstrap_do_1250cefa2274$
BEGIN
  EXECUTE $bootstrap_sql_1250cefa2274$DROP POLICY IF EXISTS "Users view own village assignments" ON public.user_villages$bootstrap_sql_1250cefa2274$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1250cefa2274$;

DO $bootstrap_do_789b5f7f875f$
BEGIN
  EXECUTE $bootstrap_sql_789b5f7f875f$CREATE POLICY "Users view own village assignments" ON public.user_villages FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin())$bootstrap_sql_789b5f7f875f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_789b5f7f875f$;

DO $bootstrap_do_8aa46787d324$
BEGIN
  EXECUTE $bootstrap_sql_8aa46787d324$DROP POLICY IF EXISTS "Users can register own village assignment" ON public.user_villages$bootstrap_sql_8aa46787d324$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8aa46787d324$;

DO $bootstrap_do_e7d022d83851$
BEGIN
  EXECUTE $bootstrap_sql_e7d022d83851$CREATE POLICY "Users can register own village assignment" ON public.user_villages FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid())$bootstrap_sql_e7d022d83851$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7d022d83851$;

DO $bootstrap_do_c12d75aa7049$
BEGIN
  EXECUTE $bootstrap_sql_c12d75aa7049$DROP POLICY IF EXISTS "Anyone can view active categories" ON public.categories$bootstrap_sql_c12d75aa7049$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c12d75aa7049$;

DO $bootstrap_do_267f396be858$
BEGIN
  EXECUTE $bootstrap_sql_267f396be858$CREATE POLICY "Anyone can view active categories" ON public.categories FOR SELECT USING (is_active = true)$bootstrap_sql_267f396be858$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_267f396be858$;

DO $bootstrap_do_760514fd59c3$
BEGIN
  EXECUTE $bootstrap_sql_760514fd59c3$DROP POLICY IF EXISTS "Admins can manage categories" ON public.categories$bootstrap_sql_760514fd59c3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_760514fd59c3$;

DO $bootstrap_do_1ba6b4a583d6$
BEGIN
  EXECUTE $bootstrap_sql_1ba6b4a583d6$CREATE POLICY "Admins can manage categories" ON public.categories FOR ALL USING (public.is_admin())$bootstrap_sql_1ba6b4a583d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ba6b4a583d6$;

DO $bootstrap_do_995fe172e51e$
BEGIN
  EXECUTE $bootstrap_sql_995fe172e51e$DROP POLICY IF EXISTS "Anyone can view active groups" ON public.trade_groups$bootstrap_sql_995fe172e51e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_995fe172e51e$;

DO $bootstrap_do_32277cdc0921$
BEGIN
  EXECUTE $bootstrap_sql_32277cdc0921$CREATE POLICY "Anyone can view active groups" ON public.trade_groups FOR SELECT USING (is_active = true)$bootstrap_sql_32277cdc0921$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_32277cdc0921$;

DO $bootstrap_do_2ab6baa7bdb0$
BEGIN
  EXECUTE $bootstrap_sql_2ab6baa7bdb0$DROP POLICY IF EXISTS "Admins can manage all groups" ON public.trade_groups$bootstrap_sql_2ab6baa7bdb0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ab6baa7bdb0$;

DO $bootstrap_do_bf7eee98976a$
BEGIN
  EXECUTE $bootstrap_sql_bf7eee98976a$CREATE POLICY "Admins can manage all groups" ON public.trade_groups FOR ALL USING (public.is_admin())$bootstrap_sql_bf7eee98976a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf7eee98976a$;

DO $bootstrap_do_39122d714242$
BEGIN
  EXECUTE $bootstrap_sql_39122d714242$DROP POLICY IF EXISTS "Verifikators can manage own groups" ON public.trade_groups$bootstrap_sql_39122d714242$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_39122d714242$;

DO $bootstrap_do_f5399343d3aa$
BEGIN
  EXECUTE $bootstrap_sql_f5399343d3aa$CREATE POLICY "Verifikators can manage own groups" ON public.trade_groups FOR ALL USING (verifikator_id = auth.uid() OR public.is_admin())$bootstrap_sql_f5399343d3aa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f5399343d3aa$;

DO $bootstrap_do_14168c372622$
BEGIN
  EXECUTE $bootstrap_sql_14168c372622$DROP POLICY IF EXISTS "Anyone can view active packages" ON public.transaction_packages$bootstrap_sql_14168c372622$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14168c372622$;

DO $bootstrap_do_e68d3c39b786$
BEGIN
  EXECUTE $bootstrap_sql_e68d3c39b786$CREATE POLICY "Anyone can view active packages" ON public.transaction_packages FOR SELECT USING (is_active = true)$bootstrap_sql_e68d3c39b786$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e68d3c39b786$;

DO $bootstrap_do_5f67b8ab4ea8$
BEGIN
  EXECUTE $bootstrap_sql_5f67b8ab4ea8$DROP POLICY IF EXISTS "Admins can manage packages" ON public.transaction_packages$bootstrap_sql_5f67b8ab4ea8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5f67b8ab4ea8$;

DO $bootstrap_do_ac0ec2250301$
BEGIN
  EXECUTE $bootstrap_sql_ac0ec2250301$CREATE POLICY "Admins can manage packages" ON public.transaction_packages FOR ALL USING (public.is_admin())$bootstrap_sql_ac0ec2250301$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ac0ec2250301$;

DO $bootstrap_do_0f7522092ed8$
BEGIN
  EXECUTE $bootstrap_sql_0f7522092ed8$DROP POLICY IF EXISTS "Anyone can view quota tiers" ON public.quota_tiers$bootstrap_sql_0f7522092ed8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f7522092ed8$;

DO $bootstrap_do_12e5725881cd$
BEGIN
  EXECUTE $bootstrap_sql_12e5725881cd$CREATE POLICY "Anyone can view quota tiers" ON public.quota_tiers FOR SELECT USING (true)$bootstrap_sql_12e5725881cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_12e5725881cd$;

DO $bootstrap_do_88a9ff997668$
BEGIN
  EXECUTE $bootstrap_sql_88a9ff997668$DROP POLICY IF EXISTS "Admins can manage quota tiers" ON public.quota_tiers$bootstrap_sql_88a9ff997668$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_88a9ff997668$;

DO $bootstrap_do_e82e95bb4f95$
BEGIN
  EXECUTE $bootstrap_sql_e82e95bb4f95$CREATE POLICY "Admins can manage quota tiers" ON public.quota_tiers FOR ALL TO authenticated USING (public.is_admin())$bootstrap_sql_e82e95bb4f95$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e82e95bb4f95$;

DO $bootstrap_do_9e5e84204f92$
BEGIN
  EXECUTE $bootstrap_sql_9e5e84204f92$DROP POLICY IF EXISTS "Anyone can view active tourism" ON public.tourism$bootstrap_sql_9e5e84204f92$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e5e84204f92$;

DO $bootstrap_do_a77dadc35d84$
BEGIN
  EXECUTE $bootstrap_sql_a77dadc35d84$CREATE POLICY "Anyone can view active tourism" ON public.tourism FOR SELECT USING (is_active = true)$bootstrap_sql_a77dadc35d84$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a77dadc35d84$;

DO $bootstrap_do_79d83a942228$
BEGIN
  EXECUTE $bootstrap_sql_79d83a942228$DROP POLICY IF EXISTS "Admins can manage tourism" ON public.tourism$bootstrap_sql_79d83a942228$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_79d83a942228$;

DO $bootstrap_do_bd055956b334$
BEGIN
  EXECUTE $bootstrap_sql_bd055956b334$CREATE POLICY "Admins can manage tourism" ON public.tourism FOR ALL USING (public.is_admin())$bootstrap_sql_bd055956b334$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bd055956b334$;

DO $bootstrap_do_4ed278014926$
BEGIN
  EXECUTE $bootstrap_sql_4ed278014926$DROP POLICY IF EXISTS "Admin desa can manage tourism" ON public.tourism$bootstrap_sql_4ed278014926$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4ed278014926$;

DO $bootstrap_do_2663a9ae562e$
BEGIN
  EXECUTE $bootstrap_sql_2663a9ae562e$CREATE POLICY "Admin desa can manage tourism" ON public.tourism FOR ALL USING (EXISTS (SELECT 1 FROM public.villages WHERE villages.id = tourism.village_id AND villages.registration_status = 'APPROVED') AND public.is_admin_desa()) WITH CHECK (EXISTS (SELECT 1 FROM public.villages WHERE villages.id = tourism.village_id AND villages.registration_status = 'APPROVED') AND public.is_admin_desa())$bootstrap_sql_2663a9ae562e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2663a9ae562e$;

DO $bootstrap_do_b827d5c9bccb$
BEGIN
  EXECUTE $bootstrap_sql_b827d5c9bccb$DROP POLICY IF EXISTS "Admins can manage merchants" ON public.merchants$bootstrap_sql_b827d5c9bccb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b827d5c9bccb$;

DO $bootstrap_do_0aa631a02c8b$
BEGIN
  EXECUTE $bootstrap_sql_0aa631a02c8b$CREATE POLICY "Admins can manage merchants" ON public.merchants FOR ALL USING (public.is_admin())$bootstrap_sql_0aa631a02c8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0aa631a02c8b$;

DO $bootstrap_do_2b3586e7395e$
BEGIN
  EXECUTE $bootstrap_sql_2b3586e7395e$DROP POLICY IF EXISTS "Verifikator can manage merchants" ON public.merchants$bootstrap_sql_2b3586e7395e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b3586e7395e$;

DO $bootstrap_do_598dee1c491d$
BEGIN
  EXECUTE $bootstrap_sql_598dee1c491d$CREATE POLICY "Verifikator can manage merchants" ON public.merchants FOR ALL USING (public.is_verifikator())$bootstrap_sql_598dee1c491d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_598dee1c491d$;

DO $bootstrap_do_5145afd6dd21$
BEGIN
  EXECUTE $bootstrap_sql_5145afd6dd21$DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants$bootstrap_sql_5145afd6dd21$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5145afd6dd21$;

DO $bootstrap_do_69e2fd3bde18$
BEGIN
  EXECUTE $bootstrap_sql_69e2fd3bde18$CREATE POLICY "Merchants can update own data" ON public.merchants FOR UPDATE USING (user_id = auth.uid())$bootstrap_sql_69e2fd3bde18$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_69e2fd3bde18$;

DO $bootstrap_do_d8b4ffabdc99$
BEGIN
  EXECUTE $bootstrap_sql_d8b4ffabdc99$DROP POLICY IF EXISTS "Anyone can register merchant" ON public.merchants$bootstrap_sql_d8b4ffabdc99$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d8b4ffabdc99$;

DO $bootstrap_do_3e223fa87eea$
BEGIN
  EXECUTE $bootstrap_sql_3e223fa87eea$CREATE POLICY "Anyone can register merchant" ON public.merchants FOR INSERT WITH CHECK (registration_status = 'PENDING')$bootstrap_sql_3e223fa87eea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e223fa87eea$;

DO $bootstrap_do_e1f79302dea7$
BEGIN
  EXECUTE $bootstrap_sql_e1f79302dea7$DROP POLICY IF EXISTS "Authenticated users view active merchants" ON public.merchants$bootstrap_sql_e1f79302dea7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e1f79302dea7$;

DO $bootstrap_do_23c246b84108$
BEGIN
  EXECUTE $bootstrap_sql_23c246b84108$CREATE POLICY "Authenticated users view active merchants" ON public.merchants FOR SELECT USING ((user_id = auth.uid()) OR ((status = 'ACTIVE' AND registration_status = 'APPROVED' AND auth.uid() IS NOT NULL)) OR public.is_admin() OR public.is_verifikator())$bootstrap_sql_23c246b84108$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_23c246b84108$;

DO $bootstrap_do_5ec262c50efe$
BEGIN
  EXECUTE $bootstrap_sql_5ec262c50efe$DROP POLICY IF EXISTS "Anon can view basic merchant info" ON public.merchants$bootstrap_sql_5ec262c50efe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ec262c50efe$;

DO $bootstrap_do_c36add1584a2$
BEGIN
  EXECUTE $bootstrap_sql_c36add1584a2$CREATE POLICY "Anon can view basic merchant info" ON public.merchants FOR SELECT TO anon USING (status = 'ACTIVE' AND registration_status = 'APPROVED')$bootstrap_sql_c36add1584a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c36add1584a2$;

DO $bootstrap_do_ca46261689ad$
BEGIN
  EXECUTE $bootstrap_sql_ca46261689ad$DROP POLICY IF EXISTS "Admins can manage all subscriptions" ON public.merchant_subscriptions$bootstrap_sql_ca46261689ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca46261689ad$;

DO $bootstrap_do_c7192b4abd1f$
BEGIN
  EXECUTE $bootstrap_sql_c7192b4abd1f$CREATE POLICY "Admins can manage all subscriptions" ON public.merchant_subscriptions FOR ALL USING (public.is_admin())$bootstrap_sql_c7192b4abd1f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7192b4abd1f$;

DO $bootstrap_do_4da8f5542d35$
BEGIN
  EXECUTE $bootstrap_sql_4da8f5542d35$DROP POLICY IF EXISTS "Merchants can view own subscriptions" ON public.merchant_subscriptions$bootstrap_sql_4da8f5542d35$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4da8f5542d35$;

DO $bootstrap_do_3e03d9270cb1$
BEGIN
  EXECUTE $bootstrap_sql_3e03d9270cb1$CREATE POLICY "Merchants can view own subscriptions" ON public.merchant_subscriptions FOR SELECT USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = merchant_subscriptions.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_3e03d9270cb1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e03d9270cb1$;

DO $bootstrap_do_548bf581ba57$
BEGIN
  EXECUTE $bootstrap_sql_548bf581ba57$DROP POLICY IF EXISTS "Merchants can create subscriptions" ON public.merchant_subscriptions$bootstrap_sql_548bf581ba57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_548bf581ba57$;

DO $bootstrap_do_00dc35e7d40b$
BEGIN
  EXECUTE $bootstrap_sql_00dc35e7d40b$CREATE POLICY "Merchants can create subscriptions" ON public.merchant_subscriptions FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = merchant_subscriptions.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_00dc35e7d40b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00dc35e7d40b$;

DO $bootstrap_do_3045576450a2$
BEGIN
  EXECUTE $bootstrap_sql_3045576450a2$DROP POLICY IF EXISTS "Public can view merchant gallery" ON public.merchant_gallery$bootstrap_sql_3045576450a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3045576450a2$;

DO $bootstrap_do_963a225b59f2$
BEGIN
  EXECUTE $bootstrap_sql_963a225b59f2$CREATE POLICY "Public can view merchant gallery" ON public.merchant_gallery FOR SELECT USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = merchant_gallery.merchant_id AND merchants.status='ACTIVE' AND merchants.registration_status='APPROVED'))$bootstrap_sql_963a225b59f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_963a225b59f2$;

DO $bootstrap_do_593eb3bb9ade$
BEGIN
  EXECUTE $bootstrap_sql_593eb3bb9ade$DROP POLICY IF EXISTS "Merchants can manage own gallery" ON public.merchant_gallery$bootstrap_sql_593eb3bb9ade$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_593eb3bb9ade$;

DO $bootstrap_do_b571cde497a6$
BEGIN
  EXECUTE $bootstrap_sql_b571cde497a6$CREATE POLICY "Merchants can manage own gallery" ON public.merchant_gallery FOR ALL USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = merchant_gallery.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_b571cde497a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b571cde497a6$;

DO $bootstrap_do_2f5f9814d8d2$
BEGIN
  EXECUTE $bootstrap_sql_2f5f9814d8d2$DROP POLICY IF EXISTS "Admins can manage all galleries" ON public.merchant_gallery$bootstrap_sql_2f5f9814d8d2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2f5f9814d8d2$;

DO $bootstrap_do_de127f20d5b2$
BEGIN
  EXECUTE $bootstrap_sql_de127f20d5b2$CREATE POLICY "Admins can manage all galleries" ON public.merchant_gallery FOR ALL USING (public.is_admin())$bootstrap_sql_de127f20d5b2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de127f20d5b2$;

DO $bootstrap_do_4dd50a355f48$
BEGIN
  EXECUTE $bootstrap_sql_4dd50a355f48$DROP POLICY IF EXISTS "Users can view their own favorites" ON public.merchant_favorites$bootstrap_sql_4dd50a355f48$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4dd50a355f48$;

DO $bootstrap_do_9616481051f2$
BEGIN
  EXECUTE $bootstrap_sql_9616481051f2$CREATE POLICY "Users can view their own favorites" ON public.merchant_favorites FOR SELECT USING (auth.uid() = user_id)$bootstrap_sql_9616481051f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9616481051f2$;

DO $bootstrap_do_22d1fd2610ed$
BEGIN
  EXECUTE $bootstrap_sql_22d1fd2610ed$DROP POLICY IF EXISTS "Users can insert their own favorites" ON public.merchant_favorites$bootstrap_sql_22d1fd2610ed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22d1fd2610ed$;

DO $bootstrap_do_86f3f05c9dac$
BEGIN
  EXECUTE $bootstrap_sql_86f3f05c9dac$CREATE POLICY "Users can insert their own favorites" ON public.merchant_favorites FOR INSERT WITH CHECK (auth.uid() = user_id)$bootstrap_sql_86f3f05c9dac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_86f3f05c9dac$;

DO $bootstrap_do_db1c024e583c$
BEGIN
  EXECUTE $bootstrap_sql_db1c024e583c$DROP POLICY IF EXISTS "Users can delete their own favorites" ON public.merchant_favorites$bootstrap_sql_db1c024e583c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db1c024e583c$;

DO $bootstrap_do_d71aaf741c94$
BEGIN
  EXECUTE $bootstrap_sql_d71aaf741c94$CREATE POLICY "Users can delete their own favorites" ON public.merchant_favorites FOR DELETE USING (auth.uid() = user_id)$bootstrap_sql_d71aaf741c94$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d71aaf741c94$;

DO $bootstrap_do_13d7d023d68f$
BEGIN
  EXECUTE $bootstrap_sql_13d7d023d68f$DROP POLICY IF EXISTS "Admins can manage all members" ON public.group_members$bootstrap_sql_13d7d023d68f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_13d7d023d68f$;

DO $bootstrap_do_af18bae42fa6$
BEGIN
  EXECUTE $bootstrap_sql_af18bae42fa6$CREATE POLICY "Admins can manage all members" ON public.group_members FOR ALL USING (public.is_admin())$bootstrap_sql_af18bae42fa6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_af18bae42fa6$;

DO $bootstrap_do_b39638b4c8fb$
BEGIN
  EXECUTE $bootstrap_sql_b39638b4c8fb$DROP POLICY IF EXISTS "Merchants can view own membership" ON public.group_members$bootstrap_sql_b39638b4c8fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b39638b4c8fb$;

DO $bootstrap_do_47f73cab2e70$
BEGIN
  EXECUTE $bootstrap_sql_47f73cab2e70$CREATE POLICY "Merchants can view own membership" ON public.group_members FOR SELECT USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = group_members.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_47f73cab2e70$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47f73cab2e70$;

DO $bootstrap_do_acba83ed4021$
BEGIN
  EXECUTE $bootstrap_sql_acba83ed4021$DROP POLICY IF EXISTS "Verifikators can manage group members" ON public.group_members$bootstrap_sql_acba83ed4021$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_acba83ed4021$;

DO $bootstrap_do_86c3967103e1$
BEGIN
  EXECUTE $bootstrap_sql_86c3967103e1$CREATE POLICY "Verifikators can manage group members" ON public.group_members FOR ALL USING (EXISTS (SELECT 1 FROM public.trade_groups WHERE trade_groups.id = group_members.group_id AND (trade_groups.verifikator_id = auth.uid() OR public.is_admin())))$bootstrap_sql_86c3967103e1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_86c3967103e1$;

DO $bootstrap_do_5e1ef0a03d4d$
BEGIN
  EXECUTE $bootstrap_sql_5e1ef0a03d4d$DROP POLICY IF EXISTS "Admins can manage all payments" ON public.kas_payments$bootstrap_sql_5e1ef0a03d4d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5e1ef0a03d4d$;

DO $bootstrap_do_7ecfa16c101a$
BEGIN
  EXECUTE $bootstrap_sql_7ecfa16c101a$CREATE POLICY "Admins can manage all payments" ON public.kas_payments FOR ALL USING (public.is_admin())$bootstrap_sql_7ecfa16c101a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ecfa16c101a$;

DO $bootstrap_do_4d0f43d09eac$
BEGIN
  EXECUTE $bootstrap_sql_4d0f43d09eac$DROP POLICY IF EXISTS "Merchants can view own payments" ON public.kas_payments$bootstrap_sql_4d0f43d09eac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d0f43d09eac$;

DO $bootstrap_do_d87dc4a6738e$
BEGIN
  EXECUTE $bootstrap_sql_d87dc4a6738e$CREATE POLICY "Merchants can view own payments" ON public.kas_payments FOR SELECT USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = kas_payments.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_d87dc4a6738e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d87dc4a6738e$;

DO $bootstrap_do_b9702a793847$
BEGIN
  EXECUTE $bootstrap_sql_b9702a793847$DROP POLICY IF EXISTS "Verifikators can manage payments in their groups" ON public.kas_payments$bootstrap_sql_b9702a793847$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9702a793847$;

DO $bootstrap_do_047750f89e3d$
BEGIN
  EXECUTE $bootstrap_sql_047750f89e3d$CREATE POLICY "Verifikators can manage payments in their groups" ON public.kas_payments FOR ALL USING (EXISTS (SELECT 1 FROM public.trade_groups WHERE trade_groups.id = kas_payments.group_id AND (trade_groups.verifikator_id = auth.uid() OR public.is_admin())))$bootstrap_sql_047750f89e3d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_047750f89e3d$;

DO $bootstrap_do_5468a9f044d5$
BEGIN
  EXECUTE $bootstrap_sql_5468a9f044d5$DROP POLICY IF EXISTS "Verifikator can manage own announcements" ON public.group_announcements$bootstrap_sql_5468a9f044d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5468a9f044d5$;

DO $bootstrap_do_bef4f6be4031$
BEGIN
  EXECUTE $bootstrap_sql_bef4f6be4031$CREATE POLICY "Verifikator can manage own announcements" ON public.group_announcements FOR ALL USING (verifikator_id = auth.uid())$bootstrap_sql_bef4f6be4031$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bef4f6be4031$;

DO $bootstrap_do_cda58e7ce03a$
BEGIN
  EXECUTE $bootstrap_sql_cda58e7ce03a$DROP POLICY IF EXISTS "Group members can read announcements" ON public.group_announcements$bootstrap_sql_cda58e7ce03a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cda58e7ce03a$;

DO $bootstrap_do_490c4df524d1$
BEGIN
  EXECUTE $bootstrap_sql_490c4df524d1$CREATE POLICY "Group members can read announcements" ON public.group_announcements FOR SELECT USING (EXISTS (SELECT 1 FROM public.group_members gm JOIN public.merchants m ON m.id = gm.merchant_id WHERE gm.group_id = group_announcements.group_id AND m.user_id = auth.uid()))$bootstrap_sql_490c4df524d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_490c4df524d1$;

DO $bootstrap_do_aabe63ac5d0f$
BEGIN
  EXECUTE $bootstrap_sql_aabe63ac5d0f$DROP POLICY IF EXISTS "Anyone can view active codes" ON public.verifikator_codes$bootstrap_sql_aabe63ac5d0f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aabe63ac5d0f$;

DO $bootstrap_do_594217a27d6c$
BEGIN
  EXECUTE $bootstrap_sql_594217a27d6c$CREATE POLICY "Anyone can view active codes" ON public.verifikator_codes FOR SELECT USING (is_active = true)$bootstrap_sql_594217a27d6c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_594217a27d6c$;

DO $bootstrap_do_6db52f585c5d$
BEGIN
  EXECUTE $bootstrap_sql_6db52f585c5d$DROP POLICY IF EXISTS "Admin can manage all codes" ON public.verifikator_codes$bootstrap_sql_6db52f585c5d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6db52f585c5d$;

DO $bootstrap_do_a7d9670959e1$
BEGIN
  EXECUTE $bootstrap_sql_a7d9670959e1$CREATE POLICY "Admin can manage all codes" ON public.verifikator_codes FOR ALL USING (public.is_admin())$bootstrap_sql_a7d9670959e1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7d9670959e1$;

DO $bootstrap_do_174ddeb10641$
BEGIN
  EXECUTE $bootstrap_sql_174ddeb10641$DROP POLICY IF EXISTS "Verifikator can manage own codes" ON public.verifikator_codes$bootstrap_sql_174ddeb10641$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_174ddeb10641$;

DO $bootstrap_do_7bd3c01a5746$
BEGIN
  EXECUTE $bootstrap_sql_7bd3c01a5746$CREATE POLICY "Verifikator can manage own codes" ON public.verifikator_codes FOR ALL USING (verifikator_id = auth.uid() OR public.is_admin())$bootstrap_sql_7bd3c01a5746$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7bd3c01a5746$;

DO $bootstrap_do_bae93f861a58$
BEGIN
  EXECUTE $bootstrap_sql_bae93f861a58$DROP POLICY IF EXISTS "Admins can manage all earnings" ON public.verifikator_earnings$bootstrap_sql_bae93f861a58$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bae93f861a58$;

DO $bootstrap_do_6017bec70ab2$
BEGIN
  EXECUTE $bootstrap_sql_6017bec70ab2$CREATE POLICY "Admins can manage all earnings" ON public.verifikator_earnings FOR ALL USING (public.is_admin())$bootstrap_sql_6017bec70ab2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6017bec70ab2$;

DO $bootstrap_do_05d788f3627c$
BEGIN
  EXECUTE $bootstrap_sql_05d788f3627c$DROP POLICY IF EXISTS "Verifikators can view own earnings" ON public.verifikator_earnings$bootstrap_sql_05d788f3627c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_05d788f3627c$;

DO $bootstrap_do_ed04aff29d45$
BEGIN
  EXECUTE $bootstrap_sql_ed04aff29d45$CREATE POLICY "Verifikators can view own earnings" ON public.verifikator_earnings FOR SELECT USING (verifikator_id = auth.uid())$bootstrap_sql_ed04aff29d45$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed04aff29d45$;

DO $bootstrap_do_cb3839aef94f$
BEGIN
  EXECUTE $bootstrap_sql_cb3839aef94f$DROP POLICY IF EXISTS "Admins manage withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_cb3839aef94f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb3839aef94f$;

DO $bootstrap_do_0e9336043c73$
BEGIN
  EXECUTE $bootstrap_sql_0e9336043c73$CREATE POLICY "Admins manage withdrawals" ON public.verifikator_withdrawals FOR ALL USING (public.is_admin())$bootstrap_sql_0e9336043c73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e9336043c73$;

DO $bootstrap_do_591598cc7de9$
BEGIN
  EXECUTE $bootstrap_sql_591598cc7de9$DROP POLICY IF EXISTS "Verifikators can create withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_591598cc7de9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_591598cc7de9$;

DO $bootstrap_do_e7a1bcc434ca$
BEGIN
  EXECUTE $bootstrap_sql_e7a1bcc434ca$CREATE POLICY "Verifikators can create withdrawals" ON public.verifikator_withdrawals FOR INSERT WITH CHECK (verifikator_id = auth.uid() AND status = 'PENDING')$bootstrap_sql_e7a1bcc434ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7a1bcc434ca$;

DO $bootstrap_do_6bd3031843ab$
BEGIN
  EXECUTE $bootstrap_sql_6bd3031843ab$DROP POLICY IF EXISTS "Verifikators view own withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_6bd3031843ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6bd3031843ab$;

DO $bootstrap_do_ce47765c51b8$
BEGIN
  EXECUTE $bootstrap_sql_ce47765c51b8$CREATE POLICY "Verifikators view own withdrawals" ON public.verifikator_withdrawals FOR SELECT USING (verifikator_id = auth.uid() OR public.is_admin())$bootstrap_sql_ce47765c51b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ce47765c51b8$;

DO $bootstrap_do_6e86a2fc0e76$
BEGIN
  EXECUTE $bootstrap_sql_6e86a2fc0e76$DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers$bootstrap_sql_6e86a2fc0e76$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e86a2fc0e76$;

DO $bootstrap_do_984ec05e051c$
BEGIN
  EXECUTE $bootstrap_sql_984ec05e051c$CREATE POLICY "Admins can manage couriers" ON public.couriers FOR ALL TO authenticated USING (public.is_admin())$bootstrap_sql_984ec05e051c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_984ec05e051c$;

DO $bootstrap_do_84e43915d8f7$
BEGIN
  EXECUTE $bootstrap_sql_84e43915d8f7$DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers$bootstrap_sql_84e43915d8f7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_84e43915d8f7$;

DO $bootstrap_do_a94f8fd6ae26$
BEGIN
  EXECUTE $bootstrap_sql_a94f8fd6ae26$CREATE POLICY "Verifikator can manage couriers" ON public.couriers FOR ALL TO authenticated USING (public.is_verifikator())$bootstrap_sql_a94f8fd6ae26$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a94f8fd6ae26$;

DO $bootstrap_do_500ff9017c64$
BEGIN
  EXECUTE $bootstrap_sql_500ff9017c64$DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers$bootstrap_sql_500ff9017c64$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_500ff9017c64$;

DO $bootstrap_do_97f8c8a1219b$
BEGIN
  EXECUTE $bootstrap_sql_97f8c8a1219b$CREATE POLICY "Anyone can register as courier" ON public.couriers FOR INSERT TO authenticated WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE')$bootstrap_sql_97f8c8a1219b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_97f8c8a1219b$;

DO $bootstrap_do_5d7284b6358e$
BEGIN
  EXECUTE $bootstrap_sql_5d7284b6358e$DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers$bootstrap_sql_5d7284b6358e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d7284b6358e$;

DO $bootstrap_do_2c34d7e87e27$
BEGIN
  EXECUTE $bootstrap_sql_2c34d7e87e27$CREATE POLICY "Couriers can view own data" ON public.couriers FOR SELECT TO authenticated USING (user_id = auth.uid())$bootstrap_sql_2c34d7e87e27$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c34d7e87e27$;

DO $bootstrap_do_3577ae88ed62$
BEGIN
  EXECUTE $bootstrap_sql_3577ae88ed62$DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers$bootstrap_sql_3577ae88ed62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3577ae88ed62$;

DO $bootstrap_do_326009932ec9$
BEGIN
  EXECUTE $bootstrap_sql_326009932ec9$CREATE POLICY "Couriers can update own location" ON public.couriers FOR UPDATE TO authenticated USING (user_id = auth.uid() AND status = 'ACTIVE')$bootstrap_sql_326009932ec9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_326009932ec9$;

DO $bootstrap_do_1b2373698f56$
BEGIN
  EXECUTE $bootstrap_sql_1b2373698f56$DROP POLICY IF EXISTS "Public can view approved couriers" ON public.couriers$bootstrap_sql_1b2373698f56$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1b2373698f56$;

DO $bootstrap_do_1abd32eb5add$
BEGIN
  EXECUTE $bootstrap_sql_1abd32eb5add$CREATE POLICY "Public can view approved couriers" ON public.couriers FOR SELECT USING (registration_status = 'APPROVED' AND status = 'ACTIVE')$bootstrap_sql_1abd32eb5add$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1abd32eb5add$;

DO $bootstrap_do_6d07e187e627$
BEGIN
  EXECUTE $bootstrap_sql_6d07e187e627$DROP POLICY IF EXISTS "Admins can manage courier earnings" ON public.courier_earnings$bootstrap_sql_6d07e187e627$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d07e187e627$;

DO $bootstrap_do_9ddf46a5c476$
BEGIN
  EXECUTE $bootstrap_sql_9ddf46a5c476$CREATE POLICY "Admins can manage courier earnings" ON public.courier_earnings FOR ALL USING (public.is_admin())$bootstrap_sql_9ddf46a5c476$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ddf46a5c476$;

DO $bootstrap_do_a66ef731575c$
BEGIN
  EXECUTE $bootstrap_sql_a66ef731575c$DROP POLICY IF EXISTS "Couriers can view own earnings" ON public.courier_earnings$bootstrap_sql_a66ef731575c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a66ef731575c$;

DO $bootstrap_do_e76c4716ec7b$
BEGIN
  EXECUTE $bootstrap_sql_e76c4716ec7b$CREATE POLICY "Couriers can view own earnings" ON public.courier_earnings FOR SELECT USING (EXISTS (SELECT 1 FROM public.couriers WHERE couriers.id = courier_earnings.courier_id AND couriers.user_id = auth.uid()))$bootstrap_sql_e76c4716ec7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e76c4716ec7b$;

DO $bootstrap_do_485b2f8e39b5$
BEGIN
  EXECUTE $bootstrap_sql_485b2f8e39b5$DROP POLICY IF EXISTS "Admins full access courier withdrawals" ON public.courier_withdrawal_requests$bootstrap_sql_485b2f8e39b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_485b2f8e39b5$;

DO $bootstrap_do_16327f0b97e8$
BEGIN
  EXECUTE $bootstrap_sql_16327f0b97e8$CREATE POLICY "Admins full access courier withdrawals" ON public.courier_withdrawal_requests FOR ALL USING (public.is_admin())$bootstrap_sql_16327f0b97e8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_16327f0b97e8$;

DO $bootstrap_do_dd22a7c3ae5f$
BEGIN
  EXECUTE $bootstrap_sql_dd22a7c3ae5f$DROP POLICY IF EXISTS "Couriers can view own withdrawals" ON public.courier_withdrawal_requests$bootstrap_sql_dd22a7c3ae5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dd22a7c3ae5f$;

DO $bootstrap_do_dda8558e94fd$
BEGIN
  EXECUTE $bootstrap_sql_dda8558e94fd$CREATE POLICY "Couriers can view own withdrawals" ON public.courier_withdrawal_requests FOR SELECT USING (courier_id = public.get_user_courier_id())$bootstrap_sql_dda8558e94fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dda8558e94fd$;

DO $bootstrap_do_47ff500d2d0d$
BEGIN
  EXECUTE $bootstrap_sql_47ff500d2d0d$DROP POLICY IF EXISTS "Couriers can create own withdrawals" ON public.courier_withdrawal_requests$bootstrap_sql_47ff500d2d0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47ff500d2d0d$;

DO $bootstrap_do_309562226448$
BEGIN
  EXECUTE $bootstrap_sql_309562226448$CREATE POLICY "Couriers can create own withdrawals" ON public.courier_withdrawal_requests FOR INSERT WITH CHECK (courier_id = public.get_user_courier_id())$bootstrap_sql_309562226448$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_309562226448$;

DO $bootstrap_do_587a90654c5e$
BEGIN
  EXECUTE $bootstrap_sql_587a90654c5e$DROP POLICY IF EXISTS "Couriers can view own deposits" ON public.courier_deposits$bootstrap_sql_587a90654c5e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_587a90654c5e$;

DO $bootstrap_do_fe4c735d4822$
BEGIN
  EXECUTE $bootstrap_sql_fe4c735d4822$CREATE POLICY "Couriers can view own deposits" ON public.courier_deposits FOR SELECT USING (courier_id = public.get_user_courier_id())$bootstrap_sql_fe4c735d4822$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fe4c735d4822$;

DO $bootstrap_do_851593c17e01$
BEGIN
  EXECUTE $bootstrap_sql_851593c17e01$DROP POLICY IF EXISTS "Couriers can create own deposits" ON public.courier_deposits$bootstrap_sql_851593c17e01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_851593c17e01$;

DO $bootstrap_do_386e1b72c66e$
BEGIN
  EXECUTE $bootstrap_sql_386e1b72c66e$CREATE POLICY "Couriers can create own deposits" ON public.courier_deposits FOR INSERT WITH CHECK (courier_id = public.get_user_courier_id())$bootstrap_sql_386e1b72c66e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_386e1b72c66e$;

DO $bootstrap_do_308501d5b38e$
BEGIN
  EXECUTE $bootstrap_sql_308501d5b38e$DROP POLICY IF EXISTS "Admins full access courier deposits" ON public.courier_deposits$bootstrap_sql_308501d5b38e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_308501d5b38e$;

DO $bootstrap_do_3dfe0fb0431e$
BEGIN
  EXECUTE $bootstrap_sql_3dfe0fb0431e$CREATE POLICY "Admins full access courier deposits" ON public.courier_deposits FOR ALL USING (public.is_admin())$bootstrap_sql_3dfe0fb0431e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3dfe0fb0431e$;

DO $bootstrap_do_b687727eee17$
BEGIN
  EXECUTE $bootstrap_sql_b687727eee17$DROP POLICY IF EXISTS "Couriers can view own balance logs" ON public.courier_balance_logs$bootstrap_sql_b687727eee17$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b687727eee17$;

DO $bootstrap_do_1b4988507f80$
BEGIN
  EXECUTE $bootstrap_sql_1b4988507f80$CREATE POLICY "Couriers can view own balance logs" ON public.courier_balance_logs FOR SELECT USING (courier_id = public.get_user_courier_id())$bootstrap_sql_1b4988507f80$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1b4988507f80$;

DO $bootstrap_do_aab2c50f44c7$
BEGIN
  EXECUTE $bootstrap_sql_aab2c50f44c7$DROP POLICY IF EXISTS "Admins full access balance logs" ON public.courier_balance_logs$bootstrap_sql_aab2c50f44c7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aab2c50f44c7$;

DO $bootstrap_do_46edd8de6e98$
BEGIN
  EXECUTE $bootstrap_sql_46edd8de6e98$CREATE POLICY "Admins full access balance logs" ON public.courier_balance_logs FOR ALL USING (public.is_admin())$bootstrap_sql_46edd8de6e98$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46edd8de6e98$;

DO $bootstrap_do_692f9f7980a5$
BEGIN
  EXECUTE $bootstrap_sql_692f9f7980a5$
