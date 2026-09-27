-- Product categories may have one optional parent category.
-- Existing categories remain top-level because parent_id defaults to NULL.
ALTER TABLE public.categories
  ADD COLUMN IF NOT EXISTS parent_id uuid REFERENCES public.categories(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS categories_parent_id_idx
  ON public.categories(parent_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'categories_parent_not_self'
      AND conrelid = 'public.categories'::regclass
  ) THEN
    ALTER TABLE public.categories
      ADD CONSTRAINT categories_parent_not_self CHECK (parent_id IS NULL OR parent_id <> id);
  END IF;
END $$;
