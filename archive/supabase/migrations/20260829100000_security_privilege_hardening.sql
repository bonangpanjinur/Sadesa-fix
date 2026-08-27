-- SECURITY DEFINER trigger/helper functions must not be callable by browser roles.
-- Their execution is reserved for database triggers or server-side worker paths.
REVOKE ALL ON FUNCTION public.mark_crm_cart_recovered_after_pos_sale() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) FROM PUBLIC, anon, authenticated;

-- Keep the critical transaction functions callable only by authenticated users
-- after their own tenant/outlet checks; service_role retains ownership access.
REVOKE ALL ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) FROM PUBLIC, anon;
