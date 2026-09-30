# Audit End-to-End Checkout SaDesa

**Tanggal:** 18 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Ruang lingkup:** checkout marketplace produk, cart, pembayaran COD/transfer/online, reservasi stok, order buyer, pemrosesan merchant, pengiriman, dan kontrol akses terkait.

## Ringkasan eksekutif

Secara arsitektur, checkout sudah bergerak ke arah yang benar. Jalur pembuatan order telah dipusatkan pada RPC `create_marketplace_checkout`, client tidak lagi menjadi sumber kebenaran harga/order, terdapat idempotency key, validasi stok dan merchant di database, reservasi stok, serta webhook Xendit yang diproses secara atomic dan idempotent. Checkout multi-merchant juga sengaja ditolak agar satu order tidak memiliki ambiguitas pembayaran dan fulfilment.

Namun, sistem belum layak dinyatakan production-ready tanpa perbaikan berikut. Temuan paling serius adalah bucket `payment-proofs` dibuat **public** dan policy storage memberikan hak `SELECT`, `UPDATE`, dan `DELETE` terlalu luas. Bukti transfer dapat terbaca publik dan file milik user lain dapat diubah atau dihapus oleh user terautentikasi lain. Selain itu, pengalaman pembeli ketika pembayaran online gagal masih kontradiktif, kontrol expiry transfer perlu diverifikasi di staging, dan alur merchant masih membutuhkan pengujian state transition serta rekonsiliasi operasional.

## Matriks temuan

| ID | Prioritas | Area | Temuan | Dampak utama | Status |
|---|---|---|---|---|---|
| P0-01 | **P0** | Keamanan bukti pembayaran | Bucket `payment-proofs` public; SELECT/UPDATE/DELETE tidak scoped ke pemilik order | Kebocoran data finansial, manipulasi atau penghapusan bukti transfer | **Wajib diperbaiki sebelum produksi** |
| P1-01 | P1 | Online payment UX | Invoice gagal setelah order berhasil dibuat; UI menampilkan toast gagal lalu melanjutkan ke sukses generik | Pembeli bingung, order unpaid tetap menahan stok sampai expiry, retry tidak jelas | Perlu diperbaiki |
| P1-02 | P1 | Buyer transfer | Bukti transfer dapat diganti berkali-kali selama order belum final; belum tampak audit trail/versioning proof | Sengketa sulit direkonstruksi; merchant dapat melihat bukti terakhir saja | Perlu diputuskan dan diuji |
| P1-03 | P1 | Stok/expiry | Reservasi stok menggunakan worker `service_role`; bila scheduler tidak aktif, stok dapat tertahan hingga cleanup berjalan | Produk tampak habis walau pembayaran tidak selesai | Wajib diverifikasi deployment |
| P1-04 | P1 | Merchant operations | Merchant dapat menandai status fulfilment dari UI; safety bergantung pada RPC/state machine dan policy database yang benar-benar terpasang | Lompatan status, pengiriman sebelum pembayaran, atau order stuck bila migration tidak sinkron | Wajib diuji staging |
| P1-05 | P1 | Multi-merchant cart | Cart boleh berisi beberapa toko, tetapi checkout ditolak dan pembeli diminta memisahkan manual | Friksi conversion; pembeli tidak mendapat split-checkout otomatis | Keputusan produk, bukan bug keamanan |
| P2-01 | P2 | Buyer UX | Stock pre-check di client bersifat informatif dan dapat stale; pesan error server masih raw pada beberapa jalur | Kebingungan saat race condition stok/merchant | Perbaikan UX |
| P2-02 | P2 | Observability | Belum ada bukti static bahwa metrik checkout mencakup funnel per payment method, expiry, reservation failure, dan merchant acknowledgement | Diagnosis kegagalan produksi lambat | Tambahkan dashboard/alert |

## Alur yang diaudit

### Sisi pembeli

Alur normal adalah: pembeli memilih item → cart mengelompokkan berdasarkan merchant → pembeli masuk checkout → alamat dan titik lokasi divalidasi → metode pengiriman dipilih → metode pembayaran dipilih → server memvalidasi item, merchant, harga, stok, voucher, ongkir, dan fee → order dibuat melalui RPC → stok direservasi → untuk online invoice dibuat → untuk transfer pembeli mengunggah bukti → merchant memproses → kurir/ekspedisi/ambil sendiri → pembeli melihat status dan menyelesaikan transaksi.

Guard yang terlihat di kode:

- user wajib login;
- cart kosong ditolak;
- checkout multi-merchant ditolak di UI dan database;
- toko tutup ditolak;
- alamat dan titik koordinat diwajibkan untuk pengiriman;
- COD hanya memakai nomor WhatsApp yang lolos validasi;
- client mengirim `product_id` dan quantity, sedangkan harga dan flash price dihitung ulang server;
- order creation memakai `p_checkout_key` dan advisory lock untuk mencegah duplikasi akibat retry;
- insert langsung ke `orders` dan `order_items` untuk buyer dicabut, sehingga jalur resmi adalah RPC.

### Sisi pedagang

Merchant menerima order berdasarkan status, melihat informasi pembeli/pengiriman, memverifikasi bukti transfer, menerima atau menolak order, menyiapkan barang, memilih antar sendiri atau kurir desa, memasukkan data ekspedisi/resi, dan menandai status pengiriman. Order history merchant juga memiliki filter status, tipe pengiriman, tanggal, refresh, export, serta dialog detail.

Risiko operasional utama bukan lagi sekadar UI, melainkan sinkronisasi antara status order, payment status, delivery assignment, reservasi stok, notifikasi, dan laporan omzet. Semua state transition harus diuji sebagai transaksi database, bukan hanya diuji dengan mengklik UI.

## Temuan detail

### P0-01 — Bukti transfer terbuka publik dan storage policy terlalu luas

**Bukti kode:** `supabase/bootstrap/03_20260203_updat_to_20260208001230.sql` baris 1104–1131.

Bucket dibuat dengan `public = true`, kemudian policy berikut dipasang:

```sql
CREATE POLICY "Payment proofs are publicly viewable"
ON storage.objects FOR SELECT
USING (bucket_id = 'payment-proofs');

CREATE POLICY "Users can update their own payment proofs"
ON storage.objects FOR UPDATE
USING (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated');

CREATE POLICY "Users can delete their own payment proofs"
ON storage.objects FOR DELETE
USING (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated');
```

Policy INSERT juga hanya mensyaratkan role authenticated dan tidak membatasi folder ke `auth.uid()` atau order milik user. Nama policy menyebut “own”, tetapi predicate tidak memeriksa ownership.

**Dampak pembeli:** screenshot rekening, nama, nominal, waktu transfer, dan informasi finansial dapat diakses publik bila URL diketahui/terindeks; user lain dapat mengubah atau menghapus object bukti.

**Dampak merchant:** bukti dapat berubah setelah dilihat atau hilang sebelum diverifikasi; status order dan keputusan pembayaran tidak lagi memiliki evidence yang kuat.

**Perbaikan yang direkomendasikan:**

1. Ubah bucket menjadi private.
2. Gunakan path deterministik yang diawali user/order, misalnya `<buyer_id>/<order_id>/<uuid>.webp`.
3. Batasi INSERT dengan `auth.uid()` dan validasi bahwa order dimiliki user tersebut serta metode pembayarannya TRANSFER. Karena storage policy tidak selalu nyaman melakukan join kompleks, gunakan RPC/Edge Function upload yang melakukan validasi ownership sebelum upload.
4. Batasi SELECT ke buyer pemilik order, merchant pemilik order, admin/verifikator sesuai kebutuhan, atau jangan berikan SELECT langsung dan selalu keluarkan signed URL dari server/RPC scoped.
5. Batasi UPDATE/DELETE ke object yang dimiliki uploader/order terkait; idealnya bukti immutable setelah tersimpan dan penggantian membuat versi baru dengan audit trail.
6. Hapus policy lama yang broad dari bootstrap/migration dan tambahkan regression test RLS storage.

### P1-01 — Kegagalan invoice online menghasilkan state UI yang kontradiktif

**Bukti kode:** `src/pages/CheckoutPage.tsx` baris 562–585.

Order dibuat lebih dulu. Bila `createPaymentInvoice()` gagal, kode menampilkan “Pesanan dibuat, tapi pembayaran gagal”, tetapi tidak menghentikan alur. Kode kemudian menghapus item dari cart, mereset checkout key, mengisi state success, dan menampilkan toast “Pesanan berhasil dibuat!”.

**Dampak:** pembeli menerima dua pesan yang bertentangan. Order tetap `UNPAID` dan stok tetap direservasi, tetapi pembeli tidak diarahkan secara tegas ke retry invoice atau halaman order. Bila halaman order tidak memiliki CTA retry yang jelas, order berpotensi expired tanpa tindakan pembeli.

**Perbaikan:** setelah order berhasil tetapi invoice gagal, arahkan ke halaman order/payment recovery dengan status “order created, payment pending”, pertahankan cart atau tampilkan informasi bahwa item sudah menjadi order, sediakan tombol retry invoice yang idempotent, dan jangan tampilkan success generik. Tambahkan test untuk network failure, timeout, refresh, dan retry.

