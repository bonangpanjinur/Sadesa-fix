# Evidence implementasi Fase 3–5

Dokumen ini membedakan kontrak yang sudah ada di repository dari validasi
staging, pilot, dan keputusan komersial yang belum boleh dianggap produksi.

## Fase 3 — POS online/offline yang aman

- Queue, checkpoint sebelum RPC, lease, retry, dead-letter, conflict center,
  dan scope tenant/outlet tetap menjadi fondasi offline.
- `src/lib/posDevicePolicy.ts` sekarang menyatakan capability minimum secara
  eksplisit: HTTPS, IndexedDB, dan service worker. Operasi offline hanya
  mencakup penjualan tunai, katalog cache, dan receipt lokal; payment online,
  order marketplace, laporan final, dan settlement tetap online-only.
- Conflict center menyediakan reset data lokal dengan scope tenant/outlet.
  Reset membutuhkan konfirmasi karena dapat menghapus transaksi yang belum
  tersinkronisasi dari perangkat.
- Uji fisik browser/PWA/printer, crash, listrik mati, dan recovery lintas
  channel masih menjadi gate staging/pilot.

## Fase 4 — laporan yang layak dipercaya

- Laporan penjualan utama, laba-rugi, cashflow, akuntansi, dan kas memakai
  `get_pos_canonical_report` atau RPC rekonsiliasi harian.
- Bundle canonical reporting diperbaiki agar ringkasan pembelian masuk ke
  `purchases`, bukan tertimpa/tertinggal di variabel jurnal.
- Export hanya boleh memakai dataset canonical yang sama dengan layar. Laporan
  pajak tetap berlabel estimasi.
- Migration, golden dataset, timezone, rekonsiliasi nyata, dan import finance
  belum diuji di Supabase staging.

## Fase 5 — pertumbuhan dan monetisasi lanjutan

- Bundle komersial `26`–`27` menyediakan limit outlet/user, add-on user,
  promo onboarding idempotent, partner eligibility, dan SLA support.
- `src/lib/feeEngine.ts` menambahkan kontrak lokal untuk fee schedule forward-only,
  effective date, payer (buyer/merchant/provider), dan fee snapshot per order.
  Snapshot menyimpan versi jadwal dan nominal tiap rule sehingga perubahan tarif
  tidak retroaktif.
- Fee engine belum terhubung ke checkout/payout ledger produksi. Tarif, pajak,
  waiver, dispute, usage fee provider, risk scoring, maker-checker, dan
  approval bisnis tetap membutuhkan desain serta staging/payment sign-off.

## Status

Fase 3 tetap **sebagian selesai** sampai uji fisik. Fase 4 **selesai secara
teknis di repository, belum lulus staging**. Fase 5 **sebagian selesai**:
kontrol paket/promo/support dan kontrak fee snapshot tersedia, sedangkan
monetisasi produksi dan control tower belum diklaim selesai.