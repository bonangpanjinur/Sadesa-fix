-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260925234500_pos_table_menu_settings_hardening.sql .. 20260925234500_pos_table_menu_settings_hardening.sql

-- ===== BEGIN SOURCE: 20260925234500_pos_table_menu_settings_hardening.sql =====
-- Harden merchant table/menu settings at the database boundary.
-- Tables and table orders must never cross tenant/outlet scope, and staff
-- workflow RPCs must respect assigned-outlet access.

CREATE OR REPLACE FUNCTION public.validate_pos_table_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.outlet_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.pos_outlets o
    WHERE o.id = NEW.outlet_id AND o.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS outlet does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;
  IF TG_TABLE_NAME = 'pos_table_orders' AND NEW.table_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.pos_tables t
    WHERE t.id = NEW.table_id
      AND t.tenant_id = NEW.tenant_id
      AND t.outlet_id IS NOT DISTINCT FROM NEW.outlet_id
  ) THEN
    RAISE EXCEPTION 'POS table does not belong to the specified tenant and outlet'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_pos_table_scope ON public.pos_tables;
CREATE TRIGGER validate_pos_table_scope
  BEFORE INSERT OR UPDATE OF tenant_id, outlet_id
  ON public.pos_tables
  FOR EACH ROW EXECUTE FUNCTION public.validate_pos_table_scope();

DROP TRIGGER IF EXISTS validate_pos_table_order_scope ON public.pos_table_orders;
CREATE TRIGGER validate_pos_table_order_scope
  BEFORE INSERT OR UPDATE OF tenant_id, outlet_id, table_id
  ON public.pos_table_orders
  FOR EACH ROW EXECUTE FUNCTION public.validate_pos_table_scope();

CREATE OR REPLACE FUNCTION public.transition_pos_table_order(
  p_order_id uuid,
  p_to_status text,
  p_expected_status text DEFAULT NULL
)
RETURNS public.pos_table_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.pos_table_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.pos_table_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order meja tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.pos_user_has_role(v_order.tenant_id, ARRAY['owner','manager','kasir','cashier'])
     OR NOT public.pos_user_can_access_outlet(v_order.tenant_id, v_order.outlet_id) THEN
    RAISE EXCEPTION 'Tidak memiliki akses mengubah order meja' USING ERRCODE = '42501';
  END IF;
  IF p_expected_status IS NOT NULL AND v_order.status <> p_expected_status THEN
    RAISE EXCEPTION 'Order sudah berubah dari % menjadi %', p_expected_status, v_order.status USING ERRCODE = '40001';
  END IF;
  IF p_to_status NOT IN ('pending','cooking','ready','served','paid','cancelled') THEN
    RAISE EXCEPTION 'Status order tidak valid' USING ERRCODE = '22023';
  END IF;
  IF NOT ((v_order.status = 'pending' AND p_to_status IN ('cooking','cancelled')) OR
          (v_order.status = 'cooking' AND p_to_status IN ('ready','cancelled')) OR
          (v_order.status = 'ready' AND p_to_status IN ('served','cancelled')) OR
          (v_order.status = 'served' AND p_to_status = 'paid')) THEN
    RAISE EXCEPTION 'Transisi order % ke % tidak diizinkan', v_order.status, p_to_status USING ERRCODE = '55000';
  END IF;
  UPDATE public.pos_table_orders
  SET status = p_to_status,
      cooking_started_at = CASE WHEN p_to_status = 'cooking' THEN COALESCE(cooking_started_at, now()) ELSE cooking_started_at END,
      ready_at = CASE WHEN p_to_status = 'ready' THEN COALESCE(ready_at, now()) ELSE ready_at END,
      served_at = CASE WHEN p_to_status = 'served' THEN COALESCE(served_at, now()) ELSE served_at END,
      updated_at = now()
  WHERE id = p_order_id RETURNING * INTO v_order;
  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_pos_table(
  p_table_id uuid,
  p_to_status text,
  p_expected_status text DEFAULT NULL
)
RETURNS public.pos_tables
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_table public.pos_tables%ROWTYPE;
BEGIN
  SELECT * INTO v_table FROM public.pos_tables WHERE id = p_table_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Meja tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.pos_user_has_role(v_table.tenant_id, ARRAY['owner','manager','kasir','cashier'])
     OR NOT public.pos_user_can_access_outlet(v_table.tenant_id, v_table.outlet_id) THEN
    RAISE EXCEPTION 'Tidak memiliki akses mengubah meja' USING ERRCODE = '42501';
  END IF;
  IF p_expected_status IS NOT NULL AND v_table.status <> p_expected_status THEN
    RAISE EXCEPTION 'Meja sudah berubah dari % menjadi %', p_expected_status, v_table.status USING ERRCODE = '40001';
  END IF;
  IF p_to_status NOT IN ('available','occupied','reserved','cleaning') THEN
    RAISE EXCEPTION 'Status meja tidak valid' USING ERRCODE = '22023';
  END IF;
  IF NOT ((v_table.status = 'available' AND p_to_status IN ('reserved','occupied','cleaning')) OR
          (v_table.status = 'reserved' AND p_to_status IN ('occupied','available')) OR
          (v_table.status = 'occupied' AND p_to_status IN ('cleaning','available')) OR
          (v_table.status = 'cleaning' AND p_to_status = 'available')) THEN
    RAISE EXCEPTION 'Transisi meja % ke % tidak diizinkan', v_table.status, p_to_status USING ERRCODE = '55000';
  END IF;
  UPDATE public.pos_tables SET status = p_to_status, updated_at = now()
  WHERE id = p_table_id RETURNING * INTO v_table;
  RETURN v_table;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_pos_table_order(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_table_id uuid,
  p_order_number text,
  p_customer_name text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS public.pos_table_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_table public.pos_tables%ROWTYPE;
  v_order public.pos_table_orders%ROWTYPE;
BEGIN
  IF NOT public.pos_user_has_role(p_tenant_id, ARRAY['owner','manager','kasir','cashier'])
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Tidak memiliki akses membuat order meja' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_table FROM public.pos_tables WHERE id = p_table_id AND tenant_id = p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Meja tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF p_outlet_id IS DISTINCT FROM v_table.outlet_id THEN
    RAISE EXCEPTION 'Outlet order tidak sesuai dengan outlet meja' USING ERRCODE = '22023';
  END IF;
  IF v_table.status NOT IN ('available','reserved') THEN
    RAISE EXCEPTION 'Meja sedang tidak tersedia' USING ERRCODE = '55000';
  END IF;
  INSERT INTO public.pos_table_orders(tenant_id, outlet_id, table_id, table_name, order_number, status, items, customer_name, notes)
  VALUES (p_tenant_id, p_outlet_id, p_table_id, v_table.name, p_order_number, 'pending', COALESCE(p_items, '[]'::jsonb), p_customer_name, p_notes)
  RETURNING * INTO v_order;
  UPDATE public.pos_tables SET status = 'occupied', updated_at = now() WHERE id = p_table_id;
  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.transition_pos_table_order(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.transition_pos_table(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_pos_table_order(uuid, uuid, uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_pos_table_order(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_pos_table(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_pos_table_order(uuid, uuid, uuid, text, text, text, jsonb) TO authenticated;

-- ===== END SOURCE: 20260925234500_pos_table_menu_settings_hardening.sql =====
