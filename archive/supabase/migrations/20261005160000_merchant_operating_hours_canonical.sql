-- Keep weekly hours authoritative and synchronize legacy columns only as a
-- compatibility summary for older clients.

CREATE OR REPLACE FUNCTION public.sync_merchant_legacy_hours_from_weekly()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id uuid;
  v_open_time time;
  v_close_time time;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_merchant_id := OLD.merchant_id;
  ELSE
    v_merchant_id := NEW.merchant_id;
  END IF;

  SELECT schedule.open_time, schedule.close_time
  INTO v_open_time, v_close_time
  FROM public.merchant_operating_hours AS schedule
  WHERE schedule.merchant_id = v_merchant_id
    AND NOT schedule.is_closed
  ORDER BY CASE schedule.day_of_week
    WHEN 1 THEN 1
    WHEN 2 THEN 2
    WHEN 3 THEN 3
    WHEN 4 THEN 4
    WHEN 5 THEN 5
    WHEN 6 THEN 6
    WHEN 0 THEN 7
  END
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.merchants AS merchant
    SET open_time = v_open_time,
        close_time = v_close_time
    WHERE merchant.id = v_merchant_id
      AND (
        merchant.open_time IS DISTINCT FROM v_open_time
        OR merchant.close_time IS DISTINCT FROM v_close_time
      );
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_merchant_legacy_hours_from_weekly() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_merchant_legacy_hours_from_weekly() TO authenticated;

DROP TRIGGER IF EXISTS merchant_operating_hours_sync_legacy ON public.merchant_operating_hours;
CREATE TRIGGER merchant_operating_hours_sync_legacy
AFTER INSERT OR UPDATE OR DELETE ON public.merchant_operating_hours
FOR EACH ROW
EXECUTE FUNCTION public.sync_merchant_legacy_hours_from_weekly();

-- Repair the compatibility summary for merchants that already have a weekly
-- schedule. Weekly rows are not changed.
WITH first_open_day AS (
  SELECT DISTINCT ON (schedule.merchant_id)
    schedule.merchant_id,
    schedule.open_time,
    schedule.close_time
  FROM public.merchant_operating_hours AS schedule
  WHERE NOT schedule.is_closed
  ORDER BY schedule.merchant_id, CASE schedule.day_of_week
    WHEN 1 THEN 1
    WHEN 2 THEN 2
    WHEN 3 THEN 3
    WHEN 4 THEN 4
    WHEN 5 THEN 5
    WHEN 6 THEN 6
    WHEN 0 THEN 7
  END
)
UPDATE public.merchants AS merchant
SET open_time = first_open_day.open_time,
    close_time = first_open_day.close_time
FROM first_open_day
WHERE merchant.id = first_open_day.merchant_id
  AND (
    merchant.open_time IS DISTINCT FROM first_open_day.open_time
    OR merchant.close_time IS DISTINCT FROM first_open_day.close_time
  );

