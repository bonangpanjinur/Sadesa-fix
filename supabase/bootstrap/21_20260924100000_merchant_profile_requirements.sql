-- Merchant profile requirements: KTP number belongs to the account owner,
-- not to the merchant storefront record.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS ktp_number TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_ktp_number_unique_idx
  ON public.profiles (ktp_number)
  WHERE ktp_number IS NOT NULL AND btrim(ktp_number) <> '';
