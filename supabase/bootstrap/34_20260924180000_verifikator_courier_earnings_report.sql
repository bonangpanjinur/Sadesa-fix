-- Allow verifikators to read courier earnings only for couriers assigned to their own referral scope.
-- The policy is intentionally SELECT-only; courier earnings remain writable by the service/admin flow.
DO $bootstrap_do_verifikator_courier_earnings_report$
BEGIN
  EXECUTE $bootstrap_sql_verifikator_courier_earnings_report$
    DROP POLICY IF EXISTS "Verifikators can view scoped courier earnings" ON public.courier_earnings;
    CREATE POLICY "Verifikators can view scoped courier earnings"
      ON public.courier_earnings
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.couriers AS c
          WHERE c.id = courier_earnings.courier_id
            AND (
              c.verifikator_id = auth.uid()
              OR EXISTS (
                SELECT 1
                FROM public.verifikator_codes AS vc
                WHERE vc.code = c.verifikator_code
                  AND vc.verifikator_id = auth.uid()
              )
            )
        )
      )
  $bootstrap_sql_verifikator_courier_earnings_report$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_verifikator_courier_earnings_report$;
