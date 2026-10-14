-- SECURITY DEFINER trigger/helper functions must not be callable by browser roles.
-- Their execution is reserved for database triggers or server-side worker paths.
REVOKE ALL ON FUNCTION public.mark_crm_cart_recovered_after_pos_sale() FROM PUBLIC, anon, authenticated$bootstrap_sql_8a675dea2122$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8a675dea2122$;

DO $bootstrap_do_4c87fee7820c$
BEGIN
  EXECUTE $bootstrap_sql_4c87fee7820c$REVOKE ALL ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) FROM PUBLIC, anon, authenticated$bootstrap_sql_4c87fee7820c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c87fee7820c$;

DO $bootstrap_do_e4f1a4f5e280$
BEGIN
  EXECUTE $bootstrap_sql_e4f1a4f5e280$-- Keep the critical transaction functions callable only by authenticated users
-- after their own tenant/outlet checks; service_role retains ownership access.
REVOKE ALL ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon$bootstrap_sql_e4f1a4f5e280$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4f1a4f5e280$;

DO $bootstrap_do_6f04af8a48f1$
BEGIN
  EXECUTE $bootstrap_sql_6f04af8a48f1$GRANT EXECUTE ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) TO authenticated$bootstrap_sql_6f04af8a48f1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f04af8a48f1$;

DO $bootstrap_do_56beea22ce6a$
BEGIN
  EXECUTE $bootstrap_sql_56beea22ce6a$REVOKE ALL ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric) FROM PUBLIC, anon, authenticated$bootstrap_sql_56beea22ce6a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56beea22ce6a$;

DO $bootstrap_do_bdd1bd0a88ca$
BEGIN
  EXECUTE $bootstrap_sql_bdd1bd0a88ca$REVOKE ALL ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) FROM PUBLIC, anon$bootstrap_sql_bdd1bd0a88ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bdd1bd0a88ca$;

DO $bootstrap_do_1f66148b73d1$
BEGIN
  EXECUTE $bootstrap_sql_1f66148b73d1$REVOKE ALL ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) FROM PUBLIC, anon$bootstrap_sql_1f66148b73d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f66148b73d1$;

DO $bootstrap_do_4dde815cef6e$
BEGIN
  EXECUTE $bootstrap_sql_4dde815cef6e$
