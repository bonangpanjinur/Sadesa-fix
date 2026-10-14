-- Create wishlists table for buyer wishlist functionality
CREATE TABLE IF NOT EXISTS public.wishlists (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE(user_id, product_id)
)$bootstrap_sql_a06466910e91$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a06466910e91$;

DO $bootstrap_do_d286b92184a8$
BEGIN
  EXECUTE $bootstrap_sql_d286b92184a8$-- Enable RLS on wishlists
ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY$bootstrap_sql_d286b92184a8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d286b92184a8$;

DO $bootstrap_do_3ea2878f4a18$
BEGIN
  EXECUTE $bootstrap_sql_3ea2878f4a18$-- RLS policies for wishlists
DROP POLICY IF EXISTS "Users can view own wishlists" ON public.wishlists$bootstrap_sql_3ea2878f4a18$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ea2878f4a18$;

DO $bootstrap_do_19f6ef3f53c5$
BEGIN
  EXECUTE $bootstrap_sql_19f6ef3f53c5$CREATE POLICY "Users can view own wishlists"
    ON public.wishlists
    FOR SELECT
    USING (auth.uid() = user_id)$bootstrap_sql_19f6ef3f53c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19f6ef3f53c5$;

DO $bootstrap_do_5cf2da1b99b7$
BEGIN
  EXECUTE $bootstrap_sql_5cf2da1b99b7$DROP POLICY IF EXISTS "Users can add to own wishlist" ON public.wishlists$bootstrap_sql_5cf2da1b99b7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5cf2da1b99b7$;

DO $bootstrap_do_60765eb7ffc1$
BEGIN
  EXECUTE $bootstrap_sql_60765eb7ffc1$CREATE POLICY "Users can add to own wishlist"
    ON public.wishlists
    FOR INSERT
    WITH CHECK (auth.uid() = user_id)$bootstrap_sql_60765eb7ffc1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_60765eb7ffc1$;

DO $bootstrap_do_08d47ffc50e7$
BEGIN
  EXECUTE $bootstrap_sql_08d47ffc50e7$DROP POLICY IF EXISTS "Users can remove from own wishlist" ON public.wishlists$bootstrap_sql_08d47ffc50e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08d47ffc50e7$;

DO $bootstrap_do_b5c49ea6413c$
BEGIN
  EXECUTE $bootstrap_sql_b5c49ea6413c$CREATE POLICY "Users can remove from own wishlist"
    ON public.wishlists
    FOR DELETE
    USING (auth.uid() = user_id)$bootstrap_sql_b5c49ea6413c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b5c49ea6413c$;

DO $bootstrap_do_56e01992b2f8$
BEGIN
  EXECUTE $bootstrap_sql_56e01992b2f8$-- Create index for better query performance
CREATE INDEX idx_wishlists_user_id ON public.wishlists(user_id)$bootstrap_sql_56e01992b2f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56e01992b2f8$;

DO $bootstrap_do_00592dc46bdd$
BEGIN
  EXECUTE $bootstrap_sql_00592dc46bdd$CREATE INDEX idx_wishlists_product_id ON public.wishlists(product_id)$bootstrap_sql_00592dc46bdd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00592dc46bdd$;

DO $bootstrap_do_f07c9e875600$
BEGIN
  EXECUTE $bootstrap_sql_f07c9e875600$
