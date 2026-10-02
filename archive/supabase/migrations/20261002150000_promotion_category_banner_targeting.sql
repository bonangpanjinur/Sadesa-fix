-- Add optional category targeting for admin-managed banner promotions.
-- NULL remains the backward-compatible homepage-wide banner scope.
ALTER TABLE public.promotions
  ADD COLUMN IF NOT EXISTS category_id uuid;

DO $promotion_category_banner_fk$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'promotions_category_id_fkey'
      AND conrelid = 'public.promotions'::regclass
  ) THEN
    ALTER TABLE public.promotions
      ADD CONSTRAINT promotions_category_id_fkey
      FOREIGN KEY (category_id)
      REFERENCES public.categories(id)
      ON DELETE RESTRICT;
  END IF;
END $promotion_category_banner_fk$;

CREATE INDEX IF NOT EXISTS idx_promotions_category_sort
  ON public.promotions(category_id, sort_order)
  WHERE category_id IS NOT NULL;
