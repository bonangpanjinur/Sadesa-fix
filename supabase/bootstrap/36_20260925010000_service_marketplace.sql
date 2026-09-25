-- Marketplace jasa lokal SaDesa
create table if not exists public.service_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  description text,
  icon text not null default 'Wrench',
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.service_subcategories (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.service_categories(id) on delete cascade,
  name text not null,
  slug text not null,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique(category_id, slug)
);

create table if not exists public.service_profiles (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null unique references auth.users(id) on delete cascade,
  provider_name text not null,
  headline text not null,
  bio text,
  village text,
  phone text,
  min_price numeric(14,2) not null default 0 check (min_price >= 0),
  rating numeric(3,2) not null default 0 check (rating between 0 and 5),
  review_count integer not null default 0,
  is_active boolean not null default true,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.service_skills (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.service_profiles(id) on delete cascade,
  subcategory_id uuid not null references public.service_subcategories(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(profile_id, subcategory_id)
);

create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete restrict,
  provider_id uuid not null references auth.users(id) on delete restrict,
  profile_id uuid not null references public.service_profiles(id) on delete restrict,
  subcategory_id uuid references public.service_subcategories(id) on delete set null,
  title text not null,
  description text not null,
  location text not null,
  agreed_price numeric(14,2) check (agreed_price is null or agreed_price >= 0),
  platform_fee numeric(14,2) not null default 0,
  transfer_fee numeric(14,2) not null default 0,
  provider_payout numeric(14,2) check (provider_payout is null or provider_payout >= 0),
  status text not null default 'NEGOTIATING' check (status in ('NEGOTIATING','WAITING_PAYMENT','PAID_TO_ADMIN','APPROVED_TO_START','IN_PROGRESS','WAITING_CONFIRMATION','COMPLETED','DISPUTED','CANCELLED','REFUNDED')),
  requester_approved boolean not null default false,
  provider_approved boolean not null default false,
  requester_completed boolean not null default false,
  provider_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.service_messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.service_requests(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  proposed_price numeric(14,2),
  created_at timestamptz not null default now()
);

create table if not exists public.service_payment_proofs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.service_requests(id) on delete cascade,
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  transfer_reference text,
  proof_url text,
  status text not null default 'PENDING' check (status in ('PENDING','VERIFIED','REJECTED')),
  admin_note text,
  created_at timestamptz not null default now(),
  verified_at timestamptz
);

create table if not exists public.service_payouts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.service_requests(id) on delete cascade,
  gross_amount numeric(14,2) not null,
  platform_fee numeric(14,2) not null default 0,
  transfer_fee numeric(14,2) not null default 0,
  net_amount numeric(14,2) not null,
  status text not null default 'PENDING' check (status in ('PENDING','RELEASED','FAILED')),
  released_by uuid references auth.users(id),
  released_at timestamptz,
  note text
);

create index if not exists idx_service_profiles_active on public.service_profiles(is_active, is_verified);
create index if not exists idx_service_skills_subcategory on public.service_skills(subcategory_id);
create index if not exists idx_service_requests_participants on public.service_requests(requester_id, provider_id, status);
create index if not exists idx_service_messages_request on public.service_messages(request_id, created_at);

insert into public.service_categories (name, slug, description, icon, sort_order) values
 ('Jasa Elektronik','elektronik','Perbaikan perangkat elektronik rumah tangga','Tv',1),
 ('Jasa Bengkel Kendaraan','bengkel-kendaraan','Servis kendaraan dan bantuan di jalan','CarFront',2),
 ('Jasa Pertukangan','pertukangan','Pekerjaan kayu, rumah, atap, dan pengecatan','Hammer',3),
 ('Jasa Kebun','kebun','Perawatan halaman, taman, dan pengangkutan sampah','Trees',4),
 ('Jasa Angkut & Pengiriman','angkut-pengiriman','Angkut barang, pindahan, dan titip belanja','Truck',5),
 ('Jasa Sewa','sewa','Sewa kendaraan dan perlengkapan acara','Armchair',6),
 ('Jasa Kesehatan & Perawatan','kesehatan-perawatan','Perawatan tubuh dan kebutuhan harian','HeartPulse',7),
 ('Jasa Pendidikan','pendidikan','Les, mengaji, komputer, dan keterampilan','GraduationCap',8)
on conflict (slug) do nothing;

