# Audit Frontend SaDesa

**Tanggal audit:** 10 September 2026  
**Cakupan:** halaman buyer, discovery, produk, keranjang, checkout, pesanan, akun, navigasi mobile, state loading/error, dan responsivitas.  
**Metode:** inspeksi source code, penelusuran alur state, pemeriksaan query dan event handler, build produksi, lint, serta pengujian Vitest.

## Kesimpulan umum

Frontend SaDesa sudah memiliki fondasi marketplace yang cukup lengkap. Alur utama seperti katalog produk, detail produk, keranjang, checkout, pembayaran, pesanan, wishlist, dan akun telah tersedia. Namun, kesiapan pengalaman belanja belum konsisten karena beberapa keputusan state di frontend dapat menghasilkan total yang membingungkan atau perilaku checkout yang salah pada skenario lebih dari satu toko.

**Prioritas tertinggi adalah checkout multi-toko dan konsistensi keranjang.** Keduanya menyentuh nominal pembayaran dan status order, sehingga harus diperbaiki sebelum fokus pada polish visual. Setelah itu, perbaikan utama berada pada error state, filter eksplorasi, dan affordance navigasi mobile.

## Ringkasan prioritas

| Prioritas | Area | Temuan utama | Dampak |
|---|---|---|---|
| P0 | Checkout multi-toko | Ongkir dan biaya COD dihitung ulang untuk setiap toko menggunakan nilai total yang sama. | Total order dapat terhitung lebih besar dari ringkasan checkout. |
| P0 | Pembayaran online multi-toko | Redirect ke invoice terjadi di dalam loop toko, sehingga order toko berikutnya tidak pernah dibuat. | Sebagian order hilang dari transaksi pengguna. |
| P0 | Metode pembayaran | Pengaturan pembayaran hanya mengambil toko pertama, tetapi checkout dapat membuat order untuk banyak toko. | Metode pembayaran bisa tidak valid untuk toko lain. |
| P1 | Keranjang | Total floating cart menghitung semua item, sedangkan halaman keranjang menghitung item yang dipilih. | Pengguna melihat dua total berbeda. |
| P1 | Keranjang | Pengelompokan menggunakan nama toko, bukan ID toko. | Dua toko dengan nama sama dapat tercampur. |
| P1 | Eksplorasi | Filter rating dihitung sebagai filter aktif, tetapi tidak diterapkan pada data. | UI memberi kesan filter bekerja padahal hasil tidak berubah. |
| P1 | Error state | Beberapa halaman menganggap error API sebagai data kosong atau tidak memberi tombol retry. | Pengguna tidak dapat membedakan sistem kosong dari sistem gagal. |
| P1 | Produk | Product list dibatasi 200 item dan infinite scroll hanya membagi data yang sudah diambil. | Produk setelah item ke-200 tidak pernah muncul. |
| P2 | UX mobile | Floating cart berpotensi bertabrakan dengan bottom navigation. | CTA keranjang dapat menutupi atau tertutup navigasi. |
| P2 | Aksesibilitas | Tombol tambah keranjang berada di dalam elemen Link yang sama. | Struktur interaktif bertumpuk dan perilaku keyboard kurang ideal. |
| P2 | Checkout | Banyak data awal memakai default sebelum konfigurasi toko selesai dimuat. | Pengguna dapat melihat opsi pembayaran atau ongkir sementara yang belum final. |

## Temuan detail

### 1. Checkout multi-toko berisiko salah menghitung nominal

Di `CheckoutPage.tsx`, `shippingCost` dan `codServiceFee` dihitung sebagai nilai checkout global. Namun, ketika order dibuat, nilai tersebut dipakai ulang untuk setiap merchant pada loop `itemsByMerchant`.

Akibatnya, jika satu checkout berisi dua toko, setiap order toko menerima `merchantShipping = shippingCost` dan `merchantCodFee = codServiceFee`. Ringkasan di layar hanya menampilkan satu ongkir dan satu biaya COD, sedangkan payload order dapat menjumlahkan biaya tersebut dua kali.

**Rekomendasi:** pilih salah satu kontrak produk berikut dan terapkan konsisten.

1. Batasi checkout menjadi satu toko per transaksi dan berikan pesan yang jelas ketika keranjang berisi beberapa toko.
2. Pertahankan multi-toko, tetapi hitung ongkir, biaya COD, voucher, dan total secara terpisah per toko serta tampilkan rincian per toko di UI.

Untuk stabilitas jangka pendek, opsi pertama lebih aman. Untuk marketplace yang matang, opsi kedua lebih lengkap tetapi memerlukan kontrak backend yang eksplisit.

