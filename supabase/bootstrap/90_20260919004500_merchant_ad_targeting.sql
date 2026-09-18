-- Optional targeting metadata for merchant ad planning and reporting.
ALTER TABLE public.merchant_ads
  ADD COLUMN IF NOT EXISTS target_area TEXT,
  ADD COLUMN IF NOT EXISTS target_category TEXT,
  ADD COLUMN IF NOT EXISTS target_start_hour SMALLINT CHECK (target_start_hour IS NULL OR target_start_hour BETWEEN 0 AND 23),
  ADD COLUMN IF NOT EXISTS target_end_hour SMALLINT CHECK (target_end_hour IS NULL OR target_end_hour BETWEEN 0 AND 23);

COMMENT ON COLUMN public.merchant_ads.target_area IS 'Optional village, district, or service area requested by the merchant.';
COMMENT ON COLUMN public.merchant_ads.target_category IS 'Optional category targeting requested by the merchant.';
COMMENT ON COLUMN public.merchant_ads.target_start_hour IS 'Optional local hour window start for future delivery targeting.';
COMMENT ON COLUMN public.merchant_ads.target_end_hour IS 'Optional local hour window end for future delivery targeting.';

NOTIFY pgrst, 'reload schema';
