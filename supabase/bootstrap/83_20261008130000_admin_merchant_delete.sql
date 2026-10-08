-- Allow the authenticated admin UI to issue DELETE on merchants. RLS remains
-- the authorization boundary: only admins may delete merchant rows.
DO $bootstrap_do_admin_merchant_delete_grant$
BEGIN
  EXECUTE 'GRANT DELETE ON public.merchants TO authenticated';
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END;
$bootstrap_do_admin_merchant_delete_grant$;

-- The previous FOR ALL policy also permitted verifier deletes once the table
-- privilege is granted. Preserve verifier read/insert/update access explicitly.
DROP POLICY IF EXISTS "Verifikator can manage merchants" ON public.merchants;
DROP POLICY IF EXISTS "Verifikator can select merchants" ON public.merchants;
DROP POLICY IF EXISTS "Verifikator can insert merchants" ON public.merchants;
DROP POLICY IF EXISTS "Verifikator can update merchants" ON public.merchants;

CREATE POLICY "Verifikator can select merchants"
  ON public.merchants FOR SELECT
  USING (public.is_verifikator());
CREATE POLICY "Verifikator can insert merchants"
  ON public.merchants FOR INSERT
  WITH CHECK (public.is_verifikator());
CREATE POLICY "Verifikator can update merchants"
  ON public.merchants FOR UPDATE
  USING (public.is_verifikator())
  WITH CHECK (public.is_verifikator());