### 2. Pembayaran online multi-toko dapat membuat order parsial

Pada `CheckoutPage.tsx`, pembuatan invoice online berada di dalam loop pembuatan order. Setelah order pertama berhasil, kode mengubah `window.location.href` ke invoice dan langsung keluar dari fungsi. Merchant berikutnya belum diproses.

Ini dapat menghasilkan kondisi ketika pengguna membayar satu invoice, tetapi item dari toko lain tidak memiliki order. Masalah ini bersifat **P0** karena menyentuh konsistensi transaksi.

**Rekomendasi:** buat seluruh order dan seluruh order item terlebih dahulu dalam satu proses atomik, kemudian buat satu payment session yang mereferensikan seluruh order. Jika provider pembayaran hanya mendukung satu order per invoice, batasi checkout online ke satu merchant.

### 3. Pengaturan pembayaran hanya berasal dari merchant pertama

`firstMerchantId` dipakai untuk mengambil lokasi, wilayah, rekening bank, QRIS, dan pengaturan COD/transfer. Namun, `itemsByMerchant` dapat berisi beberapa merchant.

Akibatnya, UI dapat menampilkan rekening toko pertama untuk pembayaran item dari toko lain. Checkout juga dapat mengizinkan COD atau transfer berdasarkan toko pertama saja.

**Rekomendasi:** tampilkan dan validasi pengaturan pembayaran per merchant. Jika belum ada dukungan pembayaran multi-toko, batasi checkout satu merchant.

### 4. Total floating cart tidak konsisten dengan halaman keranjang

`FloatingCartButton.tsx` menggunakan `getCartTotal()`, yang menghitung seluruh item di keranjang. `CartPage.tsx` menggunakan `selectedTotal`, yang hanya menghitung item yang dicentang.

Ketika pengguna menghapus centang satu produk, tombol floating masih menampilkan total semua produk, sedangkan ringkasan keranjang menampilkan total item terpilih. Label `Total` menjadi ambigu.

**Rekomendasi:** gunakan total item terpilih untuk CTA menuju checkout, atau ubah label menjadi `Subtotal semua item` dan tambahkan indikator jumlah item. State selection sebaiknya diekspos dari `CartContext` agar semua komponen memakai sumber kebenaran yang sama.

### 5. Pengelompokan cart berdasarkan nama toko

`CartPage.tsx` membuat group key menggunakan `item.product.merchantName`. Nama bukan identifier unik. Dua merchant berbeda dapat memakai nama yang sama dan akhirnya tampil dalam satu grup. Status buka/tutup juga diambil dari merchant pertama pada grup tersebut.

**Rekomendasi:** gunakan `merchantId` sebagai key internal. Nama toko tetap digunakan sebagai label tampilan.

### 6. Tombol pilih semua bersifat global, bukan per toko

Tombol `Pilih semua` dirender pada setiap grup merchant, tetapi memanggil `selectAllItems()` dari context. Artinya, tombol pada toko A memilih seluruh item dari semua toko, bukan hanya item toko A.

**Rekomendasi:** tambahkan `selectMerchantItems(merchantId)` dan `clearMerchantItems(merchantId)`. Label tombol juga perlu berubah menjadi `Pilih semua toko` jika memang perilakunya global.

### 7. Perubahan harga belum memiliki jalur pemulihan yang baik

Cart melakukan validasi stok dan harga dari server. Jika harga berubah, item diberi warning dan checkout diblokir. Namun, pengguna tidak mendapat tombol untuk menerima harga terbaru atau memuat ulang item.

**Rekomendasi:** sediakan aksi `Perbarui harga`, tampilkan harga lama dan harga baru dengan jelas, lalu minta konfirmasi pengguna sebelum checkout.

### 8. Filter rating di Explore belum diterapkan

`ExplorePage.tsx` menghitung `activeFilterCount` dari `filters.minRating`, tetapi `filteredData` hanya menerapkan district dan price range. Tidak ada kondisi yang menyaring berdasarkan rating.

Ini adalah bug UX yang mudah diverifikasi: pengguna memilih rating minimum, badge jumlah filter berubah, tetapi daftar hasil tidak berubah.

**Rekomendasi:** tentukan rating yang dimaksud, misalnya rating merchant atau rating wisata, lalu terapkan filter pada entity terkait. Jika belum tersedia, jangan tampilkan opsi rating atau tandai sebagai belum didukung.

### 9. Error API sering tampil sebagai empty state

`ProductsPage.tsx` hanya membaca `isLoading` dari React Query. `ExplorePage.tsx` juga hanya membaca flag loading. Sementara itu, `fetchProducts()` mengembalikan array kosong ketika query Supabase gagal.

