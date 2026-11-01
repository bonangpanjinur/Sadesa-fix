# Perbaikan dan Audit Workflow QRIS Merchant

## 1. Tujuan

Dokumen ini menjelaskan hasil audit dan implementasi perbaikan workflow QRIS Merchant pada repository `Sadesa-fix`, branch `qr_app2`.

Target desain:

- Pedagang hanya mengajukan dan memperbaiki pengajuan ketika diminta admin.
- Admin dapat memverifikasi, mengoreksi data, menyetujui, menerbitkan, dan mengaktifkan QRIS.
- QRIS tidak boleh aktif hanya karena kolom gambar pada tabel merchant terisi.
- Satu merchant tidak boleh memiliki lebih dari satu pengajuan QRIS yang sedang berjalan.
- Approval tidak boleh dilakukan jika dokumen wajib belum ada secara fisik di storage.
- Semua perubahan penting tetap terlacak melalui activity log.

## 2. Status workflow canonical

Workflow yang digunakan:

```text
SUBMITTED
  -> IN_REVIEW
  -> NEEDS_CORRECTION
  -> SUBMITTED
  -> IN_REVIEW
  -> APPROVED_PENDING_ISSUANCE
  -> ISSUED_PENDING_ACTIVATION
  -> ACTIVE
```

Cabang penolakan:

```text
SUBMITTED / IN_REVIEW -> REJECTED
```

Aturan status:

| Status | Makna | Pedagang dapat mengedit? | Admin dapat melakukan aksi? |
|---|---|---:|---|
| `SUBMITTED` | Pengajuan baru menunggu verifikasi | Tidak | Mulai review, minta perbaikan, tolak, setujui |
| `IN_REVIEW` | Sedang diverifikasi admin | Tidak | Minta perbaikan, tolak, setujui |
| `NEEDS_CORRECTION` | Ada data/dokumen yang perlu diperbaiki | Ya | Melihat dan mengoreksi data |
| `REJECTED` | Pengajuan ditolak | Tidak pada record tersebut | Melihat riwayat |
| `APPROVED_PENDING_ISSUANCE` | Disetujui, QRIS belum diterbitkan | Tidak | Mengisi data penerbitan |
| `ISSUED_PENDING_ACTIVATION` | QRIS sudah dicatat, menunggu aktivasi | Tidak | Aktivasi akhir |
| `ACTIVE` | QRIS aktif untuk merchant | Tidak | Mengubah identitas GDC melalui aksi khusus |

## 3. Perubahan yang diimplementasikan

### 3.1. Sumber kebenaran workflow

`qris_applications` tetap menjadi sumber kebenaran untuk pengajuan dan status QRIS Merchant.

Kolom `merchants.qris_image_url` tidak lagi boleh diubah melalui jalur edit merchant biasa. Pengisian kolom tersebut hanya boleh dilakukan oleh RPC penerbitan QRIS yang dikontrol server.

Perubahan ini mencegah kondisi berikut:

```text
merchants.qris_image_url terisi
qris_applications.status bukan ACTIVE
```

### 3.2. Jalur upload QRIS di edit merchant dihapus

Field upload QRIS di `MerchantEditDialog` dihapus. Admin harus menggunakan halaman:

```text
/admin/qris-applications
```

Dengan demikian, admin tidak lagi memiliki dua jalur yang tumpang tindih untuk menetapkan QRIS.

Field rekening bank biasa tetap berada pada dialog edit merchant karena rekening tersebut merupakan konfigurasi pembayaran merchant, bukan assignment QRIS Sadesa.

### 3.3. Assignment QRIS dikontrol dengan transaction context

Trigger baru pada tabel `merchants` menolak perubahan `qris_image_url` kecuali session memiliki context internal:

```sql
app.qris_assignment = 'true'
```

Context tersebut hanya diset oleh fungsi penerbitan QRIS admin setelah pemeriksaan status dan data penerbitan selesai.

RPC yang digunakan:

```text
admin_issue_qris_mpm
```

RPC tersebut memeriksa:

