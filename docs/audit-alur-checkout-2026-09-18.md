# Audit Alur Checkout End-to-End

**Tanggal:** 18 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Ruang lingkup:** cart, checkout buyer, harga produk, flash sale, voucher, ongkir, COD, transfer, pembayaran online, stok, order split merchant, cashback, refund, dan kontrol database.

## Kesimpulan

Checkout sudah memiliki fondasi keamanan yang jauh lebih baik dibandingkan audit 11 September. Fungsi `create_marketplace_checkout` sekarang menghitung harga produk dan flash sale di server, memeriksa merchant, mengunci produk, membuat order dan order item, memakai reservation stok, serta mengonsumsi voucher di dalam transaksi database. Buyer juga tidak lagi memiliki jalur INSERT langsung ke `orders` dan `order_items` melalui policy authenticated.

Namun, checkout belum siap dinyatakan **production-grade untuk semua skenario**. Temuan paling penting adalah perbedaan total antara UI dan server pada checkout lebih dari satu merchant, ketiadaan idempotency key untuk retry checkout, dan lifecycle pembayaran online yang dapat meninggalkan order serta reservation ketika pembuatan invoice gagal. Integrasi redeem cashback juga belum masuk ke RPC checkout authoritative.

**Status kesiapan:** siap untuk pilot single-merchant dengan staging test yang memadai; belum siap untuk checkout multi-merchant dan retry pembayaran tanpa hardening tambahan.

## Alur aktual

1. Produk dan quantity disimpan di `CartContext` serta `localStorage`.
2. `CheckoutPage` menghitung preview subtotal, ongkir, biaya COD, voucher, dan total dari state client.
3. Saat submit, client mengirim hanya `product_id`, `quantity`, alamat, delivery type, payment method, dan voucher ID ke `create_marketplace_checkout`.
4. RPC mengunci product, menghitung ulang harga dan flash sale, mengelompokkan item berdasarkan merchant, membuat order per merchant, membuat `order_items`, dan memanggil reservation stok.
5. Untuk voucher, RPC mengunci voucher, memeriksa periode, merchant, minimum belanja, usage limit, dan one-use per user, lalu membuat `voucher_usages` serta menambah `used_count`.
6. Untuk online payment, client menerima `primary_order_id`, membuat invoice provider pada request terpisah, lalu mengarahkan browser ke provider.
7. Untuk transfer, client hanya mengarahkan buyer ke halaman pembayaran berdasarkan `primary_order_id`.
8. Cashback belum dipotong atau dipakai sebagai pembayaran di checkout. RPC redeem sudah tersedia sebagai fungsi terpisah.

## Temuan audit

| ID | Prioritas | Temuan | Dampak |
|---|---:|---|---|
| CHK-P1-01 | P1 | Total preview UI berbeda dari total order server ketika cart memiliki beberapa merchant. | Buyer dapat melihat nominal berbeda dengan total order yang dibuat; biaya COD dan ongkir dapat diterapkan per order merchant di server tetapi hanya sekali di UI. |
| CHK-P1-02 | P1 | Checkout tidak memiliki idempotency key. | Double click, retry jaringan, atau refresh setelah timeout dapat membuat order dan reservation ganda, terutama tanpa voucher. |
| CHK-P1-03 | P1 | Order dibuat sebelum invoice online berhasil dibuat. | Kegagalan provider dapat meninggalkan order `NEW/UNPAID` dan reservation stok yang tidak segera dilepas. |
| CHK-P1-04 | P1 | Transfer multi-merchant diarahkan ke halaman pembayaran hanya untuk `primary_order_id`. | Buyer mungkin hanya melihat instruksi dan upload bukti untuk merchant pertama, sementara order merchant lain sudah ikut dibuat. |
| CHK-P1-05 | P1 | Voucher tidak didesain untuk multi-merchant dan preview hanya memakai merchant pertama. | Voucher lintas cart ditolak oleh server setelah buyer melihat preview berdasarkan merchant pertama; UX membingungkan dan voucher platform tidak dapat dipakai pada cart multi-merchant. |
| CHK-P2-06 | P2 | Cart tetap menyimpan price, merchant, name, dan availability dari localStorage. | Preview dapat stale atau dimanipulasi. Harga final memang dihitung server, tetapi UX dapat menampilkan angka lama sebelum submit. |
| CHK-P2-07 | P2 | `CartContext.addToCart` tidak membatasi quantity maksimum. | Quantity lokal dapat membesar tanpa batas sebelum server menolak di atas 1000; cart dapat menampilkan nilai tidak konsisten. |
| CHK-P2-08 | P2 | Precheck stok dari client terjadi sebelum RPC, tetapi tidak memberikan atomic quote. | Precheck dapat berubah di antara request. Reservation server tetap menjadi kontrol akhir, tetapi error dapat terjadi setelah proses checkout dimulai. |
| CHK-P2-09 | P2 | `p_distance_km` dikirim null dan RPC menghitung jarak server dari koordinat, tetapi UI belum menampilkan quote server. | Angka ongkir pada layar dapat berbeda dari order final, khususnya jika koordinat atau aturan shipping berubah. |
| CHK-P2-10 | P2 | Cashback belum menjadi komponen checkout. | Saldo confirmed belum dapat dipakai buyer untuk mengurangi total order secara atomic. |
| CHK-P2-11 | P2 | Partial refund yang mengubah order ke `REFUNDED` menjalankan reversal cashback secara konservatif untuk seluruh earn order. | Bila bisnis mendukung refund parsial, saldo cashback dapat dikembalikan lebih besar daripada porsi item yang direfund. |
| CHK-P2-12 | P2 | Tidak terlihat contract test database yang menjalankan concurrency checkout dan voucher pada database staging. | Validasi kode belum membuktikan race pada dua submit paralel, reservation gagal, dan provider timeout. |

