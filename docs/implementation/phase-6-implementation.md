# Evidence implementasi Tahap 6 — Quality engineering, observability, dan hardening

## Fitur yang dikerjakan

1. **Quality gate CI reliability surface**
   - Dependency dipasang dengan `pnpm install --frozen-lockfile`.
   - TypeScript, unit test, build, audit dependency, dan validasi package manager tetap dijalankan.
   - File yang menyentuh offline POS, service worker, dan observability wajib lulus ESLint dengan `--max-warnings=0`.

2. **Observability yang aman**
   - Correlation ID yang dikirim oleh caller tetap dipertahankan di setiap event lifecycle.
   - Pesan error dan context dibatasi panjangnya.
   - Email, nomor telepon, bearer token, secret, alamat, lokasi, payload, dan field sensitif lain tidak ditulis ke log.
   - Jumlah key context dibatasi agar cardinality log tidak tidak terkendali.

3. **Regression test operasional**
   - Test sanitasi PII dan credential.
   - Test pembatasan cardinality context.
   - Test kesinambungan correlation ID untuk event start/failure.
   - Test POS offline dan payment tetap dijalankan sebagai acceptance surface.

## Verifikasi lokal

```bash
pnpm install --frozen-lockfile
pnpm exec tsc --noEmit
pnpm exec eslint src/lib/observability.ts src/lib/observability.test.ts src/hooks/usePOSOfflineSync.ts src/lib/posOfflineDB.ts src/pages/pos/POSKasirPage.tsx src/sw.ts --max-warnings=0
pnpm exec vitest run src/lib/observability.test.ts src/hooks/usePOSOfflineSync.test.ts src/lib/posOfflineRecovery.test.ts src/lib/posOfflineCoordinator.test.ts src/test/pos-payment-e2e.test.tsx
pnpm build
```

## Batasan dan pekerjaan staging

CI repository tidak menggantikan dynamic staging test. Sebelum production scale, tetap diperlukan validasi RLS, race condition dua worker, pg_net/Vault, provider push/WhatsApp, cron lag, dan alert threshold menggunakan project staging terisolasi. Tidak ada secret production yang ditambahkan ke workflow.
