-- Make buyer transaction classification explicit while preserving legacy orders.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS service_type text NOT NULL DEFAULT 'MARKETPLACE';

UPDATE public.orders
SET service_type = 'COURIER_DELIVERY'
WHERE service_type = 'MARKETPLACE'
  AND merchant_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.order_items oi WHERE oi.order_id = orders.id
  )
  AND pickup_address IS NOT NULL
  AND package_type IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'orders_service_type_check'
      AND conrelid = 'public.orders'::regclass
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_service_type_check
      CHECK (service_type IN ('MARKETPLACE', 'COURIER_DELIVERY'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_orders_buyer_service_type_created
  ON public.orders (buyer_id, service_type, created_at DESC);

NOTIFY pgrst, 'reload schema';
