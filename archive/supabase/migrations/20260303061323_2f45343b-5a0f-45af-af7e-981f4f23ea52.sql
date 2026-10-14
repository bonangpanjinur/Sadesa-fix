-- Create ride_requests table for Ojek Desa feature
CREATE TABLE public.ride_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  passenger_id uuid NOT NULL,
  driver_id uuid REFERENCES public.couriers(id) ON DELETE SET NULL,
  pickup_lat numeric NOT NULL,
  pickup_lng numeric NOT NULL,
  pickup_address text NOT NULL DEFAULT '',
  destination_lat numeric NOT NULL,
  destination_lng numeric NOT NULL,
  destination_address text NOT NULL DEFAULT '',
  distance_km numeric NOT NULL DEFAULT 0,
  estimated_fare integer NOT NULL DEFAULT 0,
  final_fare integer,
  status text NOT NULL DEFAULT 'SEARCHING',
  accepted_at timestamp with time zone,
  picked_up_at timestamp with time zone,
  completed_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  cancellation_reason text,
  rating integer,
  rating_comment text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
)$bootstrap_sql_b7da336bd7ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b7da336bd7ef$;

DO $bootstrap_do_fa3717e3477c$
BEGIN
  EXECUTE $bootstrap_sql_fa3717e3477c$-- Enable RLS
ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_fa3717e3477c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa3717e3477c$;

DO $bootstrap_do_b3e24d76352f$
BEGIN
  EXECUTE $bootstrap_sql_b3e24d76352f$-- Passengers can create ride requests
DROP POLICY IF EXISTS "Passengers can create rides" ON public.ride_requests$bootstrap_sql_b3e24d76352f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b3e24d76352f$;

DO $bootstrap_do_308cc661238a$
BEGIN
  EXECUTE $bootstrap_sql_308cc661238a$CREATE POLICY "Passengers can create rides"
ON public.ride_requests
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = passenger_id)$bootstrap_sql_308cc661238a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_308cc661238a$;

DO $bootstrap_do_68433fdb3a7d$
BEGIN
  EXECUTE $bootstrap_sql_68433fdb3a7d$-- Passengers can view own rides
DROP POLICY IF EXISTS "Passengers can view own rides" ON public.ride_requests$bootstrap_sql_68433fdb3a7d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68433fdb3a7d$;

DO $bootstrap_do_2f7a8772ff98$
BEGIN
  EXECUTE $bootstrap_sql_2f7a8772ff98$CREATE POLICY "Passengers can view own rides"
ON public.ride_requests
FOR SELECT
TO authenticated
USING (auth.uid() = passenger_id)$bootstrap_sql_2f7a8772ff98$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2f7a8772ff98$;

DO $bootstrap_do_0584c8ca327b$
BEGIN
  EXECUTE $bootstrap_sql_0584c8ca327b$-- Passengers can update own rides (cancel)
DROP POLICY IF EXISTS "Passengers can update own rides" ON public.ride_requests$bootstrap_sql_0584c8ca327b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0584c8ca327b$;

DO $bootstrap_do_578c1d616679$
BEGIN
  EXECUTE $bootstrap_sql_578c1d616679$CREATE POLICY "Passengers can update own rides"
ON public.ride_requests
FOR UPDATE
TO authenticated
USING (auth.uid() = passenger_id)$bootstrap_sql_578c1d616679$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_578c1d616679$;

DO $bootstrap_do_d62de757839e$
BEGIN
  EXECUTE $bootstrap_sql_d62de757839e$-- Drivers can view SEARCHING rides (to accept)
DROP POLICY IF EXISTS "Drivers can view searching rides" ON public.ride_requests$bootstrap_sql_d62de757839e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d62de757839e$;

DO $bootstrap_do_b524ad82fe1d$
BEGIN
  EXECUTE $bootstrap_sql_b524ad82fe1d$CREATE POLICY "Drivers can view searching rides"
