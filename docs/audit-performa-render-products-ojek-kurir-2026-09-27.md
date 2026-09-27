# Audit Performa Render, `/products`, dan Pendaftaran Ojek/Kurir

**Tanggal:** 27 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`

## Ringkasan

Audit source dan production build menemukan tiga area yang paling berdampak pada pengalaman awal:

1. **Render awal:** splash screen menahan konten aplikasi selama 1.520 ms secara artifisial (1.100 ms minimum + 420 ms transisi).
2. **`/products`:** query katalog mengambil nested merchant reviews walaupun kartu produk tidak merender review body; pencarian melakukan filter/sort ulang pada setiap keystroke; semua kartu menjalankan animasi bertingkat.
3. **Pendaftaran ojek/kurir:** tiga dokumen di-upload serial; pendaftar aktif tidak diperiksa sebelum upload, sehingga retry dapat membuang bandwidth dan berisiko membuat duplikasi; file belum divalidasi di sisi UI sebelum dikirim.

## Perbaikan yang diterapkan

### 1. Render awal

- Splash gate dipangkas menjadi 350 ms + 250 ms transisi.
- Durasi Tailwind diselaraskan sehingga tidak menghasilkan warning class ambigu.
- Konten route tetap dipertahankan di bawah splash, sehingga pekerjaan render dapat berlangsung paralel dengan brand moment.

### 2. `/products`

- `ProductsPage` memanggil `fetchProducts({ includeReviews: false })`; nested review body tidak lagi dikirim pada jalur katalog.
- `useDeferredValue` dipakai untuk query pencarian agar input tetap responsif saat daftar besar sedang difilter.
- `ProductCard` hanya menganimasikan 12 kartu pertama; kartu berikutnya menggunakan `content-visibility: auto` dan intrinsic size untuk mengurangi layout/paint work.
- `fetchProducts` melempar error database/API agar React Query menampilkan state error dan tombol retry, bukan pesan katalog kosong yang menyesatkan.

### 3. Pendaftaran ojek/kurir

- File diverifikasi di browser dengan `validateUploadFile` (JPG/PNG/WebP, maksimal 5 MB) sebelum state upload disimpan.
- Pendaftaran aktif (`PENDING` atau `APPROVED`) dicek sebelum upload dokumen.
- Tiga upload independen dijalankan paralel; cleanup object yang sudah berhasil tetap dilakukan bila salah satu upload atau insert gagal.
- Tombol submit tetap disabled selama mutation berjalan, sehingga tidak menambah request paralel dari UI.

### Catatan alur booking kurir

Pada branch yang diaudit, `CourierBookingPage` sudah memanggil RPC `create_courier_order`, memeriksa `order_id`, dan mengarahkan buyer ke tracking. Area ini diverifikasi dan tidak perlu diubah pada patch ini.

## Validasi

| Pemeriksaan | Hasil |
|---|---:|
| `git diff --check` | PASS |
| `pnpm exec tsc --noEmit` | PASS |
| `pnpm lint` | PASS, 1 warning lama di `FoodFilterSheet.tsx` |
| Test terarah `fileValidation` + `buyerTransaction` | PASS — 9/9 |
| `pnpm build` | PASS |
| Full `pnpm test` | 289 passed, 20 skipped, 3 failure kontrak lama |

Full-suite failure berada di `serviceEnhancementContract.test.ts` dan `chat/phase8Acceptance.test.ts` (tiga assertion kontrak service/chat), tidak menyentuh file yang diubah oleh audit ini. Failure tersebut dicatat sebagai baseline repository dan tidak diperbaiki agar scope perubahan tetap terbatas.

## File yang diubah

- `src/components/SplashScreen.tsx`
- `src/pages/ProductsPage.tsx`
- `src/lib/api.ts`
- `src/components/ProductCard.tsx`
- `src/pages/RegisterCourierPage.tsx`
