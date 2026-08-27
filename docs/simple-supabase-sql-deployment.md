# Panduan Deployment SQL Supabase

## Kebijakan utama

Repository ini memakai **model bootstrap terpusat**. Seluruh SQL yang digunakan untuk deployment baru berada di:

```text
supabase/bootstrap/
```

Folder tersebut berisi delapan bundle SQL berurutan. Jalankan bundle `01` sampai `08` secara berurutan dan jangan menjalankan file secara acak.

Migration per-file lama disimpan di:

```text
archive/supabase/migrations/
```

Folder arsip hanya untuk audit, perbandingan, regenerasi bundle, dan rollback historis. Folder tersebut bukan sumber deployment aktif.

## Struktur deployment

```text
supabase/
├── config.toml
├── bootstrap/                  # SATU-SATUNYA SQL deployment aktif
│   ├── 01_*.sql
│   ├── 02_*.sql
│   ├── 03_*.sql
│   ├── 04_*.sql
│   ├── 05_*.sql
│   ├── 06_*.sql
│   ├── 07_*.sql
│   ├── 08_*.sql
│   └── manifest.json
└── functions/

archive/supabase/migrations/    # arsip read-only, tidak dijalankan langsung
```

## Deployment ke project baru

Gunakan bundle hanya untuk project Supabase baru yang belum memiliki data atau histori migration. Pastikan project ref dan database target sudah benar, lalu jalankan:

```bash
export SUPABASE_DB_URL='postgresql://...'

for file in supabase/bootstrap/[0-9][0-9]_*.sql; do
  echo "Applying $file"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$file"
done
```

Alternatifnya, buka file di Supabase SQL Editor dan jalankan satu per satu sesuai nomor. Tunggu setiap file selesai sebelum menjalankan file berikutnya.

Sebelum deployment, regenerasi dan validasi bundle jika source archive berubah:

```bash
pnpm build:db-bootstrap
pnpm validate:db-bootstrap
pnpm validate:migrations
```

`manifest.json` memastikan seluruh 183 source migration tercakup tepat satu kali dan mencatat checksum setiap bundle.

## Deployment ke project existing

Model B menggunakan SQL bootstrap sebagai jalur deployment utama. Untuk project existing, jangan menggabungkan bundle dengan database yang sudah sebagian bermigrasi. Buat backup dan restore drill terlebih dahulu, kemudian lakukan deployment terencana dengan bundle yang sesuai terhadap target yang sudah diverifikasi.

Jangan menjalankan:

```bash
supabase db push
supabase db reset
```

sebagai jalur deployment standar model ini. `supabase db push` mengharapkan histori file migration pada direktori default Supabase, sedangkan model ini menggunakan bundle SQL. `supabase db reset` dapat menghapus data dan hanya boleh digunakan pada database lokal disposable.

## Menambahkan perubahan SQL baru

Tambahkan perubahan ke source migration arsip melalui proses review, lalu regenerasi seluruh bundle secara deterministik:

```bash
pnpm build:db-bootstrap
pnpm validate:db-bootstrap
git diff --check
```

Jangan mengedit bundle SQL secara manual karena perubahan manual akan hilang saat generator dijalankan kembali. Jangan menghapus source archive karena file tersebut diperlukan untuk membangun ulang bundle dan menelusuri histori perubahan.

## CI/CD

Migration CI hanya memproses `supabase/bootstrap/*.sql` secara alfabetis dan menjalankan setiap bundle pada PostgreSQL bersih. CI juga memvalidasi coverage manifest, menguji pengulangan bundle, memeriksa table/grant/RLS, dan memastikan tidak ada statement destructive yang tidak direview.

Perubahan pada `archive/supabase/migrations/` tidak menjadi trigger deployment. Perubahan pada `supabase/bootstrap/`, generator, validator, atau workflow migration akan memicu pemeriksaan CI.

## Aturan keselamatan

| Aturan | Ketentuan |
|---|---|
| Satu jalur aktif | Hanya `supabase/bootstrap/` yang digunakan untuk deployment |
| Urutan wajib | Bundle `01` hingga `08` harus dijalankan berurutan |
| Arsip read-only | Jangan menjalankan SQL dari `archive/supabase/` |
| Target jelas | Verifikasi project ref dan database URL sebelum eksekusi |
| Backup | Ambil backup dan lakukan restore drill sebelum perubahan besar |
| Secret | Jangan menulis credential, service-role key, atau webhook secret di SQL |
| Review | Setiap perubahan source harus melewati pull request dan CI |
| Partial state | Jika bundle gagal, hentikan proses dan evaluasi database; jangan mengulang acak |

## Jika bundle gagal

Catat nama bundle, statement, dan pesan PostgreSQL. Jangan langsung menjalankan bundle berikutnya. Untuk project baru yang disposable, buat database baru dan ulangi dari bundle `01`. Untuk staging atau production, jangan reset atau menghapus data; lakukan diagnosis terhadap schema state dan gunakan prosedur recovery yang disetujui.

Model ini memang mengorbankan tracking migration per-file demi jalur SQL yang sederhana. Karena itu, `manifest.json`, checksum, backup, dan release tag wajib dipertahankan pada setiap release database.

## Referensi command

```bash
pnpm build:db-bootstrap       # generate 8 bundle dari archive source
pnpm validate:db-bootstrap    # cek 183 source tercakup tepat satu kali
pnpm validate:migrations      # cek bundle filename dan statement berbahaya
pnpm audit:rls                # audit RLS dari bundle canonical
```

Untuk deployment baru, aturan praktisnya adalah: **gunakan hanya `supabase/bootstrap/`, jalankan file `01` sampai `08`, dan jangan menjalankan folder archive secara langsung.**
