-- Jalankan file ini di Supabase SQL Editor sebagai database owner.
-- Tujuan: mengizinkan admin menghapus merchant tanpa menghapus riwayat audit,
-- refund, earnings, dan stock reservation.
-- Aman dijalankan ulang.

BEGIN;

DO $$
DECLARE
  v_table text;
  v_constraint text;
BEGIN
  -- Data operasional POS boleh ikut terhapus bersama merchant.
  FOREACH v_table IN ARRAY ARRAY['pos_subscriptions', 'pos_transactions', 'pos_settings'] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN CONTINUE; END IF;

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

  -- Riwayat finansial/audit dipertahankan; hanya referensi merchant yang dilepas.
  FOREACH v_table IN ARRAY ARRAY[
    'quota_audit_logs',
    'verifikator_earnings',
    'refund_requests',
    'refund_settlements',
    'merchant_refund_shortfalls'
  ] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN CONTINUE; END IF;

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

DO $$
DECLARE
  v_table text;
  v_column text;
  v_target text;
  v_constraint text;
BEGIN
  -- Riwayat reservasi/alokasi stock dipertahankan; product/variant boleh NULL
  -- setelah produk milik merchant dihapus.
  FOR v_table, v_column, v_target IN
    SELECT * FROM (VALUES
      ('marketplace_stock_reservation_items', 'product_id', 'products'),
      ('marketplace_stock_reservation_items', 'variant_id', 'product_variants'),
      ('marketplace_stock_allocations', 'product_id', 'products')
    ) AS repair(table_name, column_name, target_table)
  LOOP
    IF to_regclass('public.' || v_table) IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = v_table
           AND column_name = v_column
       )
       OR to_regclass('public.' || v_target) IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_constraint IN
      SELECT c.conname
      FROM pg_constraint c
      WHERE c.conrelid = ('public.' || v_table)::regclass
        AND c.contype = 'f'
        AND c.confrelid = ('public.' || v_target)::regclass
        AND c.conkey = ARRAY[
          (SELECT a.attnum
           FROM pg_attribute a
           WHERE a.attrelid = c.conrelid
             AND a.attname = v_column
             AND NOT a.attisdropped)
        ]::smallint[]
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', v_table, v_constraint);
    END LOOP;

    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I DROP NOT NULL', v_table, v_column);
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.%I(id) ON DELETE SET NULL',
      v_table, v_table || '_' || v_column || '_fkey', v_column, v_target
    );
  END LOOP;
END;
$$;

COMMIT;

-- Verifikasi blocker yang relevan setelah script selesai.
SELECT
  child.relname AS child_table,
  child_constraint.conname,
  parent.relname AS parent_table,
  pg_get_constraintdef(child_constraint.oid) AS constraint_definition
FROM pg_constraint child_constraint
JOIN pg_class child ON child.oid = child_constraint.conrelid
JOIN pg_class parent ON parent.oid = child_constraint.confrelid
WHERE child_constraint.contype = 'f'
  AND parent.relname IN ('merchants', 'products', 'product_variants')
  AND child.relname IN (
    'pos_subscriptions', 'pos_transactions', 'pos_settings',
    'quota_audit_logs', 'verifikator_earnings', 'refund_requests',
    'refund_settlements', 'merchant_refund_shortfalls',
    'marketplace_stock_reservation_items', 'marketplace_stock_allocations'
  )
ORDER BY child.relname, child_constraint.conname;
