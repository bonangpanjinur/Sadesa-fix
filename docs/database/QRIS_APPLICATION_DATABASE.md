# Dokumentasi Database Pengajuan QRIS Sadesa

**Repository:** `bonangpanjinur/Sadesa-fix`  
**Branch:** `qr_application`  
**Migration sumber:** `supabase/bootstrap/133_20261026120000_qris_merchant_application_workflow.sql`  
**Commit implementasi saat audit:** `9aac8405`

## 1. Tujuan

Fitur ini menyediakan alur pengajuan QRIS merchant dari sisi pedagang sampai penerbitan dan aktivasi QRIS oleh admin. Fitur mencakup:

- Pengajuan data usaha dan dokumen merchant.
- Review dan permintaan koreksi oleh admin.
- Persetujuan pengajuan.
- Penerbitan referensi serta aset QRIS.
- Aktivasi QRIS pada merchant.
- Audit trail perubahan status.
- Notifikasi otomatis kepada merchant.

## 2. Hasil audit duplikasi

Pencarian dilakukan terhadap seluruh file SQL di folder `supabase`, termasuk bootstrap SQL dan `manifest.json`.

### Kesimpulan

Tidak ada duplikasi definisi tabel `public.qris_applications`.

Satu-satunya definisi tabel ditemukan di:

```text
supabase/bootstrap/133_20261026120000_qris_merchant_application_workflow.sql
```

Definisi tersebut dimulai pada baris 2:

```sql
CREATE TABLE IF NOT EXISTS public.qris_applications
```

Migration QRIS juga tercatat satu kali di:

```text
supabase/bootstrap/manifest.json
```

Tabel berikut bukan duplikasi:

| Objek | Fungsi |
|---|---|
| `public.qris_applications` | Data utama pengajuan QRIS merchant |
| `public.qris_application_activity_logs` | Audit trail aktivitas/status pengajuan |
| `public.merchants.qris_image_url` | Referensi gambar QRIS yang sudah diterbitkan/ditetapkan pada merchant lama |
| Storage bucket `qris-applications` | Penyimpanan privat dokumen pengajuan |

Migration memakai `IF NOT EXISTS`, sedangkan policy dan trigger memakai `DROP ... IF EXISTS` lalu `CREATE`, sehingga aman untuk dijalankan ulang melalui mekanisme bootstrap yang benar.

## 3. Relasi data

```text
public.merchants
      │
      │ merchant_id
      ▼
public.qris_applications
      │
      │ application_id
      ▼
public.qris_application_activity_logs
```

Relasi tabel utama:

```sql
qris_applications.merchant_id
  REFERENCES public.merchants(id)
  ON DELETE CASCADE
```

Relasi audit log:

```sql
qris_application_activity_logs.application_id
  REFERENCES public.qris_applications(id)
  ON DELETE CASCADE
```

## 4. Struktur tabel `public.qris_applications`

| Kolom | Tipe | Wajib | Keterangan |
|---|---|---:|---|
| `id` | `uuid` | Ya | Primary key, default `gen_random_uuid()` |
| `application_number` | `text` | Ya | Nomor otomatis dengan format `QR-YYYYMMDD-XXXXXXXX`, unique |
| `merchant_id` | `uuid` | Ya | Relasi ke `merchants.id` |
| `applicant_user_id` | `uuid` | Ya | Relasi ke `auth.users.id`, pemilik pengajuan |
| `default_account_id` | `uuid` | Tidak | ID akun default bila terhubung ke entitas rekening |
| `default_bank_name` | `text` | Tidak | Nama bank akun default |
| `default_account_number` | `text` | Tidak | Nomor rekening default |
| `default_account_name` | `text` | Tidak | Nama pemilik rekening default |
| `business_criteria_code` | `text` | Ya | Hanya `UMI`, `UME`, atau `UBE` |
| `business_age_code` | `text` | Ya | Kode lama usaha; tidak dibatasi CHECK pada migration saat ini |
| `qris_merchant_name_short` | `varchar(25)` | Ya | Nama merchant QRIS versi pendek |
| `qris_merchant_name` | `varchar(50)` | Ya | Nama merchant QRIS lengkap |
| `documents` | `jsonb` | Ya | Metadata/path dokumen pengajuan |
| `status` | `text` | Ya | Status workflow QRIS |
| `revision_number` | `integer` | Ya | Nomor revisi, default `1` |
| `assigned_admin_id` | `uuid` | Tidak | Admin yang ditugaskan meninjau |
| `decision_by_admin_id` | `uuid` | Tidak | Admin yang memberi keputusan |
| `decision_note` | `text` | Tidak | Catatan keputusan atau koreksi |
| `qris_reference` | `text` | Tidak | Referensi QRIS setelah diterbitkan |
| `qris_asset_key` | `text` | Tidak | Key/path aset QRIS setelah diterbitkan |
| `issued_by_admin_id` | `uuid` | Tidak | Admin yang menerbitkan QRIS |
| `issued_at` | `timestamptz` | Tidak | Waktu penerbitan QRIS |
| `activated_by_admin_id` | `uuid` | Tidak | Admin yang mengaktifkan QRIS |
| `activated_at` | `timestamptz` | Tidak | Waktu aktivasi QRIS |
| `submitted_at` | `timestamptz` | Ya | Default `now()` |
| `created_at` | `timestamptz` | Ya | Default `now()` |
| `updated_at` | `timestamptz` | Ya | Default `now()` |