insert into public.service_subcategories (category_id, name, slug, sort_order)
 select c.id, v.name, v.slug, v.sort_order from public.service_categories c join (values
 ('elektronik','Perbaikan televisi','perbaikan-televisi',1),('elektronik','Perbaikan kulkas','perbaikan-kulkas',2),('elektronik','Perbaikan kipas angin','perbaikan-kipas-angin',3),('elektronik','Servis pompa air','servis-pompa-air',4),
 ('bengkel-kendaraan','Servis motor','servis-motor',1),('bengkel-kendaraan','Servis mobil','servis-mobil',2),('bengkel-kendaraan','Ganti oli','ganti-oli',3),('bengkel-kendaraan','Tambal ban panggilan','tambal-ban-panggilan',4),('bengkel-kendaraan','Servis sepeda panggilan','servis-sepeda-panggilan',5),
 ('pertukangan','Tukang kayu','tukang-kayu',1),('pertukangan','Tukang rumah','tukang-rumah',2),('pertukangan','Pemasangan plafon','pemasangan-plafon',3),('pertukangan','Pengecatan rumah','pengecatan-rumah',4),('pertukangan','Perbaikan atap','perbaikan-atap',5),('pertukangan','Pembuatan kusen pintu & jendela','pembuatan-kusen',6),
 ('kebun','Potong rumput','potong-rumput',1),('kebun','Tebang pohon','tebang-pohon',2),('kebun','Pangkas tanaman','pangkas-tanaman',3),('kebun','Bersih-bersih halaman','bersih-halaman',4),('kebun','Pembuatan taman','pembuatan-taman',5),('kebun','Pengangkutan sampah','pengangkutan-sampah',6),('kebun','Penyemprotan hama','penyemprotan-hama',7),
 ('angkut-pengiriman','Angkut barang','angkut-barang',1),('angkut-pengiriman','Pickup atau truk desa','pickup-truk-desa',2),('angkut-pengiriman','Pindahan rumah','pindahan-rumah',3),('angkut-pengiriman','Antar hasil panen','antar-hasil-panen',4),('angkut-pengiriman','Kirim barang antardesa','kirim-antardesa',5),('angkut-pengiriman','Titip belanja dari pasar','titip-belanja-pasar',6),
 ('sewa','Sewa motor','sewa-motor',1),('sewa','Sewa mobil','sewa-mobil',2),('sewa','Sewa PlayStation','sewa-playstation',3),('sewa','Sewa kamera','sewa-kamera',4),('sewa','Sewa kursi & meja hajatan','sewa-kursi-meja',5),('sewa','Sewa tenda','sewa-tenda',6),('sewa','Sewa sound system','sewa-sound-system',7),('sewa','Sewa perlengkapan masak','sewa-perlengkapan-masak',8),
 ('kesehatan-perawatan','Pijat tradisional','pijat-tradisional',1),('kesehatan-perawatan','Pangkas rambut','pangkas-rambut',2),
 ('pendidikan','Les anak sekolah','les-anak-sekolah',1),('pendidikan','Mengaji','mengaji',2),('pendidikan','Les komputer','les-komputer',3),('pendidikan','Pelatihan keterampilan','pelatihan-keterampilan',4)
 ) as v(category_slug,name,slug,sort_order) on c.slug=v.category_slug
on conflict (category_id, slug) do nothing;

alter table public.service_categories enable row level security;
alter table public.service_subcategories enable row level security;
alter table public.service_profiles enable row level security;
alter table public.service_skills enable row level security;
alter table public.service_requests enable row level security;
alter table public.service_messages enable row level security;
alter table public.service_payment_proofs enable row level security;
alter table public.service_payouts enable row level security;

create policy "active service categories are public" on public.service_categories for select using (is_active or public.is_admin());
create policy "active service subcategories are public" on public.service_subcategories for select using (is_active or public.is_admin());
create policy "service profiles are public" on public.service_profiles for select using (is_active or provider_id = auth.uid() or public.is_admin());
create policy "providers manage own profile" on public.service_profiles for all using (provider_id = auth.uid() or public.is_admin()) with check (provider_id = auth.uid() or public.is_admin());
create policy "skills are public" on public.service_skills for select using (true);
create policy "providers manage own skills" on public.service_skills for all using (exists (select 1 from public.service_profiles p where p.id = profile_id and (p.provider_id = auth.uid() or public.is_admin()))) with check (exists (select 1 from public.service_profiles p where p.id = profile_id and (p.provider_id = auth.uid() or public.is_admin())));
create policy "participants read requests" on public.service_requests for select using (requester_id = auth.uid() or provider_id = auth.uid() or public.is_admin());
create policy "requesters create requests" on public.service_requests for insert with check (requester_id = auth.uid());
create policy "participants update requests" on public.service_requests for update using (requester_id = auth.uid() or provider_id = auth.uid() or public.is_admin()) with check (requester_id = auth.uid() or provider_id = auth.uid() or public.is_admin());
create policy "participants read messages" on public.service_messages for select using (exists (select 1 from public.service_requests r where r.id = request_id and (r.requester_id = auth.uid() or r.provider_id = auth.uid() or public.is_admin())));
create policy "participants send messages" on public.service_messages for insert with check (sender_id = auth.uid() and exists (select 1 from public.service_requests r where r.id = request_id and (r.requester_id = auth.uid() or r.provider_id = auth.uid())));
create policy "participants manage payment proofs" on public.service_payment_proofs for select using (uploaded_by = auth.uid() or exists (select 1 from public.service_requests r where r.id = request_id and (r.requester_id = auth.uid() or r.provider_id = auth.uid())) or public.is_admin());
create policy "requesters upload payment proofs" on public.service_payment_proofs for insert with check (uploaded_by = auth.uid() and exists (select 1 from public.service_requests r where r.id = request_id and r.requester_id = auth.uid()));
create policy "admins manage payment proofs" on public.service_payment_proofs for update using (public.is_admin()) with check (public.is_admin());
create policy "participants read payouts" on public.service_payouts for select using (exists (select 1 from public.service_requests r where r.id = request_id and (r.requester_id = auth.uid() or r.provider_id = auth.uid())) or public.is_admin());
create policy "admins manage payouts" on public.service_payouts for all using (public.is_admin()) with check (public.is_admin());

-- Admin-only category editing is intentionally guarded by the existing is_admin helper.
create policy "admins manage service categories" on public.service_categories for all using (public.is_admin()) with check (public.is_admin());
create policy "admins manage service subcategories" on public.service_subcategories for all using (public.is_admin()) with check (public.is_admin());
