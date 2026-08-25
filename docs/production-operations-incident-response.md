# Production Operations and Incident Response Runbook

## 1. Purpose and operating principles

Runbook ini digunakan setelah sistem dirilis ke production. Prinsip utamanya adalah menjaga integritas transaksi, mencegah tenant data leakage, menghentikan propagasi kerusakan secepat mungkin, dan menyimpan bukti audit yang cukup untuk recovery. Jangan mengubah data finansial atau stok langsung dari browser/database console tanpa migration/RPC yang direview.

## 2. Monitoring baseline

Observability frontend menghasilkan event JSON dengan `domain`, `event`, `level`, `traceId`, `durationMs`, context tersanitasi, dan error terbatas. Domain penting adalah `payment`, `upload`, `realtime`, `webhook`, `offline_sync`, dan `device`. Edge Function worker harus menulis log JSON dengan job ID, channel, attempts, provider message ID, dan error yang sudah dipotong; token dan payload sensitif tidak boleh dicatat.

| Signal | Normal expectation | Trigger investigation |
|---|---|---|
| `/health` Railway | HTTP 200 dan JSON status ok | Any non-2xx, timeout, atau restart loop |
| POS checkout failure | Rendah dan terlokalisasi | Kenaikan mendadak, duplicate meningkat, atau stock/price conflict tidak wajar |
| Payment webhook | Success dan latency stabil | Signature rejection, amount mismatch, replay, queue backlog |
| Notification queue | Queue drains within SLA | Job failed/dead-letter meningkat atau provider 401/429 |
| Realtime | Channels reconnect normally | `CHANNEL_ERROR`, `TIMED_OUT`, atau reconnect storm |
| Offline sync | Queue drains after reconnect | Conflict queue menumpuk, stale claims, duplicate sales |
| Upload | Error rate rendah | MIME/size rejection abnormal, storage 401/403, atau latency naik |
| PWA devices | Active devices heartbeat | Device revoked unexpectedly, stale cashier, abnormal device count |
| Database | Lock and connection stable | Deadlock, long transaction, connection exhaustion, migration failure |

## 3. Severity classification

**SEV-1** adalah data leakage lintas tenant, transaksi ganda/kehilangan saldo, payment settlement mismatch massal, credential compromise, atau database corruption. **SEV-2** adalah checkout/payment/stock operation gagal pada sebagian besar tenant, notification provider outage, atau offline queue tidak dapat pulih. **SEV-3** adalah satu tenant atau fitur non-critical terganggu tanpa indikasi integritas data. **SEV-4** adalah cosmetic issue, warning, atau degradation yang memiliki workaround.

## 4. First response procedure

Operator mencatat waktu mulai, commit SHA, migration version, affected tenant/outlet, trace ID, error code, dan gejala bisnis. Jangan menghapus queue, log, webhook event, atau audit record sebelum bukti diekspor. Ambil snapshot status `/health`, log Edge Function, queue counts, database locks, dan recent deployment state.

Untuk dugaan security incident, segera revoke affected PWA devices dari Admin > PWA Devices, rotate secret yang terindikasi, suspend worker atau webhook route yang diserang, dan batasi akses tanpa menghapus bukti. Untuk dugaan transaksi salah, hentikan retry otomatis terlebih dahulu; jangan melakukan refund/stock adjustment manual tanpa approval workflow.

## 5. Payment and checkout incident

Jika payment webhook gagal, periksa provider event ID, signature verification, invoice ID, order ID, paid amount, dan idempotency record. Retry hanya dengan event yang sama melalui worker/RPC idempotent. Jika ada amount mismatch atau replay, tandai unresolved dan lakukan reconciliation; jangan mengubah status order langsung.

Jika POS checkout gagal, periksa error code dan trace ID. `P0001` pada offline sync berarti price conflict dan harus masuk resolusi manual; jangan retry tanpa memperbarui harga atau meminta operator memilih tindakan. `55P03` berarti request sedang diproses/lock conflict dan perlu menunggu atau memeriksa idempotency record. Untuk stock shortage, verifikasi batch/warehouse/reservation sebelum melakukan adjustment melalui approval.

