-- Fix UPDATE policy to include WITH CHECK
DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses$bootstrap_sql_4f677ca981c3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f677ca981c3$;

DO $bootstrap_do_dbdfaf703ab4$
BEGIN
  EXECUTE $bootstrap_sql_dbdfaf703ab4$CREATE POLICY "Users can update own addresses"
ON public.saved_addresses FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id)$bootstrap_sql_dbdfaf703ab4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dbdfaf703ab4$;

DO $bootstrap_do_3fab0495709c$
BEGIN
  EXECUTE $bootstrap_sql_3fab0495709c$
