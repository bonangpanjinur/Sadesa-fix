-- Dynamic expedition provider master.
CREATE TABLE IF NOT EXISTS public.expedition_providers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  logo_url text,
  tracking_website text NOT NULL CHECK (tracking_website ~ '^https?://'),
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT expedition_providers_name_unique UNIQUE (name)
);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS expedition_provider_id uuid REFERENCES public.expedition_providers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS expedition_name_snapshot text,
  ADD COLUMN IF NOT EXISTS expedition_logo_url_snapshot text,
  ADD COLUMN IF NOT EXISTS expedition_tracking_url_snapshot text;

CREATE INDEX IF NOT EXISTS idx_expedition_providers_active_order
  ON public.expedition_providers(is_active, sort_order, name);
CREATE INDEX IF NOT EXISTS idx_orders_expedition_provider
  ON public.orders(expedition_provider_id);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('expedition-logos', 'expedition-logos', true, 2097152, ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml'])
ON CONFLICT (id) DO UPDATE SET public = true, file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml'];

ALTER TABLE public.expedition_providers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view active expedition providers" ON public.expedition_providers;
CREATE POLICY "Anyone can view active expedition providers" ON public.expedition_providers
  FOR SELECT USING (is_active = true OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage expedition providers" ON public.expedition_providers;
CREATE POLICY "Admins manage expedition providers" ON public.expedition_providers
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Public can view expedition logos" ON storage.objects;
CREATE POLICY "Public can view expedition logos" ON storage.objects
  FOR SELECT USING (bucket_id = 'expedition-logos');
DROP POLICY IF EXISTS "Admins upload expedition logos" ON storage.objects;
CREATE POLICY "Admins upload expedition logos" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'expedition-logos' AND public.is_admin());
DROP POLICY IF EXISTS "Admins update expedition logos" ON storage.objects;
CREATE POLICY "Admins update expedition logos" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'expedition-logos' AND public.is_admin())
  WITH CHECK (bucket_id = 'expedition-logos' AND public.is_admin());
DROP POLICY IF EXISTS "Admins delete expedition logos" ON storage.objects;
CREATE POLICY "Admins delete expedition logos" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'expedition-logos' AND public.is_admin());

GRANT SELECT ON public.expedition_providers TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.expedition_providers TO authenticated;
GRANT ALL ON public.expedition_providers TO service_role;
NOTIFY pgrst, 'reload schema';
