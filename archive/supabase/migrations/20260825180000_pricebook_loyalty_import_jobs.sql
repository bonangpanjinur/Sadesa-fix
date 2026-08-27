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
);
CREATE TABLE IF NOT EXISTS public.pos_price_book_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  price_book_id uuid NOT NULL REFERENCES public.pos_price_books(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE CASCADE,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE CASCADE,
  price numeric(15,2) NOT NULL CHECK (price >= 0),
  UNIQUE(price_book_id, product_id, variant_id)
);
ALTER TABLE public.pos_price_books ADD COLUMN IF NOT EXISTS priority integer NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_pos_price_books_active ON public.pos_price_books(tenant_id, is_active, starts_at, ends_at, priority DESC);

CREATE TABLE IF NOT EXISTS public.pos_loyalty_rules (
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
);
CREATE INDEX IF NOT EXISTS idx_pos_loyalty_rules_active ON public.pos_loyalty_rules(tenant_id, rule_type, is_active, priority DESC);

CREATE TABLE IF NOT EXISTS public.pos_import_jobs (
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
);
CREATE INDEX IF NOT EXISTS idx_pos_import_jobs_tenant ON public.pos_import_jobs(tenant_id, entity_type, status, created_at DESC);

ALTER TABLE public.pos_price_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_price_book_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_loyalty_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_import_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view price books" ON public.pos_price_books;
CREATE POLICY "POS users view price books" ON public.pos_price_books FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "Tenant owners manage price books" ON public.pos_price_books;
CREATE POLICY "Tenant owners manage price books" ON public.pos_price_books FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "POS users view price book items" ON public.pos_price_book_items;
CREATE POLICY "POS users view price book items" ON public.pos_price_book_items FOR SELECT TO authenticated USING (price_book_id IN (SELECT id FROM public.pos_price_books WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));
DROP POLICY IF EXISTS "Tenant owners manage price book items" ON public.pos_price_book_items;
CREATE POLICY "Tenant owners manage price book items" ON public.pos_price_book_items FOR ALL TO authenticated USING (price_book_id IN (SELECT id FROM public.pos_price_books WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))) WITH CHECK (price_book_id IN (SELECT id FROM public.pos_price_books WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())));
DROP POLICY IF EXISTS "POS users view loyalty rules" ON public.pos_loyalty_rules;
CREATE POLICY "POS users view loyalty rules" ON public.pos_loyalty_rules FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant owners manage loyalty rules" ON public.pos_loyalty_rules;
CREATE POLICY "Tenant owners manage loyalty rules" ON public.pos_loyalty_rules FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Users view own imports" ON public.pos_import_jobs;
CREATE POLICY "Users view own imports" ON public.pos_import_jobs FOR SELECT TO authenticated USING (created_by = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Users create scoped imports" ON public.pos_import_jobs;
CREATE POLICY "Users create scoped imports" ON public.pos_import_jobs FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.get_effective_pos_price(p_tenant_id uuid, p_outlet_id uuid, p_product_id uuid, p_variant_id uuid, p_segment text DEFAULT 'retail')
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT i.price FROM public.pos_price_book_items i JOIN public.pos_price_books b ON b.id = i.price_book_id WHERE b.tenant_id = p_tenant_id AND (b.outlet_id IS NULL OR b.outlet_id = p_outlet_id) AND b.customer_segment = p_segment AND b.is_active AND (b.starts_at IS NULL OR b.starts_at <= now()) AND (b.ends_at IS NULL OR b.ends_at >= now()) AND i.product_id = p_product_id AND i.variant_id IS NOT DISTINCT FROM p_variant_id ORDER BY (b.outlet_id IS NOT NULL) DESC, b.priority DESC NULLS LAST LIMIT 1), (SELECT price FROM public.pos_products WHERE id = p_product_id AND tenant_id = p_tenant_id));
$$;
REVOKE ALL ON FUNCTION public.get_effective_pos_price(uuid, uuid, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_effective_pos_price(uuid, uuid, uuid, uuid, text) TO authenticated;
