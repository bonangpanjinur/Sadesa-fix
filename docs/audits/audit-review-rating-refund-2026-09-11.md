# Audit Review, Rating, Komplain, dan Refund

**Tanggal audit:** 11 September 2026
**Cakupan:** review produk, rating kurir, validitas reviewer, RLS, dispute/complaint, refund request, bukti upload, keputusan admin, dan settlement merchant.
**Metode:** inspeksi source React, RLS/policy SQL, schema bootstrap, dan alur mutasi data. Belum dilakukan replay request ke database production.

## Kesimpulan eksekutif

Validasi UI sudah membatasi beberapa alur, misalnya review diarahkan hanya untuk order selesai dan form dispute meminta kategori/deskripsi. Namun, kontrol tersebut belum ditegakkan di database. Policy INSERT review dan refund hanya mengikat `buyer_id` kepada `auth.uid()`, bukan memastikan order milik buyer, status order selesai, produk ada di order, atau nominal refund sah.

Ditemukan **dua risiko P0 pada integritas refund/review**, satu bug fungsional kritis pada rating kurir, serta beberapa risiko P1 pada settlement, upload bukti, dan state transition.

## Matriks temuan

| ID | Prioritas | Area | Temuan | Dampak |
|---|---|---|---|---|
| REVIEW-P0-01 | **P0** | Refund authorization | Policy `Buyers can create refund requests` hanya memeriksa `buyer_id = auth.uid()` dan `status = 'PENDING'`. Tidak ada verifikasi `order_id` milik buyer, order selesai/terbayar, merchant sesuai order, atau refund belum pernah diajukan. | Buyer dapat mengirim request refund terhadap order user lain dengan `merchant_id` arbitrer dan nominal manipulatif. Jika admin menyetujui, order user lain dapat ditandai refunded dan saldo merchant dapat dipotong. |
| REVIEW-P0-02 | **P0** | Review authenticity | Policy `Buyers can create reviews for their orders` hanya memeriksa `buyer_id = auth.uid()`. Tidak ada verifikasi order milik buyer, status delivered/done, product ada di order, merchant cocok, atau uniqueness review. | Buyer dapat menaikkan rating produk/merchant dengan review palsu untuk order yang tidak dibeli atau membuat review berulang melalui request langsung/concurrent. |
| REVIEW-P1-03 | P1 | Refund amount/integrity | `amount` dari dialog refund berasal dari input client; UI hanya memberi `max`, tanpa min/validasi numeric. Tidak ada CHECK amount > 0 dan tidak ada server-side cap terhadap `orders.total`/paid amount. | Nilai negatif, NaN/invalid, atau nominal melebihi order dapat masuk/ditangani admin. Potensi settlement dan saldo merchant salah. |
| REVIEW-P1-04 | P1 | Refund transaction | Admin mengubah refund status, order status `REFUNDED`, dan saldo merchant melalui beberapa request terpisah. Tidak ada RPC transaction atau lock status PENDING. | Kegagalan di tengah proses menghasilkan refund APPROVED tanpa order refunded, order refunded tanpa settlement, atau double processing/double deduction. |
| REVIEW-P1-05 | P1 | Courier rating | `CourierRatingDialog` menulis kolom `user_id`, `target_type`, `target_id`, dan `tags` ke `reviews`, padahal schema review yang ditemukan memakai `buyer_id`, `product_id`, `merchant_id`, `rating`, `comment`, dan `image_urls`. Error insert tidak diperiksa; UI tetap dapat menampilkan sukses. | Rating kurir berpotensi selalu gagal/masuk schema yang salah. Update aggregate dan flag order juga tidak divalidasi. Jika schema dinamis pernah ditambahkan, client tetap dapat memanipulasi target/order tanpa RPC authoritative. |
| REVIEW-P1-06 | P1 | Review mutation | Policy merchant reply menggunakan `FOR UPDATE` dengan policy yang tidak membatasi kolom yang boleh diubah. Tidak ada RPC khusus reply. | Merchant dapat mencoba mengubah field review lain selain reply/rating melalui direct update; integritas atribusi review perlu diproteksi dengan RPC/trigger. |
| REVIEW-P1-07 | P1 | Review submission transaction | Review per item dibuat sebagai batch insert, lalu `orders.has_review` di-update request terpisah. Upload gambar dilakukan sebelum transaction review. | Sebagian upload/review dapat tertinggal saat request berikutnya gagal; flag order dapat gagal atau review dapat diduplikasi saat retry. |
| REVIEW-P1-08 | P1 | Evidence storage | `RefundRequestDialog` meng-upload ke bucket `public_assets` dengan nama `${Math.random()}.${ext}` dan URL publik. Tidak ada pembatasan ukuran, MIME yang benar-benar diverifikasi, ownership path, atau cleanup ketika insert refund gagal. | Bukti dapat ditebak/diakses publik, file berbahaya/berukuran besar dapat diunggah, dan file orphan memenuhi storage. |
| REVIEW-P2-09 | P2 | Dispute state machine | Admin dapat mengubah status dispute secara bebas dari UI (`OPEN`, `IN_MEDIATION`, resolved, closed), tanpa guard transisi, resolved-at metadata, atau immutable decision history. | Komplain dapat dibuka kembali/di-resolve berulang dan audit keputusan kurang kuat. |
| REVIEW-P2-10 | P2 | Review content moderation | Review/comment tidak memiliki moderation, abuse rate limit server-side, atau report mechanism yang terlihat. | Spam, konten ofensif, dan rating manipulation dapat tampil ke publik. |

## Analisis detail

### REVIEW-P0-01 — Refund request tidak mengikat order kepada buyer

Policy saat ini:

```sql
CREATE POLICY "Buyers can create refund requests"
ON public.refund_requests FOR INSERT
WITH CHECK (buyer_id = auth.uid());
```

`RefundRequestDialog` mengirim `order_id`, `merchant_id`, `amount`, `status`, dan `refund_type` dari client. `order_id` tidak diverifikasi dalam policy terhadap `orders.buyer_id`; `merchant_id` juga tidak diverifikasi terhadap order. Admin kemudian mengubah order menjadi `REFUNDED` dan mengurangi saldo merchant melalui request terpisah.

**Perbaikan wajib:** ganti direct INSERT dengan RPC `create_refund_request` yang mengambil hanya order ID, reason, amount, dan evidence references. RPC harus mengunci order, memastikan `orders.buyer_id = auth.uid()`, order memenuhi status/payment/refund window, menghitung merchant dari order, membatasi amount ke paid total/outstanding refundable balance, mencegah duplicate active request, dan menyimpan immutable snapshot.

### REVIEW-P0-02 — Review tidak membuktikan pembelian

Halaman review memang memeriksa order milik user dan status selesai di frontend, tetapi policy database tidak melakukan pemeriksaan serupa. Request langsung dapat memakai buyer ID sendiri dan order/product/merchant milik pihak lain. Tidak ada unique constraint untuk `(order_id, buyer_id, product_id)`.

**Perbaikan wajib:** buat RPC `submit_order_reviews` yang mengunci order, memastikan buyer caller, status `DONE/DELIVERED`, memastikan setiap product ada di `order_items`, memvalidasi rating 1–5, membatasi comment/image URLs, dan insert dengan unique constraint. Aggregate merchant/product rating harus dihitung server-side dalam transaction.

### REVIEW-P1-05 — Rating kurir salah kontrak

`CourierRatingDialog` menginsert ke tabel `reviews` dengan kontrak berbeda dari schema review produk. Error dari insert tidak ditangkap karena hasilnya tidak di-destructure/ditest. Setelah itu komponen tetap menjalankan query aggregate dan update courier/order tanpa memastikan operasi sebelumnya berhasil.

**Perbaikan:** gunakan tabel/RPC khusus `submit_courier_rating` dengan validasi caller, order, courier assignment, status delivered, satu rating per order/courier, dan server-side aggregate. Jangan menghitung rata-rata dari seluruh rows di frontend.

### REVIEW-P1-04 — Approval refund bukan atomic

Admin melakukan update refund, update order, update merchant balance, lalu audit log sebagai operasi terpisah. Kegagalan request kedua/ketiga tidak rollback request sebelumnya. Tidak terlihat ledger refund idempotency key atau constraint satu payout per refund.

**Perbaikan:** buat RPC `process_refund_decision` dengan row lock pada request/order/merchant, hanya menerima request PENDING, memvalidasi amount/refundable balance, menulis refund ledger idempotently, mengubah status order, dan menulis audit event dalam transaction. Integrasi provider pembayaran harus memakai idempotency key dan status settlement terpisah dari keputusan admin.

## Kontrol yang sudah baik

Review publik dibatasi pada `is_visible = true`. RLS review memisahkan reply merchant berdasarkan ownership merchant dan akses admin. Buyer hanya dapat melihat refund miliknya, sementara merchant hanya dapat melihat refund untuk merchant yang dimilikinya. Dispute page meng-query order dengan `buyer_id = user.id` dan menggunakan `maybeSingle()` untuk menampilkan dispute user tersebut.

## Urutan perbaikan

| Tahap | Pekerjaan | Prioritas |
|---|---|---|
| 1 | Cabut direct INSERT review/refund dari authenticated dan ganti dengan RPC authoritative. | P0 |
| 2 | Tambahkan ownership/order-status/product-membership/refund cap di RPC. | P0 |
| 3 | Tambahkan unique constraints untuk review per order-item dan active refund per order. | P0/P1 |
| 4 | Buat RPC atomic proses keputusan refund dan ledger settlement idempotent. | P1 |
| 5 | Pisahkan courier rating dari product review atau samakan schema melalui RPC khusus. | P1 |
| 6 | Pindahkan aggregate rating ke trigger/RPC server-side. | P1 |
| 7 | Gunakan private evidence bucket/path per user dengan MIME/size validation dan signed URLs. | P1 |
| 8 | Tambahkan state transition guard, audit history immutable, rate limit, dan moderation. | P2 |

## Test case minimum

1. Buyer tidak dapat membuat refund untuk order milik user lain.
2. Buyer tidak dapat mengatur `merchant_id` berbeda dari merchant order.
3. Refund amount nol/negatif/lebih besar dari paid total ditolak server.
4. Dua request refund paralel untuk order yang sama hanya menghasilkan satu active request.
5. Admin hanya dapat memproses refund PENDING satu kali.
6. Proses refund rollback penuh bila settlement atau ledger gagal.
7. Buyer tidak dapat menulis review untuk order belum delivered atau product di luar order.
8. Review duplikat per order-item ditolak oleh unique constraint/RPC.
9. Rating kurir hanya dapat dibuat oleh buyer order yang courier-nya benar-benar assigned dan delivered.
10. Merchant hanya dapat mengubah reply review miliknya, bukan rating/buyer/product/order.
11. Bukti refund tidak dapat dibaca publik tanpa signed URL dan tidak dapat diunggah dengan MIME/size berbahaya.
12. Aggregate rating tetap benar setelah review dibuat, dihapus, dimoderasi, atau request diulang.

## Batasan audit

Audit belum menjalankan request langsung terhadap PostgREST production, belum menguji bucket policy live, dan belum memverifikasi apakah ada schema courier-rating lain yang tidak tercermin pada bootstrap. Temuan P0 perlu diuji di staging dengan dua akun buyer dan satu akun merchant/admin sebelum modul dinyatakan aman.