CREATE OR REPLACE FUNCTION public.save_merchant_operating_hours_atomic(
  p_merchant_id uuid,
  p_schedule jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_schedule_count integer;
  v_distinct_day_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesi pengguna tidak valid' USING ERRCODE = '42501';
  END IF;

  PERFORM 1
  FROM public.merchants AS merchant
  WHERE merchant.id = p_merchant_id
    AND (public.is_admin() OR merchant.user_id = auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Merchant tidak ditemukan atau akses ditolak' USING ERRCODE = '42501';
  END IF;

  IF jsonb_typeof(p_schedule) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Jadwal operasional harus berupa daftar hari' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_schedule) <> 7 THEN
    RAISE EXCEPTION 'Jadwal operasional harus berisi 7 hari' USING ERRCODE = '22023';
  END IF;

  SELECT
    count(*)::integer,
    count(DISTINCT schedule.day_of_week)::integer
  INTO v_schedule_count, v_distinct_day_count
  FROM jsonb_to_recordset(p_schedule) AS schedule(
    day_of_week smallint,
    open_time time,
    close_time time,
    is_closed boolean
  );

  IF v_schedule_count <> 7
    OR v_distinct_day_count <> 7
    OR EXISTS (
      SELECT 1
      FROM jsonb_to_recordset(p_schedule) AS schedule(
        day_of_week smallint,
        open_time time,
        close_time time,
        is_closed boolean
      )
      WHERE schedule.day_of_week IS NULL
        OR schedule.day_of_week NOT BETWEEN 0 AND 6
        OR schedule.open_time IS NULL
        OR schedule.close_time IS NULL
        OR schedule.is_closed IS NULL
    ) THEN
    RAISE EXCEPTION 'Jadwal operasional tidak valid' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.merchant_operating_hours (
    merchant_id, day_of_week, open_time, close_time, is_closed, updated_at
  )
  SELECT
    p_merchant_id,
    schedule.day_of_week,
    schedule.open_time,
    schedule.close_time,
    schedule.is_closed,
    now()
  FROM jsonb_to_recordset(p_schedule) AS schedule(
    day_of_week smallint,
    open_time time,
    close_time time,
    is_closed boolean
  )
  ON CONFLICT (merchant_id, day_of_week)
  DO UPDATE SET
    open_time = EXCLUDED.open_time,
    close_time = EXCLUDED.close_time,
    is_closed = EXCLUDED.is_closed,
    updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.save_merchant_operating_hours_atomic(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_merchant_operating_hours_atomic(uuid, jsonb) TO authenticated;
COMMENT ON FUNCTION public.save_merchant_operating_hours_atomic(uuid, jsonb) IS
  'Atomically saves a complete weekly schedule for its merchant owner or an admin; legacy hours are synchronized by trigger.';

CREATE OR REPLACE FUNCTION public.admin_create_merchant_atomic(
  p_merchant jsonb,
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
  v_user_id uuid;
  v_requested_category_count integer;
  v_active_category_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Hanya admin yang dapat membuat merchant' USING ERRCODE = '42501';
  END IF;

  IF jsonb_typeof(p_merchant) IS DISTINCT FROM 'object'
    OR NULLIF(trim(p_merchant->>'name'), '') IS NULL
    OR length(trim(p_merchant->>'name')) < 3
    OR length(trim(p_merchant->>'name')) > 100
    OR NULLIF(trim(p_merchant->>'phone'), '') IS NULL THEN
    RAISE EXCEPTION 'Nama usaha dan nomor telepon wajib diisi' USING ERRCODE = '22023';
  END IF;

  v_requested_category_count := (
    SELECT count(DISTINCT category_id)::integer
    FROM unnest(COALESCE(p_category_ids, ARRAY[]::uuid[])) AS categories(category_id)
  );
  SELECT count(*)::integer
  INTO v_active_category_count
  FROM public.categories
  WHERE id = ANY(COALESCE(p_category_ids, ARRAY[]::uuid[]))
    AND is_active = true;
  IF v_requested_category_count = 0 OR v_active_category_count <> v_requested_category_count THEN
    RAISE EXCEPTION 'Kategori usaha tidak valid atau tidak aktif' USING ERRCODE = '23514';
  END IF;

  v_user_id := NULLIF(p_merchant->>'user_id', '')::uuid;
  INSERT INTO public.merchants (
    name, user_id, phone, address, province, city, district, subdistrict,
    village_id, business_category, business_description, is_open, status,
    registration_status, order_mode, open_time, close_time, image_url,
    cover_image_url, location_lat, location_lng, verifikator_code,
    trade_group, registered_at
  ) VALUES (
    trim(p_merchant->>'name'),
    v_user_id,
    NULLIF(trim(p_merchant->>'phone'), ''),
    NULLIF(trim(p_merchant->>'address'), ''),
    NULLIF(trim(p_merchant->>'province'), ''),
    NULLIF(trim(p_merchant->>'city'), ''),
    NULLIF(trim(p_merchant->>'district'), ''),
    NULLIF(trim(p_merchant->>'subdistrict'), ''),
    NULLIF(p_merchant->>'village_id', '')::uuid,
    NULLIF(trim(p_merchant->>'business_category'), ''),
    NULLIF(trim(p_merchant->>'business_description'), ''),
    COALESCE(NULLIF(p_merchant->>'is_open', '')::boolean, false),
    'ACTIVE',
    'PENDING',
    'ADMIN_ASSISTED',
    '08:00'::time,
    '17:00'::time,
    NULLIF(trim(p_merchant->>'image_url'), ''),
    NULLIF(trim(p_merchant->>'cover_image_url'), ''),
    NULLIF(p_merchant->>'location_lat', '')::numeric,
    NULLIF(p_merchant->>'location_lng', '')::numeric,
    NULLIF(upper(trim(p_merchant->>'verifikator_code')), ''),
    NULLIF(trim(p_merchant->>'trade_group'), ''),
    now()
  )
  RETURNING id INTO v_merchant_id;

  INSERT INTO public.merchant_categories (merchant_id, category_id)
  SELECT v_merchant_id, category_id
  FROM unnest(p_category_ids) AS categories(category_id)
  ON CONFLICT (merchant_id, category_id) DO NOTHING;

  PERFORM public.save_merchant_operating_hours_atomic(v_merchant_id, p_schedule);

  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (v_user_id, 'buyer'), (v_user_id, 'merchant')
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  RETURN v_merchant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_merchant_atomic(jsonb, uuid[], jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_merchant_atomic(jsonb, uuid[], jsonb) TO authenticated;
COMMENT ON FUNCTION public.admin_create_merchant_atomic(jsonb, uuid[], jsonb) IS
  'Atomically creates an admin-managed merchant, its categories, roles, and complete weekly schedule.';

-- General settings are not an operating-hours editor. Keep the old columns
-- unchanged here; only weekly-schedule writes may update their summary.
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

REVOKE ALL ON FUNCTION public.update_merchant_settings_atomic(uuid, jsonb, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_merchant_settings_atomic(uuid, jsonb, uuid[]) TO authenticated;
