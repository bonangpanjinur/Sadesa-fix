-- Add blocking fields to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_blocked boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS blocked_at timestamp with time zone,
ADD COLUMN IF NOT EXISTS blocked_by uuid,
ADD COLUMN IF NOT EXISTS block_reason text$bootstrap_sql_0352f166d51c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0352f166d51c$;

DO $bootstrap_do_837319092622$
BEGIN
  EXECUTE $bootstrap_sql_837319092622$-- Create refund_requests table
CREATE TABLE public.refund_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    buyer_id uuid NOT NULL,
    amount integer NOT NULL,
    reason text NOT NULL,
    status text NOT NULL DEFAULT 'PENDING',
    admin_notes text,
    processed_by uuid,
    processed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
)$bootstrap_sql_837319092622$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_837319092622$;

DO $bootstrap_do_63e1c7f6b882$
BEGIN
  EXECUTE $bootstrap_sql_63e1c7f6b882$-- Create admin_audit_logs table
CREATE TABLE public.admin_audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id uuid NOT NULL,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    old_value jsonb,
    new_value jsonb,
    ip_address text,
    user_agent text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
)$bootstrap_sql_63e1c7f6b882$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63e1c7f6b882$;

DO $bootstrap_do_d6692b26f43a$
BEGIN
  EXECUTE $bootstrap_sql_d6692b26f43a$-- Enable RLS
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_d6692b26f43a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6692b26f43a$;

DO $bootstrap_do_0050edf3f574$
BEGIN
  EXECUTE $bootstrap_sql_0050edf3f574$ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY$bootstrap_sql_0050edf3f574$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0050edf3f574$;

DO $bootstrap_do_2dcdac1c17e2$
BEGIN
  EXECUTE $bootstrap_sql_2dcdac1c17e2$-- RLS for refund_requests
DROP POLICY IF EXISTS "Admins can manage refunds" ON public.refund_requests$bootstrap_sql_2dcdac1c17e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2dcdac1c17e2$;

DO $bootstrap_do_ec1c85a90898$
BEGIN
  EXECUTE $bootstrap_sql_ec1c85a90898$CREATE POLICY "Admins can manage refunds" ON public.refund_requests
FOR ALL USING (is_admin())$bootstrap_sql_ec1c85a90898$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec1c85a90898$;

DO $bootstrap_do_9984a8ca90ce$
BEGIN
  EXECUTE $bootstrap_sql_9984a8ca90ce$DROP POLICY IF EXISTS "Buyers can view own refunds" ON public.refund_requests$bootstrap_sql_9984a8ca90ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9984a8ca90ce$;

DO $bootstrap_do_63ad4cace0d1$
BEGIN
  EXECUTE $bootstrap_sql_63ad4cace0d1$CREATE POLICY "Buyers can view own refunds" ON public.refund_requests
FOR SELECT USING (buyer_id = auth.uid())$bootstrap_sql_63ad4cace0d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63ad4cace0d1$;

DO $bootstrap_do_17e45e426862$
BEGIN
  EXECUTE $bootstrap_sql_17e45e426862$DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests$bootstrap_sql_17e45e426862$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17e45e426862$;

DO $bootstrap_do_5fbd043a9843$
BEGIN
  EXECUTE $bootstrap_sql_5fbd043a9843$CREATE POLICY "Buyers can create refund requests" ON public.refund_requests
FOR INSERT WITH CHECK (buyer_id = auth.uid() AND status = 'PENDING')$bootstrap_sql_5fbd043a9843$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5fbd043a9843$;

DO $bootstrap_do_7b66fc9a1623$
BEGIN
  EXECUTE $bootstrap_sql_7b66fc9a1623$-- RLS for admin_audit_logs (admin only)
DROP POLICY IF EXISTS "Admins can view logs" ON public.admin_audit_logs$bootstrap_sql_7b66fc9a1623$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b66fc9a1623$;

DO $bootstrap_do_5fe5dc916a80$
BEGIN
  EXECUTE $bootstrap_sql_5fe5dc916a80$CREATE POLICY "Admins can view logs" ON public.admin_audit_logs
