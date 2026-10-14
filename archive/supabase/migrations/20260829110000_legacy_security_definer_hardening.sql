-- Harden legacy SECURITY DEFINER functions created before explicit search_path
-- conventions were applied. Trigger functions are not browser APIs.
ALTER FUNCTION public.check_low_quota_alert() SET search_path = public$bootstrap_sql_4dde815cef6e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4dde815cef6e$;

DO $bootstrap_do_8bf291a33ea7$
BEGIN
  EXECUTE $bootstrap_sql_8bf291a33ea7$ALTER FUNCTION public.increment_product_view(uuid) SET search_path = public$bootstrap_sql_8bf291a33ea7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8bf291a33ea7$;

DO $bootstrap_do_6f6637c97a44$
BEGIN
  EXECUTE $bootstrap_sql_6f6637c97a44$ALTER FUNCTION public.auto_assign_merchant_to_group() SET search_path = public$bootstrap_sql_6f6637c97a44$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f6637c97a44$;

DO $bootstrap_do_32180f27a275$
BEGIN
  EXECUTE $bootstrap_sql_32180f27a275$ALTER FUNCTION public.auto_assign_village_admin_role() SET search_path = public$bootstrap_sql_32180f27a275$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_32180f27a275$;

DO $bootstrap_do_6a7a1f561f09$
BEGIN
  EXECUTE $bootstrap_sql_6a7a1f561f09$ALTER FUNCTION public.handle_merchant_approval_role() SET search_path = public$bootstrap_sql_6a7a1f561f09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a7a1f561f09$;

DO $bootstrap_do_6feac2149e99$
BEGIN
  EXECUTE $bootstrap_sql_6feac2149e99$REVOKE ALL ON FUNCTION public.check_low_quota_alert() FROM PUBLIC, anon, authenticated$bootstrap_sql_6feac2149e99$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6feac2149e99$;

DO $bootstrap_do_c8f6f3906725$
BEGIN
  EXECUTE $bootstrap_sql_c8f6f3906725$REVOKE ALL ON FUNCTION public.auto_assign_merchant_to_group() FROM PUBLIC, anon, authenticated$bootstrap_sql_c8f6f3906725$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8f6f3906725$;

DO $bootstrap_do_6343d71feda2$
BEGIN
  EXECUTE $bootstrap_sql_6343d71feda2$REVOKE ALL ON FUNCTION public.auto_assign_village_admin_role() FROM PUBLIC, anon, authenticated$bootstrap_sql_6343d71feda2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6343d71feda2$;

DO $bootstrap_do_e53984c0bcc5$
BEGIN
  EXECUTE $bootstrap_sql_e53984c0bcc5$REVOKE ALL ON FUNCTION public.handle_merchant_approval_role() FROM PUBLIC, anon, authenticated$bootstrap_sql_e53984c0bcc5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e53984c0bcc5$;

DO $bootstrap_do_59da677d0c06$
BEGIN
  EXECUTE $bootstrap_sql_59da677d0c06$
