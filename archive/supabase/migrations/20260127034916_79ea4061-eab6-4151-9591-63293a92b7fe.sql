-- ============================================
-- DESA WISATA & UMKM - DATABASE SCHEMA
-- ============================================

-- 1. Create app_role enum for user roles.
-- The bootstrap may be retried after a partial run, so tolerate an existing type.
DO $$
BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'buyer');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$$bootstrap_sql_5183f66badea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5183f66badea$;

DO $bootstrap_do_72a5a79de8d7$
BEGIN
  EXECUTE $bootstrap_sql_72a5a79de8d7$-- 2. Create user_roles table (separate from profiles for security)
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role app_role NOT NULL DEFAULT 'buyer',
    UNIQUE (user_id, role)
)$bootstrap_sql_72a5a79de8d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_72a5a79de8d7$;

DO $bootstrap_do_049d409561cb$
BEGIN
  EXECUTE $bootstrap_sql_049d409561cb$-- 3. Create profiles table
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
    full_name TEXT NOT NULL DEFAULT '',
    phone TEXT,
    address TEXT,
    village TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_049d409561cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_049d409561cb$;

DO $bootstrap_do_d95a653fe039$
BEGIN
  EXECUTE $bootstrap_sql_d95a653fe039$-- 4. Create villages table
CREATE TABLE public.villages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    district TEXT NOT NULL,
    regency TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_d95a653fe039$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d95a653fe039$;

DO $bootstrap_do_ddd2cd3d44da$
BEGIN
  EXECUTE $bootstrap_sql_ddd2cd3d44da$-- 5. Create merchants table
