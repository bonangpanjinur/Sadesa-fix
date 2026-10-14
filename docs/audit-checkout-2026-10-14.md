# Audit Alur Checkout — 2026-10-14

## Ringkasan

Audit dilakukan terhadap alur **cart → checkout → quote ongkir → validasi → create order → pembayaran**, termasuk checkout akun dan guest, serta kontrak RPC/migration terbaru.

**Kesimpulan audit awal:** fondasi checkout sudah cukup kuat dan tidak perlu dirombak. Dua gap yang ditemukan pada audit awal sekarang sudah diperbaiki melalui migration `20261014113000_enforce_marketplace_checkout_payment_and_phone.sql` dan bootstrap bundle `119_20261014113000_to_20261014113000.sql`.

1. **P1 — Validasi metode pembayaran di server:** **sudah diperbaiki** dengan trigger database yang menolak transfer merchant-disabled dan online ketika Xendit tidak aktif.
2. **P2 — Validasi nomor telepon di server:** **sudah diperbaiki** dengan kontrak 8–15 digit setelah separator non-digit dibuang.
3. **P2 — Regression guard:** **sudah ditambahkan** untuk migration dan bootstrap contract.

Perubahan tidak menyentuh UX checkout, pricing, stock reservation, single-merchant policy, atau order type non-marketplace.

## Bagian yang sudah baik dan sengaja tidak disentuh

- **Server quote authoritative:** subtotal, harga flash sale, diskon voucher, ongkir, total, dan line price dikalkulasi dari server.
- **Create order authoritative dan atomic:** create path mengunci product, memvalidasi merchant/product/stock, menghitung ulang harga/ongkir, membuat order, order items, dan reservation dalam satu fungsi database.
- **Idempotency:** checkout key memakai advisory transaction lock dan tabel idempotency; retry tidak seharusnya membuat order kedua.
- **Single merchant policy:** client dan server sama-sama menolak cart lintas merchant untuk checkout ini.
- **Stok:** cart direfresh, submit melakukan pengecekan ulang, lalu database melakukan lock/reservation final.
- **Guest checkout:** guest dibatasi ke transfer, menerima token akses order, dan memiliki jalur idempotency/session yang berbeda.
- **Payment recovery:** jika order berhasil tetapi invoice online gagal, order tidak dibuang; user mendapat aksi retry.
- **Fail-closed:** CTA diblokir ketika quote, lokasi, payment settings, jam toko, atau stok belum siap.
- **Cart preservation:** item tidak dihapus ketika quote/order gagal; item hanya dibersihkan setelah order berhasil.
- **Jarak:** isu `p_distance_km` yang ditemukan pada audit 2026-10-13 sudah diperbaiki; server sekarang menghitung jarak dari koordinat sendiri.

## Temuan detail

### P1 — Metode pembayaran dapat dibypass melalui direct RPC — fixed

**Bukti:**

- Client memuat `payment_transfer_enabled` dan `isXenditEnabled()` lalu menentukan pilihan yang tampil di `CheckoutPage.tsx`.
- Namun migration terbaru `supabase/migrations/20261014090000_checkout_authoritative_create_and_line_quotes.sql` pada fungsi `create_marketplace_checkout` hanya memvalidasi:
  - `p_payment_method IN ('COD', 'TRANSFER', 'ONLINE')`;
  - pembatasan `ONLINE` untuk satu merchant.
- Tidak ada validasi server yang mengikat:
  - `TRANSFER` ke `merchants.payment_transfer_enabled`;
  - `ONLINE` ke `app_settings.payment_xendit.enabled`.

**Dampak:** caller yang tidak memakai UI dapat membuat order transfer pada merchant yang sudah mematikan transfer, atau membuat order online ketika gateway global tidak aktif. Order dapat masuk dengan status pembayaran yang tidak dapat diselesaikan secara normal. Ini juga membuka kemungkinan status operasional yang membingungkan merchant/buyer.

**Prioritas:** P1 karena menyangkut integritas state pembayaran dan dapat dicapai dengan memanggil RPC langsung.

**Implementasi:**

- Migration baru memasang trigger `enforce_marketplace_checkout_contract` pada order marketplace.
- Trigger menolak `TRANSFER` ketika merchant menonaktifkan transfer dan `ONLINE` ketika `payment_xendit.enabled` tidak aktif.
- Guard client tetap dipertahankan dan regression guard baru sudah ditambahkan.

