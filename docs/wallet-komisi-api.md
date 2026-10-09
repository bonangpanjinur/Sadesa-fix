# Wallet Komisi — Ringkasan Fitur dan Dokumentasi API

Dokumen ini menjelaskan implementasi wallet pedagang/ojek pada repository Sadesa-fix. Ini menggambarkan kontrak kode saat ini, bukan pengganti dokumentasi resmi Xendit atau konfigurasi deployment Supabase.

## 1. Ringkasan fitur yang telah diimplementasikan

### Saldo, tarif, dan pencatatan

- Satu wallet rupiah untuk setiap pedagang dan courier/ojek; saldo disimpan sebagai `BIGINT` rupiah bulat.
- Tarif terpisah untuk `MERCHANT` dan `COURIER`, dapat diaktifkan/dinonaktifkan admin. Tarif awal `0%` dan nonaktif untuk mencegah potongan sebelum konfigurasi.
- Nilai komisi dibulatkan ke rupiah terdekat: `ROUND(nilai_dasar × tarif / 100)`.
- Potongan dihitung di database dari record transaksi yang tersimpan, bukan nominal/persentase yang dikirim client.
- Ledger mencatat mutasi saldo, perubahan tagihan, nilai dasar, snapshot tarif, sumber transaksi, waktu, dan kunci idempotensi.

### Basis komisi saat ini

| Pemilik | Sumber | Basis perhitungan | Kapan dicatat |
|---|---|---|---|
| Pedagang | Order marketplace | `orders.subtotal` (tidak termasuk ongkir) | Order masuk status selesai (`DONE`, `DELIVERED`, atau `COMPLETED`) |
| Ojek | Perjalanan penumpang | `ride_requests.final_fare` | Ride berstatus `COMPLETED` |
| Ojek | Pengiriman barang | `COALESCE(orders.courier_earning_estimate, orders.shipping_cost, 0)` | Order pengiriman selesai; diaktifkan terpisah dengan `charge_courier_delivery` |

Tarif delivery memakai persentase COURIER yang sama dengan ride; admin dapat mematikan komisi delivery tanpa mematikan komisi ride. Konfirmasi basis terhadap aturan bisnis (diskon/voucher/subsidi) masih menjadi prasyarat sebelum production.

### Kekurangan saldo, top-up, dan penguncian transaksi

- Jika saldo mencukupi, biaya komisi didebit dari saldo.
- Jika saldo tidak cukup, sisa komisi dicatat sebagai `debt_rupiah`; penyelesaian order/ride fisik tidak dibatalkan. Aktivitas baru pemilik yang memiliki utang diblokir sampai utang lunas.
- Courier yang dikenai komisi harus memiliki saldo positif dan tidak punya utang untuk online/menerima pekerjaan.
- Top-up selalu membayar utang terlebih dahulu; sisanya baru menjadi saldo yang dapat dipakai.
- Top-up manual menggunakan bukti transfer privat dan persetujuan admin. Satu permintaan pending per owner.
- Top-up Xendit mengkredit wallet hanya setelah callback terautentikasi, invoice/nominal cocok, dan event diproses secara idempoten.
- Wallet komisi courier terpisah dari `courier_deposits`/deposit operasional. Belum ada API penarikan/payout wallet.

### Refund dan notifikasi

- Jendela refund default 7 hari dan dapat diatur admin (rentang valid 1–365 hari).
- Komisi dikembalikan secara proporsional terhadap nilai refund, hanya setelah settlement refund sukses; reversal memakai idempotency key sendiri.
- Notifikasi in-app muncul pada saldo mencapai/di bawah ambang atau saat ada utang. Ambang default Rp10.000 dan dapat diubah admin.
- Peringatan hanya berjalan jika tarif role aktif dan lebih dari 0%. Satu notifikasi per siklus saldo rendah/tagihan; gate dibuka kembali setelah wallet pulih. Ini notifikasi di dalam aplikasi, bukan push browser.

### Migrasi dan UI

