# Panduan Sederhana Deployment SQL Supabase

## Prinsip utama

Repository ini menggunakan **satu sumber migration aktif**, yaitu:

```text
supabase/migrations/
```

Supabase CLI hanya boleh membaca dan menjalankan file SQL dari direktori tersebut. Migration diberi nama dengan timestamp sehingga urutannya deterministik dan migration yang sudah pernah dijalankan tidak boleh diedit atau dihapus.

## Struktur direktori

```text
supabase/
├── config.toml
├── functions/
└── migrations/                 # SATU-SATUNYA sumber aktif
    ├── 2026....sql
    └── 2026....sql

archive/supabase/
├── main_migration.sql          # snapshot lama, tidak aktif
├── migrations_backup/          # backup lama, tidak aktif
└── migrations_consolidated/    # snapshot test lama, tidak aktif
```

Direktori `archive/supabase` hanya untuk referensi, perbandingan, atau pemulihan historis. File di dalamnya **tidak boleh dijalankan langsung** pada project staging atau production.

## Deployment normal

Dari root repository, login ke Supabase CLI dan hubungkan project yang benar. Untuk staging, gunakan project ref staging. Untuk production, gunakan project ref production.

```bash
supabase login
supabase link --project-ref <PROJECT_REF>
supabase db push
```

Sebelum `supabase db push`, periksa target project dan status migration:

```bash
supabase status
supabase migration list
./scripts/validate-migrations.sh
```

Jangan menjalankan `supabase db reset` pada staging atau production karena perintah tersebut dapat menghapus data. Reset hanya boleh digunakan pada database lokal disposable.

## Menambahkan perubahan database baru

Setiap perubahan baru harus dibuat sebagai migration baru:

```bash
supabase migration new add_feature_name
```

Edit file baru tersebut, lalu validasi pada database lokal atau staging. Jangan mengubah migration lama yang sudah pernah diterapkan. Jika terdapat kesalahan pada migration lama, buat migration koreksi baru dengan timestamp yang lebih besar.

Contoh alur pull request:

```bash
supabase migration new add_stock_reservation_index
# edit supabase/migrations/<timestamp>_add_stock_reservation_index.sql
./scripts/validate-migrations.sh
supabase db push --dry-run
pnpm lint
pnpm test
pnpm build
```

## Aturan wajib

| Aturan | Keterangan |
|---|---|
| Satu sumber aktif | Hanya `supabase/migrations/` yang diproses deployment |
| Migration immutable | Jangan mengedit atau menghapus migration yang sudah pernah dijalankan |
| Arsip tidak aktif | Jangan menjalankan file dari `archive/supabase/` |
| Target harus jelas | Selalu periksa project ref sebelum push |
| Staging lebih dulu | Uji migration pada staging sebelum production |
| Backup sebelum perubahan besar | Pastikan backup dan restore drill tersedia |
| Tidak ada secret di SQL | Credential dan service-role key tidak boleh ditulis dalam file migration |
| Review wajib | Migration harus direview dalam pull request |

## Jika migration gagal

Hentikan proses dan simpan output error. Jangan langsung mengedit migration yang sudah tercatat atau menjalankan seluruh snapshot lama. Identifikasi apakah migration gagal karena urutan, object yang sudah ada, privilege, extension, atau perbedaan schema. Setelah perbaikan dibuat, tambahkan migration koreksi baru dan uji ulang pada staging.

Untuk project existing, jangan mengganti seluruh database dengan `main_migration.sql` atau folder consolidated. Jalur tersebut merupakan snapshot historis dan tidak menggantikan histori migration Supabase. Gunakan `supabase db push` dari direktori aktif agar Supabase menerapkan hanya migration yang belum tercatat.

## CI/CD

Workflow migration CI menggunakan `supabase/migrations/` sebagai `MIG_DIR`. Workflow tersebut menjalankan migration aktif secara berurutan pada database PostgreSQL bersih, mengulanginya untuk pemeriksaan idempotency, lalu melakukan smoke test table, grant, RLS, dan skenario akses.

Dengan aturan ini, anggota tim tidak perlu memilih di antara beberapa folder SQL. Untuk deploy terbaru, jawabannya selalu: **gunakan `supabase/migrations/`, lalu jalankan `supabase db push` terhadap project yang sudah diverifikasi**.
