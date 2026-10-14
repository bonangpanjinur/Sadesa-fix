CREATE TABLE IF NOT EXISTS public.pos_price_books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  customer_segment text NOT NULL DEFAULT 'retail' CHECK (customer_segment IN ('retail','wholesale','reseller','member','outlet')),
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  priority integer NOT NULL DEFAULT 0,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_d368ad88f3fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d368ad88f3fe$;

DO $bootstrap_do_dc1ca72a44ee$
BEGIN
  EXECUTE $bootstrap_sql_dc1ca72a44ee$CREATE TABLE IF NOT EXISTS public.pos_price_book_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  price_book_id uuid NOT NULL REFERENCES public.pos_price_books(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE CASCADE,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE CASCADE,
  price numeric(15,2) NOT NULL CHECK (price >= 0),
  UNIQUE(price_book_id, product_id, variant_id)
)$bootstrap_sql_dc1ca72a44ee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc1ca72a44ee$;

DO $bootstrap_do_17bc6e4e85fa$
BEGIN
  EXECUTE $bootstrap_sql_17bc6e4e85fa$ALTER TABLE public.pos_price_books ADD COLUMN IF NOT EXISTS priority integer NOT NULL DEFAULT 0$bootstrap_sql_17bc6e4e85fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17bc6e4e85fa$;

DO $bootstrap_do_ae7d31849a7f$
BEGIN
  EXECUTE $bootstrap_sql_ae7d31849a7f$CREATE INDEX IF NOT EXISTS idx_pos_price_books_active ON public.pos_price_books(tenant_id, is_active, starts_at, ends_at, priority DESC)$bootstrap_sql_ae7d31849a7f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae7d31849a7f$;

DO $bootstrap_do_da8b2530d667$
BEGIN
  EXECUTE $bootstrap_sql_da8b2530d667$CREATE TABLE IF NOT EXISTS public.pos_loyalty_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  rule_type text NOT NULL CHECK (rule_type IN ('earn','redeem','tier','expiry','category_bonus')),
  category_id uuid REFERENCES public.pos_categories(id) ON DELETE SET NULL,
  min_spend numeric(15,2) NOT NULL DEFAULT 0 CHECK (min_spend >= 0),
  points_per_currency numeric(12,4) NOT NULL DEFAULT 0 CHECK (points_per_currency >= 0),
  points_value numeric(15,2) NOT NULL DEFAULT 0 CHECK (points_value >= 0),
  tier_name text,
  expires_after_days integer CHECK (expires_after_days IS NULL OR expires_after_days > 0),
  is_active boolean NOT NULL DEFAULT true,
  priority integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_da8b2530d667$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_da8b2530d667$;

DO $bootstrap_do_0dd2abb26b60$
BEGIN
  EXECUTE $bootstrap_sql_0dd2abb26b60$CREATE INDEX IF NOT EXISTS idx_pos_loyalty_rules_active ON public.pos_loyalty_rules(tenant_id, rule_type, is_active, priority DESC)$bootstrap_sql_0dd2abb26b60$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0dd2abb26b60$;

DO $bootstrap_do_12b586fa3550$
BEGIN
  EXECUTE $bootstrap_sql_12b586fa3550$CREATE TABLE IF NOT EXISTS public.pos_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  entity_type text NOT NULL CHECK (entity_type IN ('products','stock','customers','suppliers')),
  status text NOT NULL DEFAULT 'preview' CHECK (status IN ('preview','validated','committed','rolled_back','failed')),
  source_filename text,
  row_count integer NOT NULL DEFAULT 0,
  valid_count integer NOT NULL DEFAULT 0,
  invalid_count integer NOT NULL DEFAULT 0,
  preview_rows jsonb NOT NULL DEFAULT '[]'::jsonb,
  validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  rollback_token text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  rolled_back_at timestamptz
)$bootstrap_sql_12b586fa3550$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_12b586fa3550$;

DO $bootstrap_do_d4ac185e533b$
BEGIN
  EXECUTE $bootstrap_sql_d4ac185e533b$CREATE INDEX IF NOT EXISTS idx_pos_import_jobs_tenant ON public.pos_import_jobs(tenant_id, entity_type, status, created_at DESC)$bootstrap_sql_d4ac185e533b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d4ac185e533b$;

