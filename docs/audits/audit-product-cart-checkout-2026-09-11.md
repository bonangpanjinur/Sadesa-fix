# Audit Produk, Cart, dan Checkout

**Tanggal audit:** 11 September 2026
**Cakupan:** katalog produk, persistensi cart, harga/promo, stok, voucher, pembuatan order, order items, reservation stok, merchant isolation, dan pembayaran checkout.
**Metode:** inspeksi frontend React, RPC/SQL bootstrap, RLS, dan test yang tersedia. Belum dilakukan pengujian terhadap database production atau replay request dengan anon key.

## Kesimpulan eksekutif

UI cart memiliki validasi stok dan harga terbaru sebelum checkout, dan RPC `reserve_marketplace_stock` memakai row lock serta mengalokasikan stok POS secara atomik. Namun, boundary keamanan checkout masih terlalu bergantung pada client: buyer dapat langsung INSERT order dan order items dengan nominal yang dikirim client, sementara checkout membangun subtotal, total, harga item, dan discount dari state/localStorage.

Ditemukan **dua temuan P0 terkait integritas harga/voucher**, satu temuan P1 terkait partial order, dan beberapa bug konsistensi harga/promosi serta quantity cart.

## Matriks temuan

| ID | Prioritas | Area | Temuan | Dampak |
|---|---|---|---|---|
| CART-P0-01 | **P0** | Order pricing | Policy `Buyers can create orders` hanya memeriksa `auth.uid() = buyer_id`. Buyer dapat mengirim `subtotal`, `total`, `shipping_cost`, `cod_service_fee`, `flash_sale_discount`, dan status/payment fields arbitrer. Tidak ada RPC checkout authoritative yang menghitung ulang harga dari `products`/promo. | Manipulasi request dapat membuat order murah/gratis, mempengaruhi invoice/payment, laporan merchant, COD, dan settlement. |
| CART-P0-02 | **P0** | Voucher usage | RPC `apply_voucher` hanya menghitung preview discount. Checkout tidak membuat `voucher_usages`, tidak increment `vouchers.used_count`, dan tidak mengikat voucher ke order secara authoritative. | Voucher dapat digunakan berulang tanpa batas per user; usage limit dan one-use check tidak efektif. Discount juga berasal dari client saat order dibuat. |
| CART-P1-03 | P1 | Multi-merchant checkout | Untuk COD/TRANSFER, checkout membuat order merchant satu per satu. Jika order merchant kedua atau reservation kedua gagal, order merchant pertama sudah tersimpan dan stok sudah direservasi. Tidak ada saga/compensation/transaction lintas merchant. | Checkout parsial, reservation menggantung, buyer dapat menerima hanya sebagian order tanpa alur pemulihan yang jelas. |
| CART-P1-04 | P1 | Flash sale pricing | `ProductCard` menampilkan `flashSale.flashPrice`, tetapi `addToCart(product)` menyimpan object product dengan `product.price` reguler. Checkout kemudian menghitung dari harga reguler dan tidak membawa flash-sale ID/validity ke server. | Harga tampil berbeda dengan harga checkout; promo flash sale dapat tidak diterapkan atau dapat dimanipulasi dari client. |
| CART-P1-05 | P1 | Stok dan cart quantity | `CartContext.addToCart` menambah quantity tanpa clamp. Cart disimpan di localStorage sehingga quantity, price, name, merchant, dan availability dapat stale/manipulated. Validasi sebelum checkout hanya query `stock`, bukan validasi harga/promo/merchant status dalam transaction. | UX quantity tidak konsisten dan memperbesar ketergantungan pada input client; stok sendiri dilindungi sebagian oleh reservation RPC. |
| CART-P1-06 | P1 | Order item integrity | Buyer diizinkan INSERT `order_items` untuk order miliknya tanpa policy yang memeriksa bahwa `product_id` milik `orders.merchant_id`, harga cocok dengan produk, quantity positif, atau subtotal = harga × quantity. | Buyer dapat memasukkan item merchant lain, harga palsu, quantity aneh, dan item yang tidak sesuai order. Reservation hanya memeriksa product/quantity, bukan nominal order item. |
| CART-P2-07 | P2 | Voucher actor binding | `apply_voucher` menerima `p_user_id` dari client dan tidak terlihat memaksa `p_user_id = auth.uid()`. | User dapat menguji usage state user lain atau mem-bypass one-use check pada preview RPC. |
| CART-P2-08 | P2 | Merchant grouping | Cart mengelompokkan item berdasarkan `merchantName` di UI, sedangkan checkout berdasarkan `merchantId`. Jika state cart lama memiliki nama/ID tidak konsisten, tampilan grouping dapat berbeda dari order split. | Risiko kebingungan pengguna dan salah interpretasi jumlah/order per toko. |
| CART-P2-09 | P2 | Checkout cleanup | Pada payment online, browser redirect terjadi di tengah loop merchant setelah invoice pertama. Untuk kondisi multi-merchant yang lolos karena state berubah, merchant berikutnya tidak diproses dan cleanup cart tidak dijalankan. | Cart/order state dapat tersisa tidak konsisten setelah redirect atau payment failure. |

## Bukti utama

### CART-P0-01 — Order nominal dikendalikan client

Policy saat ini hanya memvalidasi buyer:

```sql
CREATE POLICY "Buyers can create orders"
ON public.orders FOR INSERT TO authenticated
WITH CHECK (auth.uid() = buyer_id);
```

Frontend mengirim seluruh nominal dari state client:

