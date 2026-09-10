-- Review, refund, and courier-rating hardening.
-- All buyer writes are moved behind ownership- and state-aware RPCs.

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS courier_rated boolean NOT NULL DEFAULT false;
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS rating_avg numeric NOT NULL DEFAULT 0;
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS rating_count integer NOT NULL DEFAULT 0;

DELETE FROM public.reviews a
USING public.reviews b
WHERE a.order_id = b.order_id
  AND a.product_id = b.product_id
  AND a.buyer_id = b.buyer_id
  AND a.id > b.id;

CREATE UNIQUE INDEX IF NOT EXISTS reviews_one_per_order_product_buyer
  ON public.reviews(order_id, product_id, buyer_id);
CREATE UNIQUE INDEX IF NOT EXISTS refund_requests_one_pending_per_order
  ON public.refund_requests(order_id)
  WHERE status IN ('PENDING', 'APPROVED');

CREATE OR REPLACE FUNCTION public.prevent_review_identity_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() AND (
    NEW.buyer_id IS DISTINCT FROM OLD.buyer_id OR
    NEW.order_id IS DISTINCT FROM OLD.order_id OR
    NEW.product_id IS DISTINCT FROM OLD.product_id OR
    NEW.merchant_id IS DISTINCT FROM OLD.merchant_id OR
    NEW.rating IS DISTINCT FROM OLD.rating OR
    NEW.is_visible IS DISTINCT FROM OLD.is_visible OR
    NEW.comment IS DISTINCT FROM OLD.comment OR
    NEW.image_urls IS DISTINCT FROM OLD.image_urls OR
    NEW.created_at IS DISTINCT FROM OLD.created_at
  ) THEN
    RAISE EXCEPTION 'Review identity and rating are immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS protect_review_identity ON public.reviews;
CREATE TRIGGER protect_review_identity
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.prevent_review_identity_mutation();

CREATE TABLE IF NOT EXISTS public.courier_ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL,
  rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment text,
  tags text[] DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id, courier_id, buyer_id)
);
ALTER TABLE public.courier_ratings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can view courier ratings" ON public.courier_ratings;
CREATE POLICY "Public can view courier ratings" ON public.courier_ratings FOR SELECT USING (true);
DROP POLICY IF EXISTS "Buyers can view own courier ratings" ON public.courier_ratings;
CREATE POLICY "Buyers can view own courier ratings" ON public.courier_ratings FOR SELECT USING (buyer_id = auth.uid());
GRANT SELECT ON public.courier_ratings TO anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.courier_ratings FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.submit_order_reviews(p_order_id uuid, p_reviews jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_review jsonb;
  v_product_id uuid;
  v_rating integer;
  v_count integer := 0;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR upper(v_order.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
    RAISE EXCEPTION 'Only completed orders can be reviewed' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_reviews) <> 'array' OR jsonb_array_length(p_reviews) = 0 THEN
    RAISE EXCEPTION 'At least one review is required' USING ERRCODE = '22023';
  END IF;
  FOR v_review IN SELECT value FROM jsonb_array_elements(p_reviews) LOOP
    v_product_id := NULLIF(v_review->>'product_id', '')::uuid;
    v_rating := (v_review->>'rating')::integer;
    IF v_product_id IS NULL OR v_rating IS NULL OR v_rating NOT BETWEEN 1 AND 5 THEN
      RAISE EXCEPTION 'Invalid review payload' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.order_items WHERE order_id = p_order_id AND product_id = v_product_id) THEN
      RAISE EXCEPTION 'Product is not part of this order' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.reviews(product_id, order_id, buyer_id, merchant_id, rating, comment, image_urls)
    VALUES (
      v_product_id, p_order_id, auth.uid(), v_order.merchant_id, v_rating,
      NULLIF(left(COALESCE(v_review->>'comment', ''), 2000), ''),
      COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_review->'image_urls', '[]'::jsonb))), '{}')
    );
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
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_id uuid;
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
  IF EXISTS (SELECT 1 FROM public.refund_requests WHERE order_id = p_order_id AND status IN ('PENDING', 'APPROVED')) THEN
    RAISE EXCEPTION 'An active refund request already exists' USING ERRCODE = '23505';
  END IF;
  INSERT INTO public.refund_requests(order_id, buyer_id, merchant_id, amount, reason, status, evidence_urls, refund_type, title, category, dispute_status)
  VALUES (p_order_id, auth.uid(), v_order.merchant_id, p_amount, trim(p_reason), 'PENDING',
    COALESCE(p_evidence_urls, '{}'), CASE WHEN p_amount = v_order.total THEN 'FULL' ELSE 'PARTIAL' END,
    left(COALESCE(NULLIF(trim(p_title), ''), 'Komplain Pesanan'), 200),
    left(COALESCE(NULLIF(trim(p_category), ''), 'Lainnya'), 80), 'OPEN')
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'order_id', p_order_id, 'amount', p_amount);
END;
$$;