DO $bootstrap_do_005ab2ee2a9f$
BEGIN
  EXECUTE $bootstrap_sql_005ab2ee2a9f$ALTER TABLE public.pos_price_books ENABLE ROW LEVEL SECURITY$bootstrap_sql_005ab2ee2a9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_005ab2ee2a9f$;

DO $bootstrap_do_2b6c6153f1da$
BEGIN
  EXECUTE $bootstrap_sql_2b6c6153f1da$ALTER TABLE public.pos_price_book_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_2b6c6153f1da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b6c6153f1da$;

DO $bootstrap_do_c9edd8b84f2d$
BEGIN
  EXECUTE $bootstrap_sql_c9edd8b84f2d$ALTER TABLE public.pos_loyalty_rules ENABLE ROW LEVEL SECURITY$bootstrap_sql_c9edd8b84f2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c9edd8b84f2d$;

DO $bootstrap_do_70585350d298$
BEGIN
  EXECUTE $bootstrap_sql_70585350d298$ALTER TABLE public.pos_import_jobs ENABLE ROW LEVEL SECURITY$bootstrap_sql_70585350d298$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70585350d298$;

DO $bootstrap_do_cdfd10b7999c$
BEGIN
  EXECUTE $bootstrap_sql_cdfd10b7999c$DROP POLICY IF EXISTS "POS users view price books" ON public.pos_price_books$bootstrap_sql_cdfd10b7999c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cdfd10b7999c$;

DO $bootstrap_do_358cdb087b1f$
BEGIN
  EXECUTE $bootstrap_sql_358cdb087b1f$CREATE POLICY "POS users view price books" ON public.pos_price_books FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_358cdb087b1f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_358cdb087b1f$;

DO $bootstrap_do_49534d67db83$
BEGIN
  EXECUTE $bootstrap_sql_49534d67db83$DROP POLICY IF EXISTS "Tenant owners manage price books" ON public.pos_price_books$bootstrap_sql_49534d67db83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49534d67db83$;

DO $bootstrap_do_ad75e043b4c2$
BEGIN
  EXECUTE $bootstrap_sql_ad75e043b4c2$CREATE POLICY "Tenant owners manage price books" ON public.pos_price_books FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_ad75e043b4c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad75e043b4c2$;

DO $bootstrap_do_7389a4929df2$
BEGIN
  EXECUTE $bootstrap_sql_7389a4929df2$DROP POLICY IF EXISTS "POS users view price book items" ON public.pos_price_book_items$bootstrap_sql_7389a4929df2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7389a4929df2$;

DO $bootstrap_do_f4b03993a73a$
BEGIN
  EXECUTE $bootstrap_sql_f4b03993a73a$CREATE POLICY "POS users view price book items" ON public.pos_price_book_items FOR SELECT TO authenticated USING (price_book_id IN (SELECT id FROM public.pos_price_books WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)))$bootstrap_sql_f4b03993a73a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4b03993a73a$;

DO $bootstrap_do_51791f626b18$
BEGIN
  EXECUTE $bootstrap_sql_51791f626b18$DROP POLICY IF EXISTS "Tenant owners manage price book items" ON public.pos_price_book_items$bootstrap_sql_51791f626b18$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51791f626b18$;

DO $bootstrap_do_64a7578a1dd6$
BEGIN
  EXECUTE $bootstrap_sql_64a7578a1dd6$CREATE POLICY "Tenant owners manage price book items" ON public.pos_price_book_items FOR ALL TO authenticated USING (price_book_id IN (SELECT id FROM public.pos_price_books WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))) WITH CHECK (price_book_id IN (SELECT id FROM public.pos_price_books WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())))$bootstrap_sql_64a7578a1dd6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_64a7578a1dd6$;

DO $bootstrap_do_97262f833e27$
BEGIN
  EXECUTE $bootstrap_sql_97262f833e27$DROP POLICY IF EXISTS "POS users view loyalty rules" ON public.pos_loyalty_rules$bootstrap_sql_97262f833e27$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_97262f833e27$;

