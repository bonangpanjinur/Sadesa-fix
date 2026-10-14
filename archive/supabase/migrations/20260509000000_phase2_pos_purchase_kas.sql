-- Phase 2: POS SaaS — Pembelian & Kas Harian
-- Purchase Orders + Cash Session Management

-- ============================================================
-- PURCHASE ORDERS (Pembelian ke Supplier)
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  supplier_id uuid REFERENCES pos_suppliers(id),
  supplier_name text NOT NULL,
  po_number text NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','sent','partial','received','cancelled')),
  order_date date NOT NULL DEFAULT CURRENT_DATE,
  expected_date date,
  received_date date,
  subtotal numeric(15,2) NOT NULL DEFAULT 0,
  discount_amount numeric(15,2) DEFAULT 0,
  tax_amount numeric(15,2) DEFAULT 0,
  total numeric(15,2) NOT NULL DEFAULT 0,
  amount_paid numeric(15,2) DEFAULT 0,
  notes text,
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_8addaf4e8b54$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8addaf4e8b54$;

DO $bootstrap_do_ab3c71473a04$
BEGIN
  EXECUTE $bootstrap_sql_ab3c71473a04$CREATE TABLE IF NOT EXISTS pos_purchase_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id uuid REFERENCES pos_purchase_orders(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id),
  variant_id uuid REFERENCES pos_product_variants(id),
  product_name text NOT NULL,
  sku text,
  unit text DEFAULT 'pcs',
  qty_ordered numeric(15,3) NOT NULL DEFAULT 0,
  qty_received numeric(15,3) DEFAULT 0,
  cost_price numeric(15,2) NOT NULL DEFAULT 0,
  discount numeric(15,2) DEFAULT 0,
  tax_amount numeric(15,2) DEFAULT 0,
  subtotal numeric(15,2) NOT NULL DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_ab3c71473a04$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ab3c71473a04$;

DO $bootstrap_do_40150c9a2045$
BEGIN
  EXECUTE $bootstrap_sql_40150c9a2045$-- Retur ke Supplier
CREATE TABLE IF NOT EXISTS pos_purchase_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  purchase_order_id uuid REFERENCES pos_purchase_orders(id),
  supplier_name text NOT NULL,
  return_number text NOT NULL,
  return_date date NOT NULL DEFAULT CURRENT_DATE,
  reason text,
  total_amount numeric(15,2) NOT NULL DEFAULT 0,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_40150c9a2045$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40150c9a2045$;

DO $bootstrap_do_c4fe287fb0a8$
BEGIN
  EXECUTE $bootstrap_sql_c4fe287fb0a8$CREATE TABLE IF NOT EXISTS pos_purchase_return_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_return_id uuid REFERENCES pos_purchase_returns(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id),
  product_name text NOT NULL,
  qty numeric(15,3) NOT NULL,
  cost_price numeric(15,2) NOT NULL,
  subtotal numeric(15,2) NOT NULL,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_c4fe287fb0a8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c4fe287fb0a8$;

DO $bootstrap_do_77e8e3687175$
BEGIN
  EXECUTE $bootstrap_sql_77e8e3687175$-- ============================================================
-- KAS HARIAN (Cash Management / Shift)
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_cash_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  cashier_id uuid REFERENCES auth.users(id),
  cashier_name text NOT NULL,
  session_number text NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','closed')),
  opening_balance numeric(15,2) NOT NULL DEFAULT 0,
  closing_balance numeric(15,2),
  expected_balance numeric(15,2),
  difference numeric(15,2),
  cash_sales_total numeric(15,2) DEFAULT 0,
  non_cash_sales_total numeric(15,2) DEFAULT 0,
  cash_in_total numeric(15,2) DEFAULT 0,
  cash_out_total numeric(15,2) DEFAULT 0,
  notes_open text,
  notes_close text,
  opened_at timestamptz DEFAULT now(),
  closed_at timestamptz,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_77e8e3687175$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77e8e3687175$;

DO $bootstrap_do_3ad39bc40b68$
BEGIN
  EXECUTE $bootstrap_sql_3ad39bc40b68$-- Mutasi kas manual (pemasukan & pengeluaran non-transaksi penjualan)
CREATE TABLE IF NOT EXISTS pos_cash_mutations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  cash_session_id uuid REFERENCES pos_cash_sessions(id),
  type text NOT NULL CHECK (type IN ('in','out')),
  category text NOT NULL DEFAULT 'other',
  amount numeric(15,2) NOT NULL DEFAULT 0,
  description text NOT NULL,
  reference text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_3ad39bc40b68$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ad39bc40b68$;

