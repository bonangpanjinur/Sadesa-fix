-- Multi-category merchants and safe operating-hours constraints.
-- Legacy merchants.business_category is retained for backwards compatibility.

CREATE TABLE IF NOT EXISTS public.merchant_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, category_id)
);

CREATE INDEX IF NOT EXISTS merchant_categories_category_id_idx
  ON public.merchant_categories(category_id);

ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_manage_own_categories" ON public.merchant_categories;
CREATE POLICY "merchant_manage_own_categories" ON public.merchant_categories
  FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))
  WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "admin_manage_merchant_categories" ON public.merchant_categories;
CREATE POLICY "admin_manage_merchant_categories" ON public.merchant_categories
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "public_read_merchant_categories" ON public.merchant_categories;
CREATE POLICY "public_read_merchant_categories" ON public.merchant_categories
  FOR SELECT
  USING (true);

-- Preserve the existing single-category value for all merchants during rollout.
INSERT INTO public.merchant_categories (merchant_id, category_id)
SELECT m.id, c.id
FROM public.merchants m
JOIN public.categories c ON c.slug = m.business_category
WHERE m.business_category IS NOT NULL
  AND c.is_active = true
ON CONFLICT (merchant_id, category_id) DO NOTHING;

COMMENT ON TABLE public.merchant_categories IS
  'Many-to-many category assignment for merchants. merchants.business_category remains as a legacy fallback.';

-- Make weekly schedules safe for overnight hours while preserving existing rows.
ALTER TABLE public.merchant_operating_hours
  DROP CONSTRAINT IF EXISTS merchant_operating_hours_time_order;

ALTER TABLE public.merchant_operating_hours
  ADD CONSTRAINT merchant_operating_hours_time_format
  CHECK (open_time IS NOT NULL AND close_time IS NOT NULL);

COMMENT ON TABLE public.merchant_operating_hours IS
  'Weekly merchant schedule; day_of_week uses 0 Sunday through 6 Saturday, and close_time may be earlier than open_time for overnight hours.';

NOTIFY pgrst, 'reload schema';