Index yang tersedia:

```sql
qris_applications_status_submitted_idx
  ON qris_applications(status, submitted_at DESC)

qris_applications_merchant_created_idx
  ON qris_applications(merchant_id, created_at DESC)
```

### Catatan tentang MID/NMID/MPAN

Permintaan bisnis awal menyebut field `MID`, `NMID`, dan `MPAN`. Pada migration aktual di `Sadesa-fix`, field tersebut belum dibuat sebagai kolom terpisah. Implementasi saat ini menggunakan:

- `qris_reference` untuk referensi QRIS.
- `qris_asset_key` untuk key/path aset QRIS.
- `default_account_id`, `default_bank_name`, `default_account_number`, dan `default_account_name` untuk rekening default.

Jika provider QRIS membutuhkan MID, NMID, dan MPAN sebagai data terpisah, backend perlu menambahkan migration lanjutan. Jangan membuat tabel `qris_applications` kedua; gunakan `ALTER TABLE` pada tabel yang sudah ada, misalnya:

```sql
ALTER TABLE public.qris_applications
  ADD COLUMN IF NOT EXISTS mid text,
  ADD COLUMN IF NOT EXISTS nmid text,
  ADD COLUMN IF NOT EXISTS mpan text;
```

Keputusan penambahan field tersebut harus disepakati dengan backend/provider sebelum migration baru dibuat.

## 5. Tabel audit `public.qris_application_activity_logs`

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid` | Primary key |
| `application_id` | `uuid` | FK ke `qris_applications.id` |
| `actor_user_id` | `uuid` | User yang melakukan aktivitas |
| `actor_role` | `text` | `merchant` atau `admin` |
| `action` | `text` | Jenis aktivitas |
| `from_status` | `text` | Status sebelumnya |
| `to_status` | `text` | Status setelah perubahan |
| `reason` | `text` | Alasan/catatan |
| `metadata` | `jsonb` | Data tambahan, default `{}` |
| `occurred_at` | `timestamptz` | Waktu aktivitas |

Index:

```sql
qris_activity_application_time_idx
  ON qris_application_activity_logs(application_id, occurred_at DESC)
```

## 6. Status dan transisi workflow

Status yang tersedia:

```text
SUBMITTED
IN_REVIEW
NEEDS_CORRECTION
REJECTED
APPROVED_PENDING_ISSUANCE
ISSUED_PENDING_ACTIVATION
ACTIVE
```

Transisi yang diizinkan:

```text
SUBMITTED → IN_REVIEW
SUBMITTED → NEEDS_CORRECTION
SUBMITTED → REJECTED
SUBMITTED → APPROVED_PENDING_ISSUANCE

IN_REVIEW → IN_REVIEW
IN_REVIEW → NEEDS_CORRECTION
IN_REVIEW → REJECTED
IN_REVIEW → APPROVED_PENDING_ISSUANCE

APPROVED_PENDING_ISSUANCE → ISSUED_PENDING_ACTIVATION
ISSUED_PENDING_ACTIVATION → ACTIVE