CREATE TABLE public.merchants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    village_id UUID REFERENCES public.villages(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    open_time TIME,
    close_time TIME,
    classification_price TEXT CHECK (classification_price IN ('UNDER_5K', 'FROM_5K_TO_10K', 'FROM_10K_TO_20K', 'ABOVE_20K')),
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    order_mode TEXT NOT NULL DEFAULT 'ADMIN_ASSISTED' CHECK (order_mode IN ('SELF', 'ADMIN_ASSISTED')),
    rating_avg DECIMAL(2,1) DEFAULT 0,
    rating_count INTEGER DEFAULT 0,
    badge TEXT CHECK (badge IN ('VERIFIED', 'POPULAR', 'NEW')),
    image_url TEXT,
    is_open BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_ddd2cd3d44da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ddd2cd3d44da$;

DO $bootstrap_do_9f85498d61bd$
BEGIN
  EXECUTE $bootstrap_sql_9f85498d61bd$-- 6. Create products table
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    price INTEGER NOT NULL CHECK (price >= 0),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    image_url TEXT,
    category TEXT NOT NULL CHECK (category IN ('kuliner', 'fashion', 'kriya')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_promo BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_9f85498d61bd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f85498d61bd$;

DO $bootstrap_do_be051cd0b3ab$
BEGIN
  EXECUTE $bootstrap_sql_be051cd0b3ab$-- 7. Create tourism table
CREATE TABLE public.tourism (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    village_id UUID REFERENCES public.villages(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    location_lat DECIMAL(10, 8),
    location_lng DECIMAL(11, 8),
    wa_link TEXT,
    sosmed_link TEXT,
    facilities TEXT[] DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    view_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_be051cd0b3ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be051cd0b3ab$;

DO $bootstrap_do_e142e43e7205$
BEGIN
  EXECUTE $bootstrap_sql_e142e43e7205$-- 8. Create orders table
CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id UUID REFERENCES auth.users(id) ON DELETE SET NULL NOT NULL,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'NEW' CHECK (status IN ('NEW', 'PROCESSED', 'SENT', 'DONE', 'CANCELED')),
    handled_by TEXT NOT NULL DEFAULT 'ADMIN' CHECK (handled_by IN ('ADMIN', 'MERCHANT')),
    delivery_type TEXT NOT NULL DEFAULT 'PICKUP' CHECK (delivery_type IN ('PICKUP', 'INTERNAL')),
    delivery_address TEXT,
    delivery_phone TEXT,
    delivery_name TEXT,
    shipping_cost INTEGER NOT NULL DEFAULT 0,
    subtotal INTEGER NOT NULL DEFAULT 0,
    total INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_e142e43e7205$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e142e43e7205$;

DO $bootstrap_do_e8c3dfadc5fe$
BEGIN
  EXECUTE $bootstrap_sql_e8c3dfadc5fe$-- 9. Create order_items table
CREATE TABLE public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    product_price INTEGER NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    subtotal INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_e8c3dfadc5fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8c3dfadc5fe$;

DO $bootstrap_do_cd61ed67fdc5$
BEGIN
  EXECUTE $bootstrap_sql_cd61ed67fdc5$-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to check if user has a specific role
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$$bootstrap_sql_cd61ed67fdc5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cd61ed67fdc5$;

DO $bootstrap_do_8480a3b719c1$
BEGIN
  EXECUTE $bootstrap_sql_8480a3b719c1$-- Function to check if current user is admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'admin')
$$$bootstrap_sql_8480a3b719c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8480a3b719c1$;

DO $bootstrap_do_1ba0e5e8ea23$
BEGIN
  EXECUTE $bootstrap_sql_1ba0e5e8ea23$-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public$bootstrap_sql_1ba0e5e8ea23$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ba0e5e8ea23$;

DO $bootstrap_do_6f1cd051911e$
BEGIN
  EXECUTE $bootstrap_sql_6f1cd051911e$-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-update timestamps
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles$bootstrap_sql_6f1cd051911e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f1cd051911e$;

DO $bootstrap_do_f1c120ef68b7$
BEGIN
  EXECUTE $bootstrap_sql_f1c120ef68b7$CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_f1c120ef68b7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f1c120ef68b7$;

DO $bootstrap_do_c86cbe28f24a$
BEGIN
  EXECUTE $bootstrap_sql_c86cbe28f24a$DROP TRIGGER IF EXISTS update_merchants_updated_at ON public.merchants$bootstrap_sql_c86cbe28f24a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c86cbe28f24a$;

DO $bootstrap_do_b3fbbbc9be57$
BEGIN
  EXECUTE $bootstrap_sql_b3fbbbc9be57$CREATE TRIGGER update_merchants_updated_at
    BEFORE UPDATE ON public.merchants
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_b3fbbbc9be57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b3fbbbc9be57$;

DO $bootstrap_do_077e0020f1b9$
BEGIN
  EXECUTE $bootstrap_sql_077e0020f1b9$DROP TRIGGER IF EXISTS update_products_updated_at ON public.products$bootstrap_sql_077e0020f1b9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_077e0020f1b9$;

DO $bootstrap_do_cad0e603cfc3$
BEGIN
  EXECUTE $bootstrap_sql_cad0e603cfc3$CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_cad0e603cfc3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cad0e603cfc3$;

DO $bootstrap_do_4403002b84c1$
BEGIN
  EXECUTE $bootstrap_sql_4403002b84c1$DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders$bootstrap_sql_4403002b84c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4403002b84c1$;

DO $bootstrap_do_7617ad23589e$
BEGIN
  EXECUTE $bootstrap_sql_7617ad23589e$CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_7617ad23589e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7617ad23589e$;

DO $bootstrap_do_448545eddc8e$
BEGIN
  EXECUTE $bootstrap_sql_448545eddc8e$-- Auto-create profile and buyer role on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (user_id, full_name)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''));

    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'buyer');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_448545eddc8e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_448545eddc8e$;

DO $bootstrap_do_be863650f986$
BEGIN
  EXECUTE $bootstrap_sql_be863650f986$DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users$bootstrap_sql_be863650f986$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be863650f986$;

DO $bootstrap_do_7e437788f1d8$
BEGIN
  EXECUTE $bootstrap_sql_7e437788f1d8$CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user()$bootstrap_sql_7e437788f1d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7e437788f1d8$;

DO $bootstrap_do_0e822102e70c$
BEGIN
  EXECUTE $bootstrap_sql_0e822102e70c$-- ============================================
-- RLS POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY$bootstrap_sql_0e822102e70c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e822102e70c$;

DO $bootstrap_do_a86fe2f8d881$
BEGIN
  EXECUTE $bootstrap_sql_a86fe2f8d881$ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY$bootstrap_sql_a86fe2f8d881$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a86fe2f8d881$;

DO $bootstrap_do_c4be0efdf682$
BEGIN
  EXECUTE $bootstrap_sql_c4be0efdf682$ALTER TABLE public.villages ENABLE ROW LEVEL SECURITY$bootstrap_sql_c4be0efdf682$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c4be0efdf682$;

