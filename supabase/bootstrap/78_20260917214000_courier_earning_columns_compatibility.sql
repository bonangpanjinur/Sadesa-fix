-- Compatibility repair for projects where courier payout columns were not applied.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS courier_earning_estimate integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_platform_fee integer NOT NULL DEFAULT 0;

UPDATE public.orders
SET courier_earning_estimate = COALESCE(shipping_cost, 0),
    courier_platform_fee = 0
WHERE courier_earning_estimate = 0
  AND COALESCE(shipping_cost, 0) > 0;

NOTIFY pgrst, 'reload schema';
