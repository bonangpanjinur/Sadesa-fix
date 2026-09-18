# Audit Ulang Alur Checkout End-to-End

**Tanggal:** 18 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Commit yang diaudit:** `3ef1343`  
**Ruang lingkup:** cart, checkout buyer, perhitungan harga, flash sale, voucher, ongkir, COD, transfer, pembayaran online, invoice provider, stok, reservation, order split merchant, cashback, refund, RLS, dan test coverage.

## Kesimpulan

Hardening terakhir telah memperbaiki sebagian risiko audit sebelumnya. Checkout sekarang memiliki key idempotensi pada jalur client baru, pembatasan UI untuk pembayaran online dan transfer multi-merchant, validasi bentuk data cart, serta batas quantity lokal. Lint, production build, validasi bootstrap, dan test suite repository juga lulus.

Namun, checkout belum dapat dinyatakan **production-grade**. Temuan paling penting adalah **RPC checkout dengan signature lama masih dapat dipanggil oleh role `authenticated`**, sehingga kontrol idempotensi dan guard transfer multi-merchant dapat dilewati. Selain itu, reservation stok dapat dilepas setelah order online sudah dibayar, upload bukti transfer berbenturan dengan revoke `UPDATE` pada tabel `orders`, dan ketika provider online tidak aktif frontend masih dapat membuat order `ONLINE` tanpa invoice.

**Status kesiapan:** belum siap untuk production penuh. Single-merchant COD dapat dilanjutkan ke staging/pilot setelah verifikasi database aktif, tetapi checkout transfer dan online masih memerlukan perbaikan lifecycle serta pengujian concurrency.

## Verifikasi yang dijalankan

| Pemeriksaan | Hasil |
| --- | --- |
| ESLint pada file checkout terkait | Lulus |
| Test suite | 65 test files lulus; 238 test lulus; 20 skipped |
| Production build | Lulus; hanya terdapat warning class Tailwind yang ambigu |
| Bootstrap bundle validation | Lulus; 227 migration dalam 42 ordered bundles |
| `git diff --check` | Lulus |
| Replay request authenticated ke database staging | Belum dilakukan |
| Concurrency checkout, voucher, dan reservation pada database aktif | Belum dilakukan |
| Transaksi nyata dengan payment provider | Belum dilakukan |

## Temuan prioritas

### CHK-R2-P1-01 — Signature lama checkout masih menjadi jalur tulis yang dapat melewati idempotensi

Migration idempotensi membuat overload baru `create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text)` dan hanya mencabut akses pada signature tujuh parameter. Signature lama enam parameter sebelumnya tetap diberi `GRANT EXECUTE TO authenticated` pada migration authoritative. Migration baru tidak mencabut grant tersebut.

Akibatnya, buyer yang memanggil RPC lama dapat membuat order tanpa `p_checkout_key`. Jalur ini melewati advisory lock dan tabel `marketplace_checkout_idempotency`. Jalur lama juga tidak memiliki guard `TRANSFER` multi-merchant. Kontrol yang terlihat aktif di frontend dan jalur baru dengan demikian bukan kontrol server tunggal.

**Bukti:** `supabase/bootstrap/50_20260911071000_transaction_critical_high_hardening.sql` memberikan grant pada signature enam parameter; `supabase/bootstrap/86_20260918220000_checkout_idempotency_and_payment_guard.sql` hanya mencabut grant signature tujuh parameter.

**Dampak:** retry atau request paralel melalui signature lama tetap dapat membuat order dan reservation ganda. Transfer multi-merchant juga dapat kembali menghasilkan beberapa child order tanpa halaman instruksi pembayaran batch.

**Rekomendasi:** cabut `EXECUTE` untuk signature lama dari `authenticated` dan `anon`, lalu pastikan hanya signature tujuh parameter yang dapat dipanggil buyer. Pertahankan akses signature lama hanya untuk `service_role` bila masih diperlukan untuk kompatibilitas internal. Tambahkan contract test yang memeriksa privilege kedua signature.

### CHK-R2-P1-02 — Reservation dapat expired setelah pembayaran online berhasil

Untuk pembayaran online, order dibuat dengan `payment_status = 'UNPAID'` dan reservation memakai fallback expiry 30 menit karena `v_deadline` bernilai `NULL`. Webhook Xendit mengubah order menjadi `payment_status = 'PAID'` dan status `CONFIRMED`, tetapi tidak mengonsumsi reservation. Fungsi `expire_marketplace_stock_reservations` hanya memeriksa reservation berstatus `active` dan `expires_at <= now()`; fungsi tersebut tidak mengecualikan order yang sudah `PAID` atau `CONFIRMED`.

Jika worker expiry berjalan setelah 30 menit sebelum order masuk status `SHIPPED`, reservation dilepas. Ketika order kemudian dikirim, `consume_marketplace_stock_reservation` melihat reservation sudah `expired` dan tidak mengurangi stok. Order dapat tetap paid/confirmed sementara stok tidak pernah dikonsumsi.

**Bukti:** `supabase/bootstrap/50_20260911071000_transaction_critical_high_hardening.sql` membuat reservation online dengan `now() + interval '30 minutes'`; `supabase/bootstrap/07_20260823080000_to_20260826000000.sql` memproses webhook menjadi `PAID/CONFIRMED`; lifecycle reservation di `supabase/bootstrap/08_20260826010000_to_20260829160000.sql` dapat expire semua reservation aktif.

**Rekomendasi:** pada webhook PAID, konsumsi reservation secara atomik atau ubah lease menjadi reservation paid yang tidak boleh di-expire. Tambahkan guard pada worker expiry agar hanya order unpaid/pending yang dapat dilepas. Uji urutan `checkout -> PAID -> expiry worker -> shipped` dan pastikan stok berkurang tepat satu kali.

### CHK-R2-P1-03 — Upload bukti transfer tidak konsisten dengan RLS orders

`PaymentProofUpload` mengunggah file lalu melakukan update langsung ke `orders` hanya dengan `.eq('id', orderId)`. Namun migration buyer cancellation mencabut `UPDATE` pada tabel `orders` dari role `authenticated` dan mengarahkan mutasi buyer melalui RPC scoped. Tidak terlihat RPC khusus untuk menyimpan `payment_proof_url` pada alur upload ini.

Akibatnya, upload storage dapat berhasil tetapi penyimpanan URL ke order gagal. Buyer menerima error setelah file telanjur tersimpan, dan halaman transfer tidak memiliki bukti pembayaran yang dapat diproses merchant.

**Bukti:** `src/components/checkout/PaymentProofUpload.tsx` melakukan `.from('orders').update(...)`; `supabase/bootstrap/57_20260912220000_buyer_order_cancellation.sql` melakukan `REVOKE UPDATE ON public.orders FROM authenticated, anon`.

**Rekomendasi:** buat RPC `buyer_submit_payment_proof(p_order_id, p_url)` yang mengunci order, memverifikasi buyer, metode pembayaran, status yang valid, dan path storage. Hapus update langsung dari client. Tambahkan cleanup file apabila RPC gagal agar tidak meninggalkan orphan object.

### CHK-R2-P1-04 — Provider online tidak tersedia tetapi order ONLINE masih dapat dibuat

Handler checkout hanya memanggil `createPaymentInvoice` bila `paymentMethod === 'ONLINE' && xenditAvailable`. Jika `xenditAvailable` false, kode tetap melanjutkan ke penghapusan cart dan menampilkan order berhasil dibuat. RPC checkout menerima `ONLINE` tanpa memverifikasi provider aktif.

Akibatnya, buyer dapat memperoleh order `ONLINE` dengan status unpaid tetapi tidak memperoleh invoice. Order tersebut tidak memiliki jalur pembayaran yang jelas dan reservation tetap berjalan sampai expiry.

**Bukti:** `src/pages/CheckoutPage.tsx` membatasi pembuatan invoice pada kondisi `xenditAvailable`; RPC authoritative hanya memvalidasi enum metode pembayaran dan membuat status `NEW/UNPAID`.

**Rekomendasi:** tolak `ONLINE` di server ketika provider tidak aktif, atau buat invoice sebagai bagian dari state machine yang memerlukan payment intent sebelum checkout dianggap berhasil. Di frontend, nonaktifkan metode online ketika provider tidak tersedia dan jangan membuat order sebagai fallback diam-diam.

### CHK-R2-P1-05 — Total preview multi-merchant masih berbeda dari total order server untuk COD

RPC authoritative menghitung ongkir di dalam loop setiap merchant dan menambahkan biaya COD pada setiap child order. Preview `CheckoutPage` tetap menampilkan satu `shippingCost`, satu `codServiceFee`, dan satu `total` untuk cart gabungan. Pembatasan baru hanya menolak online dan transfer multi-merchant; COD multi-merchant masih dapat dibuat.

