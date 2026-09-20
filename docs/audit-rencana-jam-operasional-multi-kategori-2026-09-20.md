# Audit dan Rencana Perbaikan Jam Operasional & Multi-Kategori

## Ringkasan eksekutif

Aplikasi sudah memiliki tabel `merchant_operating_hours` dengan jadwal per hari dan komponen `MerchantOperatingHoursCard`, tetapi komponen tersebut belum dipasang pada halaman pengaturan merchant. Alur publik masih menghitung status toko dari kolom tunggal `merchants.open_time` dan `merchants.close_time`, sehingga perbedaan weekday/weekend belum terlihat oleh pelanggan. Kategori usaha masih disimpan pada satu kolom `merchants.business_category`, dan validasi database hanya mengizinkan satu slug kategori aktif.

## Temuan audit

| Area | Temuan | Dampak | Prioritas |
| --- | --- | --- | --- |
| Data jadwal | Tabel `merchant_operating_hours` sudah tersedia untuk 7 hari, tetapi tidak menjadi sumber data utama pada profil publik. | Jadwal weekday/weekend yang berbeda tidak konsisten dengan status buka dan tampilan pelanggan. | P0 |
| Admin merchant | Pengaturan masih menampilkan dua input waktu tunggal. Komponen jadwal harian yang sudah tersedia tidak dirender. | Admin tidak memiliki UX untuk mengatur jadwal harian secara langsung. | P0 |
| Kategori | `merchants.business_category` hanya menampung satu slug. | Satu toko tidak dapat ditemukan/ditampilkan di lebih dari satu kategori. | P0 |
| Integritas data | Belum ada relasi `merchant_categories` dan belum ada backfill dari kategori lama. | Migrasi multi-kategori berisiko kehilangan data kategori lama bila dilakukan tanpa kompatibilitas. | P0 |
| Frontend publik | Profil toko menampilkan satu kategori dan jam tunggal. | Informasi pelanggan tidak merepresentasikan konfigurasi terbaru. | P1 |
| Kompatibilitas | Banyak area lama masih membaca `open_time/close_time` dan `business_category`. | Migrasi big-bang akan berisiko memutus halaman lama. | P1 |

## Rencana perbaikan yang diterapkan

1. Menambahkan tabel `merchant_categories` dengan unique `(merchant_id, category_id)`, foreign key cascade, index, dan RLS. Data `business_category` lama di-backfill ke relasi baru.
2. Mempertahankan kolom legacy agar area lama tetap berjalan, sambil menjadikan relasi baru sebagai sumber data kategori pada pengaturan dan profil toko.
3. Memasang `MerchantOperatingHoursCard` pada halaman pengaturan merchant dengan UX per hari, penanda hari ini, status buka, dan validasi jam.
4. Mengubah utilitas status operasional agar dapat mengevaluasi jadwal berdasarkan hari dan zona waktu Asia/Jakarta, termasuk jadwal melewati tengah malam.
5. Memuat jadwal mingguan dan multi-kategori pada profil publik, menampilkan ringkasan jam mingguan dan badge kategori.
6. Menambahkan test unit untuk status jadwal dan validasi migrasi melalui build/typecheck yang tersedia.

## Kriteria penerimaan

- Admin dapat memilih minimal satu atau beberapa kategori aktif untuk satu toko.
- Kategori lama tetap tampil setelah migrasi karena otomatis dibackfill.
- Admin dapat mengatur jam berbeda untuk setiap hari serta menandai hari libur/tutup.
- Profil publik menampilkan status berdasarkan jadwal hari berjalan di WIB dan daftar kategori toko.
- Jadwal malam seperti 22:00–02:00 diperlakukan sebagai buka lintas tengah malam.
- Build dan test yang relevan berhasil tanpa mengubah alur lama di luar ruang lingkup.

## Catatan deployment

File migrasi perlu dijalankan pada database Supabase melalui pipeline migrasi yang digunakan proyek. Setelah deploy, verifikasi RLS dan lakukan smoke test sebagai merchant, admin, dan visitor anonim.

## Status

Implementasi dilakukan pada branch kerja ini; perubahan belum dipublish ke production.
