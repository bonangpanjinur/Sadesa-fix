-- Allow image-led homepage banners without a title.
-- Other promotion types must continue to have a non-empty title.
ALTER TABLE public.promotions
  ALTER COLUMN title DROP NOT NULL;

ALTER TABLE public.promotions
  DROP CONSTRAINT IF EXISTS promotions_non_banner_title_required;

ALTER TABLE public.promotions
  ADD CONSTRAINT promotions_non_banner_title_required
  CHECK (type = 'banner' OR NULLIF(btrim(title), '') IS NOT NULL);
