-- Keep one canonical merchant transition signature.
-- The 3-argument overload could be selected by stale clients/PostgREST and
-- bypass the expedition/self-delivery fields expected by the current UI.
DROP FUNCTION IF EXISTS public.merchant_transition_order(uuid, text, text);
NOTIFY pgrst, 'reload schema';