DO $bootstrap_do_5926726a139d$
BEGIN
  EXECUTE $bootstrap_sql_5926726a139d$ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY$bootstrap_sql_5926726a139d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5926726a139d$;

DO $bootstrap_do_1a78391eae8b$
BEGIN
  EXECUTE $bootstrap_sql_1a78391eae8b$ALTER TABLE public.products ENABLE ROW LEVEL SECURITY$bootstrap_sql_1a78391eae8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1a78391eae8b$;

DO $bootstrap_do_634d536912ee$
BEGIN
  EXECUTE $bootstrap_sql_634d536912ee$ALTER TABLE public.tourism ENABLE ROW LEVEL SECURITY$bootstrap_sql_634d536912ee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_634d536912ee$;

DO $bootstrap_do_9dc122f9942f$
BEGIN
  EXECUTE $bootstrap_sql_9dc122f9942f$ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY$bootstrap_sql_9dc122f9942f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9dc122f9942f$;

DO $bootstrap_do_db1b85c2b7a0$
BEGIN
  EXECUTE $bootstrap_sql_db1b85c2b7a0$ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_db1b85c2b7a0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db1b85c2b7a0$;

DO $bootstrap_do_e68cacac59cf$
BEGIN
  EXECUTE $bootstrap_sql_e68cacac59cf$-- USER_ROLES policies
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles$bootstrap_sql_e68cacac59cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e68cacac59cf$;

DO $bootstrap_do_b6b90c46d7f1$
BEGIN
  EXECUTE $bootstrap_sql_b6b90c46d7f1$CREATE POLICY "Users can view own roles"
    ON public.user_roles FOR SELECT
    USING (auth.uid() = user_id)$bootstrap_sql_b6b90c46d7f1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6b90c46d7f1$;

DO $bootstrap_do_a2431a76c2eb$
BEGIN
  EXECUTE $bootstrap_sql_a2431a76c2eb$-- PROFILES policies
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles$bootstrap_sql_a2431a76c2eb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2431a76c2eb$;

DO $bootstrap_do_bfc666879768$
BEGIN
  EXECUTE $bootstrap_sql_bfc666879768$CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin())$bootstrap_sql_bfc666879768$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bfc666879768$;

DO $bootstrap_do_44878a924b30$
BEGIN
  EXECUTE $bootstrap_sql_44878a924b30$DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles$bootstrap_sql_44878a924b30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44878a924b30$;

DO $bootstrap_do_c245bf2a0794$
BEGIN
  EXECUTE $bootstrap_sql_c245bf2a0794$CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = user_id)$bootstrap_sql_c245bf2a0794$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c245bf2a0794$;

DO $bootstrap_do_65a89c84938e$
BEGIN
  EXECUTE $bootstrap_sql_65a89c84938e$DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles$bootstrap_sql_65a89c84938e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_65a89c84938e$;

DO $bootstrap_do_962a03bb69cc$
BEGIN
  EXECUTE $bootstrap_sql_962a03bb69cc$CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id)$bootstrap_sql_962a03bb69cc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_962a03bb69cc$;

DO $bootstrap_do_8e99dc1da9dc$
BEGIN
  EXECUTE $bootstrap_sql_8e99dc1da9dc$-- VILLAGES policies (public read)
DROP POLICY IF EXISTS "Anyone can view active villages" ON public.villages$bootstrap_sql_8e99dc1da9dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e99dc1da9dc$;

DO $bootstrap_do_764ffc3d9d43$
BEGIN
  EXECUTE $bootstrap_sql_764ffc3d9d43$CREATE POLICY "Anyone can view active villages"
    ON public.villages FOR SELECT
    USING (is_active = true)$bootstrap_sql_764ffc3d9d43$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_764ffc3d9d43$;

DO $bootstrap_do_74aef0b09653$
BEGIN
  EXECUTE $bootstrap_sql_74aef0b09653$DROP POLICY IF EXISTS "Admins can manage villages" ON public.villages$bootstrap_sql_74aef0b09653$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_74aef0b09653$;

DO $bootstrap_do_cc36b138b9b8$
BEGIN
  EXECUTE $bootstrap_sql_cc36b138b9b8$CREATE POLICY "Admins can manage villages"
    ON public.villages FOR ALL
    USING (public.is_admin())$bootstrap_sql_cc36b138b9b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc36b138b9b8$;

