-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

-- DesaMart canonical bootstrap bundle for atomic merchant onboarding and settings.
DO $bootstrap_do_99c68d89f65a$
BEGIN
  EXECUTE $bootstrap_sql_99c68d89f65a$-- Atomic merchant onboarding and settings mutations.
-- All related writes occur in one PostgreSQL transaction inside each RPC.

CREATE OR REPLACE FUNCTION public.register_merchant_atomic(
  p_user_id uuid,
  p_name text,
  p_village_id uuid,
  p_address text,
  p_province text,
  p_city text,
  p_district text,
  p_subdistrict text,
  p_phone text,
  p_business_category text,
  p_business_description text,
  p_verifikator_code text,
  p_trade_group text,
  p_location_lat numeric,
  p_location_lng numeric,
  p_halal_status text,
  p_halal_certificate_url text,
  p_ktp_url text,
  p_category_ids uuid[],
  p_schedule jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id uuid;
  v_category_count integer;
  v_requested_category_count integer;
  v_schedule_count integer;
BEGIN
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pengguna tidak valid untuk pendaftaran merchant' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(trim(COALESCE(p_name, '')), '') IS NULL
     OR length(trim(p_name)) < 3
     OR length(trim(p_name)) > 100 THEN
    RAISE EXCEPTION 'Nama usaha harus berisi 3 sampai 100 karakter' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.merchants
    WHERE user_id = auth.uid()
      AND registration_status IN ('PENDING', 'APPROVED')
  ) THEN
    RAISE EXCEPTION 'Pengguna sudah memiliki pendaftaran merchant aktif' USING ERRCODE = '23505';
  END IF;

  v_requested_category_count := (
    SELECT count(DISTINCT category_id)::integer
    FROM unnest(COALESCE(p_category_ids, ARRAY[]::uuid[])) AS categories(category_id)
  );
  SELECT count(*)::integer INTO v_category_count
  FROM public.categories
  WHERE id = ANY(COALESCE(p_category_ids, ARRAY[]::uuid[]))
    AND is_active = true;
  IF v_requested_category_count = 0 OR v_category_count <> v_requested_category_count THEN
    RAISE EXCEPTION 'Kategori usaha tidak valid atau tidak aktif' USING ERRCODE = '23514';
  END IF;

  IF jsonb_typeof(p_schedule) <> 'array' OR jsonb_array_length(p_schedule) <> 7 THEN
    RAISE EXCEPTION 'Jadwal operasional harus berisi 7 hari' USING ERRCODE = '22023';
  END IF;
  SELECT count(*)::integer INTO v_schedule_count
  FROM jsonb_to_recordset(p_schedule) AS schedule(day_of_week smallint, open_time time, close_time time, is_closed boolean);
  IF v_schedule_count <> 7 OR EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_schedule) AS schedule(day_of_week smallint, open_time time, close_time time, is_closed boolean)
    WHERE day_of_week NOT BETWEEN 0 AND 6
       OR open_time IS NULL
       OR close_time IS NULL
  ) OR (
    SELECT count(DISTINCT day_of_week)
    FROM jsonb_to_recordset(p_schedule) AS schedule(day_of_week smallint, open_time time, close_time time, is_closed boolean)
  ) <> 7 THEN
    RAISE EXCEPTION 'Jadwal operasional tidak valid' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.merchants (
    name, user_id, village_id, address, province, city, district, subdistrict,
    phone, business_category, business_description, verifikator_code, trade_group,
    registration_status, status, order_mode, is_open, open_time, close_time,
    registered_at, location_lat, location_lng, halal_status,
    halal_certificate_url, ktp_url
  ) VALUES (
    trim(p_name), p_user_id, p_village_id, NULLIF(trim(p_address), ''),
    NULLIF(trim(p_province), ''), NULLIF(trim(p_city), ''), NULLIF(trim(p_district), ''),
    NULLIF(trim(p_subdistrict), ''), NULLIF(trim(p_phone), ''), trim(p_business_category),
    NULLIF(trim(p_business_description), ''), NULLIF(upper(trim(p_verifikator_code)), ''),
    NULLIF(trim(p_trade_group), ''), 'PENDING', 'INACTIVE', 'ADMIN_ASSISTED', false,
    (SELECT open_time FROM jsonb_to_recordset(p_schedule) AS schedule(day_of_week smallint, open_time time, close_time time, is_closed boolean) WHERE day_of_week = 1),
    (SELECT close_time FROM jsonb_to_recordset(p_schedule) AS schedule(day_of_week smallint, open_time time, close_time time, is_closed boolean) WHERE day_of_week = 1),
    now(), p_location_lat, p_location_lng, COALESCE(NULLIF(trim(p_halal_status), ''), 'NONE'),
    NULLIF(trim(p_halal_certificate_url), ''), NULLIF(trim(p_ktp_url), '')
  ) RETURNING id INTO v_merchant_id;

  INSERT INTO public.merchant_categories (merchant_id, category_id)
  SELECT DISTINCT v_merchant_id, category_id
  FROM unnest(p_category_ids) AS categories(category_id);

  INSERT INTO public.merchant_operating_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
  SELECT v_merchant_id, schedule.day_of_week, schedule.open_time, schedule.close_time, COALESCE(schedule.is_closed, false)
  FROM jsonb_to_recordset(p_schedule) AS schedule(day_of_week smallint, open_time time, close_time time, is_closed boolean);

  RETURN v_merchant_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_merchant_settings_atomic(
  p_merchant_id uuid,
  p_settings jsonb,
  p_category_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_category_count integer;
  v_requested_category_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesi pengguna tidak valid' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.merchants
    WHERE id = p_merchant_id AND user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED'
    FOR UPDATE
  ) THEN
    RAISE EXCEPTION 'Merchant tidak ditemukan atau tidak aktif' USING ERRCODE = '42501';
  END IF;

  v_requested_category_count := (
    SELECT count(DISTINCT category_id)::integer
    FROM unnest(COALESCE(p_category_ids, ARRAY[]::uuid[])) AS categories(category_id)
  );
  SELECT count(*)::integer INTO v_category_count
  FROM public.categories
  WHERE id = ANY(COALESCE(p_category_ids, ARRAY[]::uuid[]))
    AND is_active = true;
  IF v_requested_category_count = 0 OR v_category_count <> v_requested_category_count THEN
    RAISE EXCEPTION 'Kategori usaha tidak valid atau tidak aktif' USING ERRCODE = '23514';
  END IF;

  UPDATE public.merchants
  SET name = NULLIF(trim(p_settings->>'name'), ''),
      phone = NULLIF(trim(p_settings->>'phone'), ''),
      address = NULLIF(trim(p_settings->>'address'), ''),
      province = NULLIF(trim(p_settings->>'province'), ''),
      city = NULLIF(trim(p_settings->>'city'), ''),
      district = NULLIF(trim(p_settings->>'district'), ''),
      subdistrict = NULLIF(trim(p_settings->>'subdistrict'), ''),
      location_lat = NULLIF(p_settings->>'location_lat', '')::numeric,
      location_lng = NULLIF(p_settings->>'location_lng', '')::numeric,
      google_maps_url = NULLIF(trim(p_settings->>'google_maps_url'), ''),
      business_category = NULLIF(trim(p_settings->>'business_category'), ''),
      business_description = NULLIF(trim(p_settings->>'business_description'), ''),
      open_time = NULLIF(p_settings->>'open_time', '')::time,
      close_time = NULLIF(p_settings->>'close_time', '')::time,
      is_open = COALESCE((p_settings->>'is_open')::boolean, false),
      classification_price = NULLIF(p_settings->>'classification_price', ''),
      order_mode = COALESCE(NULLIF(p_settings->>'order_mode', ''), 'ADMIN_ASSISTED'),
      image_url = NULLIF(trim(p_settings->>'image_url'), ''),
      cover_image_url = NULLIF(trim(p_settings->>'cover_image_url'), ''),
      bank_name = NULLIF(trim(p_settings->>'bank_name'), ''),
      bank_account_number = NULLIF(trim(p_settings->>'bank_account_number'), ''),
      bank_account_name = NULLIF(trim(p_settings->>'bank_account_name'), ''),
      qris_image_url = NULLIF(trim(p_settings->>'qris_image_url'), ''),
      payment_cod_enabled = false,
      payment_transfer_enabled = COALESCE((p_settings->>'payment_transfer_enabled')::boolean, false),
      notification_sound_enabled = COALESCE((p_settings->>'notification_sound_enabled')::boolean, true)
  WHERE id = p_merchant_id AND user_id = auth.uid();

  DELETE FROM public.merchant_categories WHERE merchant_id = p_merchant_id;
  INSERT INTO public.merchant_categories (merchant_id, category_id)
  SELECT DISTINCT p_merchant_id, category_id
  FROM unnest(p_category_ids) AS categories(category_id);
END;
$$;

REVOKE ALL ON FUNCTION public.register_merchant_atomic(uuid, text, uuid, text, text, text, text, text, text, text, text, text, text, numeric, numeric, text, text, text, uuid[], jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_merchant_atomic(uuid, text, uuid, text, text, text, text, text, text, text, text, text, text, numeric, numeric, text, text, text, uuid[], jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.update_merchant_settings_atomic(uuid, jsonb, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_merchant_settings_atomic(uuid, jsonb, uuid[]) TO authenticated;

COMMENT ON FUNCTION public.register_merchant_atomic IS 'Atomically creates merchant, categories, and weekly schedule for the authenticated user.';
COMMENT ON FUNCTION public.update_merchant_settings_atomic IS 'Atomically updates merchant settings and category assignments for the owner.';
$bootstrap_sql_99c68d89f65a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_99c68d89f65a$;
