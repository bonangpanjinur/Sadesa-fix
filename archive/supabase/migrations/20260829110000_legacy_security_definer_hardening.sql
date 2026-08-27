-- Harden legacy SECURITY DEFINER functions created before explicit search_path
-- conventions were applied. Trigger functions are not browser APIs.
ALTER FUNCTION public.check_low_quota_alert() SET search_path = public;
ALTER FUNCTION public.increment_product_view(uuid) SET search_path = public;
ALTER FUNCTION public.auto_assign_merchant_to_group() SET search_path = public;
ALTER FUNCTION public.auto_assign_village_admin_role() SET search_path = public;
ALTER FUNCTION public.handle_merchant_approval_role() SET search_path = public;

REVOKE ALL ON FUNCTION public.check_low_quota_alert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_assign_merchant_to_group() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_assign_village_admin_role() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_merchant_approval_role() FROM PUBLIC, anon, authenticated;
