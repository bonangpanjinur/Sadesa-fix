CREATE TABLE IF NOT EXISTS public.crm_customer_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  criteria jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_dynamic boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_29812a8ff991$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_29812a8ff991$;

DO $bootstrap_do_59abd2e3f46e$
BEGIN
  EXECUTE $bootstrap_sql_59abd2e3f46e$CREATE TABLE IF NOT EXISTS public.crm_segment_members (
  segment_id uuid NOT NULL REFERENCES public.crm_customer_segments(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(segment_id, customer_id)
)$bootstrap_sql_59abd2e3f46e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59abd2e3f46e$;

DO $bootstrap_do_b17c1eff9b36$
BEGIN
  EXECUTE $bootstrap_sql_b17c1eff9b36$CREATE TABLE IF NOT EXISTS public.crm_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  segment_id uuid REFERENCES public.crm_customer_segments(id) ON DELETE SET NULL,
  name text NOT NULL,
  channel text NOT NULL CHECK (channel IN ('in_app','email','whatsapp','push')),
  template text NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','scheduled','sending','sent','cancelled','failed')),
  scheduled_at timestamptz,
  sent_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_b17c1eff9b36$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b17c1eff9b36$;

DO $bootstrap_do_6846f28cfb4c$
BEGIN
  EXECUTE $bootstrap_sql_6846f28cfb4c$CREATE TABLE IF NOT EXISTS public.crm_campaign_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.crm_campaigns(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent','delivered','failed','opted_out')),
  provider_message_id text,
  error_message text,
  sent_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(campaign_id, customer_id)
)$bootstrap_sql_6846f28cfb4c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6846f28cfb4c$;

DO $bootstrap_do_7ef3bd026640$
BEGIN
  EXECUTE $bootstrap_sql_7ef3bd026640$CREATE TABLE IF NOT EXISTS public.crm_abandoned_carts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  cart_snapshot jsonb NOT NULL,
  total_amount numeric(15,2) NOT NULL DEFAULT 0,
  last_activity_at timestamptz NOT NULL DEFAULT now(),
  reminder_sent_at timestamptz,
  recovered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_7ef3bd026640$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ef3bd026640$;

DO $bootstrap_do_181844cb2f7c$
BEGIN
  EXECUTE $bootstrap_sql_181844cb2f7c$CREATE INDEX IF NOT EXISTS idx_crm_campaigns_status ON public.crm_campaigns(tenant_id, status, scheduled_at)$bootstrap_sql_181844cb2f7c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_181844cb2f7c$;

DO $bootstrap_do_7a2f42921ac5$
BEGIN
  EXECUTE $bootstrap_sql_7a2f42921ac5$CREATE INDEX IF NOT EXISTS idx_crm_abandoned_carts_reminder ON public.crm_abandoned_carts(tenant_id, last_activity_at, reminder_sent_at) WHERE recovered_at IS NULL$bootstrap_sql_7a2f42921ac5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7a2f42921ac5$;

DO $bootstrap_do_227bcd81c88f$
BEGIN
  EXECUTE $bootstrap_sql_227bcd81c88f$ALTER TABLE public.crm_customer_segments ENABLE ROW LEVEL SECURITY$bootstrap_sql_227bcd81c88f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_227bcd81c88f$;

DO $bootstrap_do_083b621637a5$
BEGIN
  EXECUTE $bootstrap_sql_083b621637a5$ALTER TABLE public.crm_segment_members ENABLE ROW LEVEL SECURITY$bootstrap_sql_083b621637a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_083b621637a5$;

DO $bootstrap_do_18a14fe4053b$
BEGIN
  EXECUTE $bootstrap_sql_18a14fe4053b$ALTER TABLE public.crm_campaigns ENABLE ROW LEVEL SECURITY$bootstrap_sql_18a14fe4053b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_18a14fe4053b$;

DO $bootstrap_do_323709207583$
BEGIN
  EXECUTE $bootstrap_sql_323709207583$ALTER TABLE public.crm_campaign_deliveries ENABLE ROW LEVEL SECURITY$bootstrap_sql_323709207583$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_323709207583$;

DO $bootstrap_do_a467d1ee9f57$
BEGIN
  EXECUTE $bootstrap_sql_a467d1ee9f57$ALTER TABLE public.crm_abandoned_carts ENABLE ROW LEVEL SECURITY$bootstrap_sql_a467d1ee9f57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a467d1ee9f57$;

DO $bootstrap_do_8ee186ed1dc2$
BEGIN
  EXECUTE $bootstrap_sql_8ee186ed1dc2$DROP POLICY IF EXISTS "Tenant owners manage CRM segments" ON public.crm_customer_segments$bootstrap_sql_8ee186ed1dc2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ee186ed1dc2$;

DO $bootstrap_do_8798b68168be$
BEGIN
  EXECUTE $bootstrap_sql_8798b68168be$CREATE POLICY "Tenant owners manage CRM segments" ON public.crm_customer_segments FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_8798b68168be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8798b68168be$;

DO $bootstrap_do_180743bfc683$
BEGIN
  EXECUTE $bootstrap_sql_180743bfc683$DROP POLICY IF EXISTS "Tenant users view CRM segments" ON public.crm_customer_segments$bootstrap_sql_180743bfc683$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_180743bfc683$;

DO $bootstrap_do_ad1598718dc6$
BEGIN
  EXECUTE $bootstrap_sql_ad1598718dc6$CREATE POLICY "Tenant users view CRM segments" ON public.crm_customer_segments FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true))$bootstrap_sql_ad1598718dc6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad1598718dc6$;

