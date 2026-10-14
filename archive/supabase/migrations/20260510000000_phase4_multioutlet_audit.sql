-- Phase 4: Multi-outlet & Audit Trail
-- Transfer Stok, Audit Log, Notifikasi, Akses Per Outlet

-- ============================================================
-- TRANSFER STOK ANTAR OUTLET
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_stock_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  transfer_number text NOT NULL,
  from_outlet_id uuid REFERENCES pos_outlets(id) NOT NULL,
  to_outlet_id uuid REFERENCES pos_outlets(id) NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending','approved','completed','rejected','cancelled')),
  notes text,
  rejection_reason text,
  requested_by uuid REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  completed_by uuid REFERENCES auth.users(id),
  requested_at timestamptz DEFAULT now(),
  approved_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_00dd27add7f9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00dd27add7f9$;

DO $bootstrap_do_e0afbff88b78$
BEGIN
  EXECUTE $bootstrap_sql_e0afbff88b78$CREATE TABLE IF NOT EXISTS pos_stock_transfer_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid REFERENCES pos_stock_transfers(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id) NOT NULL,
  variant_id uuid REFERENCES pos_product_variants(id),
  product_name text NOT NULL,
  sku text,
  unit text DEFAULT 'pcs',
  qty_requested numeric(15,3) NOT NULL DEFAULT 0,
  qty_sent numeric(15,3) DEFAULT 0,
  qty_received numeric(15,3) DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_e0afbff88b78$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e0afbff88b78$;

DO $bootstrap_do_7013697a34b5$
BEGIN
  EXECUTE $bootstrap_sql_7013697a34b5$-- ============================================================
-- AUDIT LOG (Jejak Aktivitas User)
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id),
  user_id uuid REFERENCES auth.users(id),
  user_name text,
  action text NOT NULL,
  module text NOT NULL,
  entity_type text,
  entity_id text,
  description text NOT NULL,
  old_values jsonb,
  new_values jsonb,
  ip_address text,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_7013697a34b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7013697a34b5$;

DO $bootstrap_do_459870693571$
BEGIN
  EXECUTE $bootstrap_sql_459870693571$-- ============================================================
-- NOTIFIKASI IN-APP
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id),
  user_id uuid REFERENCES auth.users(id),
  type text NOT NULL DEFAULT 'info'
    CHECK (type IN ('info','warning','error','success')),
  category text NOT NULL DEFAULT 'system',
  title text NOT NULL,
  message text NOT NULL,
  link text,
  is_read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_459870693571$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_459870693571$;

DO $bootstrap_do_9bba148af952$
BEGIN
  EXECUTE $bootstrap_sql_9bba148af952$-- ============================================================
-- AKSES USER PER OUTLET (granular)
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_user_outlet_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  pos_user_id uuid REFERENCES pos_users(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  role text NOT NULL DEFAULT 'kasir'
    CHECK (role IN ('owner','manager','kasir','staff_gudang','purchasing','finance','auditor')),
  is_active boolean DEFAULT true,
  granted_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(pos_user_id, outlet_id)
)$bootstrap_sql_9bba148af952$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9bba148af952$;

DO $bootstrap_do_41a5c144425a$
BEGIN
  EXECUTE $bootstrap_sql_41a5c144425a$-- ============================================================
-- RLS POLICIES
-- ============================================================

ALTER TABLE pos_stock_transfers ENABLE ROW LEVEL SECURITY$bootstrap_sql_41a5c144425a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_41a5c144425a$;

DO $bootstrap_do_a963250cac44$
BEGIN
  EXECUTE $bootstrap_sql_a963250cac44$ALTER TABLE pos_stock_transfer_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_a963250cac44$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a963250cac44$;

DO $bootstrap_do_bbbd831fbd93$
BEGIN
  EXECUTE $bootstrap_sql_bbbd831fbd93$ALTER TABLE pos_audit_logs ENABLE ROW LEVEL SECURITY$bootstrap_sql_bbbd831fbd93$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bbbd831fbd93$;