- Caller adalah admin.
- Application ID tersedia.
- Referensi QRIS tersedia.
- Asset QRIS tersedia.
- GDC Merchant ID tersedia.
- GDC Account Number tersedia.
- Status aplikasi tepat `APPROVED_PENDING_ISSUANCE`.

### 3.4. Satu pengajuan berjalan per merchant

Ditambahkan unique partial index pada `qris_applications` untuk status:

```text
SUBMITTED
IN_REVIEW
NEEDS_CORRECTION
APPROVED_PENDING_ISSUANCE
ISSUED_PENDING_ACTIVATION
ACTIVE
```

Hal ini mencegah satu merchant memiliki beberapa aplikasi aktif atau aplikasi yang sedang diproses secara bersamaan.

Aplikasi berstatus `REJECTED` tetap dapat tersimpan sebagai histori, tetapi pengajuan aktif baru tidak boleh dibuat jika masih terdapat aplikasi berjalan untuk merchant yang sama.

### 3.5. Validasi dokumen saat approval

Approval sekarang memeriksa empat dokumen wajib:

```text
OWNER_ID
OWNER_SELFIE
BUSINESS_LOCATION
PRODUCT
```

Pemeriksaan tidak hanya melihat key JSON, tetapi juga memvalidasi:

1. Path dokumen tidak kosong.
2. Bucket adalah `qris-applications`.
3. Object benar-benar ada di `storage.objects`.
4. Folder pertama sama dengan `applicant_user_id`.
5. Folder kedua sama dengan `qris_applications.id`.

Dengan demikian, path palsu atau path dari application/user lain tidak dapat dipakai untuk melewati approval.

### 3.6. Admin dapat mengoreksi data inti pengajuan

Halaman admin QRIS sekarang memiliki panel **Edit data pengajuan** sebelum QRIS diterbitkan.

Field yang dapat dikoreksi admin:

- Kriteria bisnis.
- Lama usaha.
- Nama QRIS pendek.
- Nama QRIS lengkap.
- Nama bank.
- Nomor rekening.
- Nama pemilik rekening.

Perubahan dilakukan melalui RPC:

```text
admin_update_qris_application_details
```

RPC tersebut:

- Hanya dapat dipanggil admin.
- Menolak kriteria bisnis di luar `UMI`, `UME`, dan `UBE`.
- Memvalidasi batas nama QRIS 25 dan 50 karakter.
- Tidak mengizinkan edit setelah status `ISSUED_PENDING_ACTIVATION` atau `ACTIVE`.
- Mencatat aktivitas `ADMIN_APPLICATION_EDITED`.

### 3.7. Pedagang tetap menjadi pemilik pengajuan

Pedagang hanya dapat melakukan perubahan pada status `NEEDS_CORRECTION` dan hanya atas pengajuan miliknya sendiri.

Pedagang tidak dapat mengubah:

- Merchant ID.
- Applicant user ID.
- Referensi QRIS.
- Asset QRIS penerbitan.
- Admin penerbit.
- Admin aktivasi.
- GDC Merchant ID.
- GDC Account Number.
- Status menjadi status approval atau aktif.

## 4. Hak akses final

### Pedagang

Pedagang dapat:

- Membuat pengajuan baru.
- Mengisi empat dokumen wajib.
- Mengisi data usaha dan nama QRIS.
- Melihat status.
- Melihat catatan admin.
- Memperbaiki data ketika `NEEDS_CORRECTION`.
- Mengirim kembali pengajuan setelah diperbaiki.

Pedagang tidak dapat:

- Menyetujui pengajuan sendiri.
- Mengunggah QRIS hasil penerbitan.
- Mengganti QRIS aktif.
- Mengubah identitas GDC.
- Mengaktifkan QRIS.
- Mengubah status ke `ACTIVE`.

### Admin

Admin dapat:

- Melihat semua aplikasi QRIS.
- Melihat signed URL dokumen privat.
- Memulai verifikasi.
- Meminta perbaikan dengan catatan.
- Menolak dengan alasan.
- Mengoreksi data inti pengajuan.
- Menyetujui jika dokumen lengkap.
- Mengunggah QRIS penerbitan.
- Memasukkan referensi QRIS.
- Memasukkan identitas GDC.
- Mengaktifkan QRIS.
- Mengubah identitas GDC pada aplikasi aktif melalui RPC khusus.
- Melihat aktivitas pengajuan.

## 5. Database objects yang ditambahkan atau diperkuat

Migration utama:

```text
supabase/bootstrap/140_20261101200000_qris_workflow_hardening.sql
```

Object penting:

```text
qris_applications_one_live_application_per_merchant_idx
protect_merchant_qris_assignment()
enforce_qris_application_transition()
admin_update_qris_application_details()
admin_issue_qris_mpm()
```

RPC lama berikut tidak lagi diberikan kepada role `authenticated`:

```text
admin_issue_qris(uuid, text, text)
```

RPC tersebut digantikan oleh versi MPM yang memerlukan identitas GDC dan menjalankan controlled assignment context.

## 6. Alur operasi admin yang benar

### Pengajuan baru

1. Pedagang mengisi formulir.
2. Pedagang mengunggah KTP, selfie, lokasi usaha, dan produk.
3. Pedagang mengirim pengajuan.
4. Status menjadi `SUBMITTED`.

### Verifikasi

1. Admin memilih aplikasi.
2. Admin melihat data dan signed URL dokumen.
3. Admin menekan **Mulai Verifikasi**.
4. Status menjadi `IN_REVIEW`.

### Koreksi

Jika terdapat kesalahan:

1. Admin mengisi catatan koreksi.
2. Admin menekan **Minta Perbaikan**, atau mengoreksi data langsung melalui panel admin.
3. Status menjadi `NEEDS_CORRECTION` jika koreksi harus dilakukan pedagang.
4. Pedagang memperbaiki dan mengirim ulang.
5. Status kembali menjadi `SUBMITTED`.

### Persetujuan

1. Admin memastikan empat dokumen tersedia dan benar.
2. Admin menekan **Setujui**.
3. Database memvalidasi keberadaan object dokumen.
4. Status menjadi `APPROVED_PENDING_ISSUANCE`.

### Penerbitan

1. Admin mengunggah gambar QRIS penerbitan.
2. Admin memasukkan QRIS reference.
3. Admin memasukkan GDC Merchant ID.
4. Admin memasukkan GDC Account Number.
5. Admin menyimpan penerbitan.
6. RPC mengisi `merchants.qris_image_url` menggunakan context internal.
7. Status menjadi `ISSUED_PENDING_ACTIVATION`.

### Aktivasi

1. Admin memeriksa kembali QRIS dan merchant.
2. Admin menekan **Aktifkan QRIS**.
3. Database memastikan gambar QRIS pada merchant sama dengan asset aplikasi.
4. Status menjadi `ACTIVE`.

## 7. Perubahan yang sengaja belum dilakukan

Beberapa rekomendasi lanjutan memerlukan desain produk tambahan dan belum diaktifkan pada migration ini:

### 7.1. Status suspend/revoke

Status berikut belum ditambahkan:

```text
SUSPENDED
REVOKED
DEACTIVATED
```

Alasannya, status tersebut membutuhkan aturan bisnis tambahan untuk transaksi yang sudah berjalan, penggantian QRIS, dan pemulihan merchant.

### 7.2. Upload dokumen oleh admin

Admin sudah dapat melihat dokumen dan mengoreksi data inti, tetapi upload atau penggantian dokumen oleh admin belum dibuat sebagai jalur terpisah. Ini sengaja dipisahkan agar ownership dokumen tetap jelas.

### 7.3. Penghapusan object dokumen lama

Penggantian dokumen masih dapat meninggalkan object lama di storage. Tahap berikutnya sebaiknya membuat fungsi archive/delete yang mencatat histori dokumen sebelum object lama dihapus.

### 7.4. Penyatuan penuh tabel legacy GDC