DO $bootstrap_do_31d1eca59df1$
BEGIN
  EXECUTE $bootstrap_sql_31d1eca59df1$-- MERCHANTS policies (public read)
DROP POLICY IF EXISTS "Anyone can view active merchants" ON public.merchants$bootstrap_sql_31d1eca59df1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31d1eca59df1$;

DO $bootstrap_do_667ad9d63c64$
BEGIN
  EXECUTE $bootstrap_sql_667ad9d63c64$CREATE POLICY "Anyone can view active merchants"
    ON public.merchants FOR SELECT
    USING (status = 'ACTIVE')$bootstrap_sql_667ad9d63c64$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_667ad9d63c64$;

DO $bootstrap_do_80bfb64e6a54$
BEGIN
  EXECUTE $bootstrap_sql_80bfb64e6a54$DROP POLICY IF EXISTS "Admins can manage merchants" ON public.merchants$bootstrap_sql_80bfb64e6a54$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_80bfb64e6a54$;

DO $bootstrap_do_98a5fc09b45f$
BEGIN
  EXECUTE $bootstrap_sql_98a5fc09b45f$CREATE POLICY "Admins can manage merchants"
    ON public.merchants FOR ALL
    USING (public.is_admin())$bootstrap_sql_98a5fc09b45f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_98a5fc09b45f$;

DO $bootstrap_do_ecdd08b7e733$
BEGIN
  EXECUTE $bootstrap_sql_ecdd08b7e733$-- PRODUCTS policies (public read)
DROP POLICY IF EXISTS "Anyone can view active products" ON public.products$bootstrap_sql_ecdd08b7e733$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ecdd08b7e733$;

DO $bootstrap_do_0ad21977d0f5$
BEGIN
  EXECUTE $bootstrap_sql_0ad21977d0f5$CREATE POLICY "Anyone can view active products"
    ON public.products FOR SELECT
    USING (is_active = true)$bootstrap_sql_0ad21977d0f5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ad21977d0f5$;

DO $bootstrap_do_76b152fb3f3f$
BEGIN
  EXECUTE $bootstrap_sql_76b152fb3f3f$DROP POLICY IF EXISTS "Admins can manage products" ON public.products$bootstrap_sql_76b152fb3f3f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_76b152fb3f3f$;

DO $bootstrap_do_755b2754887a$
BEGIN
  EXECUTE $bootstrap_sql_755b2754887a$CREATE POLICY "Admins can manage products"
    ON public.products FOR ALL
    USING (public.is_admin())$bootstrap_sql_755b2754887a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_755b2754887a$;

DO $bootstrap_do_5f1036345912$
BEGIN
  EXECUTE $bootstrap_sql_5f1036345912$-- TOURISM policies (public read)
DROP POLICY IF EXISTS "Anyone can view active tourism" ON public.tourism$bootstrap_sql_5f1036345912$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5f1036345912$;

DO $bootstrap_do_68429284bfcb$
BEGIN
  EXECUTE $bootstrap_sql_68429284bfcb$CREATE POLICY "Anyone can view active tourism"
    ON public.tourism FOR SELECT
    USING (is_active = true)$bootstrap_sql_68429284bfcb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68429284bfcb$;

DO $bootstrap_do_48218ffad3cf$
BEGIN
  EXECUTE $bootstrap_sql_48218ffad3cf$DROP POLICY IF EXISTS "Admins can manage tourism" ON public.tourism$bootstrap_sql_48218ffad3cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_48218ffad3cf$;

DO $bootstrap_do_fa9ad866938d$
BEGIN
  EXECUTE $bootstrap_sql_fa9ad866938d$CREATE POLICY "Admins can manage tourism"
    ON public.tourism FOR ALL
    USING (public.is_admin())$bootstrap_sql_fa9ad866938d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa9ad866938d$;

DO $bootstrap_do_d6eb794f06be$
BEGIN
  EXECUTE $bootstrap_sql_d6eb794f06be$-- ORDERS policies
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders$bootstrap_sql_d6eb794f06be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6eb794f06be$;