FOR SELECT USING (is_admin())$bootstrap_sql_5fe5dc916a80$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5fe5dc916a80$;

DO $bootstrap_do_36e82dd3663d$
BEGIN
  EXECUTE $bootstrap_sql_36e82dd3663d$DROP POLICY IF EXISTS "Admins can insert logs" ON public.admin_audit_logs$bootstrap_sql_36e82dd3663d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_36e82dd3663d$;

DO $bootstrap_do_534424f3106f$
BEGIN
  EXECUTE $bootstrap_sql_534424f3106f$CREATE POLICY "Admins can insert logs" ON public.admin_audit_logs
FOR INSERT WITH CHECK (is_admin())$bootstrap_sql_534424f3106f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_534424f3106f$;

DO $bootstrap_do_aa514d04d7da$
BEGIN
  EXECUTE $bootstrap_sql_aa514d04d7da$-- Update profiles RLS to allow admin to update block status
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles$bootstrap_sql_aa514d04d7da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa514d04d7da$;

DO $bootstrap_do_fab582eb71c2$
BEGIN
  EXECUTE $bootstrap_sql_fab582eb71c2$CREATE POLICY "Users can update own profile" ON public.profiles
FOR UPDATE USING (auth.uid() = user_id AND is_blocked = false)$bootstrap_sql_fab582eb71c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fab582eb71c2$;

DO $bootstrap_do_c46265abf41b$
BEGIN
  EXECUTE $bootstrap_sql_c46265abf41b$DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles$bootstrap_sql_c46265abf41b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c46265abf41b$;

DO $bootstrap_do_1a626bda96b7$
BEGIN
  EXECUTE $bootstrap_sql_1a626bda96b7$CREATE POLICY "Admins can update any profile" ON public.profiles
FOR ALL USING (is_admin())$bootstrap_sql_1a626bda96b7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1a626bda96b7$;

DO $bootstrap_do_46b244dec234$
BEGIN
  EXECUTE $bootstrap_sql_46b244dec234$-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_refund_requests_status ON public.refund_requests(status)$bootstrap_sql_46b244dec234$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46b244dec234$;

DO $bootstrap_do_1d849bd01064$
BEGIN
  EXECUTE $bootstrap_sql_1d849bd01064$CREATE INDEX IF NOT EXISTS idx_refund_requests_buyer ON public.refund_requests(buyer_id)$bootstrap_sql_1d849bd01064$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1d849bd01064$;

DO $bootstrap_do_946660ae528e$
BEGIN
  EXECUTE $bootstrap_sql_946660ae528e$CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin ON public.admin_audit_logs(admin_id)$bootstrap_sql_946660ae528e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_946660ae528e$;

DO $bootstrap_do_d45ba2c9fb31$
BEGIN
  EXECUTE $bootstrap_sql_d45ba2c9fb31$CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_entity ON public.admin_audit_logs(entity_type, entity_id)$bootstrap_sql_d45ba2c9fb31$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d45ba2c9fb31$;

DO $bootstrap_do_328187ed951c$
BEGIN
  EXECUTE $bootstrap_sql_328187ed951c$CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created ON public.admin_audit_logs(created_at DESC)$bootstrap_sql_328187ed951c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_328187ed951c$;

DO $bootstrap_do_7ba07d7563e2$
BEGIN
  EXECUTE $bootstrap_sql_7ba07d7563e2$-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_refund_requests_updated_at ON public.refund_requests$bootstrap_sql_7ba07d7563e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ba07d7563e2$;

DO $bootstrap_do_82f338772a6b$
BEGIN
  EXECUTE $bootstrap_sql_82f338772a6b$CREATE TRIGGER update_refund_requests_updated_at
BEFORE UPDATE ON public.refund_requests
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_82f338772a6b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_82f338772a6b$;

DO $bootstrap_do_873fd34cdaca$
BEGIN
  EXECUTE $bootstrap_sql_873fd34cdaca$