DO $bootstrap_do_efd4dd8b35b5$
BEGIN
  EXECUTE $bootstrap_sql_efd4dd8b35b5$CREATE POLICY "POS users view loyalty rules" ON public.pos_loyalty_rules FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_efd4dd8b35b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_efd4dd8b35b5$;

DO $bootstrap_do_6686cf36c49f$
BEGIN
  EXECUTE $bootstrap_sql_6686cf36c49f$DROP POLICY IF EXISTS "Tenant owners manage loyalty rules" ON public.pos_loyalty_rules$bootstrap_sql_6686cf36c49f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6686cf36c49f$;

DO $bootstrap_do_9ad89924d4c2$
BEGIN
  EXECUTE $bootstrap_sql_9ad89924d4c2$CREATE POLICY "Tenant owners manage loyalty rules" ON public.pos_loyalty_rules FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_9ad89924d4c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ad89924d4c2$;

DO $bootstrap_do_b3be625302a6$
BEGIN
  EXECUTE $bootstrap_sql_b3be625302a6$DROP POLICY IF EXISTS "Users view own imports" ON public.pos_import_jobs$bootstrap_sql_b3be625302a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b3be625302a6$;

DO $bootstrap_do_fd23ab78285c$
BEGIN
  EXECUTE $bootstrap_sql_fd23ab78285c$CREATE POLICY "Users view own imports" ON public.pos_import_jobs FOR SELECT TO authenticated USING (created_by = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_fd23ab78285c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd23ab78285c$;

DO $bootstrap_do_7fda119bd7f8$
BEGIN
  EXECUTE $bootstrap_sql_7fda119bd7f8$DROP POLICY IF EXISTS "Users create scoped imports" ON public.pos_import_jobs$bootstrap_sql_7fda119bd7f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7fda119bd7f8$;

DO $bootstrap_do_689b5fdfdb45$
BEGIN
  EXECUTE $bootstrap_sql_689b5fdfdb45$CREATE POLICY "Users create scoped imports" ON public.pos_import_jobs FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_689b5fdfdb45$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_689b5fdfdb45$;

DO $bootstrap_do_dd854180b2fc$
BEGIN
  EXECUTE $bootstrap_sql_dd854180b2fc$CREATE OR REPLACE FUNCTION public.get_effective_pos_price(p_tenant_id uuid, p_outlet_id uuid, p_product_id uuid, p_variant_id uuid, p_segment text DEFAULT 'retail')
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT i.price FROM public.pos_price_book_items i JOIN public.pos_price_books b ON b.id = i.price_book_id WHERE b.tenant_id = p_tenant_id AND (b.outlet_id IS NULL OR b.outlet_id = p_outlet_id) AND b.customer_segment = p_segment AND b.is_active AND (b.starts_at IS NULL OR b.starts_at <= now()) AND (b.ends_at IS NULL OR b.ends_at >= now()) AND i.product_id = p_product_id AND i.variant_id IS NOT DISTINCT FROM p_variant_id ORDER BY (b.outlet_id IS NOT NULL) DESC, b.priority DESC NULLS LAST LIMIT 1), (SELECT price FROM public.pos_products WHERE id = p_product_id AND tenant_id = p_tenant_id));
$$$bootstrap_sql_dd854180b2fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dd854180b2fc$;

DO $bootstrap_do_f58ed4c548e3$
BEGIN
  EXECUTE $bootstrap_sql_f58ed4c548e3$REVOKE ALL ON FUNCTION public.get_effective_pos_price(uuid, uuid, uuid, uuid, text) FROM PUBLIC, anon$bootstrap_sql_f58ed4c548e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f58ed4c548e3$;

DO $bootstrap_do_ad0f47156fc9$
BEGIN
  EXECUTE $bootstrap_sql_ad0f47156fc9$GRANT EXECUTE ON FUNCTION public.get_effective_pos_price(uuid, uuid, uuid, uuid, text) TO authenticated$bootstrap_sql_ad0f47156fc9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad0f47156fc9$;

DO $bootstrap_do_29812a8ff991$
BEGIN
  EXECUTE $bootstrap_sql_29812a8ff991$
