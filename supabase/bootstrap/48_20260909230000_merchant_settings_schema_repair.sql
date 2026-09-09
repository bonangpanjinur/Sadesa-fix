-- Keep the merchant settings form compatible with databases created from
-- older bootstrap bundles where classification_price was removed.
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS classification_price text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.merchants'::regclass
      AND conname = 'merchants_classification_price_check'
  ) THEN
    ALTER TABLE public.merchants
      ADD CONSTRAINT merchants_classification_price_check
      CHECK (
        classification_price IS NULL
        OR classification_price IN (
          'UNDER_5K',
          'FROM_5K_TO_10K',
          'FROM_10K_TO_20K',
          'ABOVE_20K'
        )
      );
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';