DO $bootstrap_do_bbd6293fbe99$
BEGIN
  EXECUTE $bootstrap_sql_bbd6293fbe99$ALTER TABLE pos_notifications ENABLE ROW LEVEL SECURITY$bootstrap_sql_bbd6293fbe99$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bbd6293fbe99$;

DO $bootstrap_do_d18ca7203b95$
BEGIN
  EXECUTE $bootstrap_sql_d18ca7203b95$ALTER TABLE pos_user_outlet_access ENABLE ROW LEVEL SECURITY$bootstrap_sql_d18ca7203b95$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d18ca7203b95$;

DO $bootstrap_do_f7a5800f054d$
BEGIN
  EXECUTE $bootstrap_sql_f7a5800f054d$-- Stock Transfers
DROP POLICY IF EXISTS "tenant_owner_manage_transfers" ON pos_stock_transfers$bootstrap_sql_f7a5800f054d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f7a5800f054d$;

DO $bootstrap_do_ee605cb79168$
BEGIN
  EXECUTE $bootstrap_sql_ee605cb79168$CREATE POLICY "tenant_owner_manage_transfers" ON pos_stock_transfers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_ee605cb79168$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ee605cb79168$;

DO $bootstrap_do_162710d20b5b$
BEGIN
  EXECUTE $bootstrap_sql_162710d20b5b$DROP POLICY IF EXISTS "tenant_users_select_transfers" ON pos_stock_transfers$bootstrap_sql_162710d20b5b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_162710d20b5b$;

DO $bootstrap_do_a24823a453ca$
BEGIN
  EXECUTE $bootstrap_sql_a24823a453ca$CREATE POLICY "tenant_users_select_transfers" ON pos_stock_transfers FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_a24823a453ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a24823a453ca$;

DO $bootstrap_do_14f695310638$
BEGIN
  EXECUTE $bootstrap_sql_14f695310638$DROP POLICY IF EXISTS "tenant_users_create_transfers" ON pos_stock_transfers$bootstrap_sql_14f695310638$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14f695310638$;