NEEDS_CORRECTION → SUBMITTED       (merchant mengirim ulang)
```

Validasi transisi ditegakkan oleh trigger:

```text
public.enforce_qris_application_transition()
```

Merchant tidak dapat mengubah status secara bebas. Merchant hanya dapat memperbarui pengajuan ketika status `NEEDS_CORRECTION`, lalu mengirim ulang ke `SUBMITTED`.

Merchant juga tidak dapat mengubah data penerbitan QRIS seperti:

- `qris_reference`
- `qris_asset_key`
- `issued_by_admin_id`
- `activated_by_admin_id`

## 7. Audit trail dan notifikasi

Trigger berikut mencatat seluruh aktivitas:

```text
public.log_qris_application_activity()
```

Aktivitas yang dicatat antara lain:

| Status | Action |
|---|---|
| Insert | `APPLICATION_SUBMITTED` |
| `IN_REVIEW` | `REVIEW_STARTED` |
| `NEEDS_CORRECTION` | `CORRECTION_REQUESTED` |
| `REJECTED` | `APPLICATION_REJECTED` |
| `APPROVED_PENDING_ISSUANCE` | `APPLICATION_APPROVED` |
| `ISSUED_PENDING_ACTIVATION` | `QRIS_ISSUED` |
| `ACTIVE` | `QRIS_ACTIVATED` |
| `SUBMITTED` setelah koreksi | `APPLICATION_RESUBMITTED` |

Trigger juga membuat notifikasi pada tabel `public.notifications` dengan tipe:

```text
qris
```

Link notifikasi saat ini:

```text
/merchant/settings
```

## 8. Storage dokumen

Bucket:

```text
qris-applications
```

Konfigurasi:

```text
public: false
maksimum file: 2 MB
MIME: image/jpeg, image/png
```

Akses storage dibatasi oleh policy:

- Merchant dapat upload hanya pada folder yang diawali `auth.uid()` miliknya.
- Merchant dapat membaca file miliknya.
- Admin dapat membaca file seluruh pengajuan.
- Merchant dapat mengganti dan menghapus file miliknya.
- Bucket tidak public.

Dokumen sensitif seperti KTP dan selfie tidak boleh diubah menjadi public URL. Gunakan signed URL untuk kebutuhan review admin.

## 9. RLS database

### Merchant

Merchant dapat:

- Membaca pengajuan miliknya melalui `applicant_user_id = auth.uid()`.
- Membuat pengajuan jika `applicant_user_id` sama dengan user login dan `merchant_id` memang miliknya.
- Memperbarui pengajuan hanya ketika status `NEEDS_CORRECTION`.

### Admin

Admin dapat:

- Membaca semua pengajuan.
- Membuat, memperbarui, dan mengelola seluruh pengajuan.
- Membaca audit log semua pengajuan.
- Menjalankan fungsi penerbitan dan aktivasi QRIS.

Fungsi otorisasi yang digunakan:

```sql
public.is_admin()
```

Pastikan fungsi tersebut tersedia pada environment Supabase target.

## 10. Fungsi admin

### Penerbitan QRIS

```sql
public.admin_issue_qris(
  p_application_id uuid,
  p_qris_reference text,
  p_qris_asset_key text
)
```

Syarat:

- Caller adalah admin.
- `p_qris_reference` tidak kosong.
- `p_qris_asset_key` tidak kosong.
- Status pengajuan harus `APPROVED_PENDING_ISSUANCE`.

Efek:

1. Mengisi `merchants.qris_image_url` dengan `p_qris_asset_key`.
2. Mengubah status menjadi `ISSUED_PENDING_ACTIVATION`.
3. Mengisi admin penerbit dan waktu penerbitan.

### Aktivasi QRIS

```sql
public.admin_activate_qris(
  p_application_id uuid
)
```

Syarat:

- Caller adalah admin.
- Status harus `ISSUED_PENDING_ACTIVATION`.
- `qris_reference` dan `qris_asset_key` harus tersedia.
- `merchants.qris_image_url` harus sama dengan `qris_asset_key`.

Efek:

- Mengubah status menjadi `ACTIVE`.
- Mengisi `activated_by_admin_id` dan `activated_at`.

## 11. Keamanan tambahan pada `merchants.qris_image_url`

Trigger berikut mencegah merchant mengubah sendiri gambar QRIS yang ditetapkan admin:

```text
public.protect_merchant_qris_assignment_trigger
```

Hanya admin yang boleh mengubah `merchants.qris_image_url`.

## 12. Deployment dan verifikasi

Migration ini adalah bootstrap migration. Ikuti urutan deployment repository dan pastikan file terdaftar di `supabase/bootstrap/manifest.json`.

Setelah deployment, verifikasi:

```sql
SELECT to_regclass('public.qris_applications');
SELECT to_regclass('public.qris_application_activity_logs');

SELECT id, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id = 'qris-applications';
```

Verifikasi tidak ada definisi tabel ganda dari source repository:

```bash
grep -RniE \
  "CREATE TABLE( IF NOT EXISTS)?[[:space:]]+(public\\.)?qris_applications" \
  supabase --include='*.sql'
```

Hasil yang diharapkan hanya satu file:

```text
supabase/bootstrap/133_20261026120000_qris_merchant_application_workflow.sql
```

## 13. Acceptance criteria

- `qris_applications` hanya memiliki satu definisi pada source SQL.
- `qris_application_activity_logs` memiliki FK ke `qris_applications`.
- Merchant tidak dapat mengakses pengajuan merchant lain.
- Admin dapat mengelola pengajuan dan membaca dokumen privat.
- Merchant hanya dapat mengirim ulang pengajuan berstatus `NEEDS_CORRECTION`.
- Transisi status ilegal ditolak oleh trigger database.
- Setiap perubahan status tercatat pada activity log.
- Notifikasi dibuat untuk merchant pada perubahan status.
- QRIS hanya dapat diterbitkan melalui fungsi admin.
- QRIS hanya dapat menjadi `ACTIVE` setelah aset terpasang pada merchant.
- Tidak ada migration kedua yang membuat `qris_applications`.
