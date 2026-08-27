# Production Deployment Runbook

Dokumen ini adalah checklist operasional untuk deploy SaDesa/UMKM SaaS ke Railway dan Supabase. Frontend statis dijalankan di Railway melalui Caddy; database, RLS, RPC, storage policy, dan Edge Function dijalankan pada project Supabase.

## 1. Prasyarat dan environment

Jangan masukkan secret server ke repository atau variable `VITE_*`. Railway frontend hanya memerlukan `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, dan `VITE_SUPABASE_PROJECT_ID`. Secret provider, service-role key, webhook secret, WhatsApp access token, serta database password hanya boleh disimpan pada secret manager/Edge Function environment Supabase atau service server yang memang membutuhkannya.

Sebelum release, pastikan URL berikut sudah benar: Railway public URL, Supabase Auth Site URL, redirect URLs untuk login, webhook callback URL, serta allowed origins pada Edge Function. Gunakan project staging yang berbeda dari production untuk semua fixture dan test.

## 2. Preflight repository

Jalankan dari root repository:

```bash
pnpm install --frozen-lockfile
pnpm exec tsc --noEmit
pnpm lint
pnpm test
pnpm build
bash scripts/validate-migrations.sh
pnpm validate:db-bootstrap
```

Working tree harus bersih atau perubahan release harus sudah direview. SQL deployment menggunakan bundle bernomor di `supabase/bootstrap/` dan dijalankan berdasarkan urutan nama file. Source migration per-file lama berada di `archive/supabase/migrations/` sebagai arsip read-only; operator tidak boleh menjalankannya langsung.

## 3. Database migration

Terapkan bundle SQL canonical terhadap project yang benar menggunakan koneksi database staging/production yang disimpan aman, bukan service-role key dari browser:

```bash
export SUPABASE_DB_URL='postgresql://...'
./scripts/validate-migrations.sh
pnpm validate:db-bootstrap
for bundle in supabase/bootstrap/[0-9][0-9]_*.sql; do
  echo "Applying $bundle"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$bundle"
done
```

`supabase db push` bukan jalur deployment standar pada model bootstrap-only karena membutuhkan histori migration pada direktori default Supabase.

Deploy dimulai dari backup/schema snapshot staging. Setelah migration selesai, jalankan smoke test RPC dengan fixture tenant terpisah untuk memastikan tenant isolation, authorization, row locking, idempotency, trigger, dan rollback transaksi. Migration P0/P1/PWA yang wajib diverifikasi meliputi atomic POS checkout, payment webhook, refund/return, reconciliation, stock adjustment/transfer, price book, loyalty ledger, CRM identity, notification queue, customer mapping, approval RPC, dan PWA device sessions.

Jangan mengubah migration yang sudah pernah diterapkan pada project production. Jika ada koreksi, tambahkan migration baru yang idempotent dan dokumentasikan operasi forward-fix. Rollback dilakukan melalui backup restore drill atau migration kompensasi yang sudah direview; jangan menghapus tabel production secara manual.

## 4. Edge Functions dan worker

Deploy function yang berubah setelah database schema tersedia:

```bash
supabase functions deploy process-notification-queue
```

Set secret function melalui secret manager Supabase. Minimal periksa `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `WORKER_CRON_SECRET`, dan secret provider yang digunakan. Worker harus dipanggil oleh scheduler terautentikasi, tidak melalui endpoint publik tanpa header secret. Uji respons `401` tanpa secret, `405` untuk method salah, serta retry/dead-letter menggunakan job staging.

## 5. Railway deploy

Railway membangun image dari `Dockerfile`, menjalankan Caddy, dan mengekspos health check `/health`. Set variable public berikut pada service Railway:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY
VITE_SUPABASE_PROJECT_ID
```

Set `PORT` hanya jika Railway tidak menyediakannya otomatis. Setelah deploy, verifikasi:

```bash
curl -fsS "$RAILWAY_PUBLIC_URL/health"
curl -fsS -I "$RAILWAY_PUBLIC_URL/"
```

Expected health response adalah `{"status":"ok"}`. Pastikan source map atau secret tidak ikut ter-publish pada `dist`, dan pastikan SPA fallback, service worker, cache headers, serta HTTPS aktif.

## 6. Smoke test release

Jalankan pemeriksaan berikut berurutan: login/logout dan redirect Auth; RLS lintas tenant; POS checkout online; POS checkout offline lalu reconnect; effective price untuk retail/member/outlet; loyalty earn/redeem dan duplicate request; payment invoice/webhook idempotency; upload dan delete storage; realtime subscribe/timeout/reconnect; notification queue retry/dead-letter; reservation/FEFO/partial fulfillment; approval refund/void/price override/stock adjustment; registrasi PWA device, heartbeat, status kasir, dan revoke session.

Gunakan script yang sudah tersedia untuk API security dan backup drill:

```bash
SUPABASE_TEST_ENV_FILE=.env.rls.staging bash scripts/run-rls-staging.sh
bash scripts/security-api-smoke.sh
bash scripts/backup-restore-drill.sh
```

Jangan menjalankan script staging terhadap URL production. Script akan menolak target yang tidak berlabel staging kecuali override eksplisit yang hanya boleh digunakan saat incident response dengan approval tertulis.

## 7. Observability dan incident response

Event frontend memakai schema terstruktur dengan `domain`, `event`, `level`, `traceId`, `durationMs`, context yang disanitasi, dan error terbatas. Pantau payment failure/latency, upload failure, realtime channel failures, webhook/notification provider rejection, offline queue conflicts, serta device revoke/heartbeat failures. Jangan mencatat token, authorization header, nomor telepon, email, signature, password, atau isi bukti pembayaran.

Jika error rate meningkat, hentikan rollout, pertahankan worker lama bila masih kompatibel, dan gunakan trace ID untuk menghubungkan browser, Edge Function, dan database audit log. Revoke device yang mencurigakan melalui Admin > PWA Devices.

## 8. Rollback dan restore

Rollback aplikasi dilakukan dengan redeploy image Railway dari commit sebelumnya. Rollback database tidak dilakukan dengan `DROP` atau penghapusan migration. Gunakan migration kompensasi atau restore ke database baru sesuai `scripts/backup-restore-drill.sh`, kemudian jalankan ulang RLS dan RPC smoke test sebelum traffic dialihkan.

Release dianggap selesai hanya jika health check, smoke test transaksi, queue worker, RLS, backup verification, dan monitoring dasar semuanya lulus. Simpan commit SHA, migration version terakhir, waktu deploy, operator, hasil test, dan keputusan go/no-go.