### P1-02 — Bukti transfer belum memiliki jejak versi yang kuat

RPC `buyer_submit_payment_proof` sudah benar dalam hal ownership order dan metode TRANSFER, serta menolak beberapa status final. Namun RPC melakukan update satu kolom `orders.payment_proof_url`; penggantian bukti menimpa URL sebelumnya.

**Dampak:** ketika buyer mengganti screenshot atau merchant menolak bukti, sistem tidak memiliki histori evidence yang memadai untuk dispute. Ini terutama penting karena pembayaran transfer masih memerlukan pemeriksaan manual.

**Perbaikan:** buat tabel `order_payment_proofs` append-only berisi order, uploader, object path, checksum, created_at, dan status review. Kolom `orders.payment_proof_url` dapat dipertahankan sebagai current pointer untuk kompatibilitas, tetapi bukan satu-satunya sumber audit.

### P1-03 — Expiry reservation bergantung pada worker deployment

Migration hardening membatasi `expire_marketplace_stock_reservations` hanya untuk `service_role`, yang tepat dari sisi privilege. Tetapi repository harus memastikan scheduler/worker benar-benar memanggil fungsi ini secara rutin. Jika tidak, order `PENDING_PAYMENT` atau `UNPAID` dapat menahan stok.

**Checklist deployment:** scheduler aktif, interval lebih kecil dari expiry, menggunakan service role hanya di lingkungan server/Edge Function, ada alert ketika reservation aktif yang sudah lewat expiry menumpuk, dan cleanup idempotent.

### P1-04 — Merchant state machine harus diuji terhadap payment guard

UI merchant menyediakan aksi menerima, menolak, siap diambil, handoff ekspedisi, antar sendiri, assignment kurir, dan delivered. Database memiliki beberapa RPC transition dan guard. Audit static belum dapat membuktikan bahwa seluruh migration production/staging terpasang berurutan dan bahwa setiap mutation UI benar-benar memakai RPC guarded, bukan direct update yang tersisa.

**Skenario wajib:**

- order TRANSFER tidak dapat diproses sebelum bukti diverifikasi;
- order ONLINE tidak dapat diproses sebelum `PAID`;
- order COD dapat diproses sesuai kebijakan COD;
- merchant A tidak dapat mengubah order merchant B;
- merchant tidak dapat menandai `DONE` tanpa delivery proof/konfirmasi yang diwajibkan;
- cancel/reject merilis reservasi tepat satu kali;
- payment callback yang datang bersamaan dengan expiry menghasilkan satu keputusan konsisten.

### P1-05 — Multi-merchant checkout masih menjadi dead-end UX

Cart dapat memuat item dari beberapa toko, tetapi `CheckoutPage` menolak `merchantIds.length > 1`. Database juga menolak multi-merchant checkout untuk versi authoritative terbaru. Ini aman dibanding membuat partial orders tanpa ringkasan biaya yang jelas, tetapi buyer harus menghapus/memisahkan item secara manual.

**Perbaikan produk:** sediakan “Checkout toko ini” pada setiap kelompok merchant, atau split checkout menjadi beberapa order dengan ringkasan biaya per toko dan aturan pembayaran yang eksplisit. Jangan mengaktifkan split tanpa idempotency, voucher allocation, shipping allocation, dan payment reconciliation per child order.

### P2-01 — Client stock check bukan jaminan final

`CheckoutPage` melakukan query stok sebelum RPC. Ini membantu feedback, tetapi race condition tetap mungkin terjadi. Jaminan final memang berada pada lock dan reservation di database. UI perlu menerjemahkan error `Insufficient stock`, `Merchant unavailable`, `reservation expired`, dan `payment unavailable` menjadi pesan yang dapat ditindaklanjuti, bukan menampilkan raw database message.

## Penilaian per perspektif

| Perspektif | Kondisi saat ini | Penilaian |
|---|---|---|
| Pembeli | Validasi alamat, pengiriman, merchant, stok, voucher, dan payment method cukup lengkap | Baik secara fondasi, tetapi recovery payment dan multi-merchant masih lemah |
| Pembeli transfer | Ownership RPC sudah ada | Tidak aman sampai storage private dan immutable/audited |
| Pembeli online | Invoice dan webhook idempotent secara desain | UX gagal invoice perlu recovery yang eksplisit |
| Pembeli COD | Ada trust score, fee, confirmation deadline | Perlu test kebijakan cancellation/no-show dan dampak reservasi |
| Pedagang | Dashboard, filter, export, detail, payment verification, fulfilment actions tersedia | Perlu validasi state machine/RLS staging dan rekonsiliasi laporan |
| Operasional | Ada observability event pada payment/upload | Perlu metrik funnel, expiry backlog, webhook lag, dan reconciliation |
| Keamanan data | Direct order insert buyer sudah dicabut | Storage bukti pembayaran adalah blocker P0 |

