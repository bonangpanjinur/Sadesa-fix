# Audit dan Implementasi Pengiriman Ekspedisi

**Tanggal:** 12 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** aturan radius pengiriman lokal, pemilihan ekspedisi, input nomor resi merchant, dan tracking resi pada frontend pembeli.

## Kesimpulan

Arsitektur SaDesa sudah memiliki dasar yang tepat untuk membedakan pengiriman lokal dan ekspedisi. Checkout authoritative membuat `delivery_type`, menyimpan jarak pembeli, dan database menolak metode `INTERNAL` apabila jarak atau wilayah administratif melampaui batas. Perbaikan yang diperlukan berada pada tahap fulfillment dan pengalaman tracking.

Implementasi telah menutup dua celah utama. Pertama, handoff ekspedisi pada salah satu jalur merchant sebelumnya dapat langsung mengubah status menjadi `SENT` tanpa meminta nama ekspedisi dan nomor resi. Kedua, data resi yang sudah disimpan belum dapat dipakai pembeli untuk membuka tracking provider. Perubahan sekarang mewajibkan data tersebut di backend dan menyediakan kartu resi yang dapat diklik pada halaman tracking pembeli.

## Temuan Audit

| ID | Tingkat | Temuan | Dampak |
|---|---|---|---|
| EXP-P1-01 | P1 | Validasi radius dan wilayah sudah berada di trigger database, sehingga aturan tidak hanya bergantung pada frontend. | Positif. Manipulasi pilihan delivery dari browser tidak dapat melewati aturan internal. |
| EXP-P1-02 | P1 | Field `expedition_name` dan `tracking_number` telah ditambahkan pada migration terbaru, tetapi satu jalur merchant masih memiliki tombol handoff langsung. | Pesanan dapat berstatus `SENT` tanpa informasi yang dibutuhkan pembeli. |
| EXP-P1-03 | P1 | Halaman pembeli belum menampilkan resi ekspedisi atau tautan tracking. | Pembeli harus mencari dan menyalin resi secara manual. |
| EXP-P1-04 | P1 | Handoff backend belum mewajibkan payload nama ekspedisi dan resi. | Client lain dapat memanggil RPC dengan data tidak lengkap. |
| EXP-P2-01 | P2 | Provider ekspedisi tidak semuanya mengizinkan halaman tracking ditampilkan melalui iframe. | Modal iframe dapat kosong untuk provider tertentu jika provider mengirim `X-Frame-Options` atau CSP. |

## Perubahan Implementasi

### Backend dan database

Migration `56_20260912211000_add_expedition_tracking_fields.sql` tetap menjadi sumber perubahan schema. Fungsi `merchant_transition_order` sekarang menolak transisi `PROCESSED -> SENT` untuk order `EXPEDITION` apabila payload tidak memuat `expedition_name` dan `tracking_number` yang tidak kosong. Data tetap dicatat melalui jalur RPC authoritative dan tidak melalui update bebas dari browser.

Aturan radius tidak diubah. Migration `47_20260909210000_delivery_method_restrictions.sql` tetap menjadi otoritas untuk batas 10 km serta perbandingan kabupaten/kota dan kecamatan.

### Frontend merchant

`MerchantOrdersPage` sekarang meminta dua input sebelum handoff ekspedisi:

| Input | Wajib | Batas |
|---|---:|---:|
| Nama ekspedisi | Ya | 100 karakter |
| Nomor resi | Ya | 120 karakter |

Jalur ini memanggil RPC yang sama dengan jalur handoff lain, sehingga pencatatan status, timestamp, dan history order tetap konsisten.

### Frontend pembeli

`OrderTrackingPage` sekarang menampilkan provider dan nomor resi apabila order bertipe `EXPEDITION`. Untuk provider yang dikenal, nomor resi dapat diklik untuk membuka modal tracking. Modal berisi iframe dan tautan fallback ke tab baru.

URL tracking dibentuk oleh `src/lib/expeditionTracking.ts` menggunakan allowlist provider. Input nama ekspedisi dinormalisasi untuk mendukung alias umum seperti `J&T`, `J&T Express`, dan `Si Cepat`. Provider yang tidak dikenal tidak menghasilkan URL eksternal, sehingga input merchant tidak dapat digunakan untuk menyuntikkan URL arbitrer ke frontend.

Provider yang didukung saat ini adalah JNE, J&T Express, SiCepat, AnterAja, Ninja Xpress, Pos Indonesia, TIKI, Wahana, dan Lion Parcel.

## Validasi

Quality gate berhasil dijalankan tanpa error:

```text
pnpm exec tsc --noEmit  -> lulus
pnpm lint               -> lulus
pnpm vitest run src/lib/expeditionTracking.test.ts src/lib/deliveryRestriction.test.ts
                         -> 2 file, 8 test lulus
```

Test baru mencakup resolusi alias provider, encoding nomor resi, dan penolakan provider tidak dikenal. Test existing untuk aturan radius juga tetap lulus.

## Rekomendasi Deployment

Migration database harus diterapkan ke Supabase environment yang digunakan aplikasi sebelum frontend dirilis. Setelah migration aktif, lakukan smoke test berikut pada staging:

1. Buat order dengan jarak di bawah batas dan pilih `INTERNAL`. Pastikan order dapat diproses.
2. Buat order di luar batas dan pastikan checkout hanya menawarkan atau memilih `EXPEDITION`.
3. Coba panggil handoff ekspedisi tanpa nama atau resi. RPC harus menolak request.
4. Handoff dengan `JNE` dan nomor resi contoh. Pastikan status berubah menjadi `SENT` dan data tersimpan.
5. Login sebagai pembeli, buka tracking order, klik nomor resi, dan pastikan modal atau tab baru terbuka.
6. Uji provider yang menolak iframe. Fallback tab baru harus tetap tersedia.

Untuk produksi, opsi paling stabil adalah menggunakan tautan tab baru sebagai perilaku utama atau menambahkan integrasi API tracking server-side apabila provider menyediakan API resmi. Iframe tidak boleh dianggap sebagai satu-satunya mekanisme karena kebijakan keamanan provider eksternal dapat berubah.

## File Perubahan

- `src/lib/expeditionTracking.ts`
- `src/lib/expeditionTracking.test.ts`
- `src/pages/OrderTrackingPage.tsx`
- `src/pages/merchant/MerchantOrdersPage.tsx`
- `src/hooks/useRealtimeOrders.ts`
- `supabase/bootstrap/56_20260912211000_add_expedition_tracking_fields.sql`

## References

[1]: https://supabase.com/docs/guides/database/postgres/row-level-security "Supabase Row Level Security documentation"
[2]: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options "MDN X-Frame-Options documentation"
[3]: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-ancestors "MDN CSP frame-ancestors documentation"
