# SOP Persiapan Onboarding Merchant Pilot SaDesa

**Versi:** 1.0  
**Tanggal:** 8 September 2026  
**Sasaran:** 10–20 merchant pilot pertama  
**Status:** Persiapan staging dan onboarding terkendali; belum merupakan rollout publik.

## 1. Tujuan

SOP ini memastikan setiap merchant pilot masuk dengan data, akses, perangkat, dan jalur support yang siap. Pilot bertujuan menguji operasi nyata secara terbatas, bukan memperluas penjualan secara massal.

Merchant pilot hanya boleh diundang setelah gate staging, keamanan, dan rollback pada bagian 3 dinyatakan lulus oleh owner terkait.

## 2. Scope pilot

Gunakan komposisi berikut sebagai target awal:

| Kelompok | Target | Fokus |
|---|---:|---|
| Barang retail | 4–6 merchant | listing, SKU/varian, stok outlet, fulfillment |
| Makanan/minuman | 4–6 merchant | modifier, waktu siapkan, pickup/delivery, QR meja bila siap |
| Jasa terjadwal | 2–4 merchant | slot, durasi, pembatalan, bukti selesai |
| Marketplace-only | minimal 2 merchant | memastikan marketplace tetap berjalan tanpa POS |

Jangan memasukkan merchant dari satu tipe usaha, satu perangkat, atau satu pola koneksi internet saja. Jasa panggilan, sewa, wisata, dan ojek tidak menjadi scope utama gelombang pertama kecuali kontrak booking dan settlement terkait sudah lulus staging.

## 3. Gate sebelum undangan

Product owner membuat keputusan **GO** hanya jika semua item berikut memiliki evidence.

| Gate | Pemeriksaan | Owner | Evidence |
|---|---|---|---|
| Staging | Bundle database Fase 2–5 terpasang dan rollback terdokumentasi | Engineering | deployment log dan rollback note |
| Security | API smoke test, RLS runtime test, dan environment check selesai | Security/Engineering | hasil test tanpa secret di client |
| Data | Seed merchant, produk, outlet, user, order, dan saldo uji tersedia | Engineering/Finance | seed manifest dan baseline report |
| POS | Offline queue, retry, conflict, printer, dan recovery diuji pada perangkat target | Engineering/Ops | device test log |
| Finance | Stok, kas, jurnal, fee snapshot, dan laporan dapat direkonsiliasi | Finance/Engineering | reconciliation snapshot |
| Support | SLA, escalation path, incident template, dan rollback owner ditetapkan | Operations | support runbook |

Jika satu gate kritis gagal, ubah keputusan menjadi **HOLD**. Jangan mengundang merchant eksternal untuk menutup kekurangan evidence.

## 4. Pembagian peran

| Peran | Tanggung jawab utama |
|---|---|
| Product owner | memilih merchant, mengunci scope, menyetujui GO/HOLD/STOP, dan menjaga perubahan scope |
| Engineering | staging, akses, seed data, monitoring, bug triage, recovery, dan rollback |
| Operations/support | menjadwalkan onboarding, mendampingi merchant, mencatat tiket, dan menjaga SLA |
| Finance/reconciliation | memvalidasi order, stok, kas, fee, refund, dan payout hold |
| Security/admin | memeriksa permission, tenant isolation, audit, dan tindakan sensitif |
| Merchant champion | menyediakan data usaha, perangkat, jadwal, dan feedback harian |

Satu orang boleh memegang lebih dari satu peran pada pilot kecil, tetapi keputusan refund besar, koreksi saldo, perubahan entitlement, dan payout tidak boleh disetujui oleh orang yang sama dengan pengaju.

## 5. Checklist persiapan per merchant

Operations mengumpulkan checklist berikut paling lambat satu hari sebelum onboarding:

- Nama usaha, nama pemilik, nomor kontak, kategori, dan lokasi.
- Persetujuan ikut pilot dan kontak utama untuk support.
- Mode pilot: marketplace-only atau POS.
- Daftar minimal tiga listing/produk/jasa, harga, foto, stok atau kapasitas, dan jam operasional.
- Metode fulfillment: pickup, delivery, pengiriman, atau jadwal layanan.
- Untuk POS: outlet, kasir, perangkat, printer bila digunakan, metode pembayaran, dan koneksi internet cadangan.
- Untuk QR meja: outlet, daftar meja, QR aktif, dan owner pencabutan QR.
- Batasan usaha yang perlu diketahui, misalnya produk musiman, stok terbatas, atau jadwal tertentu.
- Persetujuan bahwa data pilot dipakai untuk pengukuran operasional dan feedback.

Jangan meminta password merchant melalui chat. Gunakan alur login resmi dan catat hanya status akses, bukan credential.

