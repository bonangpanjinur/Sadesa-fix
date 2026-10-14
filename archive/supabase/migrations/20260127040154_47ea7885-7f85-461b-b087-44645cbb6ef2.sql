-- Update merchants table to have proper registration status
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS registration_status text NOT NULL DEFAULT 'PENDING',
ADD COLUMN IF NOT EXISTS registered_at timestamp with time zone DEFAULT now(),
ADD COLUMN IF NOT EXISTS approved_at timestamp with time zone,
ADD COLUMN IF NOT EXISTS approved_by uuid,
ADD COLUMN IF NOT EXISTS rejection_reason text$bootstrap_sql_bf048aeb1393$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf048aeb1393$;

DO $bootstrap_do_25329d23bba1$
BEGIN
  EXECUTE $bootstrap_sql_25329d23bba1$-- Update villages table to have proper registration status
ALTER TABLE public.villages
ADD COLUMN IF NOT EXISTS registration_status text NOT NULL DEFAULT 'PENDING',
ADD COLUMN IF NOT EXISTS registered_at timestamp with time zone DEFAULT now(),
ADD COLUMN IF NOT EXISTS approved_at timestamp with time zone,
ADD COLUMN IF NOT EXISTS approved_by uuid,
ADD COLUMN IF NOT EXISTS rejection_reason text,
ADD COLUMN IF NOT EXISTS contact_name text,
ADD COLUMN IF NOT EXISTS contact_phone text,
ADD COLUMN IF NOT EXISTS contact_email text$bootstrap_sql_25329d23bba1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_25329d23bba1$;

DO $bootstrap_do_b638657e26d4$
BEGIN
  EXECUTE $bootstrap_sql_b638657e26d4$-- Create helper function to check if user is verifikator
CREATE OR REPLACE FUNCTION public.is_verifikator()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'verifikator')
$$$bootstrap_sql_b638657e26d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b638657e26d4$;

DO $bootstrap_do_d47390ac3d10$
BEGIN
  EXECUTE $bootstrap_sql_d47390ac3d10$-- Allow anyone to register a village (pending approval by admin)
DROP POLICY IF EXISTS "Anyone can register village" ON public.villages$bootstrap_sql_d47390ac3d10$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d47390ac3d10$;

DO $bootstrap_do_cb59f97b210d$
BEGIN
  EXECUTE $bootstrap_sql_cb59f97b210d$CREATE POLICY "Anyone can register village"
ON public.villages
FOR INSERT
WITH CHECK (
  registration_status = 'PENDING' AND
  is_active = false
)$bootstrap_sql_cb59f97b210d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb59f97b210d$;

DO $bootstrap_do_a54cbcc473f8$
BEGIN
  EXECUTE $bootstrap_sql_a54cbcc473f8$-- Allow anyone to register a merchant (pending approval by verifikator)
DROP POLICY IF EXISTS "Anyone can register merchant" ON public.merchants$bootstrap_sql_a54cbcc473f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a54cbcc473f8$;

DO $bootstrap_do_93963015a93a$
BEGIN
  EXECUTE $bootstrap_sql_93963015a93a$CREATE POLICY "Anyone can register merchant"
ON public.merchants
FOR INSERT
WITH CHECK (
  registration_status = 'PENDING' AND
  status = 'PENDING'
)$bootstrap_sql_93963015a93a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_93963015a93a$;

DO $bootstrap_do_9027ff350ef1$
BEGIN
  EXECUTE $bootstrap_sql_9027ff350ef1$-- Verifikator can manage merchants (approve/reject)
DROP POLICY IF EXISTS "Verifikator can manage merchants" ON public.merchants$bootstrap_sql_9027ff350ef1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9027ff350ef1$;

DO $bootstrap_do_486368fee90e$
BEGIN
  EXECUTE $bootstrap_sql_486368fee90e$CREATE POLICY "Verifikator can manage merchants"
ON public.merchants
FOR ALL
USING (is_verifikator())$bootstrap_sql_486368fee90e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_486368fee90e$;

DO $bootstrap_do_e026c51c1ce6$
BEGIN
  EXECUTE $bootstrap_sql_e026c51c1ce6$-- Update existing merchants to have APPROVED status
UPDATE public.merchants SET registration_status = 'APPROVED' WHERE registration_status = 'PENDING'$bootstrap_sql_e026c51c1ce6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e026c51c1ce6$;

DO $bootstrap_do_efae0730d2be$
BEGIN
  EXECUTE $bootstrap_sql_efae0730d2be$-- Update existing villages to have APPROVED status
UPDATE public.villages SET registration_status = 'APPROVED' WHERE registration_status = 'PENDING'$bootstrap_sql_efae0730d2be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_efae0730d2be$;

DO $bootstrap_do_9b4eebf3f9e7$
BEGIN
  EXECUTE $bootstrap_sql_9b4eebf3f9e7$
