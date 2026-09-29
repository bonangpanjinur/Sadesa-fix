# Audit POS Admin & Merchant — 29 September 2026

## Ringkasan eksekutif

Audit dilakukan terhadap route, guard akses, navigation, subscription/entitlement, katalog, inventory, checkout, pembayaran, outlet, pengguna kasir, laporan, QR menu/table order, audit trail, dan panel admin POS.

**Temuan yang diperbaiki pada audit ini:** aktivasi trial merchant sebelumnya melakukan `INSERT` langsung ke `pos_subscriptions` dari browser. Pola ini rentan race condition (klik paralel dapat membuat lebih dari satu trial) dan menjadikan aturan trial bergantung pada UI. Sekarang aktivasi memakai RPC `activate_pos_trial()` yang berjalan atomik di database, mengunci merchant, memeriksa trial/subscription existing, membaca konfigurasi trial dengan batas aman 1–90 hari, dan hanya memberi hak eksekusi kepada user authenticated.

## Matriks audit

| Area | Admin | Merchant | Status |
|---|---|---|---|
| POS feature gate dan subscription state | Konfigurasi trial, paket, status, approval/reject | Langganan, trial, renewal, status aktif/pending/suspended | **Ada; trial activation di-hardening** |
| Workspace/tenant dan setup | Monitoring entitlement | Setup workspace sebelum operasional | **Ada; guarded** |
| Katalog produk | Paket dan kontrol komersial | Produk, kategori, varian, harga, gambar, status aktif | **Ada** |
| Outlet & pengguna | Limit paket dan entitlement | Multi-outlet, kasir/manager/staff, role | **Ada; guarded RPC** |
| Penjualan/checkout | Monitoring transaksi dan audit | Cart, pembayaran, invoice, total atomic, idempotency | **Ada; guarded RPC** |
| Stok | Rekonsiliasi dan alert | Stock opname, adjustment, purchase/receiving, transfer, reservation | **Ada; guarded RPC** |
| Shift kasir | Approval dan audit | Buka/tutup shift, kas masuk/keluar, rekonsiliasi | **Ada** |
| QR menu & table order | Pengaturan publik dan kontrol stok | Menu QR, order meja, KDS, reservation stock | **Ada; guarded** |
| Loyalty/promosi/CRM | Monitoring KPI dan kampanye | Pelanggan, segmentasi, loyalty, promo | **Ada** |
| Laporan | Laporan canonical, history, audit export | Penjualan, laba-rugi, stok, kasir, outlet | **Ada** |
| Pembayaran/refund | Verifikasi bukti, refund approval, ledger | Bukti bayar dan status transaksi | **Ada; server-authoritative** |
| Security/RLS | Admin-only mutation dan audit log | Tenant/outlet isolation | **Ada; perlu deploy migration terbaru** |
| Operasional | Anomaly, reconciliation, entitlement processor | Error state dan retry | **Ada sebagian; observability perlu dipantau production** |

## Detail temuan dan keputusan

### P0 — trial dapat dibuat langsung dari browser (diperbaiki)

- **Sebelum:** `MerchantPOSSubscribePage` melakukan `.from('pos_subscriptions').insert(...)`.
- **Risiko:** double click/race request, aturan `trial_days` dapat dipalsukan dari client, dan kontrol “trial sekali” tidak atomic.
- **Sesudah:** page memanggil `supabase.rpc('activate_pos_trial')`.
- **Database guard:** `FOR UPDATE` pada merchant, penolakan trial existing, penolakan subscription `PENDING/ACTIVE`, `trial_days` clamp 1–90, status `ACTIVE`, payment `FREE`, dan grant authenticated-only.

### P1 — kontrak typecheck pencarian dan admin alarm (diperbaiki)

- Kategori pencarian sekarang konsisten dengan tipe `all/products`; cabang kategori yang tidak mungkin dihapus.
- Atribut `disabled` tombol simpan alarm admin sekarang menerima boolean eksplisit saat upload berjalan.

### P1 — pekerjaan lanjutan yang direkomendasikan

1. Regenerasi `src/integrations/supabase/types.ts` setelah migration `activate_pos_trial` masuk ke project Supabase aktif agar RPC tidak perlu cast `as never`.
2. Tambahkan test database/integration untuk dua request trial bersamaan dan merchant yang sudah memiliki subscription.
3. Jalankan deployment migration di staging, lalu uji skenario admin approve/reject, merchant trial expired, renewal, dan workspace setup.
4. Tinjau ulang manifest bootstrap yang sudah memiliki mismatch historis terhadap archive; validator baseline masih melaporkan source order/hash dan marker lama yang tidak terkait perubahan POS ini.
5. Tambahkan dashboard alert untuk subscription processor/reconciliation yang gagal agar admin tidak hanya melihat empty state.

## Verifikasi lokal

- `pnpm exec tsc --noEmit`: dijalankan setelah perbaikan typecheck.
- `pnpm test`: suite masih memiliki **3 contract test legacy** yang gagal karena expectation/path migration stale (RPC overload cleanup, service page literal, dan chat `FULL JOIN` pada bundle historis); tidak berasal dari perubahan trial POS.
- `python3 scripts/validate-bootstrap-bundles.py archive/supabase/migrations supabase/bootstrap`: baseline repository masih gagal pada mismatch historis manifest/hash/source marker; migration POS baru sudah ditambahkan ke archive dan bundle terakhir.

## File perubahan utama

- `archive/supabase/migrations/20260929123000_pos_trial_activation_hardening.sql`
- `supabase/bootstrap/55_20260929011000_nearest_courier_sequential_ride_dispatch.sql`
- `src/pages/merchant/MerchantPOSSubscribePage.tsx`
- `src/pages/SearchResultsPage.tsx`
- `src/pages/admin/AdminPushNotificationPage.tsx`
