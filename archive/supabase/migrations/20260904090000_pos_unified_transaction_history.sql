-- POS unified transaction history and legacy reconciliation map.
-- New cashier writes remain exclusively in pos_sales; this migration only exposes
-- legacy records for reporting and gives operators an idempotent reconciliation key.

CREATE TABLE IF NOT EXISTS public.pos_transaction_migration_map (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legacy_transaction_id uuid NOT NULL REFERENCES public.pos_transactions(id) ON DELETE CASCADE,
  pos_sale_id uuid REFERENCES public.pos_sales(id) ON DELETE SET NULL,
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'mapped', 'migrated', 'exception')),
  exception_code text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (legacy_transaction_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_transaction_migration_map_sale
  ON public.pos_transaction_migration_map(pos_sale_id)
  WHERE pos_sale_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pos_transaction_migration_map_scope
  ON public.pos_transaction_migration_map(tenant_id, outlet_id, status);

ALTER TABLE public.pos_transaction_migration_map ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "POS users can view transaction migration map" ON public.pos_transaction_migration_map;
CREATE POLICY "POS users can view transaction migration map"
  ON public.pos_transaction_migration_map FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
    OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)
  );

DROP POLICY IF EXISTS "POS owners manage transaction migration map" ON public.pos_transaction_migration_map;
CREATE POLICY "POS owners manage transaction migration map"
  ON public.pos_transaction_migration_map FOR ALL TO authenticated
  USING (public.is_admin() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (public.is_admin() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- Allow the unified history view to expose mapped legacy transactions to POS users.
DROP POLICY IF EXISTS "POS users can view mapped legacy transactions" ON public.pos_transactions;
CREATE POLICY "POS users can view mapped legacy transactions"
  ON public.pos_transactions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.pos_transaction_migration_map map
      WHERE map.legacy_transaction_id = pos_transactions.id
        AND (
          public.is_admin()
          OR map.tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
          OR map.tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)
        )
    )
  );

-- Seed the map deterministically. A legacy merchant is auto-mapped only when it
-- resolves to exactly one POS tenant. An outlet is auto-selected only when the
-- tenant has exactly one active outlet; otherwise the row remains an exception
-- for manual outlet assignment.
INSERT INTO public.pos_transaction_migration_map (
  legacy_transaction_id,
  tenant_id,
  outlet_id,
  status,
  exception_code,
  notes
)
SELECT
  tx.id,
  tenant.id,
  CASE WHEN outlet_counts.active_outlet_count = 1 THEN outlet_counts.only_outlet_id ELSE NULL END,
  CASE
    WHEN tenant.id IS NULL THEN 'exception'
    WHEN outlet_counts.active_outlet_count = 1 THEN 'mapped'
    ELSE 'exception'
  END,
  CASE
    WHEN tenant.id IS NULL THEN 'MERCHANT_TENANT_UNMAPPED'
    WHEN outlet_counts.active_outlet_count <> 1 THEN 'OUTLET_MAPPING_AMBIGUOUS'
    ELSE NULL
  END,
  CASE
    WHEN tenant.id IS NULL THEN 'No unique POS tenant is mapped to the legacy merchant.'
    WHEN outlet_counts.active_outlet_count <> 1 THEN 'Manual outlet assignment is required before outlet-scoped reconciliation.'
    ELSE 'Initial idempotent legacy mapping.'
  END
FROM public.pos_transactions tx
LEFT JOIN public.pos_tenants tenant ON tenant.merchant_id = tx.merchant_id
LEFT JOIN LATERAL (
  SELECT
    count(*)::integer AS active_outlet_count,
    min(outlet.id) AS only_outlet_id
  FROM public.pos_outlets outlet
  WHERE outlet.tenant_id = tenant.id AND outlet.is_active = true
) outlet_counts ON true
ON CONFLICT (legacy_transaction_id) DO NOTHING;

CREATE OR REPLACE VIEW public.pos_unified_transaction_history
WITH (security_invoker = true) AS
SELECT
  sale.id,
  'modern'::text AS source,
  sale.id AS source_id,
  sale.tenant_id,
  sale.outlet_id,
  sale.sale_number,
  sale.cashier_name,
  sale.customer_name,
  sale.subtotal,
  sale.discount_amount,
  sale.tax_amount,
  sale.total,
  sale.payment_method,
  sale.payment_amount,
  sale.change_amount,
  sale.status,
  sale.notes,
  sale.created_at,
  COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', item.id,
        'product_name', item.product_name,
        'variant_name', item.variant_name,
        'qty', item.qty,
        'price', item.price,
        'discount', item.discount,
        'subtotal', item.subtotal
      ) ORDER BY item.created_at, item.id
    ) FILTER (WHERE item.id IS NOT NULL),
    '[]'::jsonb
  ) AS items
FROM public.pos_sales sale
LEFT JOIN public.pos_sale_items item ON item.sale_id = sale.id
GROUP BY sale.id

UNION ALL

SELECT
  legacy.id,
  'legacy'::text AS source,
  legacy.id AS source_id,
  mapping.tenant_id,
  mapping.outlet_id,
  legacy.transaction_number AS sale_number,
  legacy.cashier_name,
  legacy.customer_name,
  legacy.subtotal::numeric,
  legacy.discount::numeric AS discount_amount,
  legacy.tax::numeric AS tax_amount,
  legacy.total::numeric,
  lower(legacy.payment_method) AS payment_method,
  legacy.payment_amount::numeric,
  legacy.change_amount::numeric,
  lower(legacy.status) AS status,
  legacy.notes,
  legacy.created_at,
  COALESCE(legacy.items, '[]'::jsonb) AS items
FROM public.pos_transactions legacy
JOIN public.pos_transaction_migration_map mapping
  ON mapping.legacy_transaction_id = legacy.id
WHERE mapping.pos_sale_id IS NULL
  AND mapping.tenant_id IS NOT NULL;

COMMENT ON VIEW public.pos_unified_transaction_history IS
  'Read-only reporting view combining canonical pos_sales with unmigrated legacy pos_transactions. New checkout must never write legacy rows.';

GRANT SELECT ON public.pos_unified_transaction_history TO authenticated;
