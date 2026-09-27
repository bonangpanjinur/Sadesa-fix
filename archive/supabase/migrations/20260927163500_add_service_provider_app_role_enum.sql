-- Repair deployments where role exclusivity was applied before the
-- service-provider role enum extension. Keep this migration safe to rerun.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'service_provider';
