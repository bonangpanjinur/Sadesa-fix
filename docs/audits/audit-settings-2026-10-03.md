# Audit Halaman Pengaturan (`/settings`)

**Tanggal:** 3 Oktober 2026
**Cakupan:** route `/settings`, kontrol tema global, notifikasi push, perubahan/reset password, dan pilihan bahasa.

## Ringkasan audit

Route `/settings` terdaftar dan dilindungi oleh `ProtectedRoute`. Tidak ada route `/profile`; halaman akun/profil yang tersedia adalah `/account`, sehingga audit ini tidak menambahkan alias atau mengubah route profil.

### Temuan

1. **Mode gelap tidak berfungsi.** Halaman dan komponen toast memakai `useTheme()` dari `next-themes`, tetapi aplikasi belum memasang `ThemeProvider`. Akibatnya kontrol tema tidak memiliki provider yang dapat menyimpan/menerapkan pilihan. Status toggle juga perlu mengikuti tema hasil resolusi sistem, bukan hanya tema pilihan eksplisit.
2. **Status push dapat menyesatkan saat lookup gagal.** Kesalahan query subscription ditelan dan diterjemahkan menjadi `false`, sehingga UI terlihat seolah notifikasi nonaktif. Kegagalan saat menonaktifkan notifikasi juga tidak menampilkan pesan.
3. **Aturan password reset tidak konsisten.** Validasi lokal di halaman reset hanya mensyaratkan panjang, huruf, dan angka; ia tidak menggunakan kebijakan password bersama yang mensyaratkan huruf besar, huruf kecil, dan angka.
4. **Pilihan bahasa hanya melokalkan kartu bahasa.** Copy utama halaman pengaturan dan kontrol push tetap berbahasa Indonesia meskipun pengguna memilih English.
5. **Label kontrol.** Tombol kembali hanya berupa ikon; input password juga belum menyatakan autofill purpose `new-password`.

## Perbaikan yang diterapkan

- Memasang `ThemeProvider` global dengan class attribute dan dukungan tema sistem; toggle kini membaca `resolvedTheme`.
- Menghubungkan label kontrol mode gelap dan menambahkan label aksesibel pada tombol kembali.
- Menambahkan terjemahan ID/EN untuk halaman pengaturan dan state/pesan notifikasi push.
- Membedakan kegagalan lookup push dari status nonaktif, menyediakan aksi coba lagi, serta menampilkan error bila unsubscribe gagal. Error backend kini diteruskan agar dapat ditangani UI.
- Mengganti schema reset-password lokal dengan `resetPasswordSchema` bersama; petunjuk password diperbarui dan input diberi `autocomplete="new-password"`.
- Menambahkan regression tests untuk tema efektif, bahasa, validasi dan penyimpanan password, lookup push/retry, kegagalan unsubscribe, dan konsistensi kebijakan password.

## Validasi

| Pemeriksaan | Hasil |
| --- | --- |
| Suite Vitest penuh | Lulus: 111 file test; 434 lulus, 20 dilewati |
| ESLint (`pnpm lint`) | Lulus |
| Production build + PWA (`pnpm build`) | Lulus; service worker berhasil dibuat |
| TypeScript (`tsc --noEmit -p tsconfig.app.json`) | Masih gagal dengan 16 diagnostic baseline pada `GoogleAddressInput.tsx`, `GoogleRideMap.tsx`, dan `googleMaps.ts` (deklarasi global Google Maps). Tidak ada diagnostic pada file yang diubah dalam audit ini. |
| `git diff --check` | Lulus |
