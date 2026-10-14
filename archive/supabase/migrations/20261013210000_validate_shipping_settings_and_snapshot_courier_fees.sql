DO $bootstrap_do_shipping_audit$
BEGIN
  EXECUTE $bootstrap_sql_validate_shipping$CREATE OR REPLACE FUNCTION public.validate_shipping_pricing_setting(p_key text, p_value jsonb)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fields text[];
  v_field text;
  v_value numeric;
  v_zone jsonb;
  v_distance numeric;
  v_previous_distance numeric := 0;
  v_fee numeric;
BEGIN
  IF p_key = 'shipping_base_fee' THEN
    IF jsonb_typeof(p_value) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'Pengaturan tarif ongkir harus berupa objek JSON' USING ERRCODE = '22023';
    END IF;

    v_fields := ARRAY['base_fee', 'per_km_fee', 'min_fee', 'max_fee', 'free_shipping_min_order'];
    FOREACH v_field IN ARRAY v_fields LOOP
      IF jsonb_typeof(p_value->v_field) IS DISTINCT FROM 'number' THEN
        RAISE EXCEPTION 'Tarif ongkir % harus berupa bilangan rupiah bulat', v_field USING ERRCODE = '22023';
      END IF;
      v_value := (p_value->>v_field)::numeric;
      IF v_value < 0 OR trunc(v_value) <> v_value OR v_value > 2147483647 THEN
        RAISE EXCEPTION 'Tarif ongkir % harus berupa bilangan rupiah bulat non-negatif', v_field USING ERRCODE = '22023';
      END IF;
    END LOOP;

    IF (p_value->>'min_fee')::numeric > (p_value->>'max_fee')::numeric THEN
      RAISE EXCEPTION 'Biaya minimum ongkir tidak boleh melebihi biaya maksimum' USING ERRCODE = '22023';
    END IF;
  ELSIF p_key = 'shipping_zones' THEN
    IF jsonb_typeof(p_value) IS DISTINCT FROM 'object'
       OR jsonb_typeof(p_value->'zones') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'Zona ongkir harus berisi minimal satu zona' USING ERRCODE = '22023';
    END IF;
    IF jsonb_array_length(p_value->'zones') = 0 THEN
      RAISE EXCEPTION 'Zona ongkir harus berisi minimal satu zona' USING ERRCODE = '22023';
    END IF;

    FOR v_zone IN
      SELECT value
      FROM jsonb_array_elements(p_value->'zones') AS zone(value)
    LOOP
      IF jsonb_typeof(v_zone) IS DISTINCT FROM 'object'
         OR jsonb_typeof(v_zone->'name') IS DISTINCT FROM 'string'
         OR btrim(v_zone->>'name') = '' THEN
        RAISE EXCEPTION 'Setiap zona ongkir wajib memiliki nama' USING ERRCODE = '22023';
      END IF;
      IF jsonb_typeof(v_zone->'max_distance_km') IS DISTINCT FROM 'number' THEN
        RAISE EXCEPTION 'Batas jarak setiap zona harus berupa angka' USING ERRCODE = '22023';
      END IF;
      IF jsonb_typeof(v_zone->'fee') IS DISTINCT FROM 'number' THEN
        RAISE EXCEPTION 'Surcharge setiap zona harus berupa bilangan rupiah bulat' USING ERRCODE = '22023';
      END IF;

      v_distance := (v_zone->>'max_distance_km')::numeric;
      v_fee := (v_zone->>'fee')::numeric;
      IF v_distance <= 0 THEN
        RAISE EXCEPTION 'Batas jarak zona harus lebih dari 0 km' USING ERRCODE = '22023';
      END IF;
      IF v_distance <= v_previous_distance THEN
        RAISE EXCEPTION 'Zona harus diurutkan berdasarkan jarak dengan batas yang unik dan tidak tumpang tindih' USING ERRCODE = '22023';
      END IF;
      IF v_fee < 0 OR trunc(v_fee) <> v_fee OR v_fee > 2147483647 THEN
        RAISE EXCEPTION 'Surcharge zona harus berupa bilangan rupiah bulat non-negatif' USING ERRCODE = '22023';
      END IF;

      v_previous_distance := v_distance;
    END LOOP;
  END IF;
EXCEPTION
  WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RAISE EXCEPTION 'Nilai pengaturan ongkir harus berupa angka yang valid' USING ERRCODE = '22023';