- Paket/tier kuota lama dihentikan; subscription aktif menjadi `EXPIRED`, tetapi histori dipertahankan untuk audit.
- Saldo kuota lama tidak otomatis dikonversi ke uang. Wallet baru dimulai dari saldo yang benar-benar di-top-up atau dikreditkan admin setelah verifikasi.
- Cutover berhenti dengan error jika ada pembelian/pembayaran kuota legacy yang masih pending; rekonsiliasi dahulu.
- Halaman pemilik tersedia di `/merchant/wallet` dan `/courier/commission-wallet`. Admin mengelola tarif, delivery courier, kebijakan refund/ambang, antrean top-up, wallet, debt, dan ledger.
- Riwayat ledger kini memakai cursor pagination per 50 baris. Filter tanggal merchant/ojek berlaku pada rentang inklusif tanggal yang dipilih. Ringkasan dan CSV pemilik/admin hanya mencakup halaman yang sedang dibuka; navigasikan halaman lain untuk mengunduh bagian berikutnya.

## 2. Objek database utama

| Objek | Fungsi |
|---|---|
| `public.commission_wallets` | Wallet per pemilik: `owner_type`, `merchant_id`/`courier_id`, `balance_rupiah`, `debt_rupiah`, status aktif, serta gate alert |
| `public.commission_fee_settings` | Tarif per role (`fee_percent`, `is_enabled`, dan `charge_courier_delivery`) |
| `public.commission_wallet_policy_settings` | `refund_window_days` dan `low_balance_threshold_rupiah` |
| `public.commission_wallet_ledger` | Buku mutasi append-oriented; `amount_delta_rupiah` ialah perubahan saldo dan `debt_delta_rupiah` perubahan tagihan. Nilai negatif pada debt melunasi utang |
| `public.commission_wallet_topup_requests` | Request top-up manual/Xendit, nominal, status, proof, invoice, dan catatan pemeriksaan |
| `public.commission_wallet_topup_webhook_events` | Event Xendit untuk deduplikasi/idempotensi webhook; hanya service role |
| `public.notifications` | Notifikasi in-app saldo rendah/tagihan yang terlihat lewat dropdown notifikasi aplikasi |

RLS membatasi pembacaan wallet/ledger/request ke pemilik terkait dan admin. Client tidak diberi izin mutasi langsung atas saldo atau ledger. `get_merchant_wallet_gate` mengungkap eligibility toko saja, bukan nominal saldo atau debt.

## 3. API Supabase RPC yang digunakan

Gunakan Supabase URL/project key dari konfigurasi aplikasi dan session JWT pengguna. Jangan pernah menaruh `service_role` key di browser.

### RPC pemilik dan admin

| RPC | Hak akses | Parameter | Hasil / kegunaan |
|---|---|---|---|
| `create_commission_wallet_topup_request` | `authenticated`; fungsi memverifikasi owner dari `auth.uid()` | `p_owner_type text`, `p_amount_rupiah bigint`, `p_proof_path text`, `p_note text DEFAULT NULL` | `uuid` request manual. Nominal Rp10.000–Rp1.000.000.000; path bukti harus milik user dan objeknya ada di bucket privat |
| `create_commission_wallet_topup_invoice_request` | `authenticated`; owner ditentukan dari session | `p_owner_type text`, `p_amount_rupiah bigint`, `p_note text DEFAULT NULL` | `uuid` request Xendit. Nominal Rp10.000–Rp1.000.000.000 |
| `process_commission_wallet_topup` | `authenticated`, tetapi wajib lolos `public.is_admin()`; hanya untuk provider MANUAL | `p_request_id uuid`, `p_approve boolean`, `p_admin_notes text DEFAULT NULL` | `jsonb`: status, saldo wallet, dan flag `already_processed`. Approval, kredit, pelunasan debt, dan ledger atomik |
| `admin_credit_commission_wallet` | `authenticated`/`service_role`; fungsi tetap mewajibkan `public.is_admin()` | `p_owner_type text`, `p_owner_id uuid`, `p_amount_rupiah bigint`, `p_idempotency_key text`, `p_note text` | Saldo setelah kredit. Dipakai untuk kredit admin yang telah diverifikasi; gunakan key unik |
| `get_merchant_wallet_gate` | `anon` dan `authenticated` | `p_merchant_ids uuid[]` | Baris `is_enabled` dan `merchant_id` eligible; tidak mengembalikan saldo. Dipakai katalog saat mode wallet aktif |
| `is_payment_provider_enabled` | RPC aplikasi untuk pemeriksaan provider | `p_provider text` (wallet mengirim `xendit`) | Boolean provider aktif; kegagalan dianggap nonaktif oleh UI |