## Analisis temuan utama

### CHK-P1-01 — Perbedaan total multi-merchant

UI menghitung satu `shippingCost` dan satu `codServiceFee` dari nilai subtotal gabungan. RPC membuat satu order per merchant. Di dalam loop merchant, RPC menghitung ongkir dan menambahkan biaya COD pada setiap order. Karena ongkir gratis juga diperiksa per merchant, ambang gratis dapat menghasilkan hasil berbeda antara preview dan order final.

Skenario: cart berisi dua toko dengan metode COD. UI menampilkan satu biaya COD. RPC menyimpan biaya COD pada dua order. Buyer dapat menerima dua nominal order yang jumlahnya lebih tinggi daripada total yang ditampilkan saat checkout.

**Rekomendasi:** pilih kontrak bisnis yang tegas. Untuk single-merchant, batasi cart checkout menjadi satu toko. Untuk multi-merchant, tampilkan rincian total per toko dari quote server dan gunakan parent checkout yang menjumlahkan child order. Jangan menganggap satu angka UI sebagai sumber kebenaran.

### CHK-P1-02 — Tidak ada idempotency key

`create_marketplace_checkout` menerima item, delivery, metode pembayaran, voucher ID, dan jarak, tetapi tidak menerima `checkout_key` atau `idempotency_key`. UI memang mengatur `loading`, tetapi kontrol ini hanya berlaku pada satu tab dan satu instance browser. Timeout setelah database commit tetapi sebelum response akan membuat buyer tidak mengetahui apakah order sudah terbentuk. Retry dapat membuat order kedua.

**Rekomendasi:** tambahkan `p_checkout_key` yang dibuat client sekali untuk satu attempt. Simpan key pada parent checkout atau order pertama dengan unique constraint per buyer. Jika key sudah pernah sukses, kembalikan order IDs yang sama. Jika attempt gagal sebelum commit, transaction rollback. Untuk provider payment, gunakan key yang sama atau relasi payment intent.

### CHK-P1-03 — Invoice online dibuat setelah order dan reservation

RPC membuat order dan reservation, lalu frontend memanggil `createPaymentInvoice`. Jika provider gagal, frontend menampilkan pesan bahwa pesanan sudah dibuat dan buyer harus membayar dari halaman pesanan. Ini mencegah kehilangan order, tetapi reservation dapat menahan stok dan order `UNPAID` dapat menumpuk. Jika cleanup timeout tidak berjalan, stok menjadi tidak tersedia untuk buyer lain.

**Rekomendasi:** tambahkan lifecycle timeout untuk order `NEW/UNPAID`, release reservation yang expired, dan tombol regenerate invoice yang aman. Provider invoice reservation harus memiliki lease recovery untuk status `processing`. Jangan membuat invoice baru untuk order yang sudah `PAID`.

### CHK-P1-04 — Transfer multi-merchant

RPC dapat menghasilkan beberapa order untuk transfer. Frontend mengambil `primary_order_id` dan menavigasi ke `/payment/{primary_order_id}`. Halaman pembayaran mengambil satu order dan satu merchant payment info. Tidak ada parent payment atau daftar child order pada route tersebut.

**Rekomendasi:** untuk sementara batasi transfer multi-merchant menjadi satu merchant, sama seperti online. Alternatif yang lebih lengkap adalah membuat halaman payment batch yang memuat seluruh order IDs dan instruksi pembayaran per merchant.

### CHK-P1-05 — Voucher hanya single-merchant

`VoucherInput` mengirim `merchantId={merchantIds[0]}` saat preview. RPC sengaja menolak `p_voucher_id` jika terdapat lebih dari satu merchant. Aturan ini aman untuk ownership voucher, tetapi tidak konsisten dengan UI yang masih memungkinkan buyer memilih beberapa toko.