Dengan kombinasi ini, kegagalan API dapat tampil sebagai `Tidak ada produk ditemukan` atau `Belum ada data`. Pengguna tidak mendapat penjelasan atau tombol retry.

**Rekomendasi:** pertahankan error sebagai error, jangan mengubahnya menjadi array kosong. Tambahkan `isError`, pesan yang spesifik, dan aksi `Coba lagi` pada halaman Products, Explore, Home, Cart, dan Account.

### 10. Daftar produk efektif hanya mengambil maksimal 200 item

`fetchProducts()` menjalankan query dengan `.limit(200)`. Infinite scroll pada Explore hanya melakukan slicing terhadap array yang sudah diambil, bukan pagination server-side.

Ketika katalog melebihi 200 produk, produk berikutnya tidak pernah dapat dijangkau. Ini juga membuat beban awal besar pada perangkat mobile.

**Rekomendasi:** gunakan pagination berbasis cursor atau `useInfiniteQuery`. Ambil 20–40 item per halaman dan sertakan total atau `hasMore` dari API.

### 11. Cache produk dapat menahan stok, harga, dan status toko yang kedaluwarsa

`api.ts` memiliki cache in-memory 60 detik, sementara React Query memiliki cache dan stale time sendiri. Data produk yang dikembalikan sudah memuat `isAvailable`, harga promo, stok, kuota, dan status buka toko.

Cart memang melakukan validasi ulang ketika halaman keranjang dibuka, tetapi kartu produk dan detail produk dapat tetap menampilkan status lama sampai cache kedaluwarsa.

**Rekomendasi:** gunakan satu strategi caching utama. Untuk stok dan harga, gunakan stale time lebih pendek atau revalidasi saat fokus halaman. Status stok final tetap harus divalidasi oleh backend secara atomik.

### 12. Product detail tidak membedakan error dari produk tidak ditemukan

`ProductDetail.tsx` hanya menggunakan `productLoading` dan `product`. Jika query gagal karena jaringan atau Supabase, `product` tetap null dan pengguna melihat `Produk tidak ditemukan`.

**Rekomendasi:** gunakan `isError` dan `error` dari React Query. Sediakan tombol `Coba lagi` serta tombol kembali ke katalog.

### 13. Arti tombol Beli Langsung belum aman ketika cart sudah berisi item lain

`handleBuyNow()` menambahkan produk ke cart lalu menavigasi ke checkout. Checkout mengambil `selectedItems` dari context, sehingga item lain yang sudah terpilih dapat ikut masuk ke checkout.

Pengguna biasanya memahami `Beli Langsung` sebagai pembelian produk saat ini, bukan semua item yang sedang terpilih di cart.

**Rekomendasi:** dukung checkout session sementara untuk satu produk, atau kosongkan selection lama hanya untuk flow `Beli Langsung` tanpa menghapus isi keranjang.

### 14. Floating cart berpotensi bertabrakan dengan bottom navigation

`FloatingCartButton` diposisikan pada `bottom-20`, sedangkan mobile `BottomNav` berada di dasar layar dan memakai safe-area. Tinggi aktual navigasi dapat berbeda antar perangkat, terutama perangkat dengan gesture navigation.

**Rekomendasi:** buat CSS variable untuk tinggi bottom nav dan gunakan nilai yang sama untuk posisi floating cart serta padding konten. Tambahkan safe-area pada sticky action bar keranjang, detail produk, dan checkout.

### 15. Struktur interaktif ProductCard kurang ideal untuk aksesibilitas

`ProductCard` merender seluruh kartu sebagai `Link`, lalu menempatkan tombol tambah keranjang dan tombol wishlist di dalamnya. Event handler memang memanggil `preventDefault`, tetapi elemen interaktif bersarang tetap menyulitkan navigasi keyboard, pembaca layar, dan pengujian otomatis.

**Rekomendasi:** ubah struktur menjadi kartu biasa dengan link khusus pada gambar/nama produk. Letakkan tombol wishlist dan tambah keranjang sebagai sibling yang tidak bersarang di dalam link.

### 16. Checkout belum memiliki guard loading terpadu

Checkout memuat konfigurasi ongkir, COD, Xendit, status buyer, lokasi merchant, dan jam operasional melalui beberapa effect terpisah. Sebagian state memiliki default yang terlihat valid sebelum request selesai.

Pengguna dapat melihat metode COD atau transfer sebelum pengaturan toko selesai dimuat. Tombol submit memang memiliki beberapa guard, tetapi pengalaman visualnya tetap dapat membingungkan.