ON public.ride_requests
FOR SELECT
TO authenticated
USING (
  status = 'SEARCHING' AND EXISTS (
    SELECT 1 FROM public.couriers
    WHERE couriers.user_id = auth.uid()
    AND couriers.registration_status = 'APPROVED'
    AND couriers.status = 'ACTIVE'
    AND couriers.is_available = true
  )
)$bootstrap_sql_b524ad82fe1d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b524ad82fe1d$;

DO $bootstrap_do_d1d6e1067a57$
BEGIN
  EXECUTE $bootstrap_sql_d1d6e1067a57$-- Drivers can view their assigned rides
DROP POLICY IF EXISTS "Drivers can view assigned rides" ON public.ride_requests$bootstrap_sql_d1d6e1067a57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d1d6e1067a57$;

DO $bootstrap_do_da3bf8d89baf$
BEGIN
  EXECUTE $bootstrap_sql_da3bf8d89baf$CREATE POLICY "Drivers can view assigned rides"
ON public.ride_requests
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.couriers
    WHERE couriers.id = ride_requests.driver_id
    AND couriers.user_id = auth.uid()
  )
)$bootstrap_sql_da3bf8d89baf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_da3bf8d89baf$;

DO $bootstrap_do_2aa3df68c2a9$
BEGIN
  EXECUTE $bootstrap_sql_2aa3df68c2a9$-- Drivers can update rides they accepted
DROP POLICY IF EXISTS "Drivers can update assigned rides" ON public.ride_requests$bootstrap_sql_2aa3df68c2a9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2aa3df68c2a9$;

DO $bootstrap_do_68c58dfe7df1$
BEGIN
  EXECUTE $bootstrap_sql_68c58dfe7df1$CREATE POLICY "Drivers can update assigned rides"
ON public.ride_requests
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.couriers
    WHERE couriers.id = ride_requests.driver_id
    AND couriers.user_id = auth.uid()
  )
)$bootstrap_sql_68c58dfe7df1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68c58dfe7df1$;

DO $bootstrap_do_e48ef1eb13a3$
BEGIN
  EXECUTE $bootstrap_sql_e48ef1eb13a3$-- Admin full access
DROP POLICY IF EXISTS "Admins can manage all rides" ON public.ride_requests$bootstrap_sql_e48ef1eb13a3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e48ef1eb13a3$;

DO $bootstrap_do_3aa4d672314f$
BEGIN
  EXECUTE $bootstrap_sql_3aa4d672314f$CREATE POLICY "Admins can manage all rides"
ON public.ride_requests
FOR ALL
TO authenticated
USING (public.is_admin())$bootstrap_sql_3aa4d672314f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3aa4d672314f$;

DO $bootstrap_do_f0ab5b0f24c4$
BEGIN
  EXECUTE $bootstrap_sql_f0ab5b0f24c4$-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_ride_requests_updated_at ON public.ride_requests$bootstrap_sql_f0ab5b0f24c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f0ab5b0f24c4$;

DO $bootstrap_do_63f44af4e598$
BEGIN
  EXECUTE $bootstrap_sql_63f44af4e598$CREATE TRIGGER update_ride_requests_updated_at
BEFORE UPDATE ON public.ride_requests
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_63f44af4e598$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63f44af4e598$;

DO $bootstrap_do_0e78febe3a66$
BEGIN
  EXECUTE $bootstrap_sql_0e78febe3a66$-- Enable realtime for ride_requests
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'ride_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_requests;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_0e78febe3a66$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e78febe3a66$;

DO $bootstrap_do_a3b47293a4b0$
BEGIN
  EXECUTE $bootstrap_sql_a3b47293a4b0$-- Insert default ride fare settings
INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'ride_fare_settings',
  '{"base_fare": 5000, "per_km_fare": 3000, "min_fare": 5000, "max_fare": 100000}'::jsonb,
  'ride',
  'Pengaturan tarif ojek desa: base_fare (tarif dasar), per_km_fare (tarif per km), min_fare (tarif minimum), max_fare (tarif maksimum)'
)
ON CONFLICT (key) DO NOTHING$bootstrap_sql_a3b47293a4b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3b47293a4b0$;

DO $bootstrap_do_fe91f75bdf75$
BEGIN
  EXECUTE $bootstrap_sql_fe91f75bdf75$
