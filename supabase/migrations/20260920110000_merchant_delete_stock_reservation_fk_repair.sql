-- Merchant deletion repair: stock reservation history must not block product removal.
-- Reservation rows remain as historical records; references to removed products
-- or variants are detached instead of deleting the reservation audit trail.

DO $$
DECLARE
  v_table text;
  v_column text;
  v_constraint text;
  v_target text;
BEGIN
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
         WHERE table_schema = 'public' AND table_name = v_table AND column_name = v_column
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
           WHERE a.attrelid = c.conrelid AND a.attname = v_column AND NOT a.attisdropped)
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

COMMENT ON COLUMN public.marketplace_stock_reservation_items.product_id IS
  'Nullable historical reference; removed merchant products must not block merchant deletion.';
COMMENT ON COLUMN public.marketplace_stock_reservation_items.variant_id IS
  'Nullable historical reference; removed product variants must not block merchant deletion.';
COMMENT ON COLUMN public.marketplace_stock_allocations.product_id IS
  'Nullable historical reference; removed merchant products must not block merchant deletion.';
