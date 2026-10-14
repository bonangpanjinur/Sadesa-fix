-- Add auto_complete_at column to track when an order should be auto-completed
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS auto_complete_at TIMESTAMPTZ$bootstrap_sql_5a8a15504bbd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a8a15504bbd$;

DO $bootstrap_do_a22990f9393a$
BEGIN
  EXECUTE $bootstrap_sql_a22990f9393a$-- When courier marks as DELIVERED, set auto_complete_at to 24 hours later
CREATE OR REPLACE FUNCTION public.set_auto_complete_deadline()
RETURNS TRIGGER AS $$
BEGIN
  -- When status changes to DELIVERED, set auto-complete deadline to 24 hours later
  IF NEW.status = 'DELIVERED' AND (OLD.status IS NULL OR OLD.status <> 'DELIVERED') THEN
    NEW.auto_complete_at := NOW() + INTERVAL '24 hours';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_a22990f9393a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a22990f9393a$;

DO $bootstrap_do_147dfd719c73$
BEGIN
  EXECUTE $bootstrap_sql_147dfd719c73$-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS trigger_set_auto_complete_deadline ON public.orders$bootstrap_sql_147dfd719c73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_147dfd719c73$;

DO $bootstrap_do_3464a1b30e60$
BEGIN
  EXECUTE $bootstrap_sql_3464a1b30e60$CREATE TRIGGER trigger_set_auto_complete_deadline
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_auto_complete_deadline()$bootstrap_sql_3464a1b30e60$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3464a1b30e60$;

DO $bootstrap_do_ef56d9655d68$
BEGIN
  EXECUTE $bootstrap_sql_ef56d9655d68$-- Function to auto-complete orders past their deadline
-- This can be called periodically via pg_cron or an edge function
CREATE OR REPLACE FUNCTION public.auto_complete_delivered_orders()
RETURNS INTEGER AS $$
DECLARE
  completed_count INTEGER;
BEGIN
  UPDATE public.orders
  SET status = 'DONE',
      updated_at = NOW()
  WHERE status = 'DELIVERED'
    AND auto_complete_at IS NOT NULL
    AND auto_complete_at <= NOW();

  GET DIAGNOSTICS completed_count = ROW_COUNT;
  RETURN completed_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_ef56d9655d68$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef56d9655d68$;

DO $bootstrap_do_dba8dcf60a8d$
BEGIN
  EXECUTE $bootstrap_sql_dba8dcf60a8d$-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog$bootstrap_sql_dba8dcf60a8d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dba8dcf60a8d$;

DO $bootstrap_do_1716db062c5e$
BEGIN
  EXECUTE $bootstrap_sql_1716db062c5e$-- Schedule the auto-complete function to run every hour
SELECT cron.schedule(
  'auto-complete-delivered-orders',
  '0 * * * *',  -- Every hour
  $$SELECT public.auto_complete_delivered_orders()$$
)$bootstrap_sql_1716db062c5e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1716db062c5e$;

DO $bootstrap_do_df53a14b9b7b$
BEGIN
  EXECUTE $bootstrap_sql_df53a14b9b7b$