`gdc_payment_profiles` tetap dipertahankan untuk kompatibilitas data legacy. Import legacy tetap membuat `qris_applications` berstatus `NEEDS_CORRECTION`, sehingga tidak langsung aktif.

## 8. Checklist pengujian manual

### Pedagang

- [ ] Pedagang tanpa aplikasi dapat membuat pengajuan.
- [ ] Pengajuan tanpa salah satu dokumen ditolak oleh validasi UI.
- [ ] Pedagang tidak dapat mengubah pengajuan `SUBMITTED`.
- [ ] Pedagang dapat memperbaiki `NEEDS_CORRECTION`.
- [ ] Pedagang tidak dapat mengubah `qris_asset_key` melalui API.
- [ ] Pedagang tidak dapat mengubah identitas GDC.
- [ ] Pedagang tidak dapat mengaktifkan QRIS.

### Admin

- [ ] Admin dapat melihat seluruh pengajuan.
- [ ] Admin dapat memulai review.
- [ ] Admin dapat mengoreksi data inti pengajuan.
- [ ] Koreksi admin masuk activity log.
- [ ] Approval gagal jika object dokumen tidak ada.
- [ ] Approval berhasil jika empat object dokumen valid.
- [ ] Penerbitan tanpa GDC Merchant ID ditolak.
- [ ] Penerbitan tanpa GDC Account Number ditolak.
- [ ] Aktivasi sebelum penerbitan ditolak.
- [ ] Admin tidak lagi mengatur QRIS dari edit merchant biasa.

### Integritas database

- [ ] Insert aplikasi kedua untuk merchant yang masih memiliki aplikasi live ditolak.
- [ ] Update `merchants.qris_image_url` langsung dari client ditolak.
- [ ] Assignment melalui `admin_issue_qris_mpm` berhasil.
- [ ] Checkout MPM hanya berjalan untuk aplikasi `ACTIVE` dengan identitas GDC lengkap.
- [ ] Activity log menyimpan perubahan status dan koreksi admin.

## 9. Validasi teknis yang dijalankan

Setelah perubahan source:

```bash
python3 scripts/update-bootstrap-manifest.py
python3 scripts/validate-bootstrap-bundles.py
corepack pnpm@9.15.9 exec eslint \
  src/components/admin/MerchantEditDialog.tsx \
  src/pages/admin/AdminQrisApplicationsPage.tsx
corepack pnpm@9.15.9 run build
```

Jika repository memiliki environment Supabase lokal atau staging, migration harus diterapkan terlebih dahulu sebelum menjalankan checklist database.

## 10. Risiko deployment dan rollback

Migration bersifat forward-only. Sebelum deploy:

1. Backup database.
2. Periksa apakah ada merchant dengan lebih dari satu aplikasi pada status live.
3. Jika ada duplikasi, selesaikan secara manual sebelum membuat unique index.
4. Pastikan RPC `admin_issue_qris_mpm` tersedia di PostgREST.
5. Pastikan halaman admin menggunakan RPC editor baru.
6. Pastikan tidak ada client lain yang masih memanggil RPC lama.

Rollback kode frontend dapat dilakukan melalui Git, tetapi rollback database harus dilakukan dengan migration kompensasi baru, bukan menghapus migration yang sudah diterapkan.

## 11. Ringkasan hasil

Implementasi ini menyelesaikan masalah utama audit:

- Jalur QRIS langsung dari edit merchant ditutup.
- Pengajuan live ganda per merchant dicegah.
- Approval memverifikasi file dokumen secara fisik.
- Admin dapat mengoreksi data inti pengajuan melalui UI.
- Koreksi admin tercatat dalam audit log.
- QRIS assignment hanya dilakukan oleh RPC penerbitan terkontrol.
- Pedagang tetap hanya dapat mengajukan dan memperbaiki data ketika diminta.

Workflow QRIS sekarang memiliki batas yang lebih jelas antara:

```text
pengajuan pedagang
verifikasi admin
penerbitan QRIS
aktivasi QRIS
identitas GDC untuk pembayaran dinamis
```
