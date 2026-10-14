-- P2-05: Push Notification — push_subscriptions table
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     UUID NOT NULL,
  endpoint    TEXT NOT NULL UNIQUE,
  p256dh      TEXT,
  auth        TEXT,
  created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_50b10ca73a91$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_50b10ca73a91$;

DO $bootstrap_do_22a102926d0f$
BEGIN
  EXECUTE $bootstrap_sql_22a102926d0f$ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY$bootstrap_sql_22a102926d0f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22a102926d0f$;

DO $bootstrap_do_a4436dcf1790$
BEGIN
  EXECUTE $bootstrap_sql_a4436dcf1790$DROP POLICY IF EXISTS "Users can manage own push subscriptions" ON public.push_subscriptions$bootstrap_sql_a4436dcf1790$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a4436dcf1790$;

DO $bootstrap_do_4d58d4edb129$
BEGIN
  EXECUTE $bootstrap_sql_4d58d4edb129$CREATE POLICY "Users can manage own push subscriptions"
  ON public.push_subscriptions
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_4d58d4edb129$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d58d4edb129$;

DO $bootstrap_do_7b4bd87ad9d8$
BEGIN
  EXECUTE $bootstrap_sql_7b4bd87ad9d8$DROP POLICY IF EXISTS "Admins can manage all push subscriptions" ON public.push_subscriptions$bootstrap_sql_7b4bd87ad9d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b4bd87ad9d8$;

DO $bootstrap_do_10bc10d4d8bc$
BEGIN
  EXECUTE $bootstrap_sql_10bc10d4d8bc$CREATE POLICY "Admins can manage all push subscriptions"
  ON public.push_subscriptions
  FOR ALL
  USING (public.is_admin())$bootstrap_sql_10bc10d4d8bc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_10bc10d4d8bc$;

DO $bootstrap_do_ca4f6317fc1a$
BEGIN
  EXECUTE $bootstrap_sql_ca4f6317fc1a$CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id
  ON public.push_subscriptions (user_id)$bootstrap_sql_ca4f6317fc1a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca4f6317fc1a$;

DO $bootstrap_do_809e834403dc$
BEGIN
  EXECUTE $bootstrap_sql_809e834403dc$