CREATE OR REPLACE FUNCTION public.process_refund_decision(p_refund_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_refund public.refund_requests%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_new_status text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_refund FROM public.refund_requests WHERE id = p_refund_id FOR UPDATE;
  IF NOT FOUND OR v_refund.status <> 'PENDING' THEN
    RAISE EXCEPTION 'Refund is no longer pending' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = v_refund.order_id FOR UPDATE;
  IF NOT FOUND OR v_refund.amount <= 0 OR v_refund.amount > v_order.total THEN
    RAISE EXCEPTION 'Refund amount is invalid' USING ERRCODE = '22023';
  END IF;
  v_new_status := CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END;
  UPDATE public.refund_requests SET status = v_new_status, admin_notes = NULLIF(left(COALESCE(p_notes, ''), 2000), ''), processed_by = auth.uid(), processed_at = now(), updated_at = now(), dispute_status = CASE WHEN p_approve THEN 'RESOLVED_REFUND' ELSE 'RESOLVED_REJECTED' END WHERE id = p_refund_id;
  IF p_approve THEN
    UPDATE public.orders SET status = 'REFUNDED', updated_at = now() WHERE id = v_order.id;
    UPDATE public.merchants SET available_balance = GREATEST(0, COALESCE(available_balance, 0) - v_refund.amount), updated_at = now() WHERE id = v_order.merchant_id;
  END IF;
  RETURN jsonb_build_object('id', p_refund_id, 'status', v_new_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_to_refund_request(p_refund_id uuid, p_response text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF length(trim(COALESCE(p_response, ''))) < 5 OR length(p_response) > 4000 THEN
    RAISE EXCEPTION 'Merchant response is invalid' USING ERRCODE = '22023';
  END IF;
  UPDATE public.refund_requests rr
  SET merchant_response = trim(p_response), merchant_responded_at = now(),
      dispute_status = 'MERCHANT_RESPONDED', updated_at = now()
  WHERE rr.id = p_refund_id
    AND rr.status = 'PENDING'
    AND EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = rr.merchant_id AND m.user_id = auth.uid());
  IF NOT FOUND THEN RAISE EXCEPTION 'Refund request is not available to this merchant' USING ERRCODE = '42501'; END IF;
  SELECT id INTO v_id FROM public.refund_requests WHERE id = p_refund_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'MERCHANT_RESPONDED');
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_courier_rating(
  p_order_id uuid, p_courier_id uuid, p_rating integer, p_comment text DEFAULT NULL, p_tags text[] DEFAULT '{}'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_id uuid;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR upper(v_order.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') OR v_order.courier_id <> p_courier_id THEN
    RAISE EXCEPTION 'Order is not eligible for this courier rating' USING ERRCODE = '42501';
  END IF;
  IF p_rating NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'Rating must be between 1 and 5' USING ERRCODE = '22023'; END IF;
  INSERT INTO public.courier_ratings(order_id, courier_id, buyer_id, rating, comment, tags)
  VALUES (p_order_id, p_courier_id, auth.uid(), p_rating, NULLIF(left(COALESCE(p_comment, ''), 500), ''), COALESCE(p_tags, '{}'))
  RETURNING id INTO v_id;
  UPDATE public.couriers c SET
    rating_avg = COALESCE((SELECT round(avg(r.rating)::numeric, 2) FROM public.courier_ratings r WHERE r.courier_id = c.id), 0),
    rating_count = (SELECT count(*) FROM public.courier_ratings r WHERE r.courier_id = c.id),
    updated_at = now()
  WHERE c.id = p_courier_id;
  UPDATE public.orders SET courier_rated = true, updated_at = now() WHERE id = p_order_id;
  RETURN jsonb_build_object('id', v_id);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_order_reviews(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_refund_request(uuid, integer, text, text[], text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.process_refund_decision(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_courier_rating(uuid, uuid, integer, text, text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.respond_to_refund_request(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_order_reviews(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_refund_request(uuid, integer, text, text[], text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_refund_decision(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_courier_rating(uuid, uuid, integer, text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_to_refund_request(uuid, text) TO authenticated;

DROP POLICY IF EXISTS "Buyers can create reviews for their orders" ON public.reviews;
DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests;
REVOKE INSERT ON public.reviews, public.refund_requests FROM authenticated, anon;