### P2 — Validasi telepon hanya kuat di client — fixed

**Bukti:**

- Client menjalankan `validatePhone(addressData.phone).isValid` di `CheckoutPage.tsx` sebelum submit.
- RPC terbaru hanya memeriksa phone tidak kosong dan panjang maksimal 40 karakter di `create_marketplace_checkout` dan `create_guest_marketplace_checkout`.
- Tidak ada validasi format/normalisasi server yang setara.

**Dampak:** request langsung dapat menyimpan nilai seperti `abc`, nomor terlalu pendek, atau format yang tidak dapat dihubungi. Ini terutama berdampak pada delivery dan follow-up pembayaran.

**Prioritas:** P2 karena lebih merupakan kualitas data/operasional daripada bypass harga atau stok.

**Implementasi:**

- Trigger server membuang separator non-digit untuk validasi dan menolak nomor di luar rentang 8–15 digit.
- Nilai tampilan yang dikirim buyer tetap dipertahankan; tidak ada perubahan UX input.
- Regression guard migration/bootstrap sudah ditambahkan.

### P2 — Test kontrak sebelum implementasi belum mengunci enforcement server

Cakupan awal belum mengunci bahwa RPC menolak:

- transfer ketika merchant `payment_transfer_enabled = false`;
- online ketika `payment_xendit.enabled = false`;
- nomor telepon invalid yang dikirim langsung ke RPC.

**Status:** regression guard sudah ditambahkan pada `src/lib/checkoutServerContract.test.ts`. Integration test database tetap disarankan ketika staging database tersedia, khususnya untuk memastikan order dan reservation tidak tertinggal saat trigger menolak insert.

## Alur yang diaudit

| Tahap | Status | Catatan |
|---|---|---|
| Cart selection | Baik | Selection per item/topping, single merchant guard, stock refresh tersedia |
| Address/contact | Baik | Region dan koordinat diwajibkan untuk delivery; phone format 8–15 digit sekarang ditegakkan server |
| Delivery/ongkir | Baik | Quote server dan shipping contract dipakai; submit menunggu route/quote siap |
| Voucher | Baik | Account-only, merchant scope, expiry/usage/minimum order divalidasi ulang di server |
| Payment choice | Baik setelah migration | UI guard tetap ada dan database sekarang menolak direct RPC untuk merchant/gateway yang disabled |
| Create order | Baik | Reprice, stock lock, reservation, order insert, idempotency berada di server |
| Online invoice | Baik dengan recovery | Order dipertahankan bila invoice gagal; retry tersedia |
| Transfer proof | Baik | Guest transfer-only dan proof path/token contract sudah diperketat |
| Failure handling | Baik | Cart tidak dihapus pada error; CTA fail-closed pada state penting |

## Validasi yang dijalankan

- Full repository tests: **189 test files, 768 passed, 20 skipped**.
- New server-contract guard: **3 tests passed**.
- `pnpm exec tsc --noEmit`: **passed**.
- `pnpm build`: **passed**.
- `pnpm run validate:package-manager`: **passed**.
- `pnpm run validate:migrations`: **passed** dengan warning duplicate timestamp lama yang sudah dilaporkan script.
- `pnpm run validate:db-bootstrap`: **passed**.
- `pnpm run audit:rls`: **completed**; output menunjukkan tabel internal checkout/idempotency memang tanpa policy client, sesuai pola server-only.

## Tindak lanjut deployment

1. Terapkan migration `20261014113000_enforce_marketplace_checkout_payment_and_phone.sql` melalui jalur migration resmi; jangan menjalankan bootstrap bundle terhadap database yang sudah memiliki migration history.
2. Jalankan integration test di staging untuk payment transfer disabled, online gateway disabled, nomor telepon invalid, dan rollback/no-partial-reservation.
3. Setelah staging lulus, jalankan kembali full change-safety gate sebelum deploy production.

## Scope yang tidak dilakukan

- Tidak mengubah UX checkout yang sudah bekerja.
- Tidak mengaktifkan COD/expedition atau mengubah single-merchant policy.
- Tidak menguji transaksi nyata di payment provider atau database production karena tidak ada environment transaksi yang diminta/tersedia dalam audit ini.
