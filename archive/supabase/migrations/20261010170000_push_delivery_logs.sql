-- Durable, admin-readable push delivery attempts from direct admin sends and queued app notifications.
CREATE TABLE IF NOT EXISTS public.push_delivery_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  source text NOT NULL CHECK (source IN ('admin_test', 'admin_broadcast', 'queue')),
  notification_job_id uuid REFERENCES public.notification_delivery_jobs(id) ON DELETE SET NULL,
  push_subscription_id uuid REFERENCES public.push_subscriptions(id) ON DELETE SET NULL,
  recipient_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  title text NOT NULL CHECK (char_length(title) <= 160),
  status text NOT NULL CHECK (status IN ('sent', 'failed', 'expired')),
  provider_status_code integer,
  error_message text CHECK (error_message IS NULL OR char_length(error_message) <= 1000)
);

COMMENT ON TABLE public.push_delivery_logs IS
  'Per-subscription Web Push attempts. Sent means the push service accepted the request, not that a device displayed it.';
COMMENT ON COLUMN public.push_delivery_logs.status IS
  'sent: provider accepted; failed: request failed; expired: provider reported an invalid/expired subscription.';

CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_created_at
  ON public.push_delivery_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_status_created_at
  ON public.push_delivery_logs (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_recipient_created_at
  ON public.push_delivery_logs (recipient_user_id, created_at DESC);

ALTER TABLE public.push_delivery_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins read push delivery logs" ON public.push_delivery_logs;
CREATE POLICY "Admins read push delivery logs"
  ON public.push_delivery_logs
  FOR SELECT TO authenticated
  USING (public.is_admin());

REVOKE ALL ON TABLE public.push_delivery_logs FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.push_delivery_logs TO authenticated;
GRANT INSERT ON TABLE public.push_delivery_logs TO service_role;

DO $publish_push_delivery_logs$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'push_delivery_logs'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.push_delivery_logs;
  END IF;
END
$publish_push_delivery_logs$;