DO $bootstrap_do_c0ab655cbe3b$
BEGIN
  EXECUTE $bootstrap_sql_c0ab655cbe3b$DROP POLICY IF EXISTS "Tenant owners manage CRM campaigns" ON public.crm_campaigns$bootstrap_sql_c0ab655cbe3b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0ab655cbe3b$;

DO $bootstrap_do_5818b8509317$
BEGIN
  EXECUTE $bootstrap_sql_5818b8509317$CREATE POLICY "Tenant owners manage CRM campaigns" ON public.crm_campaigns FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_5818b8509317$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5818b8509317$;

DO $bootstrap_do_fe38fee689ba$
BEGIN
  EXECUTE $bootstrap_sql_fe38fee689ba$DROP POLICY IF EXISTS "Tenant users view CRM campaigns" ON public.crm_campaigns$bootstrap_sql_fe38fee689ba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fe38fee689ba$;

DO $bootstrap_do_8e6873a31deb$
BEGIN
  EXECUTE $bootstrap_sql_8e6873a31deb$CREATE POLICY "Tenant users view CRM campaigns" ON public.crm_campaigns FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true))$bootstrap_sql_8e6873a31deb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e6873a31deb$;

DO $bootstrap_do_95c24f79a13f$
BEGIN
  EXECUTE $bootstrap_sql_95c24f79a13f$DROP POLICY IF EXISTS "Customer views own campaign delivery" ON public.crm_campaign_deliveries$bootstrap_sql_95c24f79a13f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95c24f79a13f$;

DO $bootstrap_do_0aa8c06cff90$
BEGIN
  EXECUTE $bootstrap_sql_0aa8c06cff90$CREATE POLICY "Customer views own campaign delivery" ON public.crm_campaign_deliveries FOR SELECT TO authenticated USING (customer_id = auth.uid() OR campaign_id IN (SELECT id FROM public.crm_campaigns WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())))$bootstrap_sql_0aa8c06cff90$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0aa8c06cff90$;

DO $bootstrap_do_958e24089933$
BEGIN
  EXECUTE $bootstrap_sql_958e24089933$DROP POLICY IF EXISTS "Tenant users manage abandoned carts" ON public.crm_abandoned_carts$bootstrap_sql_958e24089933$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_958e24089933$;

DO $bootstrap_do_9da045ba401a$
BEGIN
  EXECUTE $bootstrap_sql_9da045ba401a$CREATE POLICY "Tenant users manage abandoned carts" ON public.crm_abandoned_carts FOR ALL TO authenticated USING (customer_id = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (customer_id = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_9da045ba401a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9da045ba401a$;

DO $bootstrap_do_eb44acd7fb3b$
BEGIN
  EXECUTE $bootstrap_sql_eb44acd7fb3b$DROP POLICY IF EXISTS "Customers view own segment membership" ON public.crm_segment_members$bootstrap_sql_eb44acd7fb3b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eb44acd7fb3b$;

DO $bootstrap_do_515193df35fc$
BEGIN
  EXECUTE $bootstrap_sql_515193df35fc$CREATE POLICY "Customers view own segment membership" ON public.crm_segment_members FOR SELECT TO authenticated USING (customer_id = auth.uid() OR segment_id IN (SELECT id FROM public.crm_customer_segments WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())))$bootstrap_sql_515193df35fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_515193df35fc$;

DO $bootstrap_do_cfbf52bdbea3$
BEGIN
  EXECUTE $bootstrap_sql_cfbf52bdbea3$
