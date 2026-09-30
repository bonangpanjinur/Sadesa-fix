# Audit dan Perbaikan Alur Ojek: RLS, Pembeli, dan Driver

**Tanggal:** 29 September 2026
**Repository:** `bonangpanjinur/Sadesa-fix`
**Lingkup:** pembacaan perjalanan oleh pembeli/penyewa dan driver/kurir, RLS `ride_requests`, inbox offer, fallback error, dan tata kelola migrasi SQL.

## Ringkasan

Log browser yang dilampirkan menunjukkan HTTP 500 berulang pada dua jenis pembacaan `public.ride_requests`:

- perjalanan aktif milik driver (`driver_id` + status `ACCEPTED/PICKED_UP/IN_TRANSIT`);
- permintaan pencarian milik pembeli (ID + status `SEARCHING`).

Kedua query mengenai tabel yang sama. Di migrasi dispatch terbaru sebelum perbaikan, policy courier untuk `SEARCHING` melakukan subquery ke `public.ride_requests` dari policy `SELECT` di tabel yang sama. Evaluasi policy tersebut dapat berulang secara rekursif dan membuat PostgREST mengembalikan 500. Selain itu, policy lama bernama **“Drivers can view searching rides”** masih berasal dari migrasi terdahulu. Karena policy RLS permisif digabungkan dengan `OR`, sekadar menambahkan policy offer privat tidak menonaktifkan policy lama itu.

Perbaikan dibuat sebagai migrasi append-only **`20260929160000_ride_requests_rls_recursion_fix.sql`**. Policy driver/courier lama dibersihkan dan diganti dengan satu pemeriksaan visibilitas melalui fungsi `SECURITY DEFINER` yang tidak membuat policy meng-query ulang `ride_requests`. Fungsi membatasi visibilitas pada ride milik driver tersebut atau offer pencarian yang aktif, belum kedaluwarsa, ditargetkan ke driver yang sama, serta memenuhi syarat driver aktif dan GPS terbaru. Migrasi yang sama mempertahankan signature dan perhitungan tarif RPC `create_ride_request`, lalu menambahkan advisory lock dan pengecekan server-side supaya dua tab/perangkat tidak dapat membuat ride aktif kedua untuk pembeli yang sama.

Di sisi UI, pembeli kini tidak boleh membuat booking baru bila pemeriksaan ride aktif gagal. Halaman tracking membedakan error pemuatan dari ride yang memang tidak ditemukan dan menyediakan retry. Perubahan ini memperbaiki penanganan kegagalan API, bukan pengganti perbaikan database.

## Bukti dari log lampiran

Pada sekitar `2026-09-29T12:11Z`–`12:13Z`, log berulang menampilkan:

```text
GET /rest/v1/ride_requests?...driver_id=eq...&status=in.(ACCEPTED,PICKED_UP,IN_TRANSIT)... 500
GET /rest/v1/ride_requests?...id=in.(...)&status=eq.SEARCHING... 500
```

Log tidak menyertakan body error PostgREST atau SQLSTATE. Karena itu log sendiri membuktikan kegagalan API pada kedua query, tetapi tidak mengungkap pesan database yang persis. Rekursi policy adalah akar masalah yang kuat dan cocok dengan pola dua query tersebut setelah dicocokkan dengan SQL di repo. Status database yang benar-benar dipakai aplikasi harus dikonfirmasi setelah migrasi diterapkan dan smoke test dijalankan pada project Supabase target.

Peringatan `beforeinstallpromptevent` dan log registrasi device/realtime bukan indikasi bahwa pesanan dihapus; keduanya tidak berkaitan langsung dengan error query `ride_requests` yang berstatus 500.

## Perubahan yang diterapkan

### Database dan keamanan RLS

- Tambah fungsi `public.courier_can_view_ride(uuid)` sebagai pemeriksa RLS `SECURITY DEFINER`, dengan `search_path` terkunci dan `row_security=off` agar query internal tidak masuk kembali ke policy yang sama.
- Ganti policy pembacaan courier dengan satu policy untuk ride yang ditugaskan ke courier sendiri atau offer `SEARCHING` yang benar-benar aktif dan ditargetkan kepada courier tersebut.
- Hapus nama policy lama yang permissive—termasuk **“Drivers can view searching rides”**—agar tidak menjadi cabang `OR` yang membocorkan ride yang belum ditawarkan.
- Tambah skrip PostgreSQL `scripts/ride-rls-smoke.sql` dan jalankan pada workflow migrations CI. Skenario menguji buyer own ride, target courier, courier yang bukan target, ride aktif driver, dan offer pencarian yang harus tersembunyi saat driver sudah membawa ride aktif.
- Bundle `supabase/bootstrap/58_20260929160000_ride_requests_rls_recursion_fix.sql` didaftarkan dalam manifest. Bundle hanya dijalankan setelah bundle sebelumnya dan bersifat idempotent.

