-- Create couriers table for village delivery persons
CREATE TABLE public.couriers (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    email TEXT,
    -- Address fields
    province TEXT NOT NULL,
    city TEXT NOT NULL,
    district TEXT NOT NULL,
    subdistrict TEXT NOT NULL,
    address TEXT NOT NULL,
    -- Documents
    ktp_number TEXT NOT NULL,
    ktp_image_url TEXT NOT NULL,
    photo_url TEXT NOT NULL,
    vehicle_type TEXT NOT NULL DEFAULT 'motor',
    vehicle_plate TEXT,
    vehicle_image_url TEXT NOT NULL,
    -- Status
    registration_status TEXT NOT NULL DEFAULT 'PENDING',
    status TEXT NOT NULL DEFAULT 'INACTIVE',
    is_available BOOLEAN NOT NULL DEFAULT false,
    -- Tracking
    current_lat NUMERIC,
    current_lng NUMERIC,
    last_location_update TIMESTAMP WITH TIME ZONE,
    -- Metadata
    village_id UUID REFERENCES public.villages(id),
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_edf764f7ce14$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_edf764f7ce14$;

DO $bootstrap_do_bf21f5153844$
BEGIN
  EXECUTE $bootstrap_sql_bf21f5153844$-- Create app_settings table for dynamic configuration
CREATE TABLE public.app_settings (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    value JSONB NOT NULL DEFAULT '{}',
    description TEXT,
    category TEXT NOT NULL DEFAULT 'general',
    updated_by UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_bf21f5153844$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf21f5153844$;

DO $bootstrap_do_a0083492e0f5$
BEGIN
  EXECUTE $bootstrap_sql_a0083492e0f5$-- Enable RLS
ALTER TABLE public.couriers ENABLE ROW LEVEL SECURITY$bootstrap_sql_a0083492e0f5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a0083492e0f5$;

DO $bootstrap_do_c8af4832175e$
BEGIN
  EXECUTE $bootstrap_sql_c8af4832175e$ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY$bootstrap_sql_c8af4832175e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8af4832175e$;

DO $bootstrap_do_523627b64db5$
BEGIN
  EXECUTE $bootstrap_sql_523627b64db5$-- RLS policies for couriers
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers$bootstrap_sql_523627b64db5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_523627b64db5$;

DO $bootstrap_do_f120607cfd03$
BEGIN
  EXECUTE $bootstrap_sql_f120607cfd03$CREATE POLICY "Admins can manage couriers" ON public.couriers
FOR ALL USING (is_admin())$bootstrap_sql_f120607cfd03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f120607cfd03$;

DO $bootstrap_do_c9a05d14772d$
BEGIN
  EXECUTE $bootstrap_sql_c9a05d14772d$DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers$bootstrap_sql_c9a05d14772d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c9a05d14772d$;

DO $bootstrap_do_040b7badc2f4$
BEGIN
  EXECUTE $bootstrap_sql_040b7badc2f4$CREATE POLICY "Verifikator can manage couriers" ON public.couriers
FOR ALL USING (is_verifikator())$bootstrap_sql_040b7badc2f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_040b7badc2f4$;

DO $bootstrap_do_0b1245be7106$
BEGIN
  EXECUTE $bootstrap_sql_0b1245be7106$DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers$bootstrap_sql_0b1245be7106$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b1245be7106$;

DO $bootstrap_do_66788079c58f$
BEGIN
  EXECUTE $bootstrap_sql_66788079c58f$CREATE POLICY "Anyone can register as courier" ON public.couriers
FOR INSERT WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE')$bootstrap_sql_66788079c58f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_66788079c58f$;

DO $bootstrap_do_42f6c4d12e8f$
BEGIN
  EXECUTE $bootstrap_sql_42f6c4d12e8f$DROP POLICY IF EXISTS "Active couriers visible to authenticated" ON public.couriers$bootstrap_sql_42f6c4d12e8f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42f6c4d12e8f$;

DO $bootstrap_do_7ef966baf0c5$
BEGIN
  EXECUTE $bootstrap_sql_7ef966baf0c5$CREATE POLICY "Active couriers visible to authenticated" ON public.couriers
FOR SELECT USING (status = 'ACTIVE' AND auth.uid() IS NOT NULL)$bootstrap_sql_7ef966baf0c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ef966baf0c5$;

DO $bootstrap_do_d228e872fa27$
BEGIN
  EXECUTE $bootstrap_sql_d228e872fa27$DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers$bootstrap_sql_d228e872fa27$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d228e872fa27$;

DO $bootstrap_do_91bfc6677394$
BEGIN
  EXECUTE $bootstrap_sql_91bfc6677394$CREATE POLICY "Couriers can view own data" ON public.couriers
FOR SELECT USING (user_id = auth.uid())$bootstrap_sql_91bfc6677394$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_91bfc6677394$;

DO $bootstrap_do_7996be54c857$
BEGIN
  EXECUTE $bootstrap_sql_7996be54c857$DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers$bootstrap_sql_7996be54c857$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7996be54c857$;

DO $bootstrap_do_6db413bc5dc1$
BEGIN
  EXECUTE $bootstrap_sql_6db413bc5dc1$CREATE POLICY "Couriers can update own location" ON public.couriers
FOR UPDATE USING (user_id = auth.uid() AND status = 'ACTIVE')$bootstrap_sql_6db413bc5dc1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6db413bc5dc1$;

DO $bootstrap_do_dabad034bf50$
BEGIN
  EXECUTE $bootstrap_sql_dabad034bf50$-- RLS policies for app_settings
DROP POLICY IF EXISTS "Admins can manage settings" ON public.app_settings$bootstrap_sql_dabad034bf50$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dabad034bf50$;

DO $bootstrap_do_6c55ff002d84$
BEGIN
  EXECUTE $bootstrap_sql_6c55ff002d84$CREATE POLICY "Admins can manage settings" ON public.app_settings
FOR ALL USING (is_admin())$bootstrap_sql_6c55ff002d84$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c55ff002d84$;

DO $bootstrap_do_5aed5a53eebb$
BEGIN
  EXECUTE $bootstrap_sql_5aed5a53eebb$DROP POLICY IF EXISTS "Anyone can view settings" ON public.app_settings$bootstrap_sql_5aed5a53eebb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5aed5a53eebb$;

DO $bootstrap_do_2d6de60a57f0$
BEGIN
  EXECUTE $bootstrap_sql_2d6de60a57f0$CREATE POLICY "Anyone can view settings" ON public.app_settings
FOR SELECT USING (true)$bootstrap_sql_2d6de60a57f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d6de60a57f0$;

DO $bootstrap_do_779e1b0c4c9f$
BEGIN
  EXECUTE $bootstrap_sql_779e1b0c4c9f$-- Update trigger for couriers
DROP TRIGGER IF EXISTS update_couriers_updated_at ON public.couriers$bootstrap_sql_779e1b0c4c9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_779e1b0c4c9f$;

DO $bootstrap_do_77c9fe305efa$
BEGIN
  EXECUTE $bootstrap_sql_77c9fe305efa$CREATE TRIGGER update_couriers_updated_at
BEFORE UPDATE ON public.couriers
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_77c9fe305efa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77c9fe305efa$;

DO $bootstrap_do_31d54aa891fa$
BEGIN
  EXECUTE $bootstrap_sql_31d54aa891fa$-- Update trigger for app_settings
DROP TRIGGER IF EXISTS update_app_settings_updated_at ON public.app_settings$bootstrap_sql_31d54aa891fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31d54aa891fa$;

DO $bootstrap_do_55ff35189e9a$
BEGIN
  EXECUTE $bootstrap_sql_55ff35189e9a$CREATE TRIGGER update_app_settings_updated_at
BEFORE UPDATE ON public.app_settings
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_55ff35189e9a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_55ff35189e9a$;

DO $bootstrap_do_d86a5c05bbe6$
BEGIN
  EXECUTE $bootstrap_sql_d86a5c05bbe6$-- Insert default settings
INSERT INTO public.app_settings (key, value, description, category) VALUES
('registration_village', '{"enabled": true}', 'Enable/disable village registration', 'registration'),
('registration_merchant', '{"enabled": true}', 'Enable/disable merchant registration', 'registration'),
('registration_courier', '{"enabled": true}', 'Enable/disable courier registration', 'registration'),
('address_api', '{"provider": "emsifa", "base_url": "https://emsifa.github.io/api-wilayah-indonesia/api"}', 'Address API configuration', 'integration'),
('payment_midtrans', '{"enabled": false, "server_key": "", "client_key": "", "is_production": false}', 'Midtrans payment gateway', 'payment'),
('payment_xendit', '{"enabled": false, "secret_key": "", "public_key": ""}', 'Xendit payment gateway', 'payment')
ON CONFLICT DO NOTHING$bootstrap_sql_d86a5c05bbe6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d86a5c05bbe6$;

DO $bootstrap_do_360b35257b74$
BEGIN
  EXECUTE $bootstrap_sql_360b35257b74$