## Checklist staging end-to-end

1. Buyer membuat checkout COD satu merchant; verifikasi subtotal, ongkir, fee, reservation, dan order merchant.
2. Buyer membuat checkout TRANSFER; upload bukti valid, ganti bukti, upload file invalid, dan coba akses order user lain.
3. Buyer membuat checkout ONLINE; uji invoice berhasil, callback PAID berulang, callback amount mismatch, callback invoice mismatch, dan retry invoice.
4. Biarkan reservation unpaid expired; pastikan stok kembali dan order tidak dapat dibayar setelah expiry.
5. Jalankan dua request checkout bersamaan dengan checkout key sama; pastikan hanya satu order/result.
6. Jalankan dua request dengan key berbeda untuk stok terakhir; pastikan hanya satu berhasil.
7. Uji cart multi-merchant dan pastikan tidak ada partial order atau voucher usage yang terlanjur tercatat.
8. Merchant A mencoba membaca/mengubah order merchant B; harus ditolak oleh RLS/RPC.
9. Merchant menguji seluruh transition valid dan invalid untuk COD, TRANSFER, dan ONLINE.
10. Buyer dan merchant memverifikasi signed URL bukti transfer; anonymous dan buyer lain harus tidak dapat membaca object.
11. Verifikasi order courier delivery tidak masuk omzet merchant marketplace.
12. Verifikasi notifikasi buyer/merchant/courier pada setiap transisi penting.
13. Verifikasi dashboard reconciliation: order total, payment total, refund, reserved stock, consumed stock, dan payout.

## Quality gate repository

Setelah `pnpm install --frozen-lockfile`, quality gate lokal berhasil: **TypeScript lulus, ESLint lulus, 65 test files lulus dengan 238 test lulus dan 20 skipped, serta production/PWA build lulus**. Test runner menampilkan deprecation warning Node untuk modul `punycode`, tetapi tidak menyebabkan kegagalan.

Static review menunjukkan test unit untuk beberapa kontrak payment/order sudah tersedia, tetapi belum cukup untuk membuktikan RLS, storage policy, concurrency database, scheduler expiry, dan transaksi nyata dengan provider pembayaran. Area tersebut memerlukan staging test dengan fixture buyer, dua merchant, admin, dan courier.

## Urutan perbaikan yang disarankan

1. **P0 segera:** private-kan bucket payment proof, scope semua storage policy, gunakan signed URL, dan tambahkan regression test ownership.
2. **P1 berikutnya:** perbaiki recovery online invoice agar tidak ada success state kontradiktif; sediakan retry payment.
3. **P1:** tambahkan audit trail bukti transfer dan tetapkan aturan immutable/versioned.
4. **P1:** deploy dan monitor expiry worker; tambahkan alert reservation backlog.
5. **P1:** jalankan matrix state transition/RLS/payment race di staging.
6. **P2:** perbaiki copy error, multi-merchant checkout entry point, funnel metrics, dan reconciliation dashboard.

## Kesimpulan

Fondasi checkout sudah cukup matang untuk dilanjutkan ke hardening staging, bukan langsung produksi. **Blocker produksi adalah keamanan bukti transfer.** Setelah blocker tersebut ditutup dan staging membuktikan payment/expiry/state-machine race cases, alur pembeli dan pedagang secara keseluruhan dapat dinilai siap untuk pilot terbatas dengan monitoring aktif.

## Referensi file utama

- `src/pages/CheckoutPage.tsx`
- `src/contexts/CartContext.tsx`
- `src/components/checkout/PaymentProofUpload.tsx`
- `src/pages/OrdersPage.tsx`
- `src/pages/merchant/MerchantOrdersPage.tsx`
- `supabase/migrations/20260918220000_checkout_idempotency_and_payment_guard.sql`
- `supabase/migrations/20260918230000_checkout_p1_hardening.sql`
- `supabase/bootstrap/50_20260911071000_transaction_critical_high_hardening.sql`
- `supabase/bootstrap/03_20260203_updat_to_20260208001230.sql`

*Catatan: laporan ini adalah audit static repository dan review alur. Temuan yang memerlukan database runtime, RLS, scheduler, atau provider payment diberi label wajib diverifikasi staging.*
