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
)$bootstrap_sql_36332517d7bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_36332517d7bf$;

DO $bootstrap_do_1c5e76ee079c$
BEGIN
  EXECUTE $bootstrap_sql_1c5e76ee079c$CREATE UNIQUE INDEX IF NOT EXISTS pos_tenants_user_id_key ON public.pos_tenants(user_id)$bootstrap_sql_1c5e76ee079c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c5e76ee079c$;

DO $bootstrap_do_967161e2f34c$
BEGIN
  EXECUTE $bootstrap_sql_967161e2f34c$GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_tenants TO authenticated$bootstrap_sql_967161e2f34c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_967161e2f34c$;

DO $bootstrap_do_e95648f88b76$
BEGIN
  EXECUTE $bootstrap_sql_e95648f88b76$GRANT ALL ON public.pos_tenants TO service_role$bootstrap_sql_e95648f88b76$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e95648f88b76$;

DO $bootstrap_do_7bc9e34a0965$
BEGIN
  EXECUTE $bootstrap_sql_7bc9e34a0965$ALTER TABLE public.pos_tenants ENABLE ROW LEVEL SECURITY$bootstrap_sql_7bc9e34a0965$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7bc9e34a0965$;

DO $bootstrap_do_9f8caf9a1f83$
BEGIN
  EXECUTE $bootstrap_sql_9f8caf9a1f83$DROP POLICY IF EXISTS "Owners manage their POS tenant" ON public.pos_tenants$bootstrap_sql_9f8caf9a1f83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f8caf9a1f83$;

DO $bootstrap_do_90d49c9fa409$
BEGIN
  EXECUTE $bootstrap_sql_90d49c9fa409$CREATE POLICY "Owners manage their POS tenant" ON public.pos_tenants
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_90d49c9fa409$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90d49c9fa409$;

DO $bootstrap_do_ec2567fbaf97$
BEGIN
  EXECUTE $bootstrap_sql_ec2567fbaf97$DROP POLICY IF EXISTS "Admins can view POS tenants" ON public.pos_tenants$bootstrap_sql_ec2567fbaf97$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec2567fbaf97$;

DO $bootstrap_do_72d78925d517$
BEGIN
  EXECUTE $bootstrap_sql_72d78925d517$CREATE POLICY "Admins can view POS tenants" ON public.pos_tenants
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_72d78925d517$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_72d78925d517$;

DO $bootstrap_do_f6447df5376a$
BEGIN
  EXECUTE $bootstrap_sql_f6447df5376a$CREATE TABLE IF NOT EXISTS public.pos_outlets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  address text,
  phone text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_f6447df5376a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f6447df5376a$;

DO $bootstrap_do_67c0aa10e9bb$
BEGIN
  EXECUTE $bootstrap_sql_67c0aa10e9bb$CREATE INDEX IF NOT EXISTS pos_outlets_tenant_id_idx ON public.pos_outlets(tenant_id)$bootstrap_sql_67c0aa10e9bb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_67c0aa10e9bb$;

DO $bootstrap_do_114e78305b55$
BEGIN
  EXECUTE $bootstrap_sql_114e78305b55$GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_outlets TO authenticated$bootstrap_sql_114e78305b55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_114e78305b55$;

DO $bootstrap_do_248dd0fc4c3c$
BEGIN
  EXECUTE $bootstrap_sql_248dd0fc4c3c$GRANT ALL ON public.pos_outlets TO service_role$bootstrap_sql_248dd0fc4c3c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_248dd0fc4c3c$;

DO $bootstrap_do_514b980de8be$
BEGIN
  EXECUTE $bootstrap_sql_514b980de8be$ALTER TABLE public.pos_outlets ENABLE ROW LEVEL SECURITY$bootstrap_sql_514b980de8be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_514b980de8be$;

DO $bootstrap_do_2743ea1f8dfb$
BEGIN
  EXECUTE $bootstrap_sql_2743ea1f8dfb$DROP POLICY IF EXISTS "Owners manage their POS outlets" ON public.pos_outlets$bootstrap_sql_2743ea1f8dfb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2743ea1f8dfb$;

DO $bootstrap_do_0c843ebef9d1$
BEGIN
  EXECUTE $bootstrap_sql_0c843ebef9d1$CREATE POLICY "Owners manage their POS outlets" ON public.pos_outlets
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()))$bootstrap_sql_0c843ebef9d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c843ebef9d1$;

DO $bootstrap_do_e17e39cc67b7$
BEGIN
  EXECUTE $bootstrap_sql_e17e39cc67b7$DROP POLICY IF EXISTS "Admins can view POS outlets" ON public.pos_outlets$bootstrap_sql_e17e39cc67b7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e17e39cc67b7$;

DO $bootstrap_do_717d6c475060$
BEGIN
  EXECUTE $bootstrap_sql_717d6c475060$CREATE POLICY "Admins can view POS outlets" ON public.pos_outlets
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_717d6c475060$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_717d6c475060$;

DO $bootstrap_do_b5568c422801$
BEGIN
  EXECUTE $bootstrap_sql_b5568c422801$DROP TRIGGER IF EXISTS update_pos_tenants_updated_at ON public.pos_tenants$bootstrap_sql_b5568c422801$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b5568c422801$;

DO $bootstrap_do_22d68367ea40$
BEGIN
  EXECUTE $bootstrap_sql_22d68367ea40$CREATE TRIGGER update_pos_tenants_updated_at
  BEFORE UPDATE ON public.pos_tenants
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_22d68367ea40$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22d68367ea40$;

DO $bootstrap_do_17a850c4ed39$
BEGIN
  EXECUTE $bootstrap_sql_17a850c4ed39$DROP TRIGGER IF EXISTS update_pos_outlets_updated_at ON public.pos_outlets$bootstrap_sql_17a850c4ed39$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17a850c4ed39$;

DO $bootstrap_do_1ee76426a4ef$
BEGIN
  EXECUTE $bootstrap_sql_1ee76426a4ef$CREATE TRIGGER update_pos_outlets_updated_at
  BEFORE UPDATE ON public.pos_outlets
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_1ee76426a4ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ee76426a4ef$;

DO $bootstrap_do_259000afe5fe$
BEGIN
  EXECUTE $bootstrap_sql_259000afe5fe$
