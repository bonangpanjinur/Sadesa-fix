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
);
CREATE TABLE IF NOT EXISTS public.crm_segment_members (
  segment_id uuid NOT NULL REFERENCES public.crm_customer_segments(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(segment_id, customer_id)
);
CREATE TABLE IF NOT EXISTS public.crm_campaigns (
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
);
CREATE TABLE IF NOT EXISTS public.crm_campaign_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.crm_campaigns(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent','delivered','failed','opted_out')),
  provider_message_id text,
  error_message text,
  sent_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(campaign_id, customer_id)
);
CREATE TABLE IF NOT EXISTS public.crm_abandoned_carts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  cart_snapshot jsonb NOT NULL,
  total_amount numeric(15,2) NOT NULL DEFAULT 0,
  last_activity_at timestamptz NOT NULL DEFAULT now(),
  reminder_sent_at timestamptz,
  recovered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_crm_campaigns_status ON public.crm_campaigns(tenant_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_crm_abandoned_carts_reminder ON public.crm_abandoned_carts(tenant_id, last_activity_at, reminder_sent_at) WHERE recovered_at IS NULL;

ALTER TABLE public.crm_customer_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_segment_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_campaign_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_abandoned_carts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tenant owners manage CRM segments" ON public.crm_customer_segments;
CREATE POLICY "Tenant owners manage CRM segments" ON public.crm_customer_segments FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant users view CRM segments" ON public.crm_customer_segments;
CREATE POLICY "Tenant users view CRM segments" ON public.crm_customer_segments FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Tenant owners manage CRM campaigns" ON public.crm_campaigns;
CREATE POLICY "Tenant owners manage CRM campaigns" ON public.crm_campaigns FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant users view CRM campaigns" ON public.crm_campaigns;
CREATE POLICY "Tenant users view CRM campaigns" ON public.crm_campaigns FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Customer views own campaign delivery" ON public.crm_campaign_deliveries;
CREATE POLICY "Customer views own campaign delivery" ON public.crm_campaign_deliveries FOR SELECT TO authenticated USING (customer_id = auth.uid() OR campaign_id IN (SELECT id FROM public.crm_campaigns WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())));
DROP POLICY IF EXISTS "Tenant users manage abandoned carts" ON public.crm_abandoned_carts;
CREATE POLICY "Tenant users manage abandoned carts" ON public.crm_abandoned_carts FOR ALL TO authenticated USING (customer_id = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (customer_id = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Customers view own segment membership" ON public.crm_segment_members;
CREATE POLICY "Customers view own segment membership" ON public.crm_segment_members FOR SELECT TO authenticated USING (customer_id = auth.uid() OR segment_id IN (SELECT id FROM public.crm_customer_segments WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())));