DO $bootstrap_do_d8665ed7aa55$
BEGIN
  EXECUTE $bootstrap_sql_d8665ed7aa55$-- ============================================================
-- RLS POLICIES
-- ============================================================

ALTER TABLE pos_purchase_orders ENABLE ROW LEVEL SECURITY$bootstrap_sql_d8665ed7aa55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d8665ed7aa55$;

DO $bootstrap_do_57bd8c0a8eff$
BEGIN
  EXECUTE $bootstrap_sql_57bd8c0a8eff$ALTER TABLE pos_purchase_order_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_57bd8c0a8eff$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_57bd8c0a8eff$;

DO $bootstrap_do_b142d162ffbf$
BEGIN
  EXECUTE $bootstrap_sql_b142d162ffbf$ALTER TABLE pos_purchase_returns ENABLE ROW LEVEL SECURITY$bootstrap_sql_b142d162ffbf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b142d162ffbf$;

DO $bootstrap_do_ddfc38388946$
BEGIN
  EXECUTE $bootstrap_sql_ddfc38388946$ALTER TABLE pos_purchase_return_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_ddfc38388946$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ddfc38388946$;

DO $bootstrap_do_3612b0cb417e$
BEGIN
  EXECUTE $bootstrap_sql_3612b0cb417e$ALTER TABLE pos_cash_sessions ENABLE ROW LEVEL SECURITY$bootstrap_sql_3612b0cb417e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3612b0cb417e$;

DO $bootstrap_do_e8940e4f02ea$
BEGIN
  EXECUTE $bootstrap_sql_e8940e4f02ea$ALTER TABLE pos_cash_mutations ENABLE ROW LEVEL SECURITY$bootstrap_sql_e8940e4f02ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8940e4f02ea$;

DO $bootstrap_do_ce3b21f271a3$
BEGIN
  EXECUTE $bootstrap_sql_ce3b21f271a3$-- Purchase Orders
DROP POLICY IF EXISTS "tenant_owner_manage_purchase_orders" ON pos_purchase_orders$bootstrap_sql_ce3b21f271a3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ce3b21f271a3$;

DO $bootstrap_do_03b1dc2b0f2b$
BEGIN
  EXECUTE $bootstrap_sql_03b1dc2b0f2b$CREATE POLICY "tenant_owner_manage_purchase_orders" ON pos_purchase_orders FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_03b1dc2b0f2b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_03b1dc2b0f2b$;

DO $bootstrap_do_ef358869be7d$
BEGIN
  EXECUTE $bootstrap_sql_ef358869be7d$DROP POLICY IF EXISTS "tenant_users_select_purchase_orders" ON pos_purchase_orders$bootstrap_sql_ef358869be7d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef358869be7d$;

DO $bootstrap_do_a8fe8e508a28$
BEGIN
  EXECUTE $bootstrap_sql_a8fe8e508a28$CREATE POLICY "tenant_users_select_purchase_orders" ON pos_purchase_orders FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_a8fe8e508a28$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a8fe8e508a28$;

DO $bootstrap_do_c5ec33c05f47$
BEGIN
  EXECUTE $bootstrap_sql_c5ec33c05f47$DROP POLICY IF EXISTS "tenant_owner_manage_po_items" ON pos_purchase_order_items$bootstrap_sql_c5ec33c05f47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5ec33c05f47$;

