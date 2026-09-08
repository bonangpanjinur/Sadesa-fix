# Evidence implementasi Fase 0–2

Dokumen ini mencatat pekerjaan repository untuk tiga fase awal roadmap. Status
repository tidak sama dengan lulus staging atau siap produksi. Migration,
fixture, dan uji environment tetap harus dijalankan pada project Supabase
staging sebelum gate dinaikkan.

## Fase 0 — keputusan produk dan aturan komersial

### Keputusan yang menjadi kontrak aplikasi

- Marketplace gratis dan tidak membutuhkan `pos_tenant`, subscription, atau
  entitlement POS untuk membuat katalog dan menerima order.
- POS adalah akses berbayar yang hanya operasional pada status `trial`,
  `active`, atau `grace`.
- Suspend/cancel POS tidak menghapus katalog, histori, atau akses marketplace.
- QR meja hanya boleh aktif dengan entitlement POS operasional dan konteks meja
  yang tervalidasi server-side.
- Operasi offline dibatasi pada penjualan tunai, katalog cache, dan receipt
  lokal. Payment online, order marketplace, dan laporan final tetap online.
- Harga pada halaman pricing adalah harga uji, bukan konfigurasi harga produksi.

Kontrak tersebut dipusatkan di `src/lib/marketplacePosPolicy.ts` dan diuji di
`src/lib/marketplacePosPolicy.test.ts`. Halaman pricing dan FAQ tetap menjadi
permukaan komunikasi merchant.

### Masih membutuhkan sign-off

- Product/Finance: harga uji, trial, grace, downgrade, refund, dan payout.
- Operations/Legal: cancellation, dispute, pajak estimasi, privacy, retention,
  consent, dan jalur support.
- Product/Data: metric dictionary, timezone, deduplication, serta source of
  truth dashboard dan export.

## Fase 1 — entitlement dan billing

`src/lib/posSubscription.ts` sekarang menormalkan status database yang berbeda
kapitalisasi dan mendukung status eksplisit `GRACE`. Ini mencegah UI salah
menganggap subscription lowercase atau grace yang masih berlaku sebagai expired.
Test lifecycle mencakup active, expiring, pending, suspended, cancelled, dan
grace.

Guard server-side tetap berada di bootstrap Supabase (`12`, `14`, `19`, dan
`20`). Repository belum menyatakan fase ini lulus sampai bundle diterapkan,
webhook/payment retry diuji idempotent, dan marketplace-only dibuktikan dengan
fixture merchant tanpa POS.

## Fase 2 — katalog, stok, inbox, dan QR

`src/lib/categoryContracts.ts` menambahkan kontrak versionable untuk kategori
produk fisik, makanan/minuman, jasa, sewa, dan pengalaman/wisata. Setiap
template memiliki:

- workflow yang berbeda (`order`, `service_request`, `rental`, `booking`);
- atribut listing yang perlu disiapkan;
- state transition yang tidak boleh dilompati;
- alias kategori untuk slug marketplace yang sudah ada.

Form katalog merchant menampilkan template dan atributnya saat merchant memilih
kategori. Kontrak tidak membuat ledger baru: payment, refund, dispute, dan
settlement tetap memakai ledger bersama.

Fondasi mapping, reservation, projection, stale alert, varian/outlet, serta
QR/menu/meja tetap berasal dari bootstrap `10`–`28`. Evidence staging yang
masih terbuka:

1. tenant isolation dan token meja invalid/nonaktif;
2. concurrency reservation/projection dan recovery;
3. E2E merchant marketplace-only sampai fulfillment;
4. penerapan migration `28` dan validasi order `table_qr` ke KDS/status.

## Verification lokal

```sh
npx tsc --noEmit
npm run lint
npm test
npm run build
```

Lulus lokal hanya membuktikan kontrak source dapat dibangun dan diuji; tidak
membuktikan staging Supabase sudah memakai bundle yang sama.