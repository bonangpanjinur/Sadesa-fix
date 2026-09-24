-- Courier registration requires a date of birth and a minimum age of 18.
-- The column stays nullable for historical rows; the trigger enforces the rule
-- for every new registration and whenever an existing DOB is changed.

ALTER TABLE public.couriers
  ADD COLUMN IF NOT EXISTS date_of_birth date;

CREATE OR REPLACE FUNCTION public.validate_courier_minimum_age()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.date_of_birth IS NULL THEN
    RAISE EXCEPTION 'Tanggal lahir wajib diisi untuk pendaftaran ojek'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.date_of_birth IS NOT NULL
     AND NEW.date_of_birth > (CURRENT_DATE - INTERVAL '18 years')::date THEN
    RAISE EXCEPTION 'Pendaftar ojek harus berusia minimal 18 tahun'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_courier_minimum_age ON public.couriers;
CREATE TRIGGER validate_courier_minimum_age
  BEFORE INSERT OR UPDATE OF date_of_birth ON public.couriers
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_courier_minimum_age();

COMMENT ON COLUMN public.couriers.date_of_birth IS
  'Tanggal lahir courier; wajib untuk registrasi baru dan usia minimal 18 tahun.';