DO $bootstrap_do_2cf15b932ebe$
BEGIN
  EXECUTE $bootstrap_sql_2cf15b932ebe$CREATE POLICY "Buyers can view own orders"
    ON public.orders FOR SELECT
    USING (auth.uid() = buyer_id OR public.is_admin())$bootstrap_sql_2cf15b932ebe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2cf15b932ebe$;

DO $bootstrap_do_696f89f32024$
BEGIN
  EXECUTE $bootstrap_sql_696f89f32024$DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders$bootstrap_sql_696f89f32024$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_696f89f32024$;

DO $bootstrap_do_6ffb0987b41a$
BEGIN
  EXECUTE $bootstrap_sql_6ffb0987b41a$CREATE POLICY "Buyers can create orders"
    ON public.orders FOR INSERT
    WITH CHECK (auth.uid() = buyer_id)$bootstrap_sql_6ffb0987b41a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6ffb0987b41a$;

DO $bootstrap_do_04488056bc2e$
BEGIN
  EXECUTE $bootstrap_sql_04488056bc2e$DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders$bootstrap_sql_04488056bc2e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_04488056bc2e$;

DO $bootstrap_do_7f3457a0ae3d$
BEGIN
  EXECUTE $bootstrap_sql_7f3457a0ae3d$CREATE POLICY "Buyers can update own pending orders"
    ON public.orders FOR UPDATE
    USING (auth.uid() = buyer_id AND status = 'NEW')$bootstrap_sql_7f3457a0ae3d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f3457a0ae3d$;

DO $bootstrap_do_26b720be8024$
BEGIN
  EXECUTE $bootstrap_sql_26b720be8024$DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders$bootstrap_sql_26b720be8024$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_26b720be8024$;

DO $bootstrap_do_5d0dc49d6465$
BEGIN
  EXECUTE $bootstrap_sql_5d0dc49d6465$CREATE POLICY "Admins can manage all orders"
    ON public.orders FOR ALL
    USING (public.is_admin())$bootstrap_sql_5d0dc49d6465$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d0dc49d6465$;

DO $bootstrap_do_cb9d69b2adc2$
BEGIN
  EXECUTE $bootstrap_sql_cb9d69b2adc2$-- ORDER_ITEMS policies
DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items$bootstrap_sql_cb9d69b2adc2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb9d69b2adc2$;

DO $bootstrap_do_5695d6a3d6ea$
BEGIN
  EXECUTE $bootstrap_sql_5695d6a3d6ea$CREATE POLICY "Users can view own order items"
    ON public.order_items FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND (orders.buyer_id = auth.uid() OR public.is_admin())
        )
    )$bootstrap_sql_5695d6a3d6ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5695d6a3d6ea$;

DO $bootstrap_do_20db5b1335f0$
BEGIN
  EXECUTE $bootstrap_sql_20db5b1335f0$DROP POLICY IF EXISTS "Users can insert order items for own orders" ON public.order_items$bootstrap_sql_20db5b1335f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20db5b1335f0$;

DO $bootstrap_do_4c13b88c25e5$
BEGIN
  EXECUTE $bootstrap_sql_4c13b88c25e5$CREATE POLICY "Users can insert order items for own orders"
    ON public.order_items FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND orders.buyer_id = auth.uid()
        )
    )$bootstrap_sql_4c13b88c25e5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c13b88c25e5$;

DO $bootstrap_do_f7d9846c27f2$
BEGIN
  EXECUTE $bootstrap_sql_f7d9846c27f2$-- ============================================
-- SEED DATA
-- ============================================

-- Insert sample villages
INSERT INTO public.villages (id, name, district, regency, description, is_active) VALUES
('11111111-1111-1111-1111-111111111111', 'Desa Bojong', 'Megamendung', 'Bogor', 'Desa wisata dengan pemandangan sawah terasering yang memukau dan udara sejuk pegunungan.', true),
('22222222-2222-2222-2222-222222222222', 'Desa Sukamaju', 'Cisarua', 'Sukabumi', 'Desa dengan kebun teh yang indah dan arsitektur tradisional Sunda yang masih terjaga.', true)
ON CONFLICT DO NOTHING$bootstrap_sql_f7d9846c27f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f7d9846c27f2$;

DO $bootstrap_do_e070c01aad08$
BEGIN
  EXECUTE $bootstrap_sql_e070c01aad08$-- Insert sample merchants
