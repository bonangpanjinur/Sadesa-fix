-- Public-safe counters for ad performance reporting.
CREATE OR REPLACE FUNCTION public.increment_merchant_ad_view(p_ad_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.merchant_ads
  SET view_count = view_count + 1
  WHERE id = p_ad_id
    AND status = 'active'
    AND start_date <= now()
    AND (end_date IS NULL OR end_date >= now());
$$;

CREATE OR REPLACE FUNCTION public.increment_merchant_ad_click(p_ad_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.merchant_ads
  SET click_count = click_count + 1
  WHERE id = p_ad_id
    AND status = 'active'
    AND start_date <= now()
    AND (end_date IS NULL OR end_date >= now());
$$;

CREATE OR REPLACE FUNCTION public.increment_promotion_view(p_promotion_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.promotions SET view_count = view_count + 1 WHERE id = p_promotion_id;
$$;

CREATE OR REPLACE FUNCTION public.increment_promotion_click(p_promotion_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.promotions SET click_count = click_count + 1 WHERE id = p_promotion_id;
$$;

GRANT EXECUTE ON FUNCTION public.increment_merchant_ad_view(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_merchant_ad_click(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_promotion_view(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_promotion_click(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
