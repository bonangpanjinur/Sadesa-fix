-- DesaMart canonical bootstrap bundle; incremental merchant hardening.
-- Source range: 20260925230000_merchant_review_refund_input_hardening.sql

DO $bootstrap_do_merchant_review_refund_hardening$
BEGIN
  EXECUTE $bootstrap_sql_merchant_review_refund_hardening$-- Hardening for merchant-facing marketplace review and refund intake.
-- This migration is additive and safe to replay through the canonical pipeline.

CREATE UNIQUE INDEX IF NOT EXISTS reviews_one_per_order_product_buyer
  ON public.reviews(order_id, product_id, buyer_id);

CREATE OR REPLACE FUNCTION public.submit_order_reviews(p_order_id uuid, p_reviews jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_review jsonb;
  v_product_id uuid;
  v_rating integer;
  v_count integer := 0;
  v_image_urls text[];
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND OR upper(v_order.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
    RAISE EXCEPTION 'Only completed orders can be reviewed' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_reviews) <> 'array' OR jsonb_array_length(p_reviews) = 0 OR jsonb_array_length(p_reviews) > 50 THEN
    RAISE EXCEPTION 'Review payload must contain between 1 and 50 items' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(DISTINCT value->>'product_id') FROM jsonb_array_elements(p_reviews)) <> jsonb_array_length(p_reviews) THEN
    RAISE EXCEPTION 'A product may only be reviewed once per order' USING ERRCODE = '23505';
  END IF;

  FOR v_review IN SELECT value FROM jsonb_array_elements(p_reviews) LOOP
    v_product_id := NULLIF(v_review->>'product_id', '')::uuid;
    v_rating := (v_review->>'rating')::integer;
    v_image_urls := COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_review->'image_urls', '[]'::jsonb))), '{}');
    IF v_product_id IS NULL OR v_rating IS NULL OR v_rating NOT BETWEEN 1 AND 5 THEN
      RAISE EXCEPTION 'Invalid review payload' USING ERRCODE = '22023';
    END IF;
    IF cardinality(v_image_urls) > 5 OR EXISTS (SELECT 1 FROM unnest(v_image_urls) url WHERE length(url) > 1000 OR url ~* '^(javascript|data):') THEN
      RAISE EXCEPTION 'Review evidence is invalid' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.order_items WHERE order_id = p_order_id AND product_id = v_product_id) THEN
      RAISE EXCEPTION 'Product is not part of this order' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.reviews(product_id, order_id, buyer_id, merchant_id, rating, comment, image_urls)
    VALUES (v_product_id, p_order_id, auth.uid(), v_order.merchant_id, v_rating,
      NULLIF(left(COALESCE(v_review->>'comment', ''), 2000), ''), v_image_urls);
    v_count := v_count + 1;
  END LOOP;
  UPDATE public.orders SET has_review = true, updated_at = now() WHERE id = p_order_id;
  UPDATE public.merchants m SET
    rating_avg = COALESCE((SELECT round(avg(r.rating)::numeric, 2) FROM public.reviews r WHERE r.merchant_id = m.id AND r.is_visible = true), 0),
    rating_count = (SELECT count(*) FROM public.reviews r WHERE r.merchant_id = m.id AND r.is_visible = true)
  WHERE m.id = v_order.merchant_id;
  RETURN jsonb_build_object('order_id', p_order_id, 'created', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_refund_request(
  p_order_id uuid, p_amount integer, p_reason text, p_evidence_urls text[] DEFAULT '{}',
  p_title text DEFAULT 'Komplain Pesanan', p_category text DEFAULT 'Lainnya'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_id uuid;
  v_evidence text[] := COALESCE(p_evidence_urls, '{}');
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR upper(v_order.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
    RAISE EXCEPTION 'Order is not eligible for refund' USING ERRCODE = '42501';
  END IF;
  IF upper(COALESCE(v_order.payment_status, '')) IN ('UNPAID', 'PENDING_TRANSFER', 'FAILED', 'EXPIRED') THEN
    RAISE EXCEPTION 'Unpaid orders cannot be refunded' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > v_order.total THEN
    RAISE EXCEPTION 'Refund amount is outside the eligible range' USING ERRCODE = '22023';
  END IF;
  IF length(trim(COALESCE(p_reason, ''))) < 10 OR length(p_reason) > 4000 THEN
    RAISE EXCEPTION 'Refund reason is invalid' USING ERRCODE = '22023';
  END IF;
  IF cardinality(v_evidence) > 5 OR EXISTS (SELECT 1 FROM unnest(v_evidence) url WHERE length(url) > 1000 OR url ~* '^(javascript|data):') THEN
    RAISE EXCEPTION 'Refund evidence is invalid' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.refund_requests WHERE order_id = p_order_id AND status IN ('PENDING', 'APPROVED')) THEN
    RAISE EXCEPTION 'An active refund request already exists' USING ERRCODE = '23505';
  END IF;
  INSERT INTO public.refund_requests(order_id, buyer_id, merchant_id, amount, reason, status, evidence_urls, refund_type, title, category, dispute_status)
  VALUES (p_order_id, auth.uid(), v_order.merchant_id, p_amount, trim(p_reason), 'PENDING', v_evidence,
    CASE WHEN p_amount = v_order.total THEN 'FULL' ELSE 'PARTIAL' END,
    left(COALESCE(NULLIF(trim(p_title), ''), 'Komplain Pesanan'), 200),
    left(COALESCE(NULLIF(trim(p_category), ''), 'Lainnya'), 80), 'OPEN')
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'order_id', p_order_id, 'amount', p_amount);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_order_reviews(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_order_reviews(uuid, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.create_refund_request(uuid, integer, text, text[], text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_refund_request(uuid, integer, text, text[], text, text) TO authenticated;
$bootstrap_sql_merchant_review_refund_hardening$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_merchant_review_refund_hardening$;