```ts
subtotal: merchantSubtotal,
total: merchantTotal,
shippingCost: merchantShipping,
flashSaleDiscount: merchantVoucherDiscount,
codServiceFee: merchantCodFee,
```

`merchantSubtotal` dan `orderItems.product_price` berasal dari `item.product` yang disimpan di cart/localStorage. Reservation RPC memang mengunci product dan stok, tetapi tidak menghitung ulang `orders.total`, `order_items.product_price`, atau discount.

**Perbaikan wajib:** pindahkan checkout ke satu RPC authoritative yang menerima item IDs/variant IDs, quantity, address/delivery choice, payment method, dan voucher code; server mengunci product/merchant/promo, menghitung semua nominal, membuat order + items + voucher usage + reservation dalam transaction. Client hanya menerima hasil server.

### CART-P0-02 — Voucher tidak dikonsumsi

`apply_voucher` melakukan check `used_count` dan `voucher_usages`, lalu mengembalikan discount preview. Pada `CheckoutPage`, voucher hanya ditulis ke `notes` dan nilai discount dipakai untuk menghitung `total`; tidak ditemukan insert `voucher_usages` atau atomic increment `vouchers.used_count` pada flow checkout.

**Perbaikan wajib:** reservation/checkout RPC harus mengunci voucher, memvalidasi actor dari `auth.uid()`, mengecek periode/minimum/merchant/usage, insert usage dengan unique `(voucher_id,user_id)` atau constraint order, increment counter secara atomic, lalu rollback seluruh transaction jika order gagal.

### CART-P1-03 — Partial order antar merchant

Checkout menjalankan loop:

```ts
for (const [merchantId, merchantData] of Object.entries(itemsByMerchant)) {
  insert orders;
  insert order_items;
  reserve_marketplace_stock;
}
```

Kegagalan pada iteration berikutnya tidak membatalkan order dan reservation iteration sebelumnya. Online multi-merchant memang sudah diblokir, tetapi COD/TRANSFER masih dapat membuat beberapa order secara bertahap.

**Perbaikan:** gunakan batch checkout RPC yang membuat seluruh order dan reservation dalam satu transaction; atau gunakan saga eksplisit yang membatalkan dan me-release seluruh order/reservation yang sudah dibuat ketika merchant berikutnya gagal.

### CART-P1-04 — Flash sale tidak ikut ke cart

`ProductCard` menampilkan `displayPrice = flashSale.flashPrice`, tetapi handler tetap memanggil `addToCart(product, 1)`. Object `product` memiliki `price` reguler. Checkout menggunakan `item.product.price`, tanpa flash sale server validation.

**Perbaikan:** jangan percaya harga di cart. Kirim product/variant ID dan quantity saja ke server. Server menentukan promo aktif pada saat checkout; UI hanya preview.

## Kontrol yang sudah baik

`CartPage` melakukan refresh stok sebelum checkout dan menolak item yang stoknya berkurang atau harga berubah. `reserve_marketplace_stock` memeriksa buyer ownership pada order, mengunci order/product, memvalidasi quantity positif, memastikan variant milik product, dan memakai allocation ledger. Checkout online multi-merchant juga sudah diberi guard untuk mencegah satu invoice mewakili beberapa order.

## Urutan perbaikan

| Tahap | Pekerjaan | Prioritas |
|---|---|---|
| 1 | Buat RPC authoritative `create_marketplace_checkout` untuk harga, item, shipping, promo, voucher, order, dan reservation. | P0 |
| 2 | Cabut INSERT langsung buyer ke `orders`/`order_items`, atau batasi policy agar hanya RPC/security-definer path yang dapat menulis. | P0 |
| 3 | Integrasikan voucher usage atomic dan unique per user/order; ikat `p_user_id` ke `auth.uid()`. | P0 |
| 4 | Tambahkan constraint/trigger server untuk order item: product merchant, quantity > 0, harga dan subtotal authoritative. | P1 |
| 5 | Hilangkan partial multi-merchant checkout dengan transaction batch/saga compensation. | P1 |
| 6 | Samakan flash-sale preview dengan server calculation; cart hanya menyimpan ID/quantity atau selalu refresh quote. | P1 |
| 7 | Clamp quantity di CartContext dan tambahkan migration/cleanup untuk cart legacy yang malformed. | P2 |

## Test case minimum

1. Buyer tidak dapat membuat order dengan total 0 atau nominal berbeda dari harga product.
2. Buyer tidak dapat memasukkan `order_items` dari merchant lain.
3. `subtotal`, `total`, `product_price`, dan `item.subtotal` dihitung ulang server.
4. Voucher one-use hanya berhasil sekali untuk user yang sama, termasuk dua request paralel.
5. Voucher usage limit tidak bisa dilewati melalui race.
6. Checkout dua merchant rollback penuh ketika reservation merchant kedua gagal.
7. Flash sale expired saat submit tidak tetap memberi harga flash sale.
8. Quantity negatif, pecahan, terlalu besar, dan NaN ditolak server.
9. Perubahan harga antara cart dan submit menghasilkan quote baru, bukan order dengan harga client lama.
10. Reservation stock dan order creation rollback bersama jika salah satu item invalid.

## Batasan audit

Audit belum melakukan replay request ke PostgREST production, belum mengukur policy database live, dan belum menguji concurrency checkout/voucher dengan beberapa session. Temuan P0 perlu dikonfirmasi dengan test staging menggunakan anon/authenticated client dan segera ditutup sebelum checkout dianggap aman.
