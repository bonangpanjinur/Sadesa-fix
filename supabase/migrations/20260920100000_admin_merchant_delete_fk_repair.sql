-- Admin merchant deletion repair.
--
-- The merchants DELETE policy already grants admins the operation, but several
-- late-added tables kept PostgreSQL's default NO ACTION/RESTRICT FK behavior.
-- A merchant with POS or refund history therefore could never be deleted.
-- Operational configuration is cascaded; financial/audit history is retained
-- with a NULL merchant reference.

DO $$
DECLARE
  v_table text;
  v_constraint text;
BEGIN
  -- Operational merchant-owned data can be removed with the merchant.
  FOREACH v_table IN ARRAY ARRAY['pos_subscriptions', 'pos_transactions', 'pos_settings'] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_constraint IN
      SELECT c.conname
      FROM pg_constraint c
      WHERE c.conrelid = ('public.' || v_table)::regclass
        AND c.contype = 'f'
        AND c.confrelid = 'public.merchants'::regclass
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', v_table, v_constraint);
    END LOOP;

    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE',
      v_table, v_table || '_merchant_id_fkey'
    );
  END LOOP;

  -- Preserve audit, earnings, and refund history while allowing the merchant
  -- record itself to be removed. These columns are intentionally nullable.
  FOREACH v_table IN ARRAY ARRAY[
    'quota_audit_logs',
    'verifikator_earnings',
    'refund_requests',
    'refund_settlements',
    'merchant_refund_shortfalls'
  ] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_constraint IN
      SELECT c.conname
      FROM pg_constraint c
      WHERE c.conrelid = ('public.' || v_table)::regclass
        AND c.contype = 'f'
        AND c.confrelid = 'public.merchants'::regclass
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', v_table, v_constraint);
    END LOOP;

    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN merchant_id DROP NOT NULL', v_table);
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE SET NULL',
      v_table, v_table || '_merchant_id_fkey'
    );
  END LOOP;
END;
$$;

COMMENT ON COLUMN public.refund_settlements.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase refund settlement records.';
COMMENT ON COLUMN public.merchant_refund_shortfalls.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase refund shortfall records.';
COMMENT ON COLUMN public.quota_audit_logs.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase quota audit records.';
COMMENT ON COLUMN public.verifikator_earnings.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase commission records.';
