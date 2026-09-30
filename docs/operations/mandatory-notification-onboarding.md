# Mandatory Notification Onboarding Sadesa

## Tujuan

Setelah pengguna berhasil login, Sadesa menampilkan onboarding wajib untuk mengaktifkan push notification. Notifikasi digunakan untuk menyampaikan update pesanan dan informasi penting. Akses aplikasi ditahan sampai browser memiliki subscription push yang aktif, dengan pengecualian ketika browser tidak mendukung teknologi push dan pengguna perlu berpindah browser.

## Perilaku pengguna

| Kondisi | Perilaku aplikasi | Aksi pengguna |
| --- | --- | --- |
| Belum ada keputusan izin (`default`) | Menampilkan layar onboarding penuh; tidak meminta izin saat halaman dibuka | Menekan **Aktifkan Notifikasi**; hanya aksi ini yang memicu dialog browser |
| Izin `granted`, subscription belum tersimpan | Menampilkan onboarding dengan opsi aktivasi ulang | Menekan **Aktifkan Notifikasi** untuk memakai subscription yang sudah ada atau membuat subscription baru |
| Izin `granted`, subscription aktif | Aplikasi dibuka normal | Tidak ada aksi tambahan |
| Izin `denied`/Block | Menampilkan petunjuk pengaturan browser dan tidak memanggil `requestPermission()` | Mengubah izin situs menjadi **Allow**, kemudian menekan **Cek ulang izin** |
| Browser tidak mendukung Notification API, Service Worker, atau Push API | Menampilkan pesan bahwa push tidak tersedia | Menggunakan browser modern yang mendukung push notification |
| Aktivasi gagal karena jaringan/backend | Tetap menahan akses dan menampilkan pesan gagal | Mencoba aktivasi kembali |

## Batasan keamanan dan platform

Aplikasi **tidak** meminta izin secara otomatis pada saat landing page atau saat komponen pertama kali dirender. Pemanggilan `Notification.requestPermission()` hanya terjadi di rantai aksi tombol **Aktifkan Notifikasi**. Aplikasi juga tidak dapat mengubah izin `denied` menjadi `granted`, mengaktifkan notifikasi tanpa persetujuan pengguna, atau mengirim push ketika permission belum `granted`.

Saat browser sudah mengembalikan `denied`, helper push langsung berhenti dan tidak memanggil dialog izin lagi. Pengguna diarahkan secara tekstual ke pengaturan situs browser: **Site Settings → Notifications → Sadesa → Allow**. Setelah kembali ke aplikasi, tombol **Cek ulang izin** membaca ulang permission dan subscription.

## Implementasi

Komponen `src/components/notifications/NotificationOnboardingGate.tsx` ditempatkan di dalam `AuthProvider` dan `PWAProvider`, sebelum router dan halaman aplikasi. Dengan posisi ini, pengguna anonim tetap dapat membuka halaman publik/login, sedangkan pengguna terautentikasi tidak dapat menggunakan konten aplikasi sebelum onboarding selesai.

Helper `src/lib/pushNotification.ts` memakai service worker yang sudah ada, mempertahankan subscription browser yang sudah tersedia, dan menyimpan endpoint beserta kunci `p256dh`/`auth` ke tabel `push_subscriptions`. Subscription diverifikasi menggunakan `user_id`, endpoint, dan status permission.

## Alur teknis

1. `AuthProvider` menyelesaikan pemuatan session.
2. Gate memeriksa dukungan push dan membaca `Notification.permission` tanpa meminta izin.
3. Untuk permission `default`, gate menunggu klik eksplisit pengguna.
4. Klik tombol memanggil `subscribeToPush(user.id)`.
5. Helper meminta izin hanya bila status masih `default`; bila `denied`, helper mengembalikan gagal tanpa prompt.
6. Setelah permission `granted`, helper mengambil subscription yang sudah ada atau membuat subscription melalui `PushManager`.
7. Subscription disimpan melalui upsert ke `push_subscriptions`.
8. Gate membuka aplikasi hanya setelah subscription terverifikasi tersimpan.

## Acceptance criteria

- Pengguna yang belum login tidak melihat onboarding wajib.
- Pengguna login dengan permission `default` melihat teks “Aktifkan notifikasi untuk menerima update pesanan”.
- Tidak ada `Notification.requestPermission()` yang berjalan dari `useEffect`, landing page, atau render awal.
- Tombol **Aktifkan Notifikasi** memicu permission prompt browser.
- Permission `denied` tidak memicu prompt kedua dan menampilkan instruksi pengaturan browser.
- Permission `granted` dengan subscription aktif tidak melihat gate.
- Gagal menyimpan subscription tidak membuka akses aplikasi secara diam-diam.
- Service worker tetap menangani event `push` dan klik notifikasi yang sudah ada.

## Verifikasi manual

Gunakan browser dengan DevTools untuk menguji tiga kondisi permission: `default`, `granted`, dan `denied`. Setelah login, pastikan gate muncul untuk `default`; klik tombol dan konfirmasikan bahwa dialog browser hanya muncul setelah klik. Untuk `denied`, ubah izin melalui pengaturan situs, kembali ke tab aplikasi, lalu pilih **Cek ulang izin**.

Jalankan pemeriksaan otomatis dari root repository:

```bash
npm run lint
npm run test -- --run
npm run build
```

Jika proyek dijalankan menggunakan Bun, perintah ekuivalennya adalah `bun run lint`, `bun run test -- --run`, dan `bun run build`.