## 6. Notification and webhook incident

Untuk WhatsApp/provider error, cek HTTP status, provider error code, job attempt, next attempt, dan dead-letter threshold. HTTP 401/403 mengarah ke secret/permission; 429 mengarah ke rate limit; 5xx perlu retry backoff. Jangan mencatat access token atau full recipient number. Setelah provider pulih, re-drive dead-letter secara bertahap dengan idempotency key dan monitor duplicate delivery.

Worker harus tetap menggunakan header secret atau service-role authorization yang tidak pernah diterima dari browser biasa. Jika secret bocor, rotate secret, redeploy function, invalidate worker callers lama, dan jalankan API security smoke test.

## 7. Offline sync and realtime incident

Jika queue offline menumpuk, bedakan `retryable`, `conflict`, `stale`, dan `failed`. Recover stale claims hanya melalui mekanisme resmi. Konflik harga tidak boleh dipaksa retry; tampilkan server snapshot dan minta cashier menyelesaikan manual. Setelah jaringan pulih, lakukan drain bertahap dan pantau duplicate request serta stock mutation.

Jika realtime timeout atau channel error meningkat, cek status Supabase Realtime, auth token expiry, browser connectivity, dan reconnect frequency. Hindari membuat subscription baru tanpa cleanup karena dapat menimbulkan reconnect storm dan beban berlebih.

## 8. Upload and storage incident

Periksa bucket, object path tenant, MIME/size validation, signed/public URL policy, dan authorization. Untuk dugaan file leakage, segera ubah object policy atau bucket exposure, revoke URL/signed sessions sesuai provider, dan audit object access. Jangan menampilkan URL payment proof atau dokumen sensitif sebagai public URL.

## 9. Database, migration, and RLS incident

Jika migration gagal, hentikan migration berikutnya dan simpan error lengkap. Jangan mengedit migration yang sudah tercatat atau menjalankan SQL parsial secara manual. Gunakan migration kompensasi yang direview atau restore ke database baru sesuai backup drill.

Jika RLS leakage ditemukan, aktifkan containment dengan menonaktifkan route/query yang terdampak, capture reproducer tenant A/B, dan tambahkan policy/RPC fix. Setelah fix, jalankan `pnpm audit:rls`, RLS mutation suite, dan test tenant isolation di staging sebelum production redeploy.

## 10. Railway incident and rollback

Jika `/health` gagal, periksa deploy logs, container restart count, `PORT`, Caddy config, static `dist`, dan Railway environment variables. Pastikan hanya public `VITE_*` config masuk ke frontend. Rollback aplikasi dilakukan dengan redeploy commit image terakhir yang diketahui sehat.

Rollback database tidak dilakukan dengan menghapus migration. Gunakan compensating migration atau restore procedure. Setelah rollback, jalankan health check, login, checkout read-only, payment status read, RLS smoke test, dan queue status sebelum membuka kembali traffic.

## 11. Recovery closure

Incident dapat ditutup setelah error rate kembali normal, queue tidak menumpuk, payment/reconciliation balance cocok, stock mutation tidak memiliki orphan, RLS test pass, affected devices/secret sudah ditangani, dan business owner menyetujui recovery. Tulis post-incident report yang mencakup timeline, root cause, affected scope, detection gap, data integrity review, corrective migration/code commit, dan follow-up owner.

## 12. Quick commands

```bash
curl -fsS "$RAILWAY_PUBLIC_URL/health"
pnpm audit:rls
pnpm validate:migrations
pnpm test
pnpm build
RLS_ENV_FILE=.env.rls.staging ./scripts/run-rls-staging.sh
SUPABASE_TEST_ENV_FILE=.env.rls.staging bash scripts/security-api-smoke.sh
bash scripts/backup-restore-drill.sh
```

Semua command yang menyentuh staging harus menggunakan environment file staging dan target terpisah. Jangan menjalankan smoke test destructive atau restore drill terhadap production.