END;
$$$bootstrap_sql_validate_shipping$;

  EXECUTE $bootstrap_sql_guard_shipping$CREATE OR REPLACE FUNCTION public.guard_shipping_pricing_setting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.validate_shipping_pricing_setting(NEW.key, NEW.value);
  RETURN NEW;
END;
$$$bootstrap_sql_guard_shipping$;

  EXECUTE $bootstrap_sql_revoke_validate$REVOKE ALL ON FUNCTION public.validate_shipping_pricing_setting(text, jsonb) FROM PUBLIC, anon, authenticated$bootstrap_sql_revoke_validate$;
  EXECUTE $bootstrap_sql_revoke_guard$REVOKE ALL ON FUNCTION public.guard_shipping_pricing_setting() FROM PUBLIC, anon, authenticated$bootstrap_sql_revoke_guard$;
  EXECUTE $bootstrap_sql_drop_setting_trigger$DROP TRIGGER IF EXISTS app_settings_validate_shipping_pricing ON public.app_settings$bootstrap_sql_drop_setting_trigger$;
  EXECUTE $bootstrap_sql_create_setting_trigger$CREATE TRIGGER app_settings_validate_shipping_pricing
BEFORE INSERT OR UPDATE OF key, value ON public.app_settings
FOR EACH ROW
EXECUTE FUNCTION public.guard_shipping_pricing_setting()$bootstrap_sql_create_setting_trigger$;

  EXECUTE $bootstrap_sql_shipping_preflight$DO $$
DECLARE
  v_setting record;
BEGIN
  FOR v_setting IN
    SELECT key, value
    FROM public.app_settings
    WHERE key IN ('shipping_base_fee', 'shipping_zones')
  LOOP
    PERFORM public.validate_shipping_pricing_setting(v_setting.key, v_setting.value);
  END LOOP;
END;
$$$bootstrap_sql_shipping_preflight$;

  EXECUTE $bootstrap_sql_shipping_audit_table$CREATE TABLE IF NOT EXISTS public.shipping_pricing_change_log (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  setting_key text NOT NULL CHECK (setting_key IN ('shipping_base_fee', 'shipping_zones')),
  old_value jsonb,
  new_value jsonb,
  changed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_shipping_audit_table$;
  EXECUTE $bootstrap_sql_shipping_audit_index$CREATE INDEX IF NOT EXISTS shipping_pricing_change_log_created_idx
  ON public.shipping_pricing_change_log(created_at DESC)$bootstrap_sql_shipping_audit_index$;
  EXECUTE $bootstrap_sql_shipping_audit_rls$ALTER TABLE public.shipping_pricing_change_log ENABLE ROW LEVEL SECURITY$bootstrap_sql_shipping_audit_rls$;
  EXECUTE $bootstrap_sql_shipping_audit_drop_policy$DROP POLICY IF EXISTS shipping_pricing_change_log_admin_read ON public.shipping_pricing_change_log$bootstrap_sql_shipping_audit_drop_policy$;
  EXECUTE $bootstrap_sql_shipping_audit_policy$CREATE POLICY shipping_pricing_change_log_admin_read
  ON public.shipping_pricing_change_log
  FOR SELECT TO authenticated
  USING (public.is_admin())$bootstrap_sql_shipping_audit_policy$;
  EXECUTE $bootstrap_sql_shipping_audit_revoke$REVOKE ALL ON public.shipping_pricing_change_log FROM PUBLIC, anon, authenticated$bootstrap_sql_shipping_audit_revoke$;
  EXECUTE $bootstrap_sql_shipping_audit_grant$GRANT SELECT ON public.shipping_pricing_change_log TO authenticated$bootstrap_sql_shipping_audit_grant$;

  EXECUTE $bootstrap_sql_audit_shipping_function$CREATE OR REPLACE FUNCTION public.audit_shipping_pricing_settings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_key text;
  v_old_value jsonb;
  v_new_value jsonb;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.key NOT IN ('shipping_base_fee', 'shipping_zones') THEN RETURN NEW; END IF;
    v_key := NEW.key;
    v_new_value := NEW.value;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.key NOT IN ('shipping_base_fee', 'shipping_zones') THEN RETURN OLD; END IF;
    v_key := OLD.key;
    v_old_value := OLD.value;
  ELSE
    IF OLD.key NOT IN ('shipping_base_fee', 'shipping_zones')
       AND NEW.key NOT IN ('shipping_base_fee', 'shipping_zones') THEN
      RETURN NEW;
    END IF;
    IF OLD.key IS NOT DISTINCT FROM NEW.key
       AND OLD.value IS NOT DISTINCT FROM NEW.value THEN
      RETURN NEW;
    END IF;
    v_key := CASE
      WHEN NEW.key IN ('shipping_base_fee', 'shipping_zones') THEN NEW.key
      ELSE OLD.key
    END;
    IF OLD.key IN ('shipping_base_fee', 'shipping_zones') THEN v_old_value := OLD.value; END IF;
    IF NEW.key IN ('shipping_base_fee', 'shipping_zones') THEN v_new_value := NEW.value; END IF;
  END IF;

  INSERT INTO public.shipping_pricing_change_log(setting_key, old_value, new_value, changed_by)
  VALUES (v_key, v_old_value, v_new_value, auth.uid());

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_audit_shipping_function$;
  EXECUTE $bootstrap_sql_audit_shipping_revoke$REVOKE ALL ON FUNCTION public.audit_shipping_pricing_settings() FROM PUBLIC, anon, authenticated$bootstrap_sql_audit_shipping_revoke$;
  EXECUTE $bootstrap_sql_audit_shipping_drop_trigger$DROP TRIGGER IF EXISTS app_settings_audit_shipping_pricing ON public.app_settings$bootstrap_sql_audit_shipping_drop_trigger$;
  EXECUTE $bootstrap_sql_audit_shipping_create_trigger$CREATE TRIGGER app_settings_audit_shipping_pricing
AFTER INSERT OR UPDATE OR DELETE ON public.app_settings
FOR EACH ROW
EXECUTE FUNCTION public.audit_shipping_pricing_settings()$bootstrap_sql_audit_shipping_create_trigger$;

  EXECUTE $bootstrap_sql_snapshot_earnings$CREATE OR REPLACE FUNCTION public.snapshot_courier_delivery_earnings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_gross integer;
  v_fee_percent numeric := 0;
  v_fee_enabled boolean := false;
  v_delivery_fee_enabled boolean := false;
BEGIN
  IF NEW.courier_id IS NULL
     OR upper(COALESCE(NEW.status, '')) NOT IN ('DONE', 'DELIVERED', 'COMPLETED')
     OR upper(COALESCE(OLD.status, '')) IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
    RETURN NEW;
  END IF;

  v_gross := GREATEST(
    COALESCE(NULLIF(NEW.courier_earning_estimate, 0), NEW.shipping_cost, 0),
    0
  );

  SELECT fee_percent, is_enabled, COALESCE(charge_courier_delivery, false)
    INTO v_fee_percent, v_fee_enabled, v_delivery_fee_enabled
  FROM public.commission_fee_settings
  WHERE owner_type = 'COURIER';

  NEW.courier_earning_estimate := v_gross;
  NEW.courier_platform_fee := CASE
    WHEN COALESCE(v_fee_enabled, false) AND COALESCE(v_delivery_fee_enabled, false)
      THEN LEAST(v_gross, round(v_gross::numeric * COALESCE(v_fee_percent, 0) / 100)::integer)
    ELSE 0
  END;

  RETURN NEW;
END;
$$$bootstrap_sql_snapshot_earnings$;
  EXECUTE $bootstrap_sql_revoke_snapshot$REVOKE ALL ON FUNCTION public.snapshot_courier_delivery_earnings() FROM PUBLIC, anon, authenticated$bootstrap_sql_revoke_snapshot$;
  EXECUTE $bootstrap_sql_drop_snapshot_trigger$DROP TRIGGER IF EXISTS orders_snapshot_courier_delivery_earnings ON public.orders$bootstrap_sql_drop_snapshot_trigger$;
  EXECUTE $bootstrap_sql_create_snapshot_trigger$CREATE TRIGGER orders_snapshot_courier_delivery_earnings
BEFORE UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.snapshot_courier_delivery_earnings()$bootstrap_sql_create_snapshot_trigger$;
  EXECUTE $bootstrap_sql_notify$NOTIFY pgrst, 'reload schema'$bootstrap_sql_notify$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_shipping_audit$;
