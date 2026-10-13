-- DesaMart repeatable canonical bootstrap bundle.
-- Persist the required WhatsApp number submitted during signup.
DO $bootstrap_do_signup_whatsapp$
BEGIN
  EXECUTE $bootstrap_sql_signup_whatsapp$CREATE OR REPLACE FUNCTION public.handle_new_user()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
  BEGIN
    INSERT INTO public.profiles (
      user_id, full_name, email, phone,
      address, province_id, province_name, city_id, city_name,
      district_id, district_name, village_id, village_name, address_detail
    )
    VALUES (
      NEW.id,
      COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name', ''), NULLIF(NEW.raw_user_meta_data->>'name', ''), split_part(NEW.email, '@', 1)),
      NEW.email,
      NULLIF(NEW.raw_user_meta_data->>'phone', ''),
      NULLIF(NEW.raw_user_meta_data->>'address', ''),
      NULLIF(NEW.raw_user_meta_data->>'province_id', ''),
      NULLIF(NEW.raw_user_meta_data->>'province_name', ''),
      NULLIF(NEW.raw_user_meta_data->>'city_id', ''),
      NULLIF(NEW.raw_user_meta_data->>'city_name', ''),
      NULLIF(NEW.raw_user_meta_data->>'district_id', ''),
      NULLIF(NEW.raw_user_meta_data->>'district_name', ''),
      NULLIF(NEW.raw_user_meta_data->>'village_id', ''),
      NULLIF(NEW.raw_user_meta_data->>'village_name', ''),
      NULLIF(NEW.raw_user_meta_data->>'address_detail', '')
    )
    ON CONFLICT (user_id) DO UPDATE SET
      full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
      email = COALESCE(EXCLUDED.email, public.profiles.email),
      phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
      address = COALESCE(EXCLUDED.address, public.profiles.address),
      province_id = COALESCE(EXCLUDED.province_id, public.profiles.province_id),
      province_name = COALESCE(EXCLUDED.province_name, public.profiles.province_name),
      city_id = COALESCE(EXCLUDED.city_id, public.profiles.city_id),
      city_name = COALESCE(EXCLUDED.city_name, public.profiles.city_name),
      district_id = COALESCE(EXCLUDED.district_id, public.profiles.district_id),
      district_name = COALESCE(EXCLUDED.district_name, public.profiles.district_name),
      village_id = COALESCE(EXCLUDED.village_id, public.profiles.village_id),
      village_name = COALESCE(EXCLUDED.village_name, public.profiles.village_name),
      address_detail = COALESCE(EXCLUDED.address_detail, public.profiles.address_detail);

    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'buyer')
    ON CONFLICT (user_id, role) DO NOTHING;
    RETURN NEW;
  END;
  $$;$bootstrap_sql_signup_whatsapp$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_signup_whatsapp$;
