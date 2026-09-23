ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS selfie_url text;

COMMENT ON COLUMN public.profiles.selfie_url IS 'Foto selfie wajib pengguna untuk melengkapi profil.';
