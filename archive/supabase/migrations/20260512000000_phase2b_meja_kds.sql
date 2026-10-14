-- Phase 2B: Manajemen Meja & Kitchen Display System

-- Tabel Meja Restoran
CREATE TABLE IF NOT EXISTS pos_tables (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE,
  name text NOT NULL,
  section text DEFAULT 'Utama',
  capacity int DEFAULT 4,
  status text DEFAULT 'available' CHECK (status IN ('available','occupied','reserved','cleaning')),
  notes text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_d404e550d39d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d404e550d39d$;

DO $bootstrap_do_4963727a3155$
BEGIN
  EXECUTE $bootstrap_sql_4963727a3155$-- Tabel Pesanan per Meja (antrian dapur)
CREATE TABLE IF NOT EXISTS pos_table_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE,
  table_id uuid REFERENCES pos_tables(id) ON DELETE SET NULL,
  table_name text,
  order_number text NOT NULL,
  status text DEFAULT 'pending' CHECK (status IN ('pending','cooking','ready','served','paid','cancelled')),
  items jsonb NOT NULL DEFAULT '[]',
  notes text,
  customer_name text,
  cashier_name text,
  sale_id uuid REFERENCES pos_sales(id) ON DELETE SET NULL,
  priority int DEFAULT 0,
  cooking_started_at timestamptz,
  ready_at timestamptz,
  served_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_4963727a3155$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4963727a3155$;

DO $bootstrap_do_9bf20a18db78$
BEGIN
  EXECUTE $bootstrap_sql_9bf20a18db78$-- RLS
ALTER TABLE pos_tables ENABLE ROW LEVEL SECURITY$bootstrap_sql_9bf20a18db78$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9bf20a18db78$;

DO $bootstrap_do_7b46305d25ec$
BEGIN
  EXECUTE $bootstrap_sql_7b46305d25ec$ALTER TABLE pos_table_orders ENABLE ROW LEVEL SECURITY$bootstrap_sql_7b46305d25ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b46305d25ec$;

DO $bootstrap_do_f65bf9d836ce$
BEGIN
  EXECUTE $bootstrap_sql_f65bf9d836ce$DROP POLICY IF EXISTS "tenant_tables" ON pos_tables$bootstrap_sql_f65bf9d836ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f65bf9d836ce$;

DO $bootstrap_do_c846f9e7fca3$
BEGIN
  EXECUTE $bootstrap_sql_c846f9e7fca3$CREATE POLICY "tenant_tables" ON pos_tables
  FOR ALL USING (tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_c846f9e7fca3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c846f9e7fca3$;

DO $bootstrap_do_318878970468$
BEGIN
  EXECUTE $bootstrap_sql_318878970468$DROP POLICY IF EXISTS "tenant_table_orders" ON pos_table_orders$bootstrap_sql_318878970468$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_318878970468$;

DO $bootstrap_do_b28f23900e8b$
BEGIN
  EXECUTE $bootstrap_sql_b28f23900e8b$CREATE POLICY "tenant_table_orders" ON pos_table_orders
  FOR ALL USING (tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_b28f23900e8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b28f23900e8b$;

DO $bootstrap_do_51a717572c1a$
BEGIN
  EXECUTE $bootstrap_sql_51a717572c1a$-- Indexes
CREATE INDEX IF NOT EXISTS idx_pos_tables_tenant ON pos_tables(tenant_id)$bootstrap_sql_51a717572c1a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51a717572c1a$;

DO $bootstrap_do_d6d8af991bab$
BEGIN
  EXECUTE $bootstrap_sql_d6d8af991bab$CREATE INDEX IF NOT EXISTS idx_pos_tables_outlet ON pos_tables(outlet_id)$bootstrap_sql_d6d8af991bab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6d8af991bab$;

DO $bootstrap_do_90ff785416e2$
BEGIN
  EXECUTE $bootstrap_sql_90ff785416e2$CREATE INDEX IF NOT EXISTS idx_pos_table_orders_tenant ON pos_table_orders(tenant_id)$bootstrap_sql_90ff785416e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90ff785416e2$;

DO $bootstrap_do_79f2854bd526$
BEGIN
  EXECUTE $bootstrap_sql_79f2854bd526$CREATE INDEX IF NOT EXISTS idx_pos_table_orders_table ON pos_table_orders(table_id)$bootstrap_sql_79f2854bd526$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_79f2854bd526$;

DO $bootstrap_do_3afcec53ca85$
BEGIN
  EXECUTE $bootstrap_sql_3afcec53ca85$CREATE INDEX IF NOT EXISTS idx_pos_table_orders_status ON pos_table_orders(status)$bootstrap_sql_3afcec53ca85$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3afcec53ca85$;

DO $bootstrap_do_e8f1a9ad1c6c$
BEGIN
  EXECUTE $bootstrap_sql_e8f1a9ad1c6c$-- Enable realtime for KDS
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'pos_table_orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pos_table_orders;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_e8f1a9ad1c6c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8f1a9ad1c6c$;

DO $bootstrap_do_1d11acf6a05f$
BEGIN
  EXECUTE $bootstrap_sql_1d11acf6a05f$DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'pos_tables'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pos_tables;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_1d11acf6a05f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1d11acf6a05f$;

DO $bootstrap_do_8ef9eaa9331c$
BEGIN
  EXECUTE $bootstrap_sql_8ef9eaa9331c$
