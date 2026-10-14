-- P4-04: Bootstrap API keys and add the hashed key value used for server validation.
-- The AdminApiKeysPage manages this table, so new projects must receive the
-- table before the compatibility ALTER below is executed.

CREATE TABLE IF NOT EXISTS public.api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_prefix TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  key_value TEXT UNIQUE,
  permissions TEXT[] NOT NULL DEFAULT ARRAY['read:products']::TEXT[],
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  request_count BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ
)$bootstrap_sql_809e834403dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_809e834403dc$;

DO $bootstrap_do_0290b2158f08$
BEGIN
  EXECUTE $bootstrap_sql_0290b2158f08$ALTER TABLE public.api_keys
  ADD COLUMN IF NOT EXISTS key_value TEXT$bootstrap_sql_0290b2158f08$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0290b2158f08$;

DO $bootstrap_do_ef637fe976a6$
BEGIN
  EXECUTE $bootstrap_sql_ef637fe976a6$CREATE INDEX IF NOT EXISTS idx_api_keys_key_value
  ON public.api_keys (key_value)
  WHERE key_value IS NOT NULL$bootstrap_sql_ef637fe976a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef637fe976a6$;

DO $bootstrap_do_70701f8eeebb$
BEGIN
  EXECUTE $bootstrap_sql_70701f8eeebb$CREATE INDEX IF NOT EXISTS idx_api_keys_user_id
  ON public.api_keys (user_id)$bootstrap_sql_70701f8eeebb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70701f8eeebb$;

DO $bootstrap_do_eefbf8cff4df$
BEGIN
  EXECUTE $bootstrap_sql_eefbf8cff4df$ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY$bootstrap_sql_eefbf8cff4df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eefbf8cff4df$;

DO $bootstrap_do_3b6629158968$
BEGIN
  EXECUTE $bootstrap_sql_3b6629158968$DROP POLICY IF EXISTS "Admins can view all API keys" ON public.api_keys$bootstrap_sql_3b6629158968$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b6629158968$;

DO $bootstrap_do_fbdc42ba6cb8$
BEGIN
  EXECUTE $bootstrap_sql_fbdc42ba6cb8$CREATE POLICY "Admins can view all API keys"
  ON public.api_keys FOR SELECT
  TO authenticated
  USING (public.is_admin())$bootstrap_sql_fbdc42ba6cb8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fbdc42ba6cb8$;

DO $bootstrap_do_e0adf52a5331$
BEGIN
  EXECUTE $bootstrap_sql_e0adf52a5331$DROP POLICY IF EXISTS "Admins can create API keys" ON public.api_keys$bootstrap_sql_e0adf52a5331$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e0adf52a5331$;

DO $bootstrap_do_dd8e542cdb49$
BEGIN
  EXECUTE $bootstrap_sql_dd8e542cdb49$CREATE POLICY "Admins can create API keys"
  ON public.api_keys FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin())$bootstrap_sql_dd8e542cdb49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dd8e542cdb49$;

DO $bootstrap_do_c1a58c4ddbe4$
BEGIN
  EXECUTE $bootstrap_sql_c1a58c4ddbe4$DROP POLICY IF EXISTS "Admins can update API keys" ON public.api_keys$bootstrap_sql_c1a58c4ddbe4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c1a58c4ddbe4$;

DO $bootstrap_do_1644b45adc0d$
BEGIN
  EXECUTE $bootstrap_sql_1644b45adc0d$CREATE POLICY "Admins can update API keys"
  ON public.api_keys FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin())$bootstrap_sql_1644b45adc0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1644b45adc0d$;

DO $bootstrap_do_cc92aefb7a74$
BEGIN
  EXECUTE $bootstrap_sql_cc92aefb7a74$DROP POLICY IF EXISTS "Admins can delete API keys" ON public.api_keys$bootstrap_sql_cc92aefb7a74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc92aefb7a74$;

DO $bootstrap_do_76cbe90e7607$
BEGIN
  EXECUTE $bootstrap_sql_76cbe90e7607$CREATE POLICY "Admins can delete API keys"
  ON public.api_keys FOR DELETE
  TO authenticated
  USING (public.is_admin())$bootstrap_sql_76cbe90e7607$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_76cbe90e7607$;

DO $bootstrap_do_a0632af898e6$
BEGIN
  EXECUTE $bootstrap_sql_a0632af898e6$
