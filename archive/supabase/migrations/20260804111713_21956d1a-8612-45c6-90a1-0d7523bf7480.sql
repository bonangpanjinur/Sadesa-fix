CREATE TABLE IF NOT EXISTS public.pos_tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  name text NOT NULL,
  store_name text,
  logo_url text,
  phone text,
  address text,
  currency text NOT NULL DEFAULT 'IDR',
  timezone text NOT NULL DEFAULT 'Asia/Jakarta',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS pos_tenants_user_id_key ON public.pos_tenants(user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_tenants TO authenticated;
GRANT ALL ON public.pos_tenants TO service_role;

ALTER TABLE public.pos_tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners manage their POS tenant" ON public.pos_tenants;
CREATE POLICY "Owners manage their POS tenant" ON public.pos_tenants
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view POS tenants" ON public.pos_tenants;
CREATE POLICY "Admins can view POS tenants" ON public.pos_tenants
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE TABLE IF NOT EXISTS public.pos_outlets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  address text,
  phone text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pos_outlets_tenant_id_idx ON public.pos_outlets(tenant_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_outlets TO authenticated;
GRANT ALL ON public.pos_outlets TO service_role;

ALTER TABLE public.pos_outlets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners manage their POS outlets" ON public.pos_outlets;
CREATE POLICY "Owners manage their POS outlets" ON public.pos_outlets
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can view POS outlets" ON public.pos_outlets;
CREATE POLICY "Admins can view POS outlets" ON public.pos_outlets
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP TRIGGER IF EXISTS update_pos_tenants_updated_at ON public.pos_tenants;
CREATE TRIGGER update_pos_tenants_updated_at
  BEFORE UPDATE ON public.pos_tenants
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_pos_outlets_updated_at ON public.pos_outlets;
CREATE TRIGGER update_pos_outlets_updated_at
  BEFORE UPDATE ON public.pos_outlets
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();