-- Drop overloads that will cause ambiguity when policies call the no-arg form
DROP FUNCTION IF EXISTS public.get_user_courier_id(uuid);
DROP FUNCTION IF EXISTS public.get_user_merchant_id(uuid);

-- Recreate with SINGLE signature (no default arg to avoid overload conflict)
CREATE OR REPLACE FUNCTION public.get_user_merchant_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT id FROM public.merchants WHERE user_id = auth.uid() LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.get_user_courier_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT id FROM public.couriers WHERE user_id = auth.uid() LIMIT 1
$$;
