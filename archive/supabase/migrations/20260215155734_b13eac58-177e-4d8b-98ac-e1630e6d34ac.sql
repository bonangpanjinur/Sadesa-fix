-- Tabel pengumuman verifikator ke kelompok
CREATE TABLE IF NOT EXISTS public.group_announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  verifikator_id uuid REFERENCES auth.users(id),
  title text NOT NULL,
  message text NOT NULL,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_345681b30c24$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_345681b30c24$;

DO $bootstrap_do_e4d8c4cb893b$
BEGIN
  EXECUTE $bootstrap_sql_e4d8c4cb893b$ALTER TABLE public.group_announcements ENABLE ROW LEVEL SECURITY$bootstrap_sql_e4d8c4cb893b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4d8c4cb893b$;

DO $bootstrap_do_b45fbd024770$
BEGIN
  EXECUTE $bootstrap_sql_b45fbd024770$DROP POLICY IF EXISTS "Verifikator can manage own announcements" ON public.group_announcements$bootstrap_sql_b45fbd024770$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b45fbd024770$;

DO $bootstrap_do_bfdd168d22c2$
BEGIN
  EXECUTE $bootstrap_sql_bfdd168d22c2$CREATE POLICY "Verifikator can manage own announcements"
  ON public.group_announcements FOR ALL
  USING (verifikator_id = auth.uid())$bootstrap_sql_bfdd168d22c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bfdd168d22c2$;

DO $bootstrap_do_7f92cb882da0$
BEGIN
  EXECUTE $bootstrap_sql_7f92cb882da0$DROP POLICY IF EXISTS "Group members can read announcements" ON public.group_announcements$bootstrap_sql_7f92cb882da0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f92cb882da0$;

DO $bootstrap_do_ef719b676d30$
BEGIN
  EXECUTE $bootstrap_sql_ef719b676d30$CREATE POLICY "Group members can read announcements"
  ON public.group_announcements FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      JOIN public.merchants m ON m.id = gm.merchant_id
      WHERE gm.group_id = group_announcements.group_id
      AND m.user_id = auth.uid()
    )
  )$bootstrap_sql_ef719b676d30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef719b676d30$;

DO $bootstrap_do_71d21f43f2cb$
BEGIN
  EXECUTE $bootstrap_sql_71d21f43f2cb$-- Ambang batas stok per produk
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS low_stock_threshold integer DEFAULT 5$bootstrap_sql_71d21f43f2cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_71d21f43f2cb$;

DO $bootstrap_do_d3a097d1da81$
BEGIN
  EXECUTE $bootstrap_sql_d3a097d1da81$