Contoh pemanggilan top-up Xendit setelah request dibuat:

```ts
const { data: requestId, error } = await supabase.rpc(
  'create_commission_wallet_topup_invoice_request',
  { p_owner_type: 'MERCHANT', p_amount_rupiah: 100_000, p_note: 'Top-up saldo' }
);
if (error) throw error;

const response = await fetch(`${SUPABASE_URL}/functions/v1/xendit-payment/create-wallet-topup-invoice`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${session.access_token}`,
  },
  body: JSON.stringify({ topup_request_id: requestId }),
});
```

### RPC internal/trusted backend

Panggilan berikut bukan API browser umum. Database membatasi haknya ke `service_role` atau menggunakannya dari trigger/settlement tepercaya.

| RPC | Hak akses | Parameter penting | Peran |
|---|---|---|---|
| `apply_transaction_commission` | `service_role` | Overload utama: `p_owner_type`, `p_source_id`, `p_source_type`; sumber valid `ORDER`, `RIDE`, `COURIER_DELIVERY` | Mengambil nilai dasar dan owner dari record transaksi, menghitung/mencatat komisi secara idempoten, mengurangi saldo dan mencatat kekurangan sebagai debt |
| `credit_commission_wallet` | Internal; tidak diberikan ke `PUBLIC`, `anon`, atau `authenticated` | `p_wallet_id`, nominal, jenis sumber, source ID, idempotency key, catatan, user pembuat | Kredit atomik; melunasi debt lebih dahulu |
| `process_commission_wallet_topup_payment` | `service_role` saja | Request ID, event key, invoice ID, status, nominal dibayar, metode, channel | Memvalidasi callback Xendit, mendeduplikasi event dan mengkredit wallet/debt |
| `reserve_commission_wallet_topup_invoice` | `service_role` saja | `p_request_id uuid` | Reservasi invoice yang aman terhadap retry/concurrency; mengembalikan invoice terdahulu atau izin/request key |
| `complete_commission_wallet_topup_invoice` | `service_role` saja | Request ID, sukses, invoice ID/URL, expiry atau error | Menyimpan hasil create invoice dan mengakhiri reservasi |
| `reverse_commission_for_refund` | Internal, tidak dapat dieksekusi client | Refund request ID, order ID, nilai refund | Membalik komisi proporsional secara idempoten |
| `complete_refund_settlement` | `service_role` saja | Settlement ID, sukses, referensi provider, error | Menuntaskan refund dan memanggil reversal komisi hanya ketika settlement berhasil |

RPC komisi dipanggil oleh trigger saat status order/ride menjadi selesai. Client tidak seharusnya memanggilnya langsung.

## 4. Edge Function / HTTP API Xendit

Base URL Supabase: `https://<project-ref>.supabase.co/functions/v1`.

### Buat atau lanjutkan invoice top-up

`POST /xendit-payment/create-wallet-topup-invoice`

Headers: `Authorization: Bearer <user access token>`, `Content-Type: application/json`.

```json
{ "topup_request_id": "<uuid>" }
```

Sukses (`200`):

```json
{ "success": true, "invoice_id": "<provider invoice id>", "invoice_url": "https://...", "expiry_date": "<timestamp>" }
```

Invoice yang masih aktif dipakai kembali pada retry. Endpoint memverifikasi bahwa request dimiliki user, berstatus pending, dan menggunakan provider Xendit. Nominal diambil dari database. Kesalahan umum: `401` token tidak sah, `404` request/owner tidak ditemukan, `409` request tidak dapat dibayar atau sedang diproses, `502` provider gagal, `503` reservasi/payment service tidak tersedia.

### Callback provider

`POST /xendit-webhook` dipanggil server Xendit, bukan browser. Header `x-callback-token` dibandingkan dengan konfigurasi rahasia provider di server. Callback wallet memakai `external_id` berformat `wallet-topup-<request_uuid>`; field invoice ID, status (`PENDING`, `PAID`, `EXPIRED`), dan jumlah bayar diverifikasi sebelum mutasi. Balasan sukses berupa `{ "success": true }`; callback duplikat dijawab sukses dengan `duplicate: true` agar provider tidak mengulang tanpa henti.

## 5. Query ledger dan paginasi

Tabel ledger dibaca melalui Supabase PostgREST dengan JWT session dan RLS. Pemilik harus terlebih dahulu memperoleh `wallet_id` miliknya. Query halaman menerapkan:

- ukuran halaman tetap `50`;
- urutan menurun `created_at`, lalu `id` sebagai tie-breaker stabil;
- cursor keyset: `created_at < cursor.created_at OR (created_at = cursor.created_at AND id < cursor.id)`;
- pemilik juga menerapkan `wallet_id` dan rentang tanggal; batas akhir tanggal diperlakukan sebagai hari berikutnya eksklusif;
- count menghitung hasil yang tersisa dari cursor saat ini; tombol Berikutnya aktif bila jumlah tersisa lebih besar daripada jumlah baris yang sedang ditampilkan.

Sketsa query Supabase:

```ts
let query = supabase
  .from('commission_wallet_ledger')
  .select('id,wallet_id,entry_type,source_type,source_id,amount_delta_rupiah,debt_delta_rupiah,base_amount_rupiah,fee_percent,note,created_at', { count: 'exact' })
  .eq('wallet_id', walletId)
  .gte('created_at', fromIso)
  .lt('created_at', toExclusiveIso);

if (cursor) {
  query = query.or(
    `created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id})`
  );
}

const { data, count, error } = await query
  .order('created_at', { ascending: false })
  .order('id', { ascending: false })
  .limit(50);
```

Ringkasan yang ditampilkan dan CSV yang diunduh berlaku untuk halaman aktif, bukan otomatis seluruh periode. Pemilik dapat menavigasi dan mengunduh setiap halaman secara terpisah.

### Batas query UI yang bukan batas database

- Halaman pemilik memuat maksimal 10 request top-up terbaru.
- Dashboard admin memuat maksimal 100 request top-up terbaru dan 1.000 wallet pada panel akun. Karena ringkasan saldo/debt admin dihitung dari wallet yang dimuat, angka ringkasan dapat tidak lengkap bila project melewati 1.000 wallet; gunakan query/report database yang aman untuk rekonsiliasi penuh.
- Ledger pemilik dan admin telah dipaginasi; CSV mengekspor halaman aktif (maksimal 50 baris), bukan seluruh riwayat dalam satu file.

## 6. Aturan keamanan dan integritas

1. Jangan mengirim `balance_rupiah`, persentase, maupun nominal transaksi final sebagai sumber kebenaran untuk pemotongan; database membaca transaksi sendiri.
2. Jangan memberikan `service_role` key pada aplikasi web/mobile atau log.
3. Jangan mengkreditkan wallet hanya berdasarkan redirect sukses browser. Untuk Xendit, sumber kebenaran kredit adalah webhook terautentikasi dan nominal cocok.
4. Jangan menulis langsung ke `commission_wallets` atau `commission_wallet_ledger` dari client; gunakan RPC terotorisasi.
5. Simpan bukti transfer hanya di bucket privat `commission-topup-proofs`. File diterima JPG/PNG/WebP/PDF maksimal 8 MB; bukti yang terikat request tidak dapat dihapus pemilik.
6. Saldo kuota lama tidak otomatis ditukar menjadi saldo wallet. Tarif referral default 0% dan nonaktif; aktifkan di production hanya setelah bundle 92 dan skenario rekonsiliasi referral diuji di staging.

## 7. Bundle deployment

Semua SQL wallet/komisi berada di `supabase/bootstrap` dan diterapkan berurutan:

- `86_20261009090000_commission_wallet_system.sql`
- `87_20261009091000_commission_wallet_topups.sql`
- `88_20261009092000_commission_wallet_operations.sql`
- `89_20261009093000_xendit_commission_wallet_topups.sql`
- `90_20261009094000_commission_refund_policy.sql`
- `91_20261009100000_commission_wallet_alerts.sql`
- `92_20261009110000_merchant_referral_commissions.sql` (bundle standalone untuk kode referral, accrual, reversal refund, dan payout)

Sebelum production: deploy Edge Functions, set credential/callback Xendit, uji di staging, dan audit basis komisi/refund terhadap aturan bisnis aktual. Kode repository saja tidak membuktikan bundle telah diterapkan ke project Supabase tertentu.


## 8. Komisi referral pedagang (bundle 92)
Basis komisi adalah **fee platform merchant yang benar-benar tertagih**. Nilai fee yang masih menjadi debt tidak memberi earning referral; jika kemudian dibayar oleh top-up, alokasi debt fee diproses FIFO dan earning baru dicatat sebesar bagian yang tertagih. Tarif `VERIFIKATOR` dan `ADMIN_DESA` independen, `0%` dan nonaktif secara default. Tarif/referrer disnapshot pada fee source; perubahan tarif berikutnya hanya berlaku pada transaksi baru.

### Objek dan atribusi
- `merchant_referral_commission_settings`: tarif dan toggle per role.
- `merchant_referral_codes`: kode generik; kode verifikator lama dimirror, sementara admin desa membuat kode melalui RPC. Kode harus aktif dan belum mencapai batas pakai.
- `merchants.referral_owner_user_id`, `referral_owner_role`, `referral_code_id`: attribution pedagang yang tidak dapat diganti lewat edit biasa setelah kode terpasang.
- `merchant_referral_fee_sources` dan `merchant_referral_fee_collection_allocations`: rekonsiliasi fee merchant, debt, pembayaran debt, basis earning, jendela refund, dan fee lama non-referral.
- `merchant_referral_commission_ledger`: signed ledger `EARNING`, `REFUND_REVERSAL`, dan `WITHDRAWAL`; idempotency key unik.
- `merchant_referral_payout_requests`: permintaan, approval/rejection, status pembayaran, dan referensi transfer. Pembayaran dilakukan manual di luar aplikasi.

### RPC referral
| RPC | Akses | Parameter | Peran |
|---|---|---|---|
| `check_merchant_referral_code` | `anon`, `authenticated` | `p_code text` | Mengembalikan `{valid, owner_role}` saja; tidak memaparkan ID pemilik. Dipakai validasi registrasi. |
| `create_admin_desa_referral_code` | `authenticated` dengan role `admin_desa` dan desa approved | `p_code text`, `p_description text DEFAULT NULL` | Membuat kode unik 3–32 karakter. Desa dipilih dari relasi akun yang disetujui. |
| `get_merchant_referral_commission_summary` | `authenticated`, user hanya untuk role miliknya | `p_owner_role text` | Ringkasan rate, enabled, pending, tersedia, reservasi payout, net ledger. |
| `get_merchant_referral_merchants` | `authenticated`, user hanya untuk role miliknya | `p_owner_role text` | Daftar nama/status merchant yang memakai kodenya, fee tertagih, earning net, jumlah fee events; tanpa data kontak. |
| `create_merchant_referral_payout_request` | `authenticated`, role pemilik harus cocok | `p_owner_role text`, `p_amount_rupiah bigint`, `p_bank_name text`, `p_account_number text`, `p_account_holder text` | Minimal Rp10.000; mengunci akun agar request concurrent tidak melebihi saldo tersedia dan mereservasi saldo selama pending/approved. |
| `process_merchant_referral_payout` | `authenticated`, wajib `public.is_admin()` | `p_request_id uuid`, `p_status text`, `p_admin_notes text DEFAULT NULL`, `p_payout_reference text DEFAULT NULL` | `APPROVED`, `REJECTED`, atau `PAID`; PAID mensyaratkan referensi transfer dan menulis debit ledger idempoten. |

### Peristiwa internal
Trigger `process_merchant_referral_wallet_ledger` membuat fee source pada komisi merchant, mengalokasikan pelunasan debt dari top-up, lalu memanggil `post_merchant_referral_fee_collection` untuk menghitung delta earning. `reverse_commission_for_refund` tetap internal dan hanya dipanggil oleh `complete_refund_settlement` setelah settlement berhasil; ia menyesuaikan fee wallet dan membuat `REFUND_REVERSAL` referral secara idempoten. RPC `get_merchant_referral_*` dan payout memeriksa `auth.uid()`/role; ledger dan payout menerapkan RLS owner/admin, sedangkan fee source/allocations hanya dapat dibaca admin.

UI terkait:
- Admin: `/admin/referral-commissions`
- Verifikator: tab **Komisi Referral Merchant** pada halaman earnings
- Admin desa: `/desa/komisi-referral`

Bundle 92 berdiri sendiri di `supabase/bootstrap` dan tidak ditambahkan ke `archive/supabase/migrations`, sesuai ketentuan repository. Jalankan bundle setelah bundle 91. `validate:db-bootstrap` memeriksa manifest/marker; validasi tersebut bukan pengganti eksekusi dan integrasi test terhadap database staging.
