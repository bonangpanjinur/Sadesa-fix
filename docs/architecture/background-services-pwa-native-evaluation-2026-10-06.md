# Evaluasi Background Services SaDesa — PWA dan Native

Tanggal: 6 Oktober 2026

## Ringkasan

SaDesa saat ini adalah aplikasi React/Vite berbasis PWA. Service worker dapat menangani Web Push dan menampilkan notifikasi sistem ketika halaman tidak terbuka; ia **bukan** proses aplikasi yang berjalan terus-menerus. Untuk membagikan lokasi kurir terus-menerus saat layar mati atau aplikasi ditutup, SaDesa perlu target native Android/iOS beserta izin, mode lokasi, dan notifikasi persisten yang sesuai. Pembungkus Capacitor dapat mempertahankan sebagian besar UI React, tetapi lokasi background membutuhkan plugin/implementasi native khusus.

## Kondisi kode yang diaudit

- `src/sw.ts` menangani `push` dan `notificationclick`; ini jalur notifikasi saat halaman PWA tidak aktif.
- `src/components/CourierLocationUpdater.tsx` memakai `navigator.geolocation.watchPosition()`, sehingga pelacakan saat ini terikat pada halaman yang berjalan dan tidak dapat dijadikan jaminan setelah proses browser dihentikan.
- Belum ditemukan proyek/platform Android atau iOS maupun konfigurasi Capacitor.
- Web Push pesanan sudah memiliki antrean server dan worker terjadwal. Push chat kini ditambahkan melalui migrasi `20261006170000_chat_message_web_push.sql`.

## PWA vs native

| Kebutuhan | PWA/browser | Aplikasi native |
|---|---|---|
| Notifikasi pesanan/chat saat UI ditutup | Ya, lewat Web Push + service worker; perlu subscription aktif, izin OS/browser, VAPID, trigger/queue dan worker server | Ya, memakai FCM/APNs; jalur push native berbeda dari tabel subscription Web Push |
| Audio alarm terus berjalan setelah ditutup | Tidak dapat dijamin; OS yang mengatur suara/vibrasi notifikasi | Tetap bukan always-on; gunakan notifikasi lokal/foreground service yang berizin, bukan loop audio tersembunyi |
| Lokasi kurir kontinu ketika app di-background/screen-lock | Tidak andal; Geolocation API dan JS halaman tidak memiliki lifecycle service native | Bisa untuk sesi kerja aktif menggunakan layanan lokasi native dan izin eksplisit, tetap dapat dibatasi OS/vendor |
| Tugas periodik ringan | Background Sync/Periodic Sync hanya best-effort dan tidak universal | Background Runner dapat menjalankan burst terjadwal, bukan daemon permanen |

## Rekomendasi teknis

1. **Pertahankan PWA sebagai jalur universal** untuk marketplace dan notifikasi Web Push.
2. **Bangun pilot aplikasi kurir native dengan Capacitor** terlebih dahulu, bukan mengubah seluruh aplikasi. Tambahkan platform Android/iOS dan abstraksi `CourierLocationProvider` agar implementasi `watchPosition` web tetap dipakai di PWA sementara target native memakai plugin geolokasi background.
3. Evaluasi plugin background-geolocation yang benar-benar menyediakan native watcher dan kompatibel dengan versi Capacitor yang dipilih. Jangan mengandalkan `@capacitor/geolocation` standar sebagai solusi lintas platform untuk tracking background; dokumentasi Capacitor menyatakan plugin itu tidak mendukungnya secara langsung.
4. Untuk Android, lokasi aktif di background memerlukan desain foreground service tipe `location` dengan notifikasi persisten, izin lokasi runtime dan kebijakan Google Play yang sesuai. Uji battery optimization pada vendor perangkat yang digunakan kurir.
5. Untuk iOS, aktifkan Background Modes > Location updates, jelaskan penggunaan lokasi sebelum meminta izin yang diperlukan, dan implementasikan lifecycle Core Location agar tracking dapat dipulihkan setelah sistem menghentikan aplikasi. Tampilkan indikator yang sesuai.
6. Upload lokasi lewat antrean lokal yang tahan offline, dengan timestamp/akurasi dan kebijakan retensi; gunakan autentikasi yang sudah ada dan RLS server. Hentikan tracking segera saat kurir offline/selesai tugas; jangan mengumpulkan lokasi di luar sesi kerja.
7. Rencanakan push native (FCM/APNs) sebagai integrasi terpisah dari Web Push, termasuk tabel subscription/token, rotasi token, logout/revoke, dan pengujian end-to-end.

## Batasan yang harus disampaikan ke produk

“Berjalan di belakang” tidak berarti proses yang dijamin hidup selamanya. Bahkan aplikasi native diberi waktu eksekusi terbatas; Android foreground service membutuhkan notifikasi yang terlihat, sedangkan iOS mengatur dan dapat menangguhkan proses jika persyaratan/lifecycle tidak terpenuhi. `@capacitor/background-runner` cocok untuk pekerjaan berkala singkat dan sinkronisasi opportunistic—dokumentasinya secara eksplisit menyatakan bukan layanan permanen yang selalu hidup.

## Tahapan implementasi yang disarankan

- **Tahap 1 (selesai di repositori):** antrean Web Push pesanan/chat dan dokumentasi operasi; uji push dengan PWA yang ditutup pada staging.
- **Tahap 2:** keputusan produk tentang interval pembaruan lokasi, akurasi, batas baterai/data, opt-in, retensi, dan perangkat minimum; prototipe Android kurir.
- **Tahap 3:** native location provider, foreground service Android, Core Location iOS, antrean offline, telemetry, serta alur pause/stop yang eksplisit.
- **Tahap 4:** rilis internal/testflight, uji app background/force-stop, screen-lock, no-network, battery saver/OEM restrictions, restart perangkat, izin dicabut, dan validasi kebijakan toko aplikasi sebelum rollout.

## Referensi

- [MDN: Background Synchronization API](https://developer.mozilla.org/en-US/docs/Web/API/Background_Synchronization_API) — event best-effort melalui service worker; ketersediaannya terbatas.
- [Capacitor: Background Runner](https://capacitorjs.com/docs/apis/background-runner) — tugas burst; iOS/Android menjadwalkan dan membatasi waktu eksekusi, bukan proses always-on.
- [Capacitor: Geolocation](https://capacitorjs.com/docs/apis/geolocation) — API standar; tidak menyediakan tracking background secara langsung.
- [Android Developers: Request location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions) — foreground service tipe `location`, izin background, dan perhatian kebijakan Google Play.
- [Apple Developer: Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background) — background mode/lifecycle Core Location dan izin pengguna.
- [Capacitor Community Background Geolocation](https://github.com/capacitor-community/background-geolocation) — kandidat plugin yang perlu diverifikasi terhadap versi Capacitor, status pemeliharaan, perilaku platform, dan kebutuhan HTTP native sebelum dipilih.
