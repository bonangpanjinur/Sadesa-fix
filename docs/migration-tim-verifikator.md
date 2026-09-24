# Detail SQL Migration Tim Verifikator

## Status rancangan

Dokumen ini sekarang menjadi **rancangan sekaligus kontrak implementasi**. Migration aktif berada pada `supabase/bootstrap/35_20260925002000_verifikator_teams_workflow.sql`. SQL sudah dibuat idempotent, tetapi penerapan ke database tetap harus melalui pipeline deployment Supabase yang digunakan proyek. Seed anggota, tim, dan scope wilayah tetap memerlukan data operasional yang disepakati oleh admin.

Rancangan mempertahankan kolom lama seperti `verifikator_id` dan `verifikator_code` agar data existing tetap kompatibel. Lapisan baru menambahkan kepemilikan tim, keanggotaan, scope wilayah, antrean kasus, assignment, dan audit trail.

## 1. Konsep data

Struktur baru menggunakan lima lapisan:

1. **`verifikator_teams`** menyimpan identitas tim dan koordinator.
2. **`verifikator_team_members`** menyimpan anggota aktif dan role operasionalnya.
3. **`verifikator_team_scopes`** menyimpan desa atau wilayah yang boleh dikelola tim.
4. **`verifikator_codes.team_id`** menghubungkan kode referral ke tim, sementara `verifikator_id` lama tetap dipertahankan sebagai pemilik atau koordinator.
5. **`verification_cases`** dan **`verification_case_events`** mengelola antrean, assignment, keputusan, eskalasi, dan audit log.

Workspace frontend tersedia pada route `/verifikator/team`. Halaman tersebut menampilkan ringkasan tim, antrean kasus, anggota, scope wilayah, tombol claim kasus, dan aksi review dasar yang memanggil RPC terproteksi. Tab **Analitik individu** menghitung total kasus per anggota, kasus selesai, kasus berjalan, kasus lewat SLA, tingkat penyelesaian SLA, approval rate, rata-rata waktu penyelesaian, dan kasus yang belum memiliki assignment. Metrik individu dihitung berdasarkan `assigned_to`, sedangkan waktu penyelesaian menggunakan selisih `reviewed_at - submitted_at`.

Relasi utamanya adalah:

```text
verifikator_teams
  ├── verifikator_team_members ──► auth.users
  ├── verifikator_team_scopes ───► villages
  ├── verifikator_codes
  └── verification_cases
        ├── merchants
        └── couriers
```

## 2. Enum dan tipe terkontrol

Untuk database yang sudah besar, `text` dengan `CHECK` lebih mudah diperluas daripada PostgreSQL enum. Nilai role aplikasi tetap tidak berubah. Nilai berikut adalah role **operasional tim**, bukan role login.

```sql
CREATE TABLE IF NOT EXISTS public.verifikator_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  lead_verifikator_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verifikator_teams_name_check
    CHECK (length(trim(name)) BETWEEN 2 AND 120)
);

CREATE TABLE IF NOT EXISTS public.verifikator_team_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.verifikator_teams(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  joined_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verifikator_team_members_role_check
    CHECK (role IN ('LEAD', 'MERCHANT_REVIEWER', 'COURIER_REVIEWER', 'QUALITY_CONTROL')),
  CONSTRAINT verifikator_team_members_dates_check
    CHECK (ended_at IS NULL OR ended_at >= joined_at),
  CONSTRAINT verifikator_team_members_active_dates_check
    CHECK (is_active OR ended_at IS NOT NULL),
  CONSTRAINT verifikator_team_members_unique_user_per_team
    UNIQUE (team_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.verifikator_team_scopes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.verifikator_teams(id) ON DELETE CASCADE,
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE RESTRICT,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verifikator_team_scopes_unique_scope
    UNIQUE (team_id, village_id)
);
```

### Indeks keanggotaan dan scope

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_verifikator_team_one_active_lead
  ON public.verifikator_team_members(team_id)
  WHERE role = 'LEAD' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_verifikator_team_members_user_active
  ON public.verifikator_team_members(user_id, is_active, team_id);

CREATE INDEX IF NOT EXISTS idx_verifikator_team_scopes_village_active
  ON public.verifikator_team_scopes(village_id, is_active, team_id);

CREATE INDEX IF NOT EXISTS idx_verifikator_teams_lead_active
  ON public.verifikator_teams(lead_verifikator_id, is_active);
