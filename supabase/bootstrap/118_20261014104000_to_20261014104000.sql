-- DesaMart checkout shipping-column repair bundle.
-- Source: 20261014104000_repair_checkout_shipping_columns.sql
-- Safe to re-run: ADD COLUMN IF NOT EXISTS and guarded constraint creation.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS shipping_weight_kg numeric NOT NULL DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'products_shipping_weight_kg_valid'
      AND conrelid = 'public.products'::regclass
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_shipping_weight_kg_valid
      CHECK (shipping_weight_kg > 0 AND shipping_weight_kg <= 1000);
  END IF;
END;
$$;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS shipping_pricing_contract jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS merchant_delivery_fee_contract text,
  ADD COLUMN IF NOT EXISTS expedition_service_code_snapshot text,
  ADD COLUMN IF NOT EXISTS expedition_service_name_snapshot text;
