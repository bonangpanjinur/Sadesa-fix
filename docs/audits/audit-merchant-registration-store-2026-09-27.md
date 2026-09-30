# Audit Sisi Pedagang, Pendaftaran, dan Toko

**Tanggal:** 27 September 2026  
**Scope:** pendaftaran merchant, guard akses, dashboard, pengaturan toko, profil toko publik, dan Toko Admin.

## Ringkasan

Audit menemukan dua risiko akses/alur yang langsung diperbaiki serta beberapa risiko integritas data dan performa yang perlu ditangani pada fase berikutnya.

## Perbaikan pada commit ini

| Area | Temuan | Perbaikan |
|---|---|---|
| Guard subhalaman merchant | `useMerchantGuard` hanya memeriksa `registration_status = APPROVED`; merchant yang sudah dinonaktifkan masih dapat melewati guard. | Guard kini juga mensyaratkan `status = ACTIVE`. |
| Pendaftaran merchant | Pengguna dapat mencoba membuat pendaftaran kedua ketika sudah memiliki pendaftaran `PENDING` atau `APPROVED`. | Ditambahkan pemeriksaan pendaftaran aktif sebelum insert dan redirect ke dashboard. |
| Toko Admin | Input jumlah tidak benar-benar membatasi nilai ke stok dan halaman tidak memberi state loading/error yang jelas. | Jumlah di-clamp ke stok, tombol mencegah pembelian ganda, RPC tetap menjadi validasi terakhir, dan ditambahkan state loading/error/retry. |
| Validasi | Perubahan diuji melalui lint dan production build. | Lint file terkait lulus; build production lulus. |

## Perbaikan lanjutan: transaksi database atomik

Temuan P1 terkait proses multi-write sudah diselesaikan. Migration `20260927150000_atomic_merchant_registration_and_settings.sql` menambahkan dua RPC `SECURITY DEFINER` dengan ownership check, validasi kategori aktif, dan satu transaction boundary per operasi:

- `register_merchant_atomic`: membuat merchant, kategori, dan tujuh jadwal operasional secara atomik.
- `update_merchant_settings_atomic`: memperbarui data toko serta mengganti kategori toko secara atomik.

Form pendaftaran dan pengaturan toko sekarang hanya melakukan satu pemanggilan RPC. Jika validasi atau salah satu write gagal, seluruh perubahan pada operasi tersebut di-rollback oleh PostgreSQL.

## Temuan prioritas yang masih perlu ditangani

### ~~P1 — Pendaftaran dan pengaturan toko tidak atomik~~ **Selesai**

Temuan ini sudah dipindahkan ke RPC transaction seperti dijelaskan di atas.

`MerchantSettingsPage` tidak lagi melakukan update merchant, delete kategori, dan insert kategori secara terpisah dari browser.

### P1 — Auto-approval database tidak selaras dengan UI pending

Bootstrap `10_20260922191500_auto_approve_merchants.sql` mengubah insert merchant menjadi `APPROVED/ACTIVE`, sedangkan UI dan komentar pendaftaran masih menggambarkan alur review `PENDING`.

**Dampak:** layar pending/rejected masih ada untuk kompatibilitas, tetapi jalur pendaftaran normal tidak akan menggunakannya selama trigger auto-approval aktif.

**Rekomendasi:** tetapkan satu kebijakan bisnis: manual review atau auto-approval. Setelah dipilih, hapus state dan copy yang tidak digunakan agar tidak membingungkan pengguna.

### P2 — Profil publik merchant mengambil `select('*')`

`MerchantProfilePage` mengambil seluruh kolom merchant. Walaupun RLS membatasi baris merchant aktif, query wildcard tetap memperbesar risiko tereksposnya kolom internal/sensitif jika policy berubah.

**Rekomendasi:** gunakan daftar kolom publik eksplisit atau view `public_merchants` untuk halaman publik. Jangan mengambil data rekening, saldo, kode verifikator, atau kolom kontrol.

### P2 — Dashboard mengambil hingga 500 order tanpa rentang waktu

`MerchantDashboardPage` mengambil 500 order terbaru dan baru merangkum 14 hari di client. Ini membebani payload dan parsing saat data merchant tumbuh.

**Rekomendasi:** filter sejak query berdasarkan tanggal 14/30 hari, select hanya kolom yang diperlukan, dan gunakan agregasi server-side untuk grafik.

### P2 — Perubahan pengaturan merchant belum memanfaatkan satu sumber validasi

Schema client sudah memvalidasi sebagian besar input, tetapi update juga bergantung pada trigger/check constraint database. Pesan error sudah ditangani, namun proses multi-write tetap dapat menghasilkan keadaan parsial.

**Rekomendasi:** satukan schema bisnis dan mutation transaction di RPC; tambahkan test untuk kategori kosong, jam operasional invalid, slug duplikat, dan upload gagal.

## Area yang diaudit dan status

- Pendaftaran merchant: **diperiksa**, duplikasi aktif diperbaiki.
- Guard akses merchant: **diperiksa**, status `ACTIVE` diperbaiki.
- Dashboard merchant: **diperiksa**, temuan query 500 order dicatat.
- Pengaturan toko: **diperiksa**, temuan multi-write non-atomik dicatat.
- Profil toko publik: **diperiksa**, wildcard select dicatat.
- Toko Admin merchant: **diperiksa dan diperbaiki**, validasi jumlah/loading/error.
- RLS dasar merchant/category/order: **ditinjau dari bootstrap**, ownership policy tersedia; transaction boundary masih menjadi gap utama.
