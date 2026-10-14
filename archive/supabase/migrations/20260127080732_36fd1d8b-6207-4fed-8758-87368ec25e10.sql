-- ========================================
-- 7. STORAGE BUCKET FOR PRODUCT IMAGES
-- ========================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_ede29d3b9e6e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ede29d3b9e6e$;

DO $bootstrap_do_8ad91243c670$
BEGIN
  EXECUTE $bootstrap_sql_8ad91243c670$-- Storage policies for product images (safe to retry)
DROP POLICY IF EXISTS "Public view product images bucket" ON storage.objects$bootstrap_sql_8ad91243c670$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ad91243c670$;

DO $bootstrap_do_31093cbf1f05$
BEGIN
  EXECUTE $bootstrap_sql_31093cbf1f05$DROP POLICY IF EXISTS "Auth users upload product images" ON storage.objects$bootstrap_sql_31093cbf1f05$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31093cbf1f05$;

DO $bootstrap_do_6b929a4ec149$
BEGIN
  EXECUTE $bootstrap_sql_6b929a4ec149$DROP POLICY IF EXISTS "Auth users update product images" ON storage.objects$bootstrap_sql_6b929a4ec149$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b929a4ec149$;

DO $bootstrap_do_27c88537055c$
BEGIN
  EXECUTE $bootstrap_sql_27c88537055c$DROP POLICY IF EXISTS "Auth users delete product images" ON storage.objects$bootstrap_sql_27c88537055c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_27c88537055c$;

DO $bootstrap_do_4b0b2b413674$
BEGIN
  EXECUTE $bootstrap_sql_4b0b2b413674$DROP POLICY IF EXISTS "Public view product images bucket" ON storage.objects$bootstrap_sql_4b0b2b413674$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4b0b2b413674$;

DO $bootstrap_do_ee7cff3549c2$
BEGIN
  EXECUTE $bootstrap_sql_ee7cff3549c2$CREATE POLICY "Public view product images bucket" ON storage.objects
  FOR SELECT USING (bucket_id = 'product-images')$bootstrap_sql_ee7cff3549c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ee7cff3549c2$;

DO $bootstrap_do_9479b5ec94d4$
BEGIN
  EXECUTE $bootstrap_sql_9479b5ec94d4$DROP POLICY IF EXISTS "Auth users upload product images" ON storage.objects$bootstrap_sql_9479b5ec94d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9479b5ec94d4$;

DO $bootstrap_do_c8517a048ab0$
BEGIN
  EXECUTE $bootstrap_sql_c8517a048ab0$CREATE POLICY "Auth users upload product images" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'product-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_c8517a048ab0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8517a048ab0$;

DO $bootstrap_do_aa0439c53e33$
BEGIN
  EXECUTE $bootstrap_sql_aa0439c53e33$DROP POLICY IF EXISTS "Auth users update product images" ON storage.objects$bootstrap_sql_aa0439c53e33$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa0439c53e33$;

DO $bootstrap_do_733bea3be04d$
BEGIN
  EXECUTE $bootstrap_sql_733bea3be04d$CREATE POLICY "Auth users update product images" ON storage.objects
  FOR UPDATE USING (bucket_id = 'product-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_733bea3be04d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_733bea3be04d$;

DO $bootstrap_do_638b33e64b1e$
BEGIN
  EXECUTE $bootstrap_sql_638b33e64b1e$DROP POLICY IF EXISTS "Auth users delete product images" ON storage.objects$bootstrap_sql_638b33e64b1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_638b33e64b1e$;

DO $bootstrap_do_5f51725be923$
BEGIN
  EXECUTE $bootstrap_sql_5f51725be923$CREATE POLICY "Auth users delete product images" ON storage.objects
  FOR DELETE USING (bucket_id = 'product-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_5f51725be923$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5f51725be923$;

DO $bootstrap_do_d834c66893cf$
BEGIN
  EXECUTE $bootstrap_sql_d834c66893cf$-- ========================================
-- 8. ENABLE REALTIME FOR COURIER TRACKING
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'couriers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.couriers;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_d834c66893cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d834c66893cf$;

DO $bootstrap_do_75fbc279af49$
BEGIN
  EXECUTE $bootstrap_sql_75fbc279af49$DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_75fbc279af49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_75fbc279af49$;

DO $bootstrap_do_0ed12aca6eec$
BEGIN
  EXECUTE $bootstrap_sql_0ed12aca6eec$