DO $bootstrap_do_912ee89c2a61$
BEGIN
  EXECUTE $bootstrap_sql_912ee89c2a61$CREATE POLICY "tenant_owner_manage_po_items" ON pos_purchase_order_items FOR ALL USING (
  purchase_order_id IN (
    SELECT id FROM pos_purchase_orders
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
)$bootstrap_sql_912ee89c2a61$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_912ee89c2a61$;

DO $bootstrap_do_fc5e90a460de$
BEGIN
  EXECUTE $bootstrap_sql_fc5e90a460de$DROP POLICY IF EXISTS "tenant_users_select_po_items" ON pos_purchase_order_items$bootstrap_sql_fc5e90a460de$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc5e90a460de$;

DO $bootstrap_do_ef4cf62ec9e9$
BEGIN
  EXECUTE $bootstrap_sql_ef4cf62ec9e9$CREATE POLICY "tenant_users_select_po_items" ON pos_purchase_order_items FOR SELECT USING (
  purchase_order_id IN (
    SELECT id FROM pos_purchase_orders
    WHERE tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
  )
)$bootstrap_sql_ef4cf62ec9e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef4cf62ec9e9$;

DO $bootstrap_do_0d5921c45a67$
BEGIN
  EXECUTE $bootstrap_sql_0d5921c45a67$-- Purchase Returns
DROP POLICY IF EXISTS "tenant_owner_manage_purchase_returns" ON pos_purchase_returns$bootstrap_sql_0d5921c45a67$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d5921c45a67$;

DO $bootstrap_do_94fa3fa5aa0d$
BEGIN
  EXECUTE $bootstrap_sql_94fa3fa5aa0d$CREATE POLICY "tenant_owner_manage_purchase_returns" ON pos_purchase_returns FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_94fa3fa5aa0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_94fa3fa5aa0d$;

DO $bootstrap_do_e529b5e5669a$
BEGIN
  EXECUTE $bootstrap_sql_e529b5e5669a$DROP POLICY IF EXISTS "tenant_owner_manage_purchase_return_items" ON pos_purchase_return_items$bootstrap_sql_e529b5e5669a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e529b5e5669a$;

DO $bootstrap_do_5e979a8e1c86$
BEGIN
  EXECUTE $bootstrap_sql_5e979a8e1c86$CREATE POLICY "tenant_owner_manage_purchase_return_items" ON pos_purchase_return_items FOR ALL USING (
  purchase_return_id IN (
    SELECT id FROM pos_purchase_returns
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
)$bootstrap_sql_5e979a8e1c86$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5e979a8e1c86$;

DO $bootstrap_do_2f1f3254c851$
BEGIN
  EXECUTE $bootstrap_sql_2f1f3254c851$-- Cash Sessions
DROP POLICY IF EXISTS "tenant_owner_manage_cash_sessions" ON pos_cash_sessions$bootstrap_sql_2f1f3254c851$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2f1f3254c851$;

DO $bootstrap_do_bdcba4591c9c$
BEGIN
  EXECUTE $bootstrap_sql_bdcba4591c9c$CREATE POLICY "tenant_owner_manage_cash_sessions" ON pos_cash_sessions FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_bdcba4591c9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bdcba4591c9c$;

DO $bootstrap_do_79d09805d0ca$
BEGIN
  EXECUTE $bootstrap_sql_79d09805d0ca$DROP POLICY IF EXISTS "tenant_users_select_cash_sessions" ON pos_cash_sessions$bootstrap_sql_79d09805d0ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_79d09805d0ca$;

DO $bootstrap_do_0da882b3833c$
BEGIN
  EXECUTE $bootstrap_sql_0da882b3833c$CREATE POLICY "tenant_users_select_cash_sessions" ON pos_cash_sessions FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_0da882b3833c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0da882b3833c$;

DO $bootstrap_do_a2dc715cb50d$
BEGIN
  EXECUTE $bootstrap_sql_a2dc715cb50d$DROP POLICY IF EXISTS "tenant_users_manage_own_sessions" ON pos_cash_sessions$bootstrap_sql_a2dc715cb50d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2dc715cb50d$;

DO $bootstrap_do_ab251d071557$
BEGIN
  EXECUTE $bootstrap_sql_ab251d071557$CREATE POLICY "tenant_users_manage_own_sessions" ON pos_cash_sessions FOR ALL USING (
  cashier_id = auth.uid()
)$bootstrap_sql_ab251d071557$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ab251d071557$;

DO $bootstrap_do_14aa704bf10e$
BEGIN
  EXECUTE $bootstrap_sql_14aa704bf10e$-- Cash Mutations
DROP POLICY IF EXISTS "tenant_owner_manage_cash_mutations" ON pos_cash_mutations$bootstrap_sql_14aa704bf10e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14aa704bf10e$;

DO $bootstrap_do_6a8de95da25a$
BEGIN
  EXECUTE $bootstrap_sql_6a8de95da25a$CREATE POLICY "tenant_owner_manage_cash_mutations" ON pos_cash_mutations FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_6a8de95da25a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a8de95da25a$;

DO $bootstrap_do_e88dde50c4af$
BEGIN
  EXECUTE $bootstrap_sql_e88dde50c4af$DROP POLICY IF EXISTS "tenant_users_select_cash_mutations" ON pos_cash_mutations$bootstrap_sql_e88dde50c4af$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e88dde50c4af$;

DO $bootstrap_do_be465fc28946$
BEGIN
  EXECUTE $bootstrap_sql_be465fc28946$CREATE POLICY "tenant_users_select_cash_mutations" ON pos_cash_mutations FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_be465fc28946$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be465fc28946$;

DO $bootstrap_do_ea0b724a1610$
BEGIN
  EXECUTE $bootstrap_sql_ea0b724a1610$DROP POLICY IF EXISTS "tenant_users_manage_own_mutations" ON pos_cash_mutations$bootstrap_sql_ea0b724a1610$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea0b724a1610$;

DO $bootstrap_do_d45c37ce0323$
BEGIN
  EXECUTE $bootstrap_sql_d45c37ce0323$CREATE POLICY "tenant_users_manage_own_mutations" ON pos_cash_mutations FOR INSERT WITH CHECK (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_d45c37ce0323$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d45c37ce0323$;

DO $bootstrap_do_cb2eef9c99bf$
BEGIN
  EXECUTE $bootstrap_sql_cb2eef9c99bf$-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_pos_purchase_orders_tenant ON pos_purchase_orders(tenant_id, created_at DESC)$bootstrap_sql_cb2eef9c99bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb2eef9c99bf$;

DO $bootstrap_do_c9541f532493$
BEGIN
  EXECUTE $bootstrap_sql_c9541f532493$CREATE INDEX IF NOT EXISTS idx_pos_purchase_orders_outlet ON pos_purchase_orders(outlet_id)$bootstrap_sql_c9541f532493$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c9541f532493$;

DO $bootstrap_do_c0f8fb24d9be$
BEGIN
  EXECUTE $bootstrap_sql_c0f8fb24d9be$CREATE INDEX IF NOT EXISTS idx_pos_purchase_orders_status ON pos_purchase_orders(status)$bootstrap_sql_c0f8fb24d9be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0f8fb24d9be$;

DO $bootstrap_do_4826152440c6$
BEGIN
  EXECUTE $bootstrap_sql_4826152440c6$CREATE INDEX IF NOT EXISTS idx_pos_purchase_orders_supplier ON pos_purchase_orders(supplier_id)$bootstrap_sql_4826152440c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4826152440c6$;

DO $bootstrap_do_16bfa843170c$
BEGIN
  EXECUTE $bootstrap_sql_16bfa843170c$CREATE INDEX IF NOT EXISTS idx_pos_po_items_po ON pos_purchase_order_items(purchase_order_id)$bootstrap_sql_16bfa843170c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_16bfa843170c$;

DO $bootstrap_do_1752a3bde98d$
BEGIN
  EXECUTE $bootstrap_sql_1752a3bde98d$CREATE INDEX IF NOT EXISTS idx_pos_cash_sessions_tenant ON pos_cash_sessions(tenant_id, opened_at DESC)$bootstrap_sql_1752a3bde98d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1752a3bde98d$;

DO $bootstrap_do_742266338907$
BEGIN
  EXECUTE $bootstrap_sql_742266338907$CREATE INDEX IF NOT EXISTS idx_pos_cash_sessions_outlet ON pos_cash_sessions(outlet_id)$bootstrap_sql_742266338907$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_742266338907$;

DO $bootstrap_do_8576fa5baf70$
BEGIN
  EXECUTE $bootstrap_sql_8576fa5baf70$CREATE INDEX IF NOT EXISTS idx_pos_cash_sessions_status ON pos_cash_sessions(status)$bootstrap_sql_8576fa5baf70$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8576fa5baf70$;

DO $bootstrap_do_7f6806cd90c1$
BEGIN
  EXECUTE $bootstrap_sql_7f6806cd90c1$CREATE INDEX IF NOT EXISTS idx_pos_cash_mutations_session ON pos_cash_mutations(cash_session_id)$bootstrap_sql_7f6806cd90c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f6806cd90c1$;

DO $bootstrap_do_4ac9a134ba87$
BEGIN
  EXECUTE $bootstrap_sql_4ac9a134ba87$CREATE INDEX IF NOT EXISTS idx_pos_cash_mutations_tenant ON pos_cash_mutations(tenant_id, created_at DESC)$bootstrap_sql_4ac9a134ba87$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4ac9a134ba87$;

DO $bootstrap_do_881cc6fe60cd$
BEGIN
  EXECUTE $bootstrap_sql_881cc6fe60cd$
