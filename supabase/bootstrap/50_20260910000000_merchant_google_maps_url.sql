-- Store an optional public Google Maps link for the merchant profile.
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS google_maps_url text;

COMMENT ON COLUMN public.merchants.google_maps_url IS
  'Optional public URL used to open the merchant location in Google Maps';

NOTIFY pgrst, 'reload schema';