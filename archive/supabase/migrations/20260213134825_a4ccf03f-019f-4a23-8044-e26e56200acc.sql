-- Fase 0: Add missing columns and tables

-- 1. Add has_review to orders
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS has_review BOOLEAN DEFAULT false$bootstrap_sql_26690aa3acc4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_26690aa3acc4$;

DO $bootstrap_do_36fd654b8e32$
BEGIN
  EXECUTE $bootstrap_sql_36fd654b8e32$-- 2. Add halal columns to merchants
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS halal_status TEXT DEFAULT 'NONE'$bootstrap_sql_36fd654b8e32$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_36fd654b8e32$;

DO $bootstrap_do_bb439f85d863$
BEGIN
  EXECUTE $bootstrap_sql_bb439f85d863$ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS halal_certificate_url TEXT$bootstrap_sql_bb439f85d863$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb439f85d863$;

DO $bootstrap_do_e4cab0eb1ee2$
BEGIN
  EXECUTE $bootstrap_sql_e4cab0eb1ee2$ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS ktp_url TEXT$bootstrap_sql_e4cab0eb1ee2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4cab0eb1ee2$;

DO $bootstrap_do_cb263f962f66$
BEGIN
  EXECUTE $bootstrap_sql_cb263f962f66$-- 3. Create halal_regulations table
CREATE TABLE IF NOT EXISTS public.halal_regulations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
)$bootstrap_sql_cb263f962f66$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb263f962f66$;

DO $bootstrap_do_197d83276113$
BEGIN
  EXECUTE $bootstrap_sql_197d83276113$ALTER TABLE public.halal_regulations ENABLE ROW LEVEL SECURITY$bootstrap_sql_197d83276113$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_197d83276113$;

DO $bootstrap_do_ecbf3e5a60c7$
BEGIN
  EXECUTE $bootstrap_sql_ecbf3e5a60c7$DROP POLICY IF EXISTS "Anyone can read halal_regulations" ON public.halal_regulations$bootstrap_sql_ecbf3e5a60c7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ecbf3e5a60c7$;

DO $bootstrap_do_6bc89f17dae8$
BEGIN
  EXECUTE $bootstrap_sql_6bc89f17dae8$CREATE POLICY "Anyone can read halal_regulations" ON public.halal_regulations FOR SELECT USING (true)$bootstrap_sql_6bc89f17dae8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6bc89f17dae8$;

DO $bootstrap_do_c4a9d06c40e6$
BEGIN
  EXECUTE $bootstrap_sql_c4a9d06c40e6$DROP POLICY IF EXISTS "Admin can manage halal_regulations" ON public.halal_regulations$bootstrap_sql_c4a9d06c40e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c4a9d06c40e6$;

DO $bootstrap_do_9452c4102e42$
BEGIN
  EXECUTE $bootstrap_sql_9452c4102e42$CREATE POLICY "Admin can manage halal_regulations" ON public.halal_regulations FOR ALL USING (public.is_admin())$bootstrap_sql_9452c4102e42$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9452c4102e42$;

DO $bootstrap_do_a20484d5d5a7$
BEGIN
  EXECUTE $bootstrap_sql_a20484d5d5a7$-- 4. Create increment_product_view function
CREATE OR REPLACE FUNCTION public.increment_product_view(product_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.products SET view_count = COALESCE(view_count, 0) + 1 WHERE id = product_id;
END;
$$$bootstrap_sql_a20484d5d5a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a20484d5d5a7$;

DO $bootstrap_do_1f5b37b5d2d9$
BEGIN
  EXECUTE $bootstrap_sql_1f5b37b5d2d9$-- 5. Fix auto_assign_merchant_to_group trigger to work on UPDATE too
-- Drop and recreate trigger to include UPDATE
DROP TRIGGER IF EXISTS auto_assign_merchant_to_group ON public.merchants$bootstrap_sql_1f5b37b5d2d9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f5b37b5d2d9$;

DO $bootstrap_do_c9e7ca68ab91$
BEGIN
  EXECUTE $bootstrap_sql_c9e7ca68ab91$CREATE OR REPLACE FUNCTION public.auto_assign_merchant_to_group()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_group_id UUID;
  v_verifikator_id UUID;
BEGIN
  -- Only process if verifikator_code is set and group_id is not
  IF NEW.verifikator_code IS NOT NULL AND NEW.group_id IS NULL THEN
    -- Find the trade group and verifikator for this code
    SELECT tg.id, tg.verifikator_id INTO v_group_id, v_verifikator_id
    FROM public.trade_groups tg
    JOIN public.verifikator_codes vc ON vc.trade_group = tg.name
    WHERE vc.code = NEW.verifikator_code
    LIMIT 1;

    IF v_group_id IS NOT NULL THEN
      NEW.group_id := v_group_id;
      NEW.verifikator_id := v_verifikator_id;

      -- Insert into group_members if not exists
      INSERT INTO public.group_members (group_id, merchant_id, status)
      VALUES (v_group_id, NEW.id, 'ACTIVE')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_c9e7ca68ab91$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c9e7ca68ab91$;

DO $bootstrap_do_adf17957270e$
BEGIN
  EXECUTE $bootstrap_sql_adf17957270e$DROP TRIGGER IF EXISTS auto_assign_merchant_to_group ON public.merchants$bootstrap_sql_adf17957270e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_adf17957270e$;

DO $bootstrap_do_6a09513f1ef6$
BEGIN
  EXECUTE $bootstrap_sql_6a09513f1ef6$CREATE TRIGGER auto_assign_merchant_to_group
  BEFORE INSERT OR UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_assign_merchant_to_group()$bootstrap_sql_6a09513f1ef6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a09513f1ef6$;

DO $bootstrap_do_eaf370ffefb2$
BEGIN
  EXECUTE $bootstrap_sql_eaf370ffefb2$-- 6. Auto-assign admin_desa role when village is approved
CREATE OR REPLACE FUNCTION public.auto_assign_village_admin_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- When village is approved and has a user_id
  IF NEW.registration_status = 'APPROVED' AND OLD.registration_status = 'PENDING' AND NEW.user_id IS NOT NULL THEN
    -- Add admin_desa role if not exists
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.user_id, 'admin_desa')
    ON CONFLICT DO NOTHING;

    -- Add to user_villages if not exists
    INSERT INTO public.user_villages (user_id, village_id, role)
    VALUES (NEW.user_id, NEW.id, 'admin')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_eaf370ffefb2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eaf370ffefb2$;

DO $bootstrap_do_6c33178d25b0$
BEGIN
  EXECUTE $bootstrap_sql_6c33178d25b0$DROP TRIGGER IF EXISTS auto_assign_village_admin ON public.villages$bootstrap_sql_6c33178d25b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c33178d25b0$;

DO $bootstrap_do_2f66dba7fa5e$
BEGIN
  EXECUTE $bootstrap_sql_2f66dba7fa5e$CREATE TRIGGER auto_assign_village_admin
  AFTER UPDATE ON public.villages
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_assign_village_admin_role()$bootstrap_sql_2f66dba7fa5e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2f66dba7fa5e$;

DO $bootstrap_do_8d2489d7defd$
BEGIN
  EXECUTE $bootstrap_sql_8d2489d7defd$
