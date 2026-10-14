-- Multi-category merchants and safe operating-hours constraints.
-- Legacy merchants.business_category is retained for backwards compatibility.

CREATE TABLE IF NOT EXISTS public.merchant_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, category_id)
)$bootstrap_sql_19d39a7cec60$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19d39a7cec60$;

DO $bootstrap_do_651557d618a9$
BEGIN
  EXECUTE $bootstrap_sql_651557d618a9$CREATE INDEX IF NOT EXISTS merchant_categories_category_id_idx
  ON public.merchant_categories(category_id)$bootstrap_sql_651557d618a9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_651557d618a9$;

DO $bootstrap_do_ef3aa3df675d$
BEGIN
  EXECUTE $bootstrap_sql_ef3aa3df675d$ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY$bootstrap_sql_ef3aa3df675d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef3aa3df675d$;

DO $bootstrap_do_95022b59629e$
BEGIN
  EXECUTE $bootstrap_sql_95022b59629e$DROP POLICY IF EXISTS "merchant_manage_own_categories" ON public.merchant_categories$bootstrap_sql_95022b59629e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95022b59629e$;

DO $bootstrap_do_0593ea2b6a30$
BEGIN
  EXECUTE $bootstrap_sql_0593ea2b6a30$CREATE POLICY "merchant_manage_own_categories" ON public.merchant_categories
  FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))
  WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))$bootstrap_sql_0593ea2b6a30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0593ea2b6a30$;

DO $bootstrap_do_f48f32154b4b$
BEGIN
  EXECUTE $bootstrap_sql_f48f32154b4b$DROP POLICY IF EXISTS "admin_manage_merchant_categories" ON public.merchant_categories$bootstrap_sql_f48f32154b4b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f48f32154b4b$;

DO $bootstrap_do_f8ca68e7099d$
BEGIN
  EXECUTE $bootstrap_sql_f8ca68e7099d$CREATE POLICY "admin_manage_merchant_categories" ON public.merchant_categories
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin())$bootstrap_sql_f8ca68e7099d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8ca68e7099d$;

DO $bootstrap_do_741867492163$
BEGIN
  EXECUTE $bootstrap_sql_741867492163$DROP POLICY IF EXISTS "public_read_merchant_categories" ON public.merchant_categories$bootstrap_sql_741867492163$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_741867492163$;

DO $bootstrap_do_c2539c384de4$
BEGIN
  EXECUTE $bootstrap_sql_c2539c384de4$CREATE POLICY "public_read_merchant_categories" ON public.merchant_categories
  FOR SELECT
  USING (true)$bootstrap_sql_c2539c384de4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2539c384de4$;

DO $bootstrap_do_4683c6b61058$
BEGIN
  EXECUTE $bootstrap_sql_4683c6b61058$-- Preserve the existing single-category value for all merchants during rollout.
INSERT INTO public.merchant_categories (merchant_id, category_id)
SELECT m.id, c.id
FROM public.merchants m
JOIN public.categories c ON c.slug = m.business_category
WHERE m.business_category IS NOT NULL
  AND c.is_active = true
ON CONFLICT (merchant_id, category_id) DO NOTHING$bootstrap_sql_4683c6b61058$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4683c6b61058$;

DO $bootstrap_do_c5175f8b3dc5$
BEGIN
  EXECUTE $bootstrap_sql_c5175f8b3dc5$COMMENT ON TABLE public.merchant_categories IS
  'Many-to-many category assignment for merchants. merchants.business_category remains as a legacy fallback.'$bootstrap_sql_c5175f8b3dc5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5175f8b3dc5$;

DO $bootstrap_do_136489be7d62$
BEGIN
  EXECUTE $bootstrap_sql_136489be7d62$-- Make weekly schedules safe for overnight hours while preserving existing rows.
ALTER TABLE public.merchant_operating_hours
  DROP CONSTRAINT IF EXISTS merchant_operating_hours_time_order$bootstrap_sql_136489be7d62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_136489be7d62$;

DO $bootstrap_do_618016552a25$
BEGIN
  EXECUTE $bootstrap_sql_618016552a25$ALTER TABLE public.merchant_operating_hours
  ADD CONSTRAINT merchant_operating_hours_time_format
  CHECK (open_time IS NOT NULL AND close_time IS NOT NULL)$bootstrap_sql_618016552a25$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_618016552a25$;

DO $bootstrap_do_68404d81ebe3$
BEGIN
  EXECUTE $bootstrap_sql_68404d81ebe3$COMMENT ON TABLE public.merchant_operating_hours IS
  'Weekly merchant schedule; day_of_week uses 0 Sunday through 6 Saturday, and close_time may be earlier than open_time for overnight hours.'$bootstrap_sql_68404d81ebe3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68404d81ebe3$;

DO $bootstrap_do_0a39a0f287bd$
BEGIN
  EXECUTE $bootstrap_sql_0a39a0f287bd$NOTIFY pgrst, 'reload schema'$bootstrap_sql_0a39a0f287bd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a39a0f287bd$;

DO $bootstrap_do_83fa3e869a99$
BEGIN
  EXECUTE $bootstrap_sql_83fa3e869a99$
