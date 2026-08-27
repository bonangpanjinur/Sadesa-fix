-- ========================================
-- 7. STORAGE BUCKET FOR PRODUCT IMAGES
-- ========================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for product images (safe to retry)
DROP POLICY IF EXISTS "Public view product images bucket" ON storage.objects;
DROP POLICY IF EXISTS "Auth users upload product images" ON storage.objects;
DROP POLICY IF EXISTS "Auth users update product images" ON storage.objects;
DROP POLICY IF EXISTS "Auth users delete product images" ON storage.objects;

DROP POLICY IF EXISTS "Public view product images bucket" ON storage.objects;
CREATE POLICY "Public view product images bucket" ON storage.objects
  FOR SELECT USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Auth users upload product images" ON storage.objects;
CREATE POLICY "Auth users upload product images" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'product-images' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Auth users update product images" ON storage.objects;
CREATE POLICY "Auth users update product images" ON storage.objects
  FOR UPDATE USING (bucket_id = 'product-images' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Auth users delete product images" ON storage.objects;
CREATE POLICY "Auth users delete product images" ON storage.objects
  FOR DELETE USING (bucket_id = 'product-images' AND auth.uid() IS NOT NULL);

-- ========================================
-- 8. ENABLE REALTIME FOR COURIER TRACKING
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'couriers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.couriers;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;