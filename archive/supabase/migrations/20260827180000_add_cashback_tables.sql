-- SaDesa cashback rules and ledger
-- Safe to replay: all objects and policies are guarded or recreated by name.

CREATE TABLE IF NOT EXISTS public.cashback_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  cashback_percent numeric(5,2) NOT NULL,
  min_order_amount numeric(14,2) NOT NULL DEFAULT 0,
  max_cashback numeric(14,2),
  category text,
  is_active boolean NOT NULL DEFAULT true,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cashback_rules_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT cashback_rules_percent_range CHECK (cashback_percent > 0 AND cashback_percent <= 50),
  CONSTRAINT cashback_rules_min_order_non_negative CHECK (min_order_amount >= 0),
  CONSTRAINT cashback_rules_max_positive CHECK (max_cashback IS NULL OR max_cashback > 0),
  CONSTRAINT cashback_rules_valid_period CHECK (valid_until IS NULL OR valid_until >= valid_from)
)$bootstrap_sql_6e93242f1a81$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e93242f1a81$;

DO $bootstrap_do_82d6be91ef82$
BEGIN
  EXECUTE $bootstrap_sql_82d6be91ef82$CREATE INDEX IF NOT EXISTS cashback_rules_active_period_idx
  ON public.cashback_rules (is_active, valid_from, valid_until)$bootstrap_sql_82d6be91ef82$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_82d6be91ef82$;

DO $bootstrap_do_1a3d0b1cfbb5$
BEGIN
  EXECUTE $bootstrap_sql_1a3d0b1cfbb5$CREATE TABLE IF NOT EXISTS public.cashback_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  rule_id uuid REFERENCES public.cashback_rules(id) ON DELETE SET NULL,
  amount numeric(14,2) NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  CONSTRAINT cashback_transactions_amount_positive CHECK (amount > 0),
  CONSTRAINT cashback_transactions_status_valid CHECK (status IN ('pending', 'confirmed', 'cancelled', 'reversed'))
)$bootstrap_sql_1a3d0b1cfbb5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1a3d0b1cfbb5$;

DO $bootstrap_do_df46d62f8616$
BEGIN
  EXECUTE $bootstrap_sql_df46d62f8616$CREATE INDEX IF NOT EXISTS cashback_transactions_user_created_idx
  ON public.cashback_transactions (user_id, created_at DESC)$bootstrap_sql_df46d62f8616$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df46d62f8616$;

DO $bootstrap_do_bdf47e1edaa5$
BEGIN
  EXECUTE $bootstrap_sql_bdf47e1edaa5$CREATE INDEX IF NOT EXISTS cashback_transactions_status_idx
  ON public.cashback_transactions (status, created_at DESC)$bootstrap_sql_bdf47e1edaa5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bdf47e1edaa5$;

DO $bootstrap_do_74bf0ae5bfed$
BEGIN
  EXECUTE $bootstrap_sql_74bf0ae5bfed$CREATE UNIQUE INDEX IF NOT EXISTS cashback_transactions_order_rule_unique_idx
  ON public.cashback_transactions (order_id, rule_id)
  WHERE order_id IS NOT NULL AND rule_id IS NOT NULL AND status <> 'reversed'$bootstrap_sql_74bf0ae5bfed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_74bf0ae5bfed$;

DO $bootstrap_do_4c6ed3f7a7ae$
BEGIN
  EXECUTE $bootstrap_sql_4c6ed3f7a7ae$GRANT SELECT ON public.cashback_rules TO anon, authenticated$bootstrap_sql_4c6ed3f7a7ae$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c6ed3f7a7ae$;

DO $bootstrap_do_961eaa0f990d$
BEGIN
  EXECUTE $bootstrap_sql_961eaa0f990d$GRANT INSERT, UPDATE, DELETE ON public.cashback_rules TO authenticated$bootstrap_sql_961eaa0f990d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_961eaa0f990d$;

DO $bootstrap_do_c577949d70df$
BEGIN
  EXECUTE $bootstrap_sql_c577949d70df$GRANT SELECT ON public.cashback_transactions TO authenticated$bootstrap_sql_c577949d70df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c577949d70df$;

