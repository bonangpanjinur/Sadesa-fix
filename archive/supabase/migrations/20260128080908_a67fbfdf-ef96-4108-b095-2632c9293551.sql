-- Create push_subscriptions table for storing web push subscriptions
CREATE TABLE public.push_subscriptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, endpoint)
)$bootstrap_sql_61b9f67712d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_61b9f67712d0$;

DO $bootstrap_do_f1dcd902b166$
BEGIN
  EXECUTE $bootstrap_sql_f1dcd902b166$-- Enable RLS
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY$bootstrap_sql_f1dcd902b166$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f1dcd902b166$;

DO $bootstrap_do_4aaceb9b253b$
BEGIN
  EXECUTE $bootstrap_sql_4aaceb9b253b$-- Users can manage their own subscriptions
DROP POLICY IF EXISTS "Users can view their own push subscriptions" ON public.push_subscriptions$bootstrap_sql_4aaceb9b253b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4aaceb9b253b$;

DO $bootstrap_do_3e6f37711d72$
BEGIN
  EXECUTE $bootstrap_sql_3e6f37711d72$CREATE POLICY "Users can view their own push subscriptions"
ON public.push_subscriptions FOR SELECT
USING (auth.uid() = user_id)$bootstrap_sql_3e6f37711d72$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e6f37711d72$;

DO $bootstrap_do_295d1a6f142e$
BEGIN
  EXECUTE $bootstrap_sql_295d1a6f142e$DROP POLICY IF EXISTS "Users can insert their own push subscriptions" ON public.push_subscriptions$bootstrap_sql_295d1a6f142e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_295d1a6f142e$;

DO $bootstrap_do_9b5aa04d7c5f$
BEGIN
  EXECUTE $bootstrap_sql_9b5aa04d7c5f$CREATE POLICY "Users can insert their own push subscriptions"
ON public.push_subscriptions FOR INSERT
WITH CHECK (auth.uid() = user_id)$bootstrap_sql_9b5aa04d7c5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b5aa04d7c5f$;

DO $bootstrap_do_fbdf4ce5ba4d$
BEGIN
  EXECUTE $bootstrap_sql_fbdf4ce5ba4d$DROP POLICY IF EXISTS "Users can delete their own push subscriptions" ON public.push_subscriptions$bootstrap_sql_fbdf4ce5ba4d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fbdf4ce5ba4d$;

DO $bootstrap_do_121ba69766ef$
BEGIN
  EXECUTE $bootstrap_sql_121ba69766ef$CREATE POLICY "Users can delete their own push subscriptions"
ON public.push_subscriptions FOR DELETE
USING (auth.uid() = user_id)$bootstrap_sql_121ba69766ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_121ba69766ef$;

DO $bootstrap_do_fee12d95e9d2$
BEGIN
  EXECUTE $bootstrap_sql_fee12d95e9d2$DROP POLICY IF EXISTS "Users can update their own push subscriptions" ON public.push_subscriptions$bootstrap_sql_fee12d95e9d2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fee12d95e9d2$;

DO $bootstrap_do_c324fbc34461$
BEGIN
  EXECUTE $bootstrap_sql_c324fbc34461$CREATE POLICY "Users can update their own push subscriptions"
ON public.push_subscriptions FOR UPDATE
USING (auth.uid() = user_id)$bootstrap_sql_c324fbc34461$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c324fbc34461$;

DO $bootstrap_do_56067a81cdac$
BEGIN
  EXECUTE $bootstrap_sql_56067a81cdac$-- Create password_reset_tokens table
CREATE TABLE public.password_reset_tokens (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  used_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_56067a81cdac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56067a81cdac$;

DO $bootstrap_do_77b55ce92f39$
BEGIN
  EXECUTE $bootstrap_sql_77b55ce92f39$-- Enable RLS (no user access needed, only edge functions)
ALTER TABLE public.password_reset_tokens ENABLE ROW LEVEL SECURITY$bootstrap_sql_77b55ce92f39$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77b55ce92f39$;

DO $bootstrap_do_64ac68879358$
BEGIN
  EXECUTE $bootstrap_sql_64ac68879358$-- Only service role can access this table (no policies = denied for anon/authenticated)

-- Create index for faster lookups
CREATE INDEX idx_push_subscriptions_user_id ON public.push_subscriptions(user_id)$bootstrap_sql_64ac68879358$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_64ac68879358$;

DO $bootstrap_do_725c8eba1f7b$
BEGIN
  EXECUTE $bootstrap_sql_725c8eba1f7b$CREATE INDEX idx_password_reset_tokens_token ON public.password_reset_tokens(token)$bootstrap_sql_725c8eba1f7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_725c8eba1f7b$;

DO $bootstrap_do_f543feda4b43$
BEGIN
  EXECUTE $bootstrap_sql_f543feda4b43$CREATE INDEX idx_password_reset_tokens_email ON public.password_reset_tokens(email)$bootstrap_sql_f543feda4b43$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f543feda4b43$;

DO $bootstrap_do_f623660df96f$
BEGIN
  EXECUTE $bootstrap_sql_f623660df96f$
