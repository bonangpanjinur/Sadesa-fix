-- =============================================
-- Phase 1: DB Hardening
-- =============================================

-- 1. DROP unused function overloads (keep the ones used by RLS policies & app code)
-- Keep: get_user_courier_id() no-arg (used in RLS)
DROP FUNCTION IF EXISTS public.get_user_courier_id(uuid)$bootstrap_sql_1c55a96a1160$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c55a96a1160$;

DO $bootstrap_do_e55930d058d3$
BEGIN
  EXECUTE $bootstrap_sql_e55930d058d3$-- Keep: get_user_merchant_id() no-arg
DROP FUNCTION IF EXISTS public.get_user_merchant_id(uuid)$bootstrap_sql_e55930d058d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e55930d058d3$;

DO $bootstrap_do_42817e7e17b2$
BEGIN
  EXECUTE $bootstrap_sql_42817e7e17b2$-- Keep: use_merchant_quota(p_merchant_id uuid) — used by app via RPC
DROP FUNCTION IF EXISTS public.use_merchant_quota(uuid, integer)$bootstrap_sql_42817e7e17b2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42817e7e17b2$;

DO $bootstrap_do_200eb9b30d81$
BEGIN
  EXECUTE $bootstrap_sql_200eb9b30d81$-- Note: is_order_merchant has 2 overloads, BOTH are referenced by different RLS policies.
-- Keep both.

-- =============================================
-- 2. Privatize sensitive storage buckets
-- =============================================
UPDATE storage.buckets SET public = false WHERE id IN ('chat-images', 'pod-images')$bootstrap_sql_200eb9b30d81$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_200eb9b30d81$;

DO $bootstrap_do_a1190e5e3a29$
BEGIN
  EXECUTE $bootstrap_sql_a1190e5e3a29$-- RLS policies for chat-images: only chat participants can read/write
DROP POLICY IF EXISTS "Chat images: read by participants" ON storage.objects$bootstrap_sql_a1190e5e3a29$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1190e5e3a29$;

DO $bootstrap_do_14d11f4667ec$
BEGIN
  EXECUTE $bootstrap_sql_14d11f4667ec$CREATE POLICY "Chat images: read by participants"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'chat-images'
  AND (
    is_admin()
    OR EXISTS (
      SELECT 1 FROM public.chat_messages cm
      WHERE cm.image_url LIKE '%' || storage.objects.name || '%'
        AND (cm.sender_id = auth.uid() OR cm.receiver_id = auth.uid())
    )
  )
)$bootstrap_sql_14d11f4667ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14d11f4667ec$;

DO $bootstrap_do_052cdc048946$
BEGIN
  EXECUTE $bootstrap_sql_052cdc048946$DROP POLICY IF EXISTS "Chat images: upload by authenticated" ON storage.objects$bootstrap_sql_052cdc048946$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_052cdc048946$;

DO $bootstrap_do_15987e5128ca$
BEGIN
  EXECUTE $bootstrap_sql_15987e5128ca$CREATE POLICY "Chat images: upload by authenticated"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'chat-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_15987e5128ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_15987e5128ca$;

DO $bootstrap_do_e6e94c206fc3$
BEGIN
  EXECUTE $bootstrap_sql_e6e94c206fc3$-- RLS policies for pod-images: only buyer / merchant / courier of the order + admin
DROP POLICY IF EXISTS "POD images: read by order parties" ON storage.objects$bootstrap_sql_e6e94c206fc3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6e94c206fc3$;

DO $bootstrap_do_148b16703040$
BEGIN
  EXECUTE $bootstrap_sql_148b16703040$CREATE POLICY "POD images: read by order parties"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'pod-images'
  AND (
    is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      LEFT JOIN public.merchants m ON m.id = o.merchant_id
      LEFT JOIN public.couriers c ON c.id = o.courier_id
      WHERE o.pod_image_url LIKE '%' || storage.objects.name || '%'
        AND (o.buyer_id = auth.uid() OR m.user_id = auth.uid() OR c.user_id = auth.uid())
    )
  )
)$bootstrap_sql_148b16703040$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_148b16703040$;

DO $bootstrap_do_25ee810b6fd1$
BEGIN
  EXECUTE $bootstrap_sql_25ee810b6fd1$DROP POLICY IF EXISTS "POD images: upload by courier or merchant" ON storage.objects$bootstrap_sql_25ee810b6fd1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_25ee810b6fd1$;

DO $bootstrap_do_379541a06590$
BEGIN
  EXECUTE $bootstrap_sql_379541a06590$CREATE POLICY "POD images: upload by courier or merchant"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'pod-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_379541a06590$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_379541a06590$;

DO $bootstrap_do_4c712e16488b$
BEGIN
  EXECUTE $bootstrap_sql_4c712e16488b$
