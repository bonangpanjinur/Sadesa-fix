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
);

CREATE INDEX IF NOT EXISTS cashback_rules_active_period_idx
  ON public.cashback_rules (is_active, valid_from, valid_until);

CREATE TABLE IF NOT EXISTS public.cashback_transactions (
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
);

CREATE INDEX IF NOT EXISTS cashback_transactions_user_created_idx
  ON public.cashback_transactions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS cashback_transactions_status_idx
  ON public.cashback_transactions (status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS cashback_transactions_order_rule_unique_idx
  ON public.cashback_transactions (order_id, rule_id)
  WHERE order_id IS NOT NULL AND rule_id IS NOT NULL AND status <> 'reversed';

GRANT SELECT ON public.cashback_rules TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.cashback_rules TO authenticated;
GRANT SELECT ON public.cashback_transactions TO authenticated;
GRANT ALL ON public.cashback_rules, public.cashback_transactions TO service_role;

ALTER TABLE public.cashback_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cashback_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view active cashback rules" ON public.cashback_rules;
CREATE POLICY "Public can view active cashback rules"
  ON public.cashback_rules FOR SELECT
  TO anon, authenticated
  USING (is_active = true AND valid_from <= now() AND (valid_until IS NULL OR valid_until >= now()));

DROP POLICY IF EXISTS "Admins can manage cashback rules" ON public.cashback_rules;
CREATE POLICY "Admins can manage cashback rules"
  ON public.cashback_rules FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Users can view own cashback transactions" ON public.cashback_transactions;
CREATE POLICY "Users can view own cashback transactions"
  ON public.cashback_transactions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can view cashback transactions" ON public.cashback_transactions;
CREATE POLICY "Admins can view cashback transactions"
  ON public.cashback_transactions FOR SELECT
  TO authenticated
  USING (public.is_admin());

COMMENT ON TABLE public.cashback_rules IS 'Database-backed cashback programs managed by SaDesa administrators.';
COMMENT ON TABLE public.cashback_transactions IS 'Cashback ledger for buyer awards and reversals.';