**Rekomendasi:** versi pilot sebaiknya menonaktifkan input voucher ketika `merchantIds.length > 1` dan memberi pesan bahwa voucher hanya berlaku untuk checkout satu toko. Versi lanjutan dapat mendukung satu voucher per merchant melalui array voucher allocations dengan validasi server.

## Kontrol yang sudah baik

RPC checkout mengharuskan user authenticated dan menerima ID produk serta quantity, bukan harga dari client. Produk dikunci `FOR UPDATE`, status produk dan merchant diverifikasi, merchant harus approved, active, dan open, quantity dibatasi 1–1000, dan stok diperiksa sebelum reservation.

Flash sale dihitung dari tabel server berdasarkan status aktif, waktu, dan stok flash sale. Harga item, subtotal, voucher discount, biaya pengiriman, dan total order dibuat di sisi database. Buyer tidak lagi dapat memakai INSERT langsung ke order dan order item melalui role authenticated setelah migration authoritative.

Voucher memiliki unique index `(voucher_id, user_id)`, dikunci saat checkout, dan dikonsumsi bersama order dalam transaction. Reservation stok juga berada di jalur RPC yang sama, sehingga kegagalan reservation membatalkan transaction checkout tersebut.

## Rencana perbaikan

| Tahap | Pekerjaan | Prioritas | Kriteria selesai |
|---|---|---:|---|
| 1 | Batasi online dan transfer ke satu merchant atau implementasikan parent payment batch | P0/P1 | Tidak ada order child yang tidak memiliki instruksi pembayaran lengkap |
| 2 | Tambahkan idempotency key pada checkout | P1 | Retry request mengembalikan order yang sama |
| 3 | Tambahkan expiry dan release reservation untuk order unpaid | P1 | Order unpaid yang expired mengembalikan stok tepat satu kali |
| 4 | Tambahkan recovery lease invoice provider | P1 | Reservation `processing` dapat dilanjutkan setelah worker crash |
| 5 | Nonaktifkan voucher input pada cart multi-merchant | P1 | Preview UI tidak menawarkan operasi yang pasti ditolak server |
| 6 | Buat server quote atau tampilkan rincian total per merchant | P1 | Preview dan order final mempunyai sumber perhitungan yang sama |
| 7 | Integrasikan redeem cashback ke checkout RPC | P1 | Saldo terkunci, order dan debit cashback atomic, retry aman |
| 8 | Buat reversal prorata untuk partial refund | P2 | Reversal mengikuti item/nominal refund, bukan seluruh order otomatis |
| 9 | Clamp quantity cart dan validasi shape localStorage | P2 | Cart invalid dibersihkan atau dipulihkan dengan aman |

## Test matrix minimum

1. Submit checkout dua kali dengan payload dan checkout key yang sama hanya menghasilkan satu parent/child order.
2. Cart dua merchant dengan online ditolak sebelum order dibuat, atau seluruh child order memiliki satu parent payment yang benar.
3. Cart dua merchant dengan transfer menampilkan seluruh order dan seluruh instruksi pembayaran, atau ditolak dengan alasan jelas.
4. Dua request paralel memakai voucher satu kali; tepat satu request berhasil.
5. Dua request paralel membeli stok terakhir; tepat satu reservation berhasil.
6. Harga produk berubah setelah cart dibuat; server membuat order dengan harga terbaru dan UI menampilkan hasil authoritative.
7. Flash sale berakhir sebelum submit; order memakai harga reguler.
8. Pembuatan invoice provider gagal; order tetap dapat diretry dan reservation memiliki expiry.
9. Order unpaid melewati expiry; reservation dilepas satu kali dan tidak mengubah order paid.
10. Refund penuh setelah cashback confirmed membuat satu reversal; retry refund tidak mengurangi saldo dua kali.
11. Partial refund mengikuti kebijakan reversal yang disepakati.
12. Buyer tidak dapat menjalankan RPC dengan `p_user_id` atau order ID milik buyer lain.

## Batasan audit

Audit ini dilakukan melalui inspeksi source, SQL bootstrap, migration, dan test suite repository. Belum dilakukan replay request pada database staging/production, pengujian concurrency dengan beberapa session authenticated, atau transaksi nyata pada provider pembayaran. Migration checkout authoritative harus dipastikan sudah diterapkan pada database aktif; hasil audit source tidak membuktikan schema production identik dengan bootstrap.

## Referensi

[1]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/CheckoutPage.tsx "CheckoutPage source"
[2]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/50_20260911071000_transaction_critical_high_hardening.sql "Authoritative checkout RPC"
[3]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/contexts/CartContext.tsx "CartContext source"
[4]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/PaymentConfirmationPage.tsx "Transfer payment confirmation source"
[5]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/docs/audit-product-cart-checkout-2026-09-11.md "Previous product cart checkout audit"
[6]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/docs/audit-payment-notification-2026-09-11.md "Previous payment and notification audit"
