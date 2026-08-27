# Staging Bootstrap Validation

Dokumen ini menjelaskan cara menjalankan validasi otomatis terhadap seluruh **186 migration** yang dikemas dalam **8 bootstrap bundle** pada project Supabase staging yang terisolasi.

Skrip utama adalah `scripts/validate-bootstrap-staging.sh`. Skrip ini tidak menjalankan migration ke production karena memiliki guard `SUPABASE_TARGET_LABEL=staging` secara default.

## Prasyarat

Environment eksekusi harus memiliki `bash`, `psql`, `python3`, `pnpm`, dan `flock`. `SUPABASE_DB_URL` harus berupa connection URL PostgreSQL dari project staging, sedangkan `SUPABASE_PROJECT_REF` harus berisi project reference staging. Jangan menyimpan connection URL di repository atau mencetaknya ke log CI.

Contoh konfigurasi lokal:

```bash
export SUPABASE_TARGET_LABEL=staging
export SUPABASE_PROJECT_REF=your-staging-project-ref
export SUPABASE_DB_URL='postgresql://postgres:<password>@<host>:5432/postgres?sslmode=require'
```

## Menjalankan validasi penuh

```bash
pnpm validate:bootstrap:staging
```

Proses akan melakukan empat tahap. Pertama, validator lokal memeriksa urutan source migration, nama file, kelengkapan bundle, dan manifest. Kedua, skrip memeriksa koneksi database staging. Ketiga, delapan bundle dijalankan secara berurutan dengan `ON_ERROR_STOP=1`. Keempat, bundle yang sama dijalankan kembali untuk menguji idempotency atau replay safety.

Setelah replay berhasil, smoke test memeriksa keberadaan tabel subscription, usage ledger, PWA device, dan notification queue; keberadaan RPC entitlement, quota, dan worker; status RLS pada tabel tenant-sensitive; jumlah policy; serta katalog subscription plan.

Log bertimestamp disimpan di `artifacts/staging-bootstrap-validation/`. Directory tersebut sebaiknya dimasukkan ke `.gitignore` bila log mengandung informasi operasional internal.

## Dry run

Dry run tidak membutuhkan `SUPABASE_DB_URL` yang valid untuk menjalankan migration, tetapi skrip tetap meminta variable staging agar konfigurasi yang dipakai terlihat eksplisit. Mode ini hanya memvalidasi repository dan mencetak bundle yang akan dijalankan.

```bash
SUPABASE_TARGET_LABEL=staging \
SUPABASE_PROJECT_REF=dry-run \
SUPABASE_DB_URL='postgresql://invalid/dry-run' \
pnpm validate:bootstrap:staging -- --dry-run
```

## Opsi eksekusi

| Opsi | Fungsi |
|---|---|
| `--dry-run` | Tidak mengubah database dan hanya memeriksa urutan bundle. |
| `--no-replay` | Menjalankan bootstrap satu kali tanpa pengujian replay. Tidak disarankan untuk gate staging. |
| `--no-smoke` | Melewati smoke test database. Gunakan hanya untuk diagnosis. |

Environment `STAGING_BOOTSTRAP_REPLAY=false` dan `STAGING_BOOTSTRAP_SMOKE_TEST=false` menyediakan konfigurasi ekuivalen untuk CI yang membutuhkan override.

## Penggunaan pada CI/CD

Secret CI yang diperlukan adalah `SUPABASE_DB_URL` dan variable `SUPABASE_PROJECT_REF`. Tambahkan variable non-secret `SUPABASE_TARGET_LABEL=staging`. Job harus memakai environment protection bernama `staging`, sehingga secret production tidak tersedia pada job ini.

Contoh langkah workflow:

```yaml
- name: Validate staging bootstrap
  env:
    SUPABASE_DB_URL: ${{ secrets.SUPABASE_STAGING_DB_URL }}
    SUPABASE_PROJECT_REF: ${{ vars.SUPABASE_STAGING_PROJECT_REF }}
    SUPABASE_TARGET_LABEL: staging
  run: pnpm validate:bootstrap:staging
```

Jalankan job hanya pada staging yang disposable atau sudah memiliki backup dan prosedur restore. Replay menguji bahwa objek yang sudah ada tidak membuat bootstrap gagal, tetapi tidak menggantikan integration test transaksi, RLS lintas tenant, atau test dengan JWT user nyata.

## Verifikasi lanjutan setelah script lulus

Setelah script menghasilkan `STAGING_BOOTSTRAP_VALIDATION=PASS`, lakukan pengujian aplikasi menggunakan akun staging. Minimum test mencakup login, pembuatan tenant POS, registrasi device pertama dan device tambahan sesuai tier, re-register device yang sama, pemakaian quota WhatsApp, retry delivery job, checkout POS, RLS antar tenant, dan deployment Edge Function notification worker.

Jika smoke test menunjukkan RPC ada tetapi pemanggilan user-level gagal, periksa `GRANT EXECUTE`, RLS, `auth.uid()`, dan role JWT. Jika WhatsApp quota gagal pada worker, periksa mapping `pos_tenants.user_id` ke `merchants.user_id`, subscription aktif, entitlement `whatsapp_messages`, serta `SUPABASE_SERVICE_ROLE_KEY` pada Edge Function.

## Troubleshooting

Error `Refusing to run` berarti `SUPABASE_TARGET_LABEL` bukan `staging`. Error `Expected 8 bootstrap bundles` berarti file bundle tidak lengkap atau pola nama berubah. Error pada tahap replay berarti salah satu migration belum idempotent dan harus diperbaiki pada source migration, bukan dengan mengabaikan error di script. Error koneksi PostgreSQL biasanya disebabkan URL, password, allowlist jaringan, atau SSL mode yang tidak sesuai.
