-- Broadcast links and push delivery support.
DO $bootstrap_do_16_broadcast_links$
BEGIN
  EXECUTE $bootstrap_sql_16_broadcast_links$ALTER TABLE public.broadcast_notifications ADD COLUMN IF NOT EXISTS link TEXT$bootstrap_sql_16_broadcast_links$;
  EXECUTE $bootstrap_sql_16_broadcast_links$COMMENT ON COLUMN public.broadcast_notifications.link IS 'Optional internal or http(s) destination opened when a broadcast is clicked'$bootstrap_sql_16_broadcast_links$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_16_broadcast_links$;