DO $bootstrap_do_88255a638b09$
BEGIN
  EXECUTE $bootstrap_sql_88255a638b09$CREATE POLICY "tenant_users_create_transfers" ON pos_stock_transfers FOR INSERT WITH CHECK (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_88255a638b09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_88255a638b09$;

DO $bootstrap_do_fdae8251a47c$
BEGIN
  EXECUTE $bootstrap_sql_fdae8251a47c$DROP POLICY IF EXISTS "tenant_owner_manage_transfer_items" ON pos_stock_transfer_items$bootstrap_sql_fdae8251a47c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fdae8251a47c$;

DO $bootstrap_do_2ca4627c0b7b$
BEGIN
  EXECUTE $bootstrap_sql_2ca4627c0b7b$CREATE POLICY "tenant_owner_manage_transfer_items" ON pos_stock_transfer_items FOR ALL USING (
  transfer_id IN (
    SELECT id FROM pos_stock_transfers
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
)$bootstrap_sql_2ca4627c0b7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ca4627c0b7b$;

DO $bootstrap_do_34ffa25d6693$
BEGIN
  EXECUTE $bootstrap_sql_34ffa25d6693$DROP POLICY IF EXISTS "tenant_users_select_transfer_items" ON pos_stock_transfer_items$bootstrap_sql_34ffa25d6693$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_34ffa25d6693$;

DO $bootstrap_do_85127758ecb0$
BEGIN
  EXECUTE $bootstrap_sql_85127758ecb0$CREATE POLICY "tenant_users_select_transfer_items" ON pos_stock_transfer_items FOR SELECT USING (
  transfer_id IN (
    SELECT id FROM pos_stock_transfers
    WHERE tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
  )
)$bootstrap_sql_85127758ecb0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_85127758ecb0$;

DO $bootstrap_do_eba87ab5520d$
BEGIN
  EXECUTE $bootstrap_sql_eba87ab5520d$-- Audit Logs (read-only untuk semua, insert untuk semua)
DROP POLICY IF EXISTS "tenant_owner_read_audit" ON pos_audit_logs$bootstrap_sql_eba87ab5520d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eba87ab5520d$;

DO $bootstrap_do_aa2d7f0691ab$
BEGIN
  EXECUTE $bootstrap_sql_aa2d7f0691ab$CREATE POLICY "tenant_owner_read_audit" ON pos_audit_logs FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_aa2d7f0691ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa2d7f0691ab$;

DO $bootstrap_do_8cc975bf9e00$
BEGIN
  EXECUTE $bootstrap_sql_8cc975bf9e00$DROP POLICY IF EXISTS "tenant_users_read_audit" ON pos_audit_logs$bootstrap_sql_8cc975bf9e00$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8cc975bf9e00$;

DO $bootstrap_do_fb20b747a429$
BEGIN
  EXECUTE $bootstrap_sql_fb20b747a429$CREATE POLICY "tenant_users_read_audit" ON pos_audit_logs FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_fb20b747a429$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb20b747a429$;

DO $bootstrap_do_cec4b934db1b$
BEGIN
  EXECUTE $bootstrap_sql_cec4b934db1b$DROP POLICY IF EXISTS "tenant_users_write_audit" ON pos_audit_logs$bootstrap_sql_cec4b934db1b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cec4b934db1b$;

DO $bootstrap_do_debd617ed0d0$
BEGIN
  EXECUTE $bootstrap_sql_debd617ed0d0$CREATE POLICY "tenant_users_write_audit" ON pos_audit_logs FOR INSERT WITH CHECK (
  tenant_id IN (
    SELECT id FROM pos_tenants WHERE user_id = auth.uid()
    UNION
    SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true
  )
)$bootstrap_sql_debd617ed0d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_debd617ed0d0$;

DO $bootstrap_do_51f3454d9d71$
BEGIN
  EXECUTE $bootstrap_sql_51f3454d9d71$-- Notifications
DROP POLICY IF EXISTS "tenant_owner_manage_notif" ON pos_notifications$bootstrap_sql_51f3454d9d71$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51f3454d9d71$;

DO $bootstrap_do_c72f7299669a$
BEGIN
  EXECUTE $bootstrap_sql_c72f7299669a$CREATE POLICY "tenant_owner_manage_notif" ON pos_notifications FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_c72f7299669a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c72f7299669a$;

DO $bootstrap_do_5f591ef5d241$
BEGIN
  EXECUTE $bootstrap_sql_5f591ef5d241$DROP POLICY IF EXISTS "user_own_notif" ON pos_notifications$bootstrap_sql_5f591ef5d241$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5f591ef5d241$;

DO $bootstrap_do_0003af32cf9e$
BEGIN
  EXECUTE $bootstrap_sql_0003af32cf9e$CREATE POLICY "user_own_notif" ON pos_notifications FOR ALL USING (
  user_id = auth.uid()
)$bootstrap_sql_0003af32cf9e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0003af32cf9e$;

DO $bootstrap_do_15642ea18616$
BEGIN
  EXECUTE $bootstrap_sql_15642ea18616$-- User Outlet Access
DROP POLICY IF EXISTS "tenant_owner_manage_access" ON pos_user_outlet_access$bootstrap_sql_15642ea18616$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_15642ea18616$;

DO $bootstrap_do_208b36a36e9e$
BEGIN
  EXECUTE $bootstrap_sql_208b36a36e9e$CREATE POLICY "tenant_owner_manage_access" ON pos_user_outlet_access FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_208b36a36e9e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_208b36a36e9e$;

DO $bootstrap_do_322d0323f28c$
BEGIN
  EXECUTE $bootstrap_sql_322d0323f28c$DROP POLICY IF EXISTS "tenant_users_read_access" ON pos_user_outlet_access$bootstrap_sql_322d0323f28c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_322d0323f28c$;

DO $bootstrap_do_ae2610afc39a$
BEGIN
  EXECUTE $bootstrap_sql_ae2610afc39a$CREATE POLICY "tenant_users_read_access" ON pos_user_outlet_access FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_ae2610afc39a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae2610afc39a$;

DO $bootstrap_do_7a9aabdae10a$
BEGIN
  EXECUTE $bootstrap_sql_7a9aabdae10a$-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_pos_transfers_tenant ON pos_stock_transfers(tenant_id, created_at DESC)$bootstrap_sql_7a9aabdae10a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7a9aabdae10a$;

DO $bootstrap_do_cf9c08696fef$
BEGIN
  EXECUTE $bootstrap_sql_cf9c08696fef$CREATE INDEX IF NOT EXISTS idx_pos_transfers_from ON pos_stock_transfers(from_outlet_id)$bootstrap_sql_cf9c08696fef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf9c08696fef$;

DO $bootstrap_do_a897bb3fcbbf$
BEGIN
  EXECUTE $bootstrap_sql_a897bb3fcbbf$CREATE INDEX IF NOT EXISTS idx_pos_transfers_to ON pos_stock_transfers(to_outlet_id)$bootstrap_sql_a897bb3fcbbf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a897bb3fcbbf$;

DO $bootstrap_do_89438c9aafb9$
BEGIN
  EXECUTE $bootstrap_sql_89438c9aafb9$CREATE INDEX IF NOT EXISTS idx_pos_transfers_status ON pos_stock_transfers(status)$bootstrap_sql_89438c9aafb9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_89438c9aafb9$;

DO $bootstrap_do_7835b4121155$
BEGIN
  EXECUTE $bootstrap_sql_7835b4121155$CREATE INDEX IF NOT EXISTS idx_pos_transfer_items ON pos_stock_transfer_items(transfer_id)$bootstrap_sql_7835b4121155$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7835b4121155$;

DO $bootstrap_do_02697acf5561$
BEGIN
  EXECUTE $bootstrap_sql_02697acf5561$CREATE INDEX IF NOT EXISTS idx_pos_audit_tenant ON pos_audit_logs(tenant_id, created_at DESC)$bootstrap_sql_02697acf5561$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_02697acf5561$;

DO $bootstrap_do_783fad30bf5c$
BEGIN
  EXECUTE $bootstrap_sql_783fad30bf5c$CREATE INDEX IF NOT EXISTS idx_pos_audit_user ON pos_audit_logs(user_id)$bootstrap_sql_783fad30bf5c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_783fad30bf5c$;

DO $bootstrap_do_9a5d91576e57$
BEGIN
  EXECUTE $bootstrap_sql_9a5d91576e57$CREATE INDEX IF NOT EXISTS idx_pos_audit_module ON pos_audit_logs(module)$bootstrap_sql_9a5d91576e57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9a5d91576e57$;

DO $bootstrap_do_922605ca4238$
BEGIN
  EXECUTE $bootstrap_sql_922605ca4238$CREATE INDEX IF NOT EXISTS idx_pos_notif_user ON pos_notifications(user_id, is_read)$bootstrap_sql_922605ca4238$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_922605ca4238$;

DO $bootstrap_do_b2801e5dda81$
BEGIN
  EXECUTE $bootstrap_sql_b2801e5dda81$CREATE INDEX IF NOT EXISTS idx_pos_notif_tenant ON pos_notifications(tenant_id, created_at DESC)$bootstrap_sql_b2801e5dda81$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b2801e5dda81$;

DO $bootstrap_do_6fc9da02f44d$
BEGIN
  EXECUTE $bootstrap_sql_6fc9da02f44d$CREATE INDEX IF NOT EXISTS idx_pos_outlet_access ON pos_user_outlet_access(pos_user_id)$bootstrap_sql_6fc9da02f44d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6fc9da02f44d$;

DO $bootstrap_do_7142e4f0f57c$
BEGIN
  EXECUTE $bootstrap_sql_7142e4f0f57c$CREATE INDEX IF NOT EXISTS idx_pos_outlet_access_outlet ON pos_user_outlet_access(outlet_id)$bootstrap_sql_7142e4f0f57c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7142e4f0f57c$;

DO $bootstrap_do_7c2f6a5bde6f$
BEGIN
  EXECUTE $bootstrap_sql_7c2f6a5bde6f$
