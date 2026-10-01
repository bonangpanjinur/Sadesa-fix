-- Allow image-led homepage banners without a title.
-- Other promotion types must continue to have a non-empty title.
DO $bootstrap_do_optional_banner_title$
BEGIN
  IF to_regclass('public.promotions') IS NOT NULL THEN
    ALTER TABLE public.promotions
      ALTER COLUMN title DROP NOT NULL;

    ALTER TABLE public.promotions
      DROP CONSTRAINT IF EXISTS promotions_non_banner_title_required;

    ALTER TABLE public.promotions
      ADD CONSTRAINT promotions_non_banner_title_required
      CHECK (type = 'banner' OR NULLIF(btrim(title), '') IS NOT NULL);
  END IF;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_optional_banner_title$;
