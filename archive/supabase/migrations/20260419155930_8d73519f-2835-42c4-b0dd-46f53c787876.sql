-- Fix overly permissive RLS policy on page_views (WITH CHECK true)
DROP POLICY IF EXISTS "Anyone can insert page views" ON public.page_views$bootstrap_sql_262de7982c03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_262de7982c03$;

DO $bootstrap_do_cd8198dd87e2$
BEGIN
  EXECUTE $bootstrap_sql_cd8198dd87e2$DROP POLICY IF EXISTS "Authenticated or anonymous can insert their own page view" ON public.page_views$bootstrap_sql_cd8198dd87e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cd8198dd87e2$;

DO $bootstrap_do_b5d6330c5871$
BEGIN
  EXECUTE $bootstrap_sql_b5d6330c5871$CREATE POLICY "Authenticated or anonymous can insert their own page view"
ON public.page_views
FOR INSERT
TO public
WITH CHECK (
  -- Anonymous viewer (no viewer_id) is allowed
  viewer_id IS NULL
  -- Or the viewer matches the authenticated user
  OR viewer_id = auth.uid()
)$bootstrap_sql_b5d6330c5871$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b5d6330c5871$;

DO $bootstrap_do_b93b1087e1d4$
BEGIN
  EXECUTE $bootstrap_sql_b93b1087e1d4$
