-- Village tourism feature contract.
-- The frontend uses these tables; keep this migration idempotent so it can be
-- replayed by the canonical bootstrap deployment.

ALTER TABLE public.villages
  ADD COLUMN IF NOT EXISTS province_code text,
  ADD COLUMN IF NOT EXISTS regency_code text,
  ADD COLUMN IF NOT EXISTS district_code text,
  ADD COLUMN IF NOT EXISTS village_code text,
  ADD COLUMN IF NOT EXISTS subdistrict text,
  ADD COLUMN IF NOT EXISTS gallery_urls text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS social_media jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS website text,
  ADD COLUMN IF NOT EXISTS qr_code_url text;

CREATE TABLE IF NOT EXISTS public.tourism_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  description text,
  image_url text,
  price numeric NOT NULL DEFAULT 0 CHECK (price >= 0),
  duration_days integer NOT NULL DEFAULT 1 CHECK (duration_days BETWEEN 1 AND 365),
  min_persons integer NOT NULL DEFAULT 1 CHECK (min_persons >= 1),
  max_persons integer NOT NULL DEFAULT 20 CHECK (max_persons >= min_persons),
  includes text[] NOT NULL DEFAULT '{}',
  itinerary jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  guide_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tourism_guides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  phone text,
  specialization text,
  languages text[] NOT NULL DEFAULT '{}',
  photo_url text,
  daily_rate numeric NOT NULL DEFAULT 0 CHECK (daily_rate >= 0),
  bio text,
  is_available boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.tourism_packages
  DROP CONSTRAINT IF EXISTS tourism_packages_guide_id_fkey;
ALTER TABLE public.tourism_packages
  ADD CONSTRAINT tourism_packages_guide_id_fkey FOREIGN KEY (guide_id)
  REFERENCES public.tourism_guides(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.tourism_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid REFERENCES public.tourism_packages(id) ON DELETE SET NULL,
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  guide_id uuid REFERENCES public.tourism_guides(id) ON DELETE SET NULL,
  visit_date date NOT NULL,
  persons integer NOT NULL CHECK (persons >= 1),
  total_price numeric NOT NULL DEFAULT 0 CHECK (total_price >= 0),
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED')),
  payment_status text NOT NULL DEFAULT 'UNPAID' CHECK (payment_status IN ('UNPAID', 'PAID', 'REFUNDED')),
  notes text,
  contact_name text NOT NULL,
  contact_phone text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.village_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  description text,
  event_type text NOT NULL DEFAULT 'lainnya',
  location text,
  start_date date NOT NULL,
  end_date date,
  organizer text,
  status text NOT NULL DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'ongoing', 'completed', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS public.donation_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 180),
  description text,
  story text,
  image_url text,
  target_amount numeric NOT NULL CHECK (target_amount > 0),
  current_amount numeric NOT NULL DEFAULT 0 CHECK (current_amount >= 0),
  donor_count integer NOT NULL DEFAULT 0 CHECK (donor_count >= 0),
  category text NOT NULL DEFAULT 'lainnya',
  deadline date,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.donations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.donation_campaigns(id) ON DELETE CASCADE,
  donor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  amount numeric NOT NULL CHECK (amount > 0),
  message text,
  is_anonymous boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PAID', 'CANCELLED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tourism_packages_village ON public.tourism_packages(village_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tourism_guides_village ON public.tourism_guides(village_id, name);
CREATE INDEX IF NOT EXISTS idx_tourism_bookings_village ON public.tourism_bookings(village_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_village_events_village ON public.village_events(village_id, start_date DESC);
CREATE INDEX IF NOT EXISTS idx_donation_campaigns_village ON public.donation_campaigns(village_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_donations_campaign ON public.donations(campaign_id, created_at DESC);

ALTER TABLE public.tourism_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tourism_guides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tourism_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.village_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donation_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donations ENABLE ROW LEVEL SECURITY;

-- Public read paths.
DROP POLICY IF EXISTS "Public can view active tourism packages" ON public.tourism_packages;
CREATE POLICY "Public can view active tourism packages" ON public.tourism_packages
  FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Public can view available guides" ON public.tourism_guides;
CREATE POLICY "Public can view available guides" ON public.tourism_guides
  FOR SELECT USING (is_available = true);
DROP POLICY IF EXISTS "Public can view village events" ON public.village_events;
CREATE POLICY "Public can view village events" ON public.village_events
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public can view active campaigns" ON public.donation_campaigns;
CREATE POLICY "Public can view active campaigns" ON public.donation_campaigns
  FOR SELECT USING (is_active = true);

-- Admin desa ownership helper is intentionally repeated in each policy so RLS
-- remains correct even when a user is assigned to more than one village.
DROP POLICY IF EXISTS "Village admins manage tourism packages" ON public.tourism_packages;
CREATE POLICY "Village admins manage tourism packages" ON public.tourism_packages
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_packages.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_packages.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));
DROP POLICY IF EXISTS "Village admins manage tourism guides" ON public.tourism_guides;
CREATE POLICY "Village admins manage tourism guides" ON public.tourism_guides
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_guides.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_guides.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));
DROP POLICY IF EXISTS "Village admins manage village events" ON public.village_events;
CREATE POLICY "Village admins manage village events" ON public.village_events
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = village_events.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = village_events.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));
DROP POLICY IF EXISTS "Village admins manage donation campaigns" ON public.donation_campaigns;
CREATE POLICY "Village admins manage donation campaigns" ON public.donation_campaigns
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = donation_campaigns.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = donation_campaigns.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));

DROP POLICY IF EXISTS "Buyers view own tourism bookings" ON public.tourism_bookings;
CREATE POLICY "Buyers view own tourism bookings" ON public.tourism_bookings FOR SELECT USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Buyers create tourism bookings" ON public.tourism_bookings;
CREATE POLICY "Buyers create tourism bookings" ON public.tourism_bookings FOR INSERT WITH CHECK (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Village admins manage tourism bookings" ON public.tourism_bookings;
CREATE POLICY "Village admins manage tourism bookings" ON public.tourism_bookings
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_bookings.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_bookings.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));

DROP POLICY IF EXISTS "Public can view donations" ON public.donations;
CREATE POLICY "Public can view donations" ON public.donations FOR SELECT USING (status = 'PAID');
DROP POLICY IF EXISTS "Authenticated users create donations" ON public.donations;
CREATE POLICY "Authenticated users create donations" ON public.donations FOR INSERT WITH CHECK (donor_id IS NULL OR donor_id = auth.uid());
DROP POLICY IF EXISTS "Village admins view campaign donations" ON public.donations;
CREATE POLICY "Village admins view campaign donations" ON public.donations FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.donation_campaigns c JOIN public.user_villages uv ON uv.village_id = c.village_id WHERE c.id = donations.campaign_id AND (public.is_admin() OR (uv.user_id = auth.uid() AND uv.role = 'admin_desa')))
);

GRANT SELECT ON public.tourism_packages, public.tourism_guides, public.village_events, public.donation_campaigns, public.donations TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tourism_packages, public.tourism_guides, public.tourism_bookings, public.village_events, public.donation_campaigns, public.donations TO authenticated;
GRANT ALL ON public.tourism_packages, public.tourism_guides, public.tourism_bookings, public.village_events, public.donation_campaigns, public.donations TO service_role;
NOTIFY pgrst, 'reload schema';