Akibatnya, buyer dapat menyetujui nominal preview yang lebih rendah daripada akumulasi child order. Ambang gratis ongkir juga dihitung per merchant di server, sehingga selisih dapat terjadi walaupun biaya COD nol.

**Rekomendasi:** untuk pilot, batasi seluruh metode checkout ke satu merchant. Alternatifnya adalah membuat server quote yang mengembalikan rincian per merchant dan menjadikan quote tersebut sumber preview UI serta input checkout yang tervalidasi.

## Temuan prioritas menengah

### CHK-R2-P2-01 — Cashback belum terintegrasi dengan checkout authoritative

`redeem_cashback()` masih merupakan RPC terpisah. Signature checkout tidak menerima nominal cashback dan fungsi checkout tidak mengunci saldo, mencatat transaksi redemption, atau menggabungkan debit cashback dengan pembuatan order dan reservation.

Akibatnya, buyer belum dapat menggunakan cashback sebagai potongan pembayaran secara atomic. Memanggil redemption sebelum checkout juga dapat mengurangi saldo ketika checkout berikutnya gagal, kecuali client membangun kompensasi tambahan.

**Rekomendasi:** tambahkan `p_cashback_amount` ke kontrak checkout, kunci profile buyer, validasi batas nominal, buat transaksi redemption dengan reference checkout, lalu buat order dan reservation dalam transaksi yang sama. Tambahkan idempotensi pada transaksi redemption.

### CHK-R2-P2-02 — Reversal cashback belum proporsional untuk partial refund

`reverse_cashback_for_order()` membalik seluruh transaksi earn yang terkait dengan order ketika order menjadi `REFUNDED`. Fungsi tersebut tidak menerima nominal atau item refund dan tidak menghitung porsi cashback yang terkait dengan item yang direfund.

Akibatnya, bila bisnis mengizinkan partial refund, cashback dapat dikurangi lebih besar daripada porsi transaksi yang dikembalikan. Implementasi juga menggunakan `GREATEST(0, balance - amount)`, sehingga saldo dapat menyamarkan shortfall dan tidak menciptakan kewajiban reversal yang belum terbayar.

**Rekomendasi:** simpan allocation cashback per item atau per subtotal, hitung reversal dari settlement refund yang disetujui, dan catat shortfall sebagai liability ketika saldo buyer tidak cukup.

### CHK-R2-P2-03 — Idempotency key tidak mengikat payload dan tidak memiliki retention policy

Tabel idempotensi hanya menyimpan `(user_id, checkout_key)` dan `result`. Payload, payment method, product list, dan total yang diminta tidak disimpan sebagai fingerprint. Client menyimpan key di `useRef`, sehingga key hilang saat refresh dan key yang sama dapat digunakan kembali oleh state client setelah perubahan konteks.

Selain itu, tidak ada TTL atau job cleanup untuk `marketplace_checkout_idempotency`. Data akan tumbuh tanpa batas.

**Rekomendasi:** simpan hash payload yang canonical dan tolak key yang sama dengan payload berbeda. Gunakan key yang bertahan di session storage per attempt bila recovery setelah refresh memang diperlukan. Tambahkan retention policy dan cleanup job.

### CHK-R2-P2-04 — Cart masih menyimpan snapshot produk yang stale

Validasi localStorage sekarang memeriksa bentuk item dan membatasi quantity, tetapi seluruh object produk tetap disimpan di cart. Nama, harga, merchant, availability, dan stock pada preview dapat stale. Harga final memang dihitung ulang server, tetapi UI masih dapat memperlihatkan informasi yang berbeda sebelum submit.

**Rekomendasi:** simpan hanya `product_id` dan quantity sebagai data authoritative cart. Muat ulang detail produk untuk preview dan tampilkan hasil server quote sebelum submit.

### CHK-R2-P2-05 — Duplicate product IDs dalam payload tidak ditolak eksplisit

RPC memproses setiap elemen `p_items` dan memasukkannya ke temporary `checkout_lines`. Jika product yang sama dikirim dua kali, reservation membuat dua item dengan kombinasi `(reservation_id, product_id, variant_id)` yang sama dan dapat terkena unique constraint. Ini menghasilkan checkout gagal setelah order sementara masih berada dalam transaksi yang akan rollback, tetapi error tidak memberikan kontrak yang jelas.