## 6. Alur onboarding satu merchant

### Sebelum sesi

Operations mengirim jadwal, tujuan sesi, kontak support, dan checklist data. Engineering memastikan akun, tenant, outlet, dan role sudah dibuat sesuai scope. Finance mencatat baseline awal jika merchant menggunakan POS.

### Saat sesi

1. Verifikasi identitas merchant dan mode pilot.
2. Lengkapi profil dan jam operasional.
3. Terbitkan minimal tiga listing atau konfigurasi jasa.
4. Verifikasi harga, stok/kapasitas, fulfillment, dan tampilan publik.
5. Untuk POS, selesaikan setup outlet, user kasir, katalog, dan stok awal.
6. Simulasikan satu order marketplace atau booking.
7. Untuk POS, simulasikan satu transaksi kasir online dan satu transaksi offline bila perangkat mendukung.
8. Tunjukkan status sinkronisasi, cara melihat error, dan jalur meminta bantuan.
9. Tunjukkan cara membatalkan atau menonaktifkan QR tanpa menutup toko publik.
10. Catat milestone onboarding dan masalah yang ditemukan.

Onboarding dinyatakan **selesai sementara** hanya jika profil lengkap, listing pertama terbit, dan alur transaksi uji berhasil. Untuk merchant POS, setup POS dan transaksi POS pertama juga harus berhasil.

## 7. Masa observasi tujuh hari pertama

| Waktu | Aktivitas |
|---|---|
| Hari 0 | onboarding, baseline, transaksi uji, dan pengenalan support |
| Hari 1 | cek listing aktif, order pertama, sync status, dan error perangkat |
| Hari 2–3 | cek fulfillment, stok, kas, refund/dispute, dan queue conflict |
| Hari 4–5 | cek penggunaan berulang, transaksi offline, printer, dan SLA support |
| Hari 6–7 | review merchant, rekonsiliasi, feedback, dan keputusan lanjut/hold |

Operations mencatat setiap insiden dengan waktu, merchant, tenant/outlet, order ID atau request key, gejala, dampak, tindakan, dan hasil rekonsiliasi.

## 8. Metrik minimum yang dicatat

- Profil lengkap.
- Listing pertama terbit.
- Order pertama selesai.
- Fulfillment pertama selesai.
- Setup POS selesai, bila berlaku.
- Transaksi POS pertama selesai, bila berlaku.
- Sync success rate.
- Jumlah conflict/dead-letter.
- Selisih stok dan saldo.
- Waktu respons dan penyelesaian tiket.
- Refund/dispute yang berhasil diaudit.
- Aktivitas merchant pada hari ke-1, ke-3, dan ke-7.

Gunakan kontrak readiness di `src/lib/pilotReadiness.ts` untuk menentukan milestone merchant secara konsisten. Jangan menyamakan pembuatan akun atau pembuatan subscription dengan aktivasi.

## 9. Kriteria HOLD atau STOP

Set status **HOLD** pada merchant bila data usaha belum lengkap, perangkat belum didukung, staging evidence belum tersedia, atau support owner belum ditetapkan.

Hentikan sementara seluruh pilot bila terjadi kebocoran data antar-tenant, transaksi duplikat, stok atau saldo tidak dapat direkonsiliasi, refund tanpa audit, QR mengakses outlet yang salah, payout terlepas terlalu cepat, atau rollback tidak dapat dilakukan.

Selama ledger production dan rekonsiliasi belum lulus, jangan mengaktifkan fee provider, payout otomatis, atau menyebut laporan pajak/keuangan sebagai laporan resmi.

## 10. Penutupan dan keputusan gelombang berikutnya

Pada akhir hari ke-7, Product owner memimpin review dengan Engineering, Operations, Finance, dan Security. Pilihan keputusan hanya **GO terbatas**, **perpanjang pilot**, **HOLD**, atau **STOP/ROLLBACK**.

Keputusan GO terbatas memerlukan bukti bahwa tidak ada kebocoran tenant, transaksi duplikat, selisih material yang tidak dijelaskan, atau insiden tanpa owner. Kategori baru hanya boleh dibuka setelah kontrak order, fulfillment, dispute, settlement, dan support kategori tersebut tervalidasi.

## Referensi repository

- Kontrak readiness onboarding: `src/lib/pilotReadiness.ts`
- Ringkasan eksekutif pilot: `docs/ringkasan-eksekutif-pilot-merchant.md`
- Rencana bisnis dan status fase: `docs/rencana-bisnis-marketplace-pos-umkm.md`
- Static RLS audit: `scripts/audit-rls-static.py`
- API security smoke test: `scripts/security-api-smoke.sh`