DO $bootstrap_do_9e65a8c19573$
BEGIN
  EXECUTE $bootstrap_sql_9e65a8c19573$GRANT ALL ON public.cashback_rules, public.cashback_transactions TO service_role$bootstrap_sql_9e65a8c19573$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e65a8c19573$;

DO $bootstrap_do_77f1fd76bef7$
BEGIN
  EXECUTE $bootstrap_sql_77f1fd76bef7$ALTER TABLE public.cashback_rules ENABLE ROW LEVEL SECURITY$bootstrap_sql_77f1fd76bef7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77f1fd76bef7$;

DO $bootstrap_do_490a6fc9f5d5$
BEGIN
  EXECUTE $bootstrap_sql_490a6fc9f5d5$ALTER TABLE public.cashback_transactions ENABLE ROW LEVEL SECURITY$bootstrap_sql_490a6fc9f5d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_490a6fc9f5d5$;

DO $bootstrap_do_2771aeb71c2a$
BEGIN
  EXECUTE $bootstrap_sql_2771aeb71c2a$DROP POLICY IF EXISTS "Public can view active cashback rules" ON public.cashback_rules$bootstrap_sql_2771aeb71c2a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2771aeb71c2a$;

DO $bootstrap_do_dce9f6300d81$
BEGIN
  EXECUTE $bootstrap_sql_dce9f6300d81$CREATE POLICY "Public can view active cashback rules"
  ON public.cashback_rules FOR SELECT
  TO anon, authenticated
  USING (is_active = true AND valid_from <= now() AND (valid_until IS NULL OR valid_until >= now()))$bootstrap_sql_dce9f6300d81$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dce9f6300d81$;

DO $bootstrap_do_9dfe015d4dd3$
BEGIN
  EXECUTE $bootstrap_sql_9dfe015d4dd3$DROP POLICY IF EXISTS "Admins can manage cashback rules" ON public.cashback_rules$bootstrap_sql_9dfe015d4dd3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9dfe015d4dd3$;

DO $bootstrap_do_a937a6735a12$
BEGIN
  EXECUTE $bootstrap_sql_a937a6735a12$CREATE POLICY "Admins can manage cashback rules"
  ON public.cashback_rules FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin())$bootstrap_sql_a937a6735a12$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a937a6735a12$;

DO $bootstrap_do_4a37b14de43b$
BEGIN
  EXECUTE $bootstrap_sql_4a37b14de43b$DROP POLICY IF EXISTS "Users can view own cashback transactions" ON public.cashback_transactions$bootstrap_sql_4a37b14de43b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a37b14de43b$;

DO $bootstrap_do_d56bc977fa5f$
BEGIN
  EXECUTE $bootstrap_sql_d56bc977fa5f$CREATE POLICY "Users can view own cashback transactions"
  ON public.cashback_transactions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid())$bootstrap_sql_d56bc977fa5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d56bc977fa5f$;

DO $bootstrap_do_49068cf95d7a$
BEGIN
  EXECUTE $bootstrap_sql_49068cf95d7a$DROP POLICY IF EXISTS "Admins can view cashback transactions" ON public.cashback_transactions$bootstrap_sql_49068cf95d7a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49068cf95d7a$;

DO $bootstrap_do_c32fc72673b2$
BEGIN
  EXECUTE $bootstrap_sql_c32fc72673b2$CREATE POLICY "Admins can view cashback transactions"
  ON public.cashback_transactions FOR SELECT
  TO authenticated
  USING (public.is_admin())$bootstrap_sql_c32fc72673b2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c32fc72673b2$;

DO $bootstrap_do_e3131f78fd03$
BEGIN
  EXECUTE $bootstrap_sql_e3131f78fd03$COMMENT ON TABLE public.cashback_rules IS 'Database-backed cashback programs managed by SaDesa administrators.'$bootstrap_sql_e3131f78fd03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e3131f78fd03$;

DO $bootstrap_do_cb720137d1cc$
BEGIN
  EXECUTE $bootstrap_sql_cb720137d1cc$COMMENT ON TABLE public.cashback_transactions IS 'Cashback ledger for buyer awards and reversals.'$bootstrap_sql_cb720137d1cc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb720137d1cc$;

DO $bootstrap_do_a328370cc78f$
BEGIN
  EXECUTE $bootstrap_sql_a328370cc78f$
