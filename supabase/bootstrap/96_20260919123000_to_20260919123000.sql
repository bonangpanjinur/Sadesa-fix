-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260919123000_active_merchant_category.sql .. 20260919123000_active_merchant_category.sql

-- ===== BEGIN SOURCE: 20260919123000_active_merchant_category.sql =====
-- Keep merchant business categories aligned with the admin-managed categories catalog.
ALTER TABLE public.merchants
  ALTER COLUMN business_category SET DEFAULT NULL;

CREATE OR REPLACE FUNCTION public.validate_active_merchant_business_category()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.business_category IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.categories
       WHERE slug = NEW.business_category
         AND is_active = true
     ) THEN
    RAISE EXCEPTION 'business_category must reference an active admin category: %', NEW.business_category
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS merchants_active_business_category ON public.merchants;
CREATE TRIGGER merchants_active_business_category
  BEFORE INSERT OR UPDATE OF business_category ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_active_merchant_business_category();

COMMENT ON FUNCTION public.validate_active_merchant_business_category() IS
  'Prevents merchant registrations and updates from using categories that are missing or inactive in the admin catalog.';

-- ===== END SOURCE: 20260919123000_active_merchant_category.sql =====