**Rekomendasi:** tampilkan skeleton atau state `Menyiapkan checkout` sampai data wajib tersedia. Bedakan data belum dimuat, data kosong, dan data gagal.

### 17. Error profil di AccountPage hanya masuk console

`AccountPage.tsx` menangkap error fetch profile, mencetaknya ke console, lalu menampilkan halaman tanpa informasi bahwa profil gagal dimuat.

**Rekomendasi:** tambahkan inline error dengan tombol retry. Jangan membuat pengguna menyimpulkan profil kosong ketika sebenarnya request gagal.

## Audit visual dan responsivitas

Secara visual, pola mobile shell sudah konsisten dan perbaikan terakhir pada kategori, hero, header, serta bottom navigation sudah membantu layar kecil. Namun, beberapa fixed bar masih memakai aturan sendiri-sendiri. Cart summary, product detail actions, checkout action, floating cart, dan bottom navigation perlu memakai sistem spacing dan safe-area yang sama.

Beberapa halaman juga menampilkan terlalu banyak fungsi dalam satu viewport. Explore menggabungkan search, filter, sort, tabs, desa, wisata, dan produk dalam satu alur panjang. Pada perangkat 320–375 px, kontrol filter dan sort perlu diuji khusus karena tiga kontrol dalam satu baris berpotensi menyempitkan area input pencarian.

## Roadmap perbaikan yang disarankan

| Fase | Pekerjaan | Hasil yang diharapkan |
|---|---|---|
| Fase 1 | Batasi checkout multi-toko atau implementasikan kontrak multi-toko yang benar. | Tidak ada order parsial atau biaya terduplikasi. |
| Fase 1 | Samakan total floating cart dengan selection state. | Pengguna melihat total yang konsisten. |
| Fase 1 | Perbaiki grouping cart berdasarkan merchant ID dan pilih semua per merchant. | Item dan status toko tidak tercampur. |
| Fase 1 | Tambahkan error state dan retry untuk Products, Explore, Product Detail, Cart, dan Account. | Error jaringan tidak terlihat sebagai data kosong. |
| Fase 2 | Implementasikan filter rating dan pagination server-side. | Discovery bekerja sesuai kontrol yang ditampilkan. |
| Fase 2 | Tambahkan jalur update harga dan stok dari server. | Pengguna dapat memulihkan cart tanpa menghapus item manual. |
| Fase 2 | Pisahkan flow Beli Langsung dari selection cart biasa. | CTA menghasilkan perilaku yang sesuai ekspektasi. |
| Fase 3 | Satukan design token fixed bar dan safe-area. | Floating cart dan bottom navigation tidak bertabrakan. |
| Fase 3 | Rapikan struktur interaktif ProductCard dan audit keyboard navigation. | Aksesibilitas dan testability meningkat. |
| Fase 3 | Tambahkan automated tests untuk multi-merchant checkout dan cart selection. | Regresi nominal dan selection dapat dicegah. |

## Status verifikasi teknis

| Pemeriksaan | Hasil | Catatan |
|---|---|---|
| Production build | Berhasil | Vite berhasil membangun client dan service worker. |
| ESLint | Berhasil dengan 8 warning | Tidak ada error; warning berada pada fast refresh dan dependency hook di area lain. |
| Vitest command awal | Gagal dijalankan | Opsi `--runInBand` bukan opsi Vitest. Ini adalah kesalahan command, bukan kegagalan test. |
| Vitest command yang benar | Berhasil | Test suite selesai dengan exit code 0; terdapat deprecation warning `punycode`. |
| Preview visual | Terbatas | Preview Vite terbuka, tetapi browser sandbox menampilkan root kosong tanpa console error. Audit visual utama karena itu didasarkan pada source dan screenshot referensi pengguna. |

## Kesimpulan

SaDesa tidak kekurangan fitur utama. Kekurangan terbesar berada pada **konsistensi state dan kontrak transaksi**, bukan pada jumlah halaman. Fokus perbaikan sebaiknya dimulai dari checkout multi-toko, sinkronisasi selection dan total keranjang, serta error state yang jujur. Setelah tiga area tersebut stabil, peningkatan visual dan aksesibilitas akan menghasilkan dampak yang lebih terukur.

## References

[1]: https://github.com/bonangpanjinur/Sadesa-fix "SaDesa frontend repository"
[2]: https://tanstack.com/query/latest/docs/framework/react/overview "TanStack Query React documentation"
[3]: https://www.w3.org/WAI/WCAG22/Understanding/name-role-value.html "WCAG 2.2 Name, Role, Value"
[4]: https://developer.mozilla.org/en-US/docs/Web/CSS/env "MDN CSS env() function"