**Rekomendasi:** normalisasi payload menjadi satu baris per product ID sebelum validasi, atau tolak duplicate product ID dengan error yang jelas.

## Kontrol yang sudah baik

Harga produk dan flash sale dihitung ulang di server. Produk dikunci dengan `FOR UPDATE`, merchant divalidasi, quantity dibatasi 1–1000 pada RPC, dan reservation stok memakai lock pada product. Voucher dikunci saat checkout dan penggunaan voucher memiliki unique constraint pada jalur authoritative. Webhook Xendit memiliki callback token, validasi invoice, validasi paid amount, serta event idempotency.

Jalur client baru juga sudah menambahkan key idempotensi, pembatasan payment method untuk multi-merchant, validasi cart localStorage, dan batas quantity lokal. Kontrol-kontrol ini berguna, tetapi belum cukup selama signature RPC lama tetap terbuka dan lifecycle reservation paid belum diperbaiki.

## Urutan perbaikan yang disarankan

1. Cabut akses `authenticated` ke signature checkout enam parameter dan uji privilege kedua signature.
2. Perbaiki transisi `PAID` agar reservation dikonsumsi atau dipindahkan ke status paid yang tidak dapat expire.
3. Buat RPC scoped untuk submit bukti transfer dan hapus update langsung ke `orders` dari client.
4. Tolak `ONLINE` ketika provider tidak aktif sebelum order/reservation dibuat.
5. Batasi sementara COD multi-merchant atau implementasikan server quote per merchant.
6. Integrasikan cashback ke transaksi checkout dengan idempotent redemption.
7. Terapkan reversal cashback berdasarkan porsi partial refund.
8. Bind idempotency key ke payload fingerprint dan tambahkan cleanup retention.
9. Tambahkan contract test database untuk overload privilege, duplicate submit, paid-before-expiry, provider failure, upload proof, voucher race, dan stock race.

## Test matrix minimum setelah perbaikan

1. Role `authenticated` tidak dapat menjalankan signature checkout lama.
2. Dua request paralel dengan key dan payload sama menghasilkan satu hasil checkout.
3. Key sama dengan payload berbeda ditolak.
4. Order online yang menerima PAID tidak dapat dilepas oleh expiry worker.
5. Order expired sebelum PAID melepaskan reservation tepat satu kali.
6. Provider offline menolak checkout online tanpa membuat order.
7. Buyer dapat menyimpan bukti transfer melalui RPC scoped, sedangkan buyer lain tidak dapat mengubah order tersebut.
8. Cart COD multi-merchant menampilkan total server yang sama dengan total child orders, atau ditolak sebelum order.
9. Dua request paralel memakai voucher satu kali menghasilkan tepat satu penggunaan.
10. Dua request paralel membeli stok terakhir menghasilkan tepat satu reservation.
11. Cashback redemption, order creation, dan reservation rollback bersama-sama ketika salah satu langkah gagal.
12. Partial refund membalik cashback sesuai proporsi refund dan retry tidak menggandakan reversal.

## Batasan audit

Audit ini dilakukan melalui inspeksi source, migration, bootstrap bundle, RLS/grant statis, dan test suite repository. Belum dilakukan replay request pada database staging/production, pengujian dua session authenticated secara paralel, verifikasi privilege pada schema aktif, pemeriksaan scheduler expiry yang benar-benar berjalan, atau transaksi nyata dengan Xendit. Karena itu, temuan yang bergantung pada schema aktif harus dikonfirmasi setelah migration diterapkan ke staging.

## References

[1]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/CheckoutPage.tsx "CheckoutPage source"
[2]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/50_20260911071000_transaction_critical_high_hardening.sql "Authoritative marketplace checkout RPC"
[3]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/86_20260918220000_checkout_idempotency_and_payment_guard.sql "Checkout idempotency and payment guard migration"
[4]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/08_20260826010000_to_20260829160000.sql "Marketplace stock reservation lifecycle"
[5]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/functions/xendit-webhook/index.ts "Xendit payment webhook"
[6]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/components/checkout/PaymentProofUpload.tsx "Payment proof upload component"
[7]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/85_20260918201000_cashback_reversal_redemption.sql "Cashback redemption and reversal controls"
[8]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/57_20260912220000_buyer_order_cancellation.sql "Buyer order mutation and RLS hardening"
