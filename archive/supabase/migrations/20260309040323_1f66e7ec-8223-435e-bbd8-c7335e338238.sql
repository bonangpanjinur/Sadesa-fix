CREATE TABLE IF NOT EXISTS public.merchant_favorites (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, merchant_id)
)$bootstrap_sql_7bc518a86c0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7bc518a86c0d$;

DO $bootstrap_do_94fc0c378639$
BEGIN
  EXECUTE $bootstrap_sql_94fc0c378639$ALTER TABLE public.merchant_favorites ENABLE ROW LEVEL SECURITY$bootstrap_sql_94fc0c378639$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_94fc0c378639$;

DO $bootstrap_do_54828c62d82e$
BEGIN
  EXECUTE $bootstrap_sql_54828c62d82e$DROP POLICY IF EXISTS "Users can view their own favorites" ON public.merchant_favorites$bootstrap_sql_54828c62d82e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_54828c62d82e$;

DO $bootstrap_do_c61aaf4a4c76$
BEGIN
  EXECUTE $bootstrap_sql_c61aaf4a4c76$CREATE POLICY "Users can view their own favorites"
  ON public.merchant_favorites
  FOR SELECT
  USING (auth.uid() = user_id)$bootstrap_sql_c61aaf4a4c76$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c61aaf4a4c76$;

DO $bootstrap_do_5ad31f75b735$
BEGIN
  EXECUTE $bootstrap_sql_5ad31f75b735$DROP POLICY IF EXISTS "Users can insert their own favorites" ON public.merchant_favorites$bootstrap_sql_5ad31f75b735$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ad31f75b735$;

DO $bootstrap_do_529321cc28d0$
BEGIN
  EXECUTE $bootstrap_sql_529321cc28d0$CREATE POLICY "Users can insert their own favorites"
  ON public.merchant_favorites
  FOR INSERT
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_529321cc28d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_529321cc28d0$;

DO $bootstrap_do_e9789d294b2a$
BEGIN
  EXECUTE $bootstrap_sql_e9789d294b2a$DROP POLICY IF EXISTS "Users can delete their own favorites" ON public.merchant_favorites$bootstrap_sql_e9789d294b2a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e9789d294b2a$;

DO $bootstrap_do_a04c0336c23a$
BEGIN
  EXECUTE $bootstrap_sql_a04c0336c23a$CREATE POLICY "Users can delete their own favorites"
  ON public.merchant_favorites
  FOR DELETE
  USING (auth.uid() = user_id)$bootstrap_sql_a04c0336c23a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a04c0336c23a$;

DO $bootstrap_do_120bc10b03a4$
BEGIN
  EXECUTE $bootstrap_sql_120bc10b03a4$
