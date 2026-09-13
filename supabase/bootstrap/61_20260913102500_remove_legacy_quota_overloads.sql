-- RPC overload cleanup.
-- The canonical quota function is:
--   use_merchant_quota(uuid)
--   use_merchant_quota_v2(uuid, integer, uuid DEFAULT NULL)
-- The old two-argument v2 function has the same effective call shape as the
-- canonical three-argument function because p_order_id has a default. Remove
-- it so PostgREST and PL/pgSQL cannot resolve a stale/ambiguous overload.
DROP FUNCTION IF EXISTS public.use_merchant_quota_v2(uuid, integer);

-- This older quota function was already deprecated in the application and is
-- not referenced by current source or RLS policies. Keep only the one-credit
-- wrapper and deduct_merchant_quota(uuid, integer).
DROP FUNCTION IF EXISTS public.use_merchant_quota(uuid, integer);

NOTIFY pgrst, 'reload schema';