### Pembeli/penyewa

- Booking page melakukan pemeriksaan ride aktif saat dibuka dan mengunci pemesanan baru bila pemeriksaan gagal.
- Tepat sebelum RPC pembuatan booking dipanggil, UI membaca ulang ride aktif. Jika query gagal, pemesanan dihentikan; jika ride aktif ditemukan, pengguna diarahkan ke perjalanan yang sudah ada.
- RPC `create_ride_request` menerapkan aturan satu perjalanan aktif per pembeli secara atomik menggunakan advisory transaction lock dan status aktif yang sama dengan UI. Ini menutup race antara dua tab/perangkat, bukan hanya mencegah klik ulang pada satu halaman.
- Tracking page membedakan **“data belum dapat dimuat”** (dengan retry) dari **“ride tidak ditemukan/akses tidak tersedia”**. Error server tidak lagi langsung diterjemahkan sebagai pesanan hilang.
- Realtime tracking tidak lagi membangun ulang channel hanya karena data profil driver berubah; state driver dipegang melalui ref untuk callback.

Pengecekan aktif UI dipertahankan sebagai UX cepat, sedangkan RPC menjadi pengaman otoritatif ketika request datang bersamaan. `accept_ride` di bundle dispatch terbaru juga sudah memeriksa ride aktif courier sebelum assignment; skenario tersebut sekarang ikut diuji.

### Driver/kurir

- Inbox driver tetap mengambil offer `PENDING` yang tertarget ke courier ID sesi yang login dan ride aktif yang ditugaskan kepada ID itu.
- RPC `accept_ride`/`decline_ride_request` tetap menjadi mutasi otoritatif; pembacaan di UI tidak menggantikan validasi server.
- Policy RLS baru mengizinkan target offer membaca hanya ride yang masih `SEARCHING`, belum memiliki driver, offer belum expired, driver approved/active/available, GPS tidak stale, dan tidak ada ride aktif lain.
- Smoke test mencegah policy lama membuat semua courier melihat ride `SEARCHING` atau query driver aktif kembali menghasilkan error.

## Prosedur perubahan SQL agar fitur baru tidak merusak database

Ikuti prosedur ini setiap fitur membutuhkan perubahan skema, RLS, trigger, RPC, cron, atau indeks:

1. **Jangan mengedit migrasi yang sudah pernah digunakan.** Tambahkan migrasi bernomor baru di `archive/supabase/migrations/` dan bundle deployment bernomor berikutnya di `supabase/bootstrap/`. Migrasi lama adalah histori dan jangan diubah untuk memperbaiki database berjalan.
2. **Rancang perubahan additive dan idempotent.** Gunakan `CREATE ... IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `DROP POLICY IF EXISTS` hanya saat mengganti policy, dan `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`. Hindari `DROP TABLE`, `TRUNCATE`, `DROP COLUMN`, penghapusan data, atau perubahan constraint yang berisiko tanpa rencana backfill, backup, dan review eksplisit.
3. **Tentukan kontrak sebelum SQL.** Catat tabel/kolom, tipe dan status, RPC beserta parameter/return type, role/actor yang boleh memanggil, transisi yang diizinkan, perilaku retry/idempotency, serta efek trigger/realtime/cron.
4. **Periksa RLS lintas role.** Uji sebagai pembeli A, pembeli lain, driver target, driver bukan target, dan admin. Hindari subquery langsung ke tabel yang sama dalam policy; bila pemeriksaan lintas tabel rumit, pindahkan ke helper `SECURITY DEFINER` yang aman, minim informasi, ber-`search_path` tetap, dan hanya diberi `EXECUTE` ke role yang diperlukan. Perhatikan bahwa beberapa policy permissive digabung `OR`—policy lama yang tidak dihapus dapat tetap membuka akses.
5. **Jalankan CI sebelum staging.** Minimal: validasi nama dan urutan migration, validasi hash bootstrap, jalankan seluruh bundle pada PostgreSQL bersih, schema/grant/RLS smoke test, regression test untuk fitur, typecheck, unit test, lint, dan build.
6. **Uji staging, jangan mengeksekusi SQL manual di production.** Pastikan project ref/label benar-benar staging, ambil backup/snapshot yang dapat dipulihkan, deploy lewat `scripts/deploy-supabase-staging.sh`, lalu uji RPC dan REST query sebagai sesi buyer/driver terpisah. Periksa `pg_policies`, definisi fungsi (`pg_get_functiondef`), constraint/index, `cron.job` bila relevan, dan respons API termasuk SQLSTATE. Catat hasil dan versi migrasi.
7. **Lanjutkan ke production hanya melalui jalur deployment yang disetujui.** Siapkan rollback/forward-fix, pantau log, dan jangan mengklaim fitur aktif sebelum versi skema target terverifikasi.

> **Aturan praktis:** satu perubahan database = satu migrasi baru + dokumentasi kontrak + tes regresi, bukan perubahan SQL ad-hoc di dashboard.

## Celah source-of-truth yang ditemukan

### Generator bootstrap dan archive migration belum sinkron

Manifest bundle saat ini menyebut 334 source entry, tetapi `archive/supabase/migrations/` hanya menyediakan sebagian histori tersebut (106 entry manifest tidak ditemukan di archive, sementara 14 file archive tidak terdaftar di manifest). `scripts/build-bootstrap-bundles.py` sebelumnya menghapus semua file SQL pada output sebelum menulis ulang dari archive. Menjalankan generator tanpa memperbaiki arsip berisiko menghilangkan SQL yang ada di bootstrap dan mungkin sudah terpasang pada environment.

Sebagai pengaman, generator kini **berhenti sebelum menyentuh output** apabila manifest mereferensikan source yang hilang dari archive. Regression test `scripts/test-build-bootstrap-safety.py` memastikan bundle lama tetap utuh pada kondisi tersebut. Jangan memaksa rebuild atau menghapus guard; sinkronkan kembali histori source terlebih dahulu, kemudian jalankan generator dan bandingkan hash/urutan hasilnya.

Frontend memanggil `supabase.rpc('create_ride_request', ...)`. Definisi fungsi tersebut **ada dalam bundle canonical** `supabase/bootstrap/05_20260911110000_to_20260914150000.sql` (bundle source bernama `52_20260911110000_ride_authoritative_mutations.sql`) dengan argumen numeric dan return `uuid`; definisi canonical `accept_ride` paling baru berada pada bundle dispatch 55. Source individual untuk sebagian migrasi/bundle tersebut tidak tersedia di `archive/supabase/migrations/`, sehingga generator lama tidak dapat merekonstruksi histori penuh. Patch ini mempertahankan signature/fare RPC dari bundle dan menambahkan forward migration untuk guard atomik; tidak mengubah tarif atau jalur mutasi driver yang sudah ada.

Untuk perubahan berikutnya, jangan menebak kontrak fungsi. Pulihkan source individual dari histori yang telah diterapkan atau ekspor definisi staging dengan `pg_get_functiondef`, cocokan signature/return type, lalu simpan sebagai migrasi append-only dan uji pada database bersih.

## Validasi dan batas rollout

Perbaikan **sudah ditulis ke repository**, tetapi belum diterapkan ke Supabase staging/production karena sesi ini tidak memiliki koneksi database atau izin deployment yang dikonfirmasi. Maka gejala pada project live baru dapat dinyatakan selesai setelah migrasi bundle 58 diterapkan melalui jalur staging yang benar, RLS smoke test berhasil, lalu kedua query log diuji ulang sebagai buyer dan driver.

Validasi lokal yang selesai:

- Regression Vitest dispatch + RLS: **11 passed**.
- TypeScript check (dengan deklarasi tipe Google Maps yang dipakai aplikasi), ESLint file terkait, `pnpm build`, `pnpm validate:migrations`, manifest bootstrap validator, whitespace check, dan generator safety test: **lulus**.
- Seluruh unit suite: **342 passed, 20 skipped, 3 failed**. Kegagalan berada pada test kontrak yang tidak terkait perubahan ojek: `rpcOverloadCleanup.test.ts`, `serviceEnhancementContract.test.ts`, dan `chat/phase8Acceptance.test.ts`.
- Skrip SQL runtime buyer/driver sudah dimasukkan ke migrations CI, tetapi belum dapat dijalankan di sandbox ini karena PostgreSQL/`psql` tidak tersedia. Tes RLS PostgreSQL di CI tetap menjadi validasi otoritatif untuk eksekusi SQL.

Tes unit/static dan build bukan pengganti menjalankan migrasi terhadap project Supabase target. Koneksi staging/live tidak tersedia di sesi ini sehingga belum ada klaim bahwa database atau gejala produksi sudah berubah.
