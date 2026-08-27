-- P4-04: Bootstrap API keys and add the hashed key value used for server validation.
-- The AdminApiKeysPage manages this table, so new projects must receive the
-- table before the compatibility ALTER below is executed.

CREATE TABLE IF NOT EXISTS public.api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_prefix TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  key_value TEXT UNIQUE,
  permissions TEXT[] NOT NULL DEFAULT ARRAY['read:products']::TEXT[],
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  request_count BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ
);

ALTER TABLE public.api_keys
  ADD COLUMN IF NOT EXISTS key_value TEXT;

CREATE INDEX IF NOT EXISTS idx_api_keys_key_value
  ON public.api_keys (key_value)
  WHERE key_value IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_api_keys_user_id
  ON public.api_keys (user_id);

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view all API keys" ON public.api_keys;
CREATE POLICY "Admins can view all API keys"
  ON public.api_keys FOR SELECT
  TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can create API keys" ON public.api_keys;
CREATE POLICY "Admins can create API keys"
  ON public.api_keys FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can update API keys" ON public.api_keys;
CREATE POLICY "Admins can update API keys"
  ON public.api_keys FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can delete API keys" ON public.api_keys;
CREATE POLICY "Admins can delete API keys"
  ON public.api_keys FOR DELETE
  TO authenticated
  USING (public.is_admin());
