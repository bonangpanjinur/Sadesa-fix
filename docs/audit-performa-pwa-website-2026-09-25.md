# Audit Performa PWA dan Website SaDesa

**Tanggal:** 25 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`

## Ringkasan eksekutif

Audit menemukan bahwa lambatnya startup terutama berasal dari tiga hal: splash screen yang menahan aplikasi secara sengaja selama sekitar 1,52 detik, service worker yang melakukan precache terhadap seluruh chunk dan aset sehingga instalasi PWA mencapai 346 entry atau sekitar 6.275 KiB, serta import `framer-motion` di entry aplikasi untuk transisi route yang membuat library animasi ikut dikirim pada navigasi awal. Selain itu, query React Query melakukan hingga dua retry tambahan terhadap kegagalan jaringan, sehingga kondisi Supabase lambat atau offline terasa seperti aplikasi menggantung dan dapat menghasilkan error berulang.

Perbaikan telah diterapkan langsung pada kode. Splash sekarang hanya menjadi fallback visual singkat dengan durasi minimum 240 ms dan exit 220 ms. Transisi route global diganti wrapper ringan sehingga halaman tetap dapat menggunakan animasi secara lazy sesuai kebutuhan, tetapi `framer-motion` tidak lagi menjadi dependensi wajib entry route. Retry query dibatasi menjadi satu retry terkontrol untuk error transient.

Konfigurasi PWA sekarang hanya melakukan precache terhadap shell kritis: HTML, CSS, font, ikon, serta vendor inti. Chunk route, aset media, dan gambar publik dicache setelah pertama kali dipakai melalui service worker custom. Hasil build menunjukkan precache turun menjadi 19 entry atau 1.047,76 KiB, sekitar 83% lebih kecil daripada baseline, tanpa menghilangkan cache lanjutan untuk navigasi berikutnya.

## Temuan dan tindakan

| Area | Temuan | Perbaikan |
|---|---|---|
| First paint | Splash menahan UI selama minimal 1.100 ms lalu fade-out 420 ms. | Durasi startup dipangkas menjadi 240 ms + exit 220 ms; aplikasi tidak lagi menunggu delay artifisial. |
| Entry bundle | `framer-motion` di-import dari `App.tsx` hanya untuk transisi route. | Transisi route diganti wrapper `div`; animasi halaman tetap lazy-loaded pada halaman yang menggunakannya. |
| PWA install | Baseline precache 346 entry / 6.275 KiB, termasuk chunk admin, merchant, POS, screenshot, dan aset media. | `injectManifest` dipakai dengan pola precache shell yang eksplisit; chunk dan gambar masuk runtime cache setelah digunakan. |
| Runtime cache | Opsi `runtimeCaching` sebelumnya ditempatkan pada blok `workbox`, padahal strategi proyek adalah `injectManifest`, sehingga tidak mengendalikan hasil aktual. | Opsi Workbox yang tidak valid dihapus dari `injectManifest`; runtime caching ditangani langsung di `src/sw.ts` agar kompatibel dengan custom service worker. |
| Error jaringan | Query dapat dicoba sampai tiga kali total, memperpanjang loading pada jaringan buruk dan memperbanyak request saat service backend bermasalah. | Retry dibatasi satu kali; error HTTP 4xx dan kode database yang tidak layak diulang tetap tidak diretry. |
| Font | Google Fonts dimuat sebagai stylesheet render-blocking. | Pemuatan font dibuat non-blocking dengan pola `media="print"` dan fallback `noscript`. |
| Keamanan cache | Tidak semua gambar layak dicache; dokumen privat dan bukti pembayaran harus dihindari. | Runtime image cache dibatasi ke aset same-origin, branding, build assets, dan bucket Supabase public yang memang bersifat publik. |

## Validasi

Build produksi final berhasil dengan `pnpm build`. Workbox menghasilkan service worker `dist/sw.js` dengan precache **19 entry / 1.047,76 KiB**.

Lint berhasil dengan satu warning lama dari `FoodFilterSheet.tsx` terkait aturan Fast Refresh, tanpa error lint.

Test suite menjalankan 300 test: **278 lulus, 20 skip, dan 2 gagal**. Dua kegagalan berada pada `src/lib/chat/phase8Acceptance.test.ts` dan assertion SQL terkait keberadaan string `FULL JOIN`; kegagalan tidak menyentuh file atau perubahan performa yang diterapkan pada audit ini. Percobaan awal dengan flag `--runInBand` juga tidak valid untuk Vitest dan tidak dipakai sebagai hasil test.

## Catatan tindak lanjut

Pengukuran browser nyata tetap disarankan setelah deploy pada perangkat mobile kelas menengah, khususnya untuk mendapatkan metrik LCP, INP, CLS, dan waktu registrasi service worker dari jaringan 3G/4G. Aset terbesar seperti logo PNG sekitar 782 KB dan beberapa gambar lokal masih dapat dioptimalkan lagi ke WebP/AVIF pada pekerjaan berikutnya; optimasi tersebut sengaja tidak dilakukan dalam patch ini untuk menghindari perubahan visual dan kompatibilitas branding tanpa baseline screenshot.

## File yang diubah

- `index.html`
- `src/App.tsx`
- `src/components/SplashScreen.tsx`
- `src/sw.ts`
- `vite.config.ts`
- `docs/audit-performa-pwa-website-2026-09-25.md`

Perubahan masih berada di working tree repository dan belum dibuat commit atau pull request.

## Kesimpulan

Perbaikan utama sudah diimplementasikan dan build produksi kembali lulus. Jalur startup website dan PWA sekarang lebih cepat karena tidak menunggu splash artifisial, tidak memuat library animasi global untuk kebutuhan route transition, dan tidak menginstal seluruh aset aplikasi pada kunjungan pertama. Saat aplikasi dipakai kembali, chunk lazy dan media yang relevan tetap dipercepat melalui runtime cache service worker.
