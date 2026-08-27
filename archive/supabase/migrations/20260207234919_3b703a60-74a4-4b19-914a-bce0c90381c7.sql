
-- Create quota_usage_logs table for tracking per-order quota usage
CREATE TABLE IF NOT EXISTS public.quota_usage_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  subscription_id UUID REFERENCES public.merchant_subscriptions(id) ON DELETE SET NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  order_total NUMERIC NOT NULL DEFAULT 0,
  credits_used INTEGER NOT NULL DEFAULT 1,
  remaining_quota INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.quota_usage_logs ENABLE ROW LEVEL SECURITY;

-- Policies are recreated safely when a bootstrap is retried.
DROP POLICY IF EXISTS "Admin can view all quota logs" ON public.quota_usage_logs;
CREATE POLICY "Admin can view all quota logs" ON public.quota_usage_logs
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Merchant can view own quota logs" ON public.quota_usage_logs;
CREATE POLICY "Merchant can view own quota logs" ON public.quota_usage_logs
  FOR SELECT TO authenticated
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "System can insert quota logs" ON public.quota_usage_logs;
CREATE POLICY "System can insert quota logs" ON public.quota_usage_logs
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_merchant ON public.quota_usage_logs(merchant_id);
CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_order ON public.quota_usage_logs(order_id);
CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_created ON public.quota_usage_logs(created_at DESC);

-- Enable realtime only when the table is not already a member.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'quota_usage_logs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.quota_usage_logs;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;
