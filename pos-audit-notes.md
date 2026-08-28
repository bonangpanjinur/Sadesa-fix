
## Temuan audit 28 Agustus 2026

- Sidebar POS memiliki sekitar 39 menu, sedangkan route `/pos/harga` dan `/pos/setup` tidak ditampilkan di sidebar. Semua route POS terdaftar di App.tsx kecuali perbedaan akses tersebut; route `/pos/harga` terlihat tidak dibungkus ProtectedRoute, sedangkan route POS lain umumnya terlindungi.
- Sidebar tidak terlihat memfilter menu berdasarkan role/permission; halaman POSAkses mengelola role, tetapi POSSidebar merender menu statis. Ini berisiko memberi akses UI berlebihan kepada kasir, walaupun RLS mungkin tetap membatasi data.
- `POSLayout` memakai container global `min-h-screen`, child `h-screen`, dan area `overflow-y-auto`; pola ini perlu diuji di viewport kecil karena dapat menyebabkan nested scroll dan header sticky yang tidak konsisten.
- `POSMenuQRPage` mencetak QR melalui `window.open`, `document.write`, CDN QRCode eksternal, lalu `window.print`; ini menyebabkan popup/preview browser, ketergantungan jaringan CDN, dan raw HTML tanpa escaping untuk nama tenant/meja.
- Screenshot pengguna menunjukkan Chrome toolbar tetap terlihat, modal QR sangat besar pada viewport, area latar gelap, dan action/isi berpotensi terpotong atau tidak nyaman pada layar rendah. Ini perlu diperbaiki dengan modal responsive max-height, scroll body, footer sticky, dan print pipeline non-popup.
- `POSMejaPage` dan `POSKDSPage` memiliki perubahan status langsung dari UI; perlu verifikasi server-side state transition, optimistic rollback, dan race condition.
- Query POS tersebar di banyak halaman, dengan sebagian halaman tenant-level dan sebagian outlet-level; perlu matriks scope data agar tidak ada laporan atau mutasi yang lupa filter outlet.
- `POSKasirPage` masih memiliki kompleksitas tinggi; promo, voucher, loyalty, split payment, offline sale, QR Pay, dan printer berjalan dalam satu komponen besar sehingga rawan regresi dan sulit diuji end-to-end.
- `POSKasirPage` memiliki mutasi array item secara langsung pada fungsi update quantity/discount (`newCart[idx].qty = ...`, `newCart[idx].discount = ...`), yang dapat menyebabkan state React sulit dilacak dan stale update pada interaksi cepat.
- `POSPengaturanPage` tidak memiliki loading state umum untuk tenant/settings dan masih memiliki UX printer yang perlu diseragamkan dengan Print Bridge.
- Laporan baseline: `pnpm build` berhasil; `pnpm lint` berhasil dengan 3 warning Fast Refresh lama di luar modul POS; `pnpm test` gagal pada 3 suite karena environment test tidak memiliki `VITE_SUPABASE_URL`/konfigurasi runtime publik, bukan karena assertion POS.
- Live URL `https://www.sadesa.id/pos/menu-qr` mengalihkan ke `https://www.sadesa.id/?redirect=%2Fpos%2Fmenu-qr`, sehingga audit live tidak dapat melewati autentikasi pada sesi sandbox. Analisis fitur dilakukan melalui repository dan screenshot pengguna.
