# Release Readiness Checklist SaDesa

Checklist ini menjadi gate bersama sebelum perubahan fase berikutnya dipromosikan ke staging atau production.

## Baseline repository

- [ ] Branch dan commit target tercatat.
- [ ] `pnpm install --frozen-lockfile` berhasil.
- [ ] `pnpm run validate:package-manager` berhasil.
- [ ] `pnpm run validate:migrations` berhasil.
- [ ] `pnpm run validate:db-bootstrap` berhasil.
- [ ] `pnpm run audit:rls` berhasil atau seluruh exception direview.
- [ ] `pnpm run build` berhasil.
- [ ] `pnpm test -- --run` berhasil.
- [ ] `pnpm exec eslint . --max-warnings=0` berhasil.
- [ ] `pnpm audit --audit-level high` tidak menemukan High/Critical.

## Database deployment gate

- [ ] Snapshot/backup staging tersedia.
- [ ] Migration bundle dan checksum dicatat.
- [ ] Migration terbaru telah diverifikasi pada database target.
- [ ] RPC, trigger, privilege, RLS policy, dan publication Realtime diverifikasi langsung.
- [ ] Restore drill berhasil pada database disposable.
- [ ] Tidak ada migration yang dijalankan otomatis dari frontend public service.

## Dynamic security gate

- [ ] Buyer A tidak dapat membaca atau mengubah data Buyer B.
- [ ] Courier A tidak dapat mengambil alih assignment Courier B.
- [ ] Merchant hanya dapat mengelola order dan data merchant miliknya.
- [ ] Admin dapat melakukan fungsi administratif yang diperlukan.
- [ ] Anonymous client tidak dapat menjalankan RPC protected.
- [ ] Direct table update untuk field sensitif ditolak.

## Transaction gate

- [ ] Checkout menghitung distance dan total secara authoritative.
- [ ] Reservation stok rollback bila checkout gagal.
- [ ] Payment invoice retry tidak membuat invoice provider duplikat.
- [ ] Refund pending tidak ditampilkan sebagai refund selesai.
- [ ] Webhook duplicate aman dan idempotent.
- [ ] COD dan settlement dapat direkonsiliasi.

## Realtime gate

- [ ] `chat_messages` tercantum pada publication `supabase_realtime`.
- [ ] Dua participant menerima message INSERT tanpa reload.
- [ ] Channel error melakukan retry/resubscribe.
- [ ] Message gap setelah reconnect dipulihkan.
- [ ] Fallback polling aktif saat Realtime offline.
- [ ] Duplicate message tidak tampil di UI.

## UI/UX gate

- [ ] Tidak ada horizontal clipping pada 320×568 dan 375×667.
- [ ] CTA tidak tertutup bottom navigation atau safe-area.
- [ ] Kartu order courier tetap terbaca dan tombol memiliki target tap minimal 44×44 px.
- [ ] Peta tidak menutupi status atau CTA.
- [ ] Loading, empty, error, offline, dan retry state terlihat jelas.
- [ ] Visual regression device matrix telah dijalankan.

## Bukti wajib sebelum promotion

Catat commit SHA, waktu test, environment, migration checksum, hasil test, hasil build, hasil dynamic RLS/concurrency, hasil two-user Realtime, dan keputusan approver dalam release record. Jika salah satu P0 gagal, hentikan promotion dan buat remediation record.