```

> **Catatan constraint:** `lead_verifikator_id` perlu dipastikan juga memiliki membership aktif dengan role `LEAD`. Pemeriksaan tersebut tidak dapat dibuat sebagai `CHECK` biasa karena melibatkan tabel lain. Gunakan trigger atau fungsi admin untuk membuat dan mengganti koordinator secara atomik.

## 3. Menambahkan tim ke kode referral

Kolom ini dibuat nullable agar kode lama tetap dapat dibaca sebelum proses backfill selesai.

```sql
ALTER TABLE public.verifikator_codes
  ADD COLUMN IF NOT EXISTS team_id uuid
    REFERENCES public.verifikator_teams(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_by uuid
    REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_verifikator_codes_team_active
  ON public.verifikator_codes(team_id, is_active);

CREATE INDEX IF NOT EXISTS idx_verifikator_codes_owner_active
  ON public.verifikator_codes(verifikator_id, is_active);
```

Selama masa transisi, aturan pembacaan kode adalah:

```text
team_id terisi  → gunakan scope dan membership tim
team_id kosong  → gunakan verifikator_id lama
```

Setelah seluruh kode berhasil di-backfill, `team_id` dapat diwajibkan untuk kode baru melalui policy atau constraint deployment berikutnya. Kode lama tidak perlu kehilangan pemilik historisnya.

## 4. Kolom tim pada merchant dan courier

Kolom ini mempercepat query laporan dan menyimpan hasil resolusi kode pada saat registrasi. Relasi tetap menyimpan `verifikator_code` untuk audit dan kompatibilitas.

```sql
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS verifikator_team_id uuid
    REFERENCES public.verifikator_teams(id) ON DELETE SET NULL;

ALTER TABLE public.couriers
  ADD COLUMN IF NOT EXISTS verifikator_team_id uuid
    REFERENCES public.verifikator_teams(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_merchants_verifikator_team
  ON public.merchants(verifikator_team_id, registration_status);

CREATE INDEX IF NOT EXISTS idx_couriers_verifikator_team
  ON public.couriers(verifikator_team_id, registration_status);
```

### Fungsi resolusi referral

Resolusi dilakukan di server atau trigger. Client tidak boleh mengirim `verifikator_team_id` sebagai nilai yang dipercaya.

```sql
CREATE OR REPLACE FUNCTION public.resolve_verifikator_team(p_code text)
RETURNS TABLE (
  code text,
  verifikator_id uuid,
  team_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT vc.code, vc.verifikator_id, vc.team_id
  FROM public.verifikator_codes AS vc
  WHERE vc.code = upper(trim(p_code))
    AND vc.is_active = true
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.resolve_verifikator_team(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_verifikator_team(text) TO authenticated;
```

Trigger merchant dan courier yang sudah ada dapat diperluas agar mengisi `verifikator_team_id` dari hasil kode. Bila kode tidak memiliki tim, kolom team tetap `NULL` dan data tetap menggunakan `verifikator_id` lama.

## 5. Antrean kasus verifikasi

Tabel kasus menyatukan workflow merchant dan courier. Constraint memastikan satu kasus hanya terkait dengan salah satu jenis entitas.

```sql
CREATE TABLE IF NOT EXISTS public.verification_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_type text NOT NULL,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
  courier_id uuid REFERENCES public.couriers(id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES public.verifikator_teams(id) ON DELETE RESTRICT,
  village_id uuid REFERENCES public.villages(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'PENDING',
  risk_level text NOT NULL DEFAULT 'NORMAL',
  assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_at timestamptz,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  decision_reason text,
  due_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verification_cases_type_check
    CHECK (case_type IN ('MERCHANT', 'COURIER')),
  CONSTRAINT verification_cases_status_check
    CHECK (status IN ('PENDING', 'IN_REVIEW', 'NEED_REVISION', 'READY_FOR_APPROVAL', 'APPROVED', 'REJECTED', 'ESCALATED', 'CLOSED')),
  CONSTRAINT verification_cases_risk_check
    CHECK (risk_level IN ('NORMAL', 'ELEVATED', 'HIGH')),
  CONSTRAINT verification_cases_one_subject_check
    CHECK ((case_type = 'MERCHANT' AND merchant_id IS NOT NULL AND courier_id IS NULL)
        OR (case_type = 'COURIER' AND courier_id IS NOT NULL AND merchant_id IS NULL)),
  CONSTRAINT verification_cases_decision_reason_check
    CHECK (status NOT IN ('REJECTED', 'NEED_REVISION', 'ESCALATED') OR length(trim(decision_reason)) >= 3)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_verification_cases_open_merchant
  ON public.verification_cases(merchant_id)
  WHERE merchant_id IS NOT NULL
    AND status NOT IN ('APPROVED', 'REJECTED', 'CLOSED');

CREATE UNIQUE INDEX IF NOT EXISTS uq_verification_cases_open_courier
  ON public.verification_cases(courier_id)
  WHERE courier_id IS NOT NULL
    AND status NOT IN ('APPROVED', 'REJECTED', 'CLOSED');

CREATE INDEX IF NOT EXISTS idx_verification_cases_team_queue
  ON public.verification_cases(team_id, status, risk_level, due_at, submitted_at);

CREATE INDEX IF NOT EXISTS idx_verification_cases_assignee
  ON public.verification_cases(assigned_to, status, due_at);

CREATE INDEX IF NOT EXISTS idx_verification_cases_audit_period
  ON public.verification_cases(team_id, created_at, reviewed_at);
```

`verification_cases` menjadi sumber antrean. Tabel `merchants` dan `couriers` tetap menjadi sumber data domain dan status akhir. Keputusan final harus tetap diproses melalui RPC khusus, bukan update bebas dari client.

## 6. Event dan audit log

Assignment, perubahan status, keputusan, eskalasi, dan perubahan reviewer harus dicatat sebagai event append-only.

```sql
CREATE TABLE IF NOT EXISTS public.verification_case_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES public.verification_cases(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  from_status text,
  to_status text,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verification_case_events_type_check
    CHECK (event_type IN ('CREATED', 'ASSIGNED', 'REASSIGNED', 'STATUS_CHANGED', 'DECIDED', 'ESCALATED', 'NOTE_ADDED', 'SLA_BREACHED'))
);

CREATE INDEX IF NOT EXISTS idx_verification_case_events_case_time
  ON public.verification_case_events(case_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_verification_case_events_actor_time
  ON public.verification_case_events(actor_id, created_at DESC);
```

Tidak boleh ada policy `UPDATE` atau `DELETE` untuk anggota tim pada tabel event. Koreksi audit dilakukan melalui event baru dengan `event_type = 'NOTE_ADDED'` atau event koreksi khusus.

## 7. Fungsi pemeriksaan kewenangan

Semua policy dan RPC sebaiknya memakai helper yang sama agar aturan tidak berbeda antara frontend dan database.

```sql
CREATE OR REPLACE FUNCTION public.is_active_verifikator_team_member(
  p_team_id uuid,
  p_roles text[] DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.verifikator_team_members AS tm
    JOIN public.profiles AS p ON p.user_id = tm.user_id
    WHERE tm.team_id = p_team_id
      AND tm.user_id = auth.uid()
      AND tm.is_active = true
      AND p.role IN ('verifikator', 'admin')
      AND (p_roles IS NULL OR tm.role = ANY(p_roles))
  );
$$;

CREATE OR REPLACE FUNCTION public.team_has_village_scope(
  p_team_id uuid,
  p_village_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.verifikator_team_scopes AS ts
    WHERE ts.team_id = p_team_id
      AND ts.village_id = p_village_id
      AND ts.is_active = true
  );
$$;

REVOKE ALL ON FUNCTION public.is_active_verifikator_team_member(uuid, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.team_has_village_scope(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_verifikator_team_member(uuid, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.team_has_village_scope(uuid, uuid) TO authenticated;
```

Jika tabel profil di deployment menggunakan fungsi role yang berbeda, helper harus menyesuaikan nama tabel atau fungsi tersebut. Jangan mengandalkan hanya `auth.uid()` dan role global karena hal tersebut tidak membatasi wilayah.

## 8. RLS untuk tim, scope, kasus, dan event

```sql
ALTER TABLE public.verifikator_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verifikator_team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verifikator_team_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_case_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Team members can view own teams"
  ON public.verifikator_teams FOR SELECT
  USING (public.is_active_verifikator_team_member(id, NULL));

CREATE POLICY "Team members can view own membership"
  ON public.verifikator_team_members FOR SELECT
  USING (public.is_active_verifikator_team_member(team_id, NULL));

CREATE POLICY "Team members can view own scopes"
  ON public.verifikator_team_scopes FOR SELECT
  USING (public.is_active_verifikator_team_member(team_id, NULL));

CREATE POLICY "Team members can view scoped cases"
  ON public.verification_cases FOR SELECT
  USING (
    public.is_active_verifikator_team_member(team_id, NULL)
    AND (village_id IS NULL OR public.team_has_village_scope(team_id, village_id))
  );

CREATE POLICY "Assigned reviewers can update cases"
  ON public.verification_cases FOR UPDATE
  USING (
    public.is_active_verifikator_team_member(
      team_id,
      ARRAY['LEAD', 'MERCHANT_REVIEWER', 'COURIER_REVIEWER']
    )
    AND (
      assigned_to = auth.uid()
      OR public.is_active_verifikator_team_member(team_id, ARRAY['LEAD'])
    )
  )
  WITH CHECK (
    public.is_active_verifikator_team_member(team_id, ARRAY['LEAD', 'MERCHANT_REVIEWER', 'COURIER_REVIEWER'])
  );

CREATE POLICY "Team members can view case events"
  ON public.verification_case_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.verification_cases AS vc
      WHERE vc.id = case_id
        AND public.is_active_verifikator_team_member(vc.team_id, NULL)
    )
  );
```

Untuk production, policy `UPDATE` sebaiknya diganti dengan RPC `review_verification_case`. RPC dapat memvalidasi transisi status, jenis kasus, scope wilayah, role anggota, alasan keputusan, dan field yang boleh berubah. Client tidak boleh dapat mengubah `team_id`, `case_type`, `merchant_id`, atau `courier_id` melalui update langsung.

Admin pusat tetap dapat diberi policy penuh melalui fungsi `is_admin()`. Policy admin harus didefinisikan terpisah dan tidak digabung dengan policy anggota tim agar audit kewenangan tetap jelas.

## 9. RPC assignment dan keputusan

Contoh kontrak RPC untuk pengambilan kasus:

```sql
CREATE OR REPLACE FUNCTION public.claim_verification_case(p_case_id uuid)
RETURNS public.verification_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.verification_cases;
BEGIN
  SELECT * INTO v_case
  FROM public.verification_cases
  WHERE id = p_case_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verification case not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_active_verifikator_team_member(v_case.team_id, ARRAY['LEAD', 'MERCHANT_REVIEWER', 'COURIER_REVIEWER']) THEN
    RAISE EXCEPTION 'User is not allowed to claim this case' USING ERRCODE = '42501';
  END IF;

  IF v_case.status NOT IN ('PENDING', 'ESCALATED') THEN
    RAISE EXCEPTION 'Case is not available for claiming' USING ERRCODE = '55000';
  END IF;

  UPDATE public.verification_cases
  SET status = 'IN_REVIEW',
      assigned_to = auth.uid(),
      assigned_at = now(),
      updated_at = now()
  WHERE id = p_case_id
  RETURNING * INTO v_case;

  INSERT INTO public.verification_case_events
    (case_id, event_type, from_status, to_status, actor_id, assigned_to)
  VALUES
    (p_case_id, 'ASSIGNED', 'PENDING', 'IN_REVIEW', auth.uid(), auth.uid());

  RETURN v_case;
END;
$$;
```

Untuk `review_verification_case`, aturan minimum adalah:

```text
MERCHANT_REVIEWER   → hanya case_type MERCHANT
COURIER_REVIEWER    → hanya case_type COURIER
QUALITY_CONTROL     → read-only dan memberi event temuan
LEAD                → dapat menangani dua jenis kasus dan eskalasi
ADMIN               → dapat menangani semua wilayah
```

RPC keputusan juga harus menulis perubahan pada tabel domain. Misalnya, approval merchant mengubah field approval merchant dan case secara atomik. Jika salah satu update gagal, seluruh transaksi harus rollback.

## 10. Backfill data existing

Backfill harus dilakukan setelah tabel dan policy tersedia. Jangan langsung mengisi semua data dengan asumsi satu tim tanpa daftar wilayah yang disetujui.

```sql
-- Contoh: membuat tim awal. Jalankan dengan user admin atau service role.
INSERT INTO public.verifikator_teams
  (name, description, lead_verifikator_id)
VALUES
  ('Tim Verifikator Daerah A', 'Tim operasional wilayah Daerah A', :lead_verifikator_id)
RETURNING id;

-- Hubungkan kode lama ke tim.
UPDATE public.verifikator_codes
SET team_id = :team_id,
    updated_at = now()
WHERE verifikator_id IN (:lead_verifikator_id, :member_2, :member_3, :member_4)
  AND team_id IS NULL;

-- Sinkronkan merchant yang memiliki kode tim.
UPDATE public.merchants AS m
SET verifikator_team_id = vc.team_id
FROM public.verifikator_codes AS vc
WHERE upper(m.verifikator_code) = vc.code
  AND vc.team_id IS NOT NULL
  AND m.verifikator_team_id IS NULL;

-- Sinkronkan courier dengan cara yang sama.
UPDATE public.couriers AS c
SET verifikator_team_id = vc.team_id
FROM public.verifikator_codes AS vc
WHERE upper(c.verifikator_code) = vc.code
  AND vc.team_id IS NOT NULL
  AND c.verifikator_team_id IS NULL;
```

Placeholder seperti `:team_id` harus diganti oleh migration runner atau RPC admin. Nilai tersebut tidak boleh dikirim dari browser sebagai kewenangan yang dipercaya.

Pembuatan kasus awal dapat dilakukan dengan fungsi idempotent yang hanya membuat kasus bila belum ada kasus terbuka untuk merchant atau courier tersebut. Jangan membuat duplicate case setiap kali migration dijalankan.

## 11. Urutan rollout yang aman

| Fase | Perubahan | Risiko yang dikendalikan |
|---|---|---|
| 1 | Buat tabel tim, membership, scope, dan indeks | Tidak mengubah alur existing |
| 2 | Tambah `team_id` nullable pada kode, merchant, dan courier | Kompatibilitas data lama |
| 3 | Buat helper scope dan RLS `SELECT` | Akses baca terbatas |
| 4 | Backfill tim dan scope melalui admin | Mencegah assignment salah wilayah |
| 5 | Buat antrean kasus dan backfill kasus terbuka | Migrasi workflow bertahap |
| 6 | Aktifkan RPC claim/review | Mencegah update status bebas |
| 7 | Migrasikan UI antrean dan dashboard KPI | Penggunaan operasional |
| 8 | Wajibkan `team_id` untuk kode baru | Menutup data baru tanpa tim |

Selama fase transisi, mode legacy dapat dipertahankan untuk verifikator yang belum masuk tim. Namun mode legacy harus diberi tanggal penghentian agar tidak menjadi jalur permanen yang melewati scope wilayah.

## 12. Test penerimaan migration

Migration dianggap siap jika seluruh kondisi berikut lulus:

1. Anggota aktif hanya dapat membaca tim dan scope tempat ia terdaftar.
2. Anggota dari Daerah A tidak dapat membaca kasus Daerah B.
3. Admin Merchant tidak dapat mengambil case `COURIER`.
4. Admin Ojek tidak dapat mengambil case `MERCHANT`.
5. Admin QC dapat membaca dan memberi temuan, tetapi tidak dapat mengubah keputusan langsung.
6. Koordinator dapat mengambil alih kasus normal dan kasus eskalasi dalam scope timnya.
7. Admin pusat dapat melihat seluruh tim.
8. Kasus tidak dapat memiliki `merchant_id` dan `courier_id` sekaligus.
9. Kasus yang ditolak, dikembalikan, atau dieskalasikan wajib memiliki alasan.
10. Setiap assignment dan keputusan menghasilkan satu atau lebih baris audit event.
11. User yang dinonaktifkan dari membership kehilangan akses tanpa menghapus histori.
12. Backfill dapat dijalankan ulang tanpa membuat duplicate team, membership, kode, atau kasus terbuka.

## Kesimpulan

Migration ini membedakan tiga hal yang sebelumnya tercampur: **siapa pemilik kode**, **siapa anggota tim yang memeriksa**, dan **wilayah mana yang boleh dikelola**. Pemisahan tersebut penting untuk laporan fee, pembagian tugas, audit, dan keamanan.

Kolom lama tetap dipertahankan. `team_id`, membership, scope, dan case workflow ditambahkan secara nullable dan bertahap. Setelah backfill serta pengujian selesai, workflow approval harus dipindahkan ke RPC terproteksi dan policy berbasis scope.

## References

[1]: https://github.com/bonangpanjinur/Sadesa-fix "Repository SaDesa-fix"
