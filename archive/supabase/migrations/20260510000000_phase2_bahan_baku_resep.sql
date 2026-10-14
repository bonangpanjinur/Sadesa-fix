-- Phase 2: Bahan Baku (Raw Materials) & Resep/BOM

-- Tabel Bahan Baku
CREATE TABLE IF NOT EXISTS pos_raw_materials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE,
  name text NOT NULL,
  unit text NOT NULL DEFAULT 'gram',
  current_stock numeric(15,3) DEFAULT 0,
  min_stock numeric(15,3) DEFAULT 0,
  cost_per_unit numeric(15,4) DEFAULT 0,
  description text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_881cc6fe60cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_881cc6fe60cd$;

DO $bootstrap_do_72379c46bad2$
BEGIN
  EXECUTE $bootstrap_sql_72379c46bad2$-- Tabel Resep / Bill of Materials (BOM)
CREATE TABLE IF NOT EXISTS pos_recipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id) ON DELETE CASCADE NOT NULL,
  raw_material_id uuid REFERENCES pos_raw_materials(id) ON DELETE CASCADE NOT NULL,
  qty_needed numeric(15,4) NOT NULL DEFAULT 0,
  unit text NOT NULL,
  notes text,
  created_at timestamptz DEFAULT now(),
  UNIQUE(product_id, raw_material_id)
)$bootstrap_sql_72379c46bad2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_72379c46bad2$;

DO $bootstrap_do_16a2cc4f68b6$
BEGIN
  EXECUTE $bootstrap_sql_16a2cc4f68b6$-- Tabel Mutasi Bahan Baku
CREATE TABLE IF NOT EXISTS pos_raw_material_mutations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE,
  raw_material_id uuid REFERENCES pos_raw_materials(id) ON DELETE CASCADE NOT NULL,
  type text NOT NULL CHECK (type IN ('initial','purchase','usage','adjustment','waste','return')),
  qty numeric(15,4) NOT NULL,
  qty_before numeric(15,4) DEFAULT 0,
  qty_after numeric(15,4) DEFAULT 0,
  reference_id uuid,
  reference_type text,
  notes text,
  created_by uuid,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_16a2cc4f68b6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_16a2cc4f68b6$;

DO $bootstrap_do_1dbcfe87d537$
BEGIN
  EXECUTE $bootstrap_sql_1dbcfe87d537$-- RLS Policies
ALTER TABLE pos_raw_materials ENABLE ROW LEVEL SECURITY$bootstrap_sql_1dbcfe87d537$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1dbcfe87d537$;

DO $bootstrap_do_8efa5001f0eb$
BEGIN
  EXECUTE $bootstrap_sql_8efa5001f0eb$ALTER TABLE pos_recipes ENABLE ROW LEVEL SECURITY$bootstrap_sql_8efa5001f0eb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8efa5001f0eb$;

DO $bootstrap_do_aab48896dcde$
BEGIN
  EXECUTE $bootstrap_sql_aab48896dcde$ALTER TABLE pos_raw_material_mutations ENABLE ROW LEVEL SECURITY$bootstrap_sql_aab48896dcde$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aab48896dcde$;

DO $bootstrap_do_9e73ee09d006$
BEGIN
  EXECUTE $bootstrap_sql_9e73ee09d006$DROP POLICY IF EXISTS "tenant_raw_materials" ON pos_raw_materials$bootstrap_sql_9e73ee09d006$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e73ee09d006$;

DO $bootstrap_do_7fafa811f572$
BEGIN
  EXECUTE $bootstrap_sql_7fafa811f572$CREATE POLICY "tenant_raw_materials" ON pos_raw_materials
  FOR ALL USING (
    tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )$bootstrap_sql_7fafa811f572$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7fafa811f572$;

DO $bootstrap_do_5d2b3e2a9658$
BEGIN
  EXECUTE $bootstrap_sql_5d2b3e2a9658$DROP POLICY IF EXISTS "tenant_recipes" ON pos_recipes$bootstrap_sql_5d2b3e2a9658$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d2b3e2a9658$;

DO $bootstrap_do_df074306480c$
BEGIN
  EXECUTE $bootstrap_sql_df074306480c$CREATE POLICY "tenant_recipes" ON pos_recipes
  FOR ALL USING (
    tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )$bootstrap_sql_df074306480c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df074306480c$;

DO $bootstrap_do_6d4b228b73d3$
BEGIN
  EXECUTE $bootstrap_sql_6d4b228b73d3$DROP POLICY IF EXISTS "tenant_raw_material_mutations" ON pos_raw_material_mutations$bootstrap_sql_6d4b228b73d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d4b228b73d3$;

DO $bootstrap_do_0e9645eec862$
BEGIN
  EXECUTE $bootstrap_sql_0e9645eec862$CREATE POLICY "tenant_raw_material_mutations" ON pos_raw_material_mutations
  FOR ALL USING (
    tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )$bootstrap_sql_0e9645eec862$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e9645eec862$;

DO $bootstrap_do_b67e7ec2b944$
BEGIN
  EXECUTE $bootstrap_sql_b67e7ec2b944$-- Indexes
CREATE INDEX IF NOT EXISTS idx_raw_materials_tenant ON pos_raw_materials(tenant_id)$bootstrap_sql_b67e7ec2b944$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b67e7ec2b944$;

DO $bootstrap_do_e26f6868b081$
BEGIN
  EXECUTE $bootstrap_sql_e26f6868b081$CREATE INDEX IF NOT EXISTS idx_raw_materials_outlet ON pos_raw_materials(outlet_id)$bootstrap_sql_e26f6868b081$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e26f6868b081$;

DO $bootstrap_do_51b5cd9c7070$
BEGIN
  EXECUTE $bootstrap_sql_51b5cd9c7070$CREATE INDEX IF NOT EXISTS idx_recipes_product ON pos_recipes(product_id)$bootstrap_sql_51b5cd9c7070$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51b5cd9c7070$;

DO $bootstrap_do_e514fd4fd8d3$
BEGIN
  EXECUTE $bootstrap_sql_e514fd4fd8d3$CREATE INDEX IF NOT EXISTS idx_recipes_material ON pos_recipes(raw_material_id)$bootstrap_sql_e514fd4fd8d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e514fd4fd8d3$;

DO $bootstrap_do_de99754b0ffb$
BEGIN
  EXECUTE $bootstrap_sql_de99754b0ffb$CREATE INDEX IF NOT EXISTS idx_raw_mut_material ON pos_raw_material_mutations(raw_material_id)$bootstrap_sql_de99754b0ffb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de99754b0ffb$;

DO $bootstrap_do_9d763bdb29b6$
BEGIN
  EXECUTE $bootstrap_sql_9d763bdb29b6$CREATE INDEX IF NOT EXISTS idx_raw_mut_tenant ON pos_raw_material_mutations(tenant_id)$bootstrap_sql_9d763bdb29b6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9d763bdb29b6$;

DO $bootstrap_do_00dd27add7f9$
BEGIN
  EXECUTE $bootstrap_sql_00dd27add7f9$