INSERT INTO public.merchants (id, village_id, name, address, phone, open_time, close_time, classification_price, status, order_mode, rating_avg, rating_count, badge, is_open) VALUES
('aaaa1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Warung Bu Siti', 'Jl. Sawah Indah No. 5', '081234567890', '08:00', '17:00', 'UNDER_5K', 'ACTIVE', 'ADMIN_ASSISTED', 4.8, 124, 'VERIFIED', true),
('aaaa2222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Kopi Desa', 'Jl. Perkebunan No. 12', '081234567891', '07:00', '20:00', 'FROM_10K_TO_20K', 'ACTIVE', 'SELF', 4.9, 89, 'POPULAR', true),
('aaaa3333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'Kerajinan Mandiri', 'Kampung Kriya Rt 03/02', '081234567892', '09:00', '16:00', 'ABOVE_20K', 'ACTIVE', 'ADMIN_ASSISTED', 4.7, 56, 'VERIFIED', true),
('aaaa4444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Dapur Emak', 'Jl. Kuliner Desa No. 8', '081234567893', '06:00', '18:00', 'FROM_5K_TO_10K', 'ACTIVE', 'ADMIN_ASSISTED', 4.6, 203, NULL, true)
ON CONFLICT DO NOTHING$bootstrap_sql_e070c01aad08$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e070c01aad08$;

DO $bootstrap_do_a37e39a845e0$
BEGIN
  EXECUTE $bootstrap_sql_a37e39a845e0$-- Insert sample products
INSERT INTO public.products (id, merchant_id, name, description, price, stock, category, is_active, is_promo) VALUES
('bbbb1111-1111-1111-1111-111111111111', 'aaaa1111-1111-1111-1111-111111111111', 'Keripik Pisang Manis', 'Keripik pisang renyah dengan rasa manis gurih khas desa. Dibuat dari pisang pilihan yang diolah dengan cara tradisional.', 15000, 50, 'kuliner', true, true),
('bbbb2222-2222-2222-2222-222222222222', 'aaaa2222-2222-2222-2222-222222222222', 'Kopi Bubuk Robusta', 'Kopi robusta pilihan dari kebun kopi desa, digiling halus dengan aroma yang kuat dan rasa yang nikmat.', 35000, 30, 'kuliner', true, false),
('bbbb3333-3333-3333-3333-333333333333', 'aaaa3333-3333-3333-3333-333333333333', 'Tas Anyaman Bambu', 'Tas anyaman bambu buatan tangan dengan desain modern namun tetap tradisional. Cocok untuk berbagai acara.', 75000, 15, 'kriya', true, false),
('bbbb4444-4444-4444-4444-444444444444', 'aaaa4444-4444-4444-4444-444444444444', 'Sambal Bawang Botol', 'Sambal bawang pedas gurih dalam kemasan botol, tahan lama dan cocok untuk oleh-oleh.', 20000, 100, 'kuliner', true, true)
ON CONFLICT DO NOTHING$bootstrap_sql_a37e39a845e0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a37e39a845e0$;

DO $bootstrap_do_83992b026b20$
BEGIN
  EXECUTE $bootstrap_sql_83992b026b20$-- Insert sample tourism
INSERT INTO public.tourism (id, village_id, name, description, wa_link, sosmed_link, facilities, is_active, view_count) VALUES
('cccc1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Kampung Awan & Sawah', 'Menawarkan pengalaman otentik hidup di desa dengan pemandangan sawah terasering yang memukau mata. Udara sejuk pegunungan dan keramahan warga lokal akan membuat liburan Anda tak terlupakan.', 'https://wa.me/6281234567890', 'https://instagram.com/kampungawan', ARRAY['Area Parkir Luas', 'Toilet Bersih', 'Spot Foto', 'Warung Makan', 'Mushola', 'Penginapan'], true, 1523),
('cccc2222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Kebun Teh Panorama', 'Hamparan kebun teh yang hijau dengan pemandangan pegunungan. Udara segar dan suasana tenang cocok untuk melepas penat.', 'https://wa.me/6281234567891', NULL, ARRAY['Parkir', 'Toilet', 'Warung', 'Spot Foto'], true, 892)
ON CONFLICT DO NOTHING$bootstrap_sql_83992b026b20$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83992b026b20$;

DO $bootstrap_do_cd8754722b11$
BEGIN
  EXECUTE $bootstrap_sql_cd8754722b11$
