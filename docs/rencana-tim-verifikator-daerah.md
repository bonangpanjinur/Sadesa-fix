# Rencana Tim Verifikator Daerah

## Ringkasan keputusan

Untuk satu wilayah daerah dengan empat orang, struktur yang paling seimbang adalah **satu Koordinator Verifikator Daerah dan tiga Admin Verifikasi**. Koordinator memegang kendali wilayah, keputusan akhir untuk kasus berisiko, distribusi pekerjaan, dan laporan kepada admin pusat. Tiga admin verifikasi menangani pemeriksaan merchant, ojek atau courier, serta kontrol kualitas dan monitoring.

Model ini tidak menjadikan satu orang sebagai pemeriksa sekaligus penyetuju semua kasus. Pemeriksaan dilakukan oleh admin yang bertugas, sedangkan keputusan akhir mengikuti tingkat risiko. Pemisahan tersebut mengurangi kesalahan, konflik kepentingan, dan perubahan data tanpa jejak audit.

> **Rekomendasi utama:** gunakan satu wilayah kerja bersama, satu antrean kasus, pembagian tugas berdasarkan spesialisasi, dan kewenangan persetujuan berjenjang.

## 1. Struktur organisasi

```text
Admin Pusat / Pemilik Sistem
            │
            ▼
Koordinator Verifikator Daerah
            │
   ┌────────┼────────┐
   ▼        ▼        ▼
Admin      Admin     Admin
Merchant   Ojek      Quality Control
```

Struktur ini berlaku untuk satu daerah yang memiliki satu atau beberapa kode verifikator. Kode referral sebaiknya tetap dikaitkan dengan wilayah dan tim, bukan hanya dengan satu akun personal. Pemilik kode dapat dicatat sebagai koordinator, sementara seluruh anggota yang diberi kewenangan dapat memproses kasus dalam scope wilayah yang sama.

## 2. Komposisi dan tanggung jawab

### 2.1 Koordinator Verifikator Daerah

Koordinator adalah pemimpin operasional tim. Ia tidak harus mengerjakan pemeriksaan rutin terbanyak, tetapi bertanggung jawab memastikan seluruh proses berjalan sesuai standar.

Tanggung jawabnya meliputi penetapan prioritas, pembagian antrean, keputusan akhir untuk kasus berisiko, penanganan eskalasi, persetujuan perubahan yang sensitif, dan pengiriman laporan berkala kepada admin pusat. Koordinator juga bertanggung jawab atas rekonsiliasi jumlah kasus, kualitas keputusan, dan kepatuhan terhadap batas wilayah.

Koordinator dapat menyetujui kasus normal setelah pemeriksaan admin selesai. Untuk kasus yang memiliki indikasi duplikasi, dokumen meragukan, konflik kepemilikan, atau potensi fraud, koordinator wajib meminta pemeriksaan kedua atau eskalasi ke admin pusat.

### 2.2 Admin Verifikasi Merchant

Admin ini menjadi pemeriksa utama untuk pendaftaran dan perubahan data pedagang. Ia memeriksa identitas pemilik, nama usaha, lokasi, kategori usaha, dokumen pendukung, serta kelengkapan profil.

Admin Merchant tidak mengubah data sensitif secara langsung tanpa permintaan resmi. Jika data perlu diperbaiki, ia mengembalikan kasus kepada merchant dengan alasan yang jelas. Ia juga memastikan merchant terhubung dengan kode verifikator dan kelompok dagang yang benar.

### 2.3 Admin Verifikasi Ojek atau Courier

Admin ini bertanggung jawab atas registrasi dan status operasional ojek atau courier. Pemeriksaan mencakup identitas, usia minimum, dokumen kendaraan, foto, nomor kendaraan, wilayah kerja, serta rekening payout jika diperlukan.

Admin Ojek dapat melakukan pemeriksaan lapangan atau meminta bukti tambahan. Ia tidak boleh menyetujui dokumen miliknya sendiri atau dokumen pengguna yang memiliki hubungan langsung dengannya. Kasus dengan lokasi di luar wilayah tim harus dikembalikan atau dialihkan, bukan diproses secara manual.

### 2.4 Admin Quality Control dan Monitoring

Admin ini berfungsi sebagai penjaga kualitas. Ia mengambil sampel keputusan yang sudah disetujui, memeriksa konsistensi alasan penolakan, memantau kasus yang melewati SLA, dan mencocokkan data antara pendaftaran, kode referral, status approval, serta pendapatan.

Admin QC juga menyiapkan laporan harian dan mingguan. Jika ditemukan pola yang tidak wajar, seperti terlalu banyak approval dari satu perangkat, dokumen berulang, atau perubahan data setelah approval, kasus tersebut ditandai untuk pemeriksaan koordinator dan admin pusat.

## 3. Pembagian kewenangan

| Aktivitas | Koordinator | Admin Merchant | Admin Ojek | Admin QC |
|---|---|---|---|---|
| Melihat antrean wilayah | Penuh | Penuh untuk merchant | Penuh untuk ojek | Penuh untuk monitoring |
| Memeriksa dokumen merchant | Dapat mengambil alih | Utama | Tidak menjadi tugas utama | Sampling |
| Memeriksa dokumen ojek | Dapat mengambil alih | Tidak menjadi tugas utama | Utama | Sampling |
| Meminta perbaikan data | Ya | Ya untuk merchant | Ya untuk ojek | Ya melalui temuan QC |
| Menyetujui kasus normal | Ya | Menyiapkan rekomendasi | Menyiapkan rekomendasi | Tidak sebagai pemilik kasus |
| Menolak kasus normal | Ya | Dengan alasan terstruktur | Dengan alasan terstruktur | Mengusulkan koreksi |
| Menyetujui kasus risiko tinggi | Bersama admin pusat | Tidak | Tidak | Memberikan temuan |
| Mengubah role atau scope anggota | Mengusulkan | Tidak | Tidak | Tidak |
| Melihat laporan fee | Penuh | Terbatas pada kebutuhan tugas | Terbatas pada kebutuhan tugas | Penuh untuk rekonsiliasi |
| Mengakses rekening payout | Terbatas | Tidak | Hanya bila diperlukan | Read-only dan termasking |
| Mengelola anggota tim | Mengusulkan | Tidak | Tidak | Tidak |

**Catatan penting:** role “Admin QC” sebaiknya tidak memiliki kewenangan mengubah hasil pemeriksaan yang sedang diaudit. Bila koreksi diperlukan, koreksi dilakukan oleh koordinator atau admin pusat dengan alasan dan audit log.

## 4. Model status kasus

Agar pekerjaan dapat dilacak, setiap pengajuan sebaiknya mengikuti status berikut:

| Status | Arti | Penanggung jawab berikutnya |
|---|---|---|
| `PENDING` | Pengajuan baru masuk dan belum diperiksa | Admin sesuai jenis kasus |
| `IN_REVIEW` | Sedang diperiksa | Admin pemilik kasus |
| `NEED_REVISION` | Data atau dokumen perlu diperbaiki | Merchant atau courier |
| `READY_FOR_APPROVAL` | Pemeriksaan selesai dan menunggu keputusan | Koordinator |
| `APPROVED` | Pengajuan diterima | Sistem dan tim onboarding |
| `REJECTED` | Pengajuan ditolak dengan alasan | Pemohon dapat mengajukan ulang |
| `ESCALATED` | Kasus memiliki risiko atau berada di luar kewenangan | Koordinator atau admin pusat |
| `CLOSED` | Kasus selesai dan tidak ada tindakan lanjutan | Admin QC untuk arsip |

Alasan `REJECTED`, `NEED_REVISION`, dan `ESCALATED` harus menggunakan kategori terstruktur serta catatan bebas. Catatan bebas tetap diperlukan agar pemohon memahami tindakan yang harus dilakukan.

## 5. Alur kerja harian

### Pagi: pembukaan antrean

Koordinator melihat jumlah kasus baru, kasus yang melewati SLA, serta kasus eskalasi. Ia membagi antrean berdasarkan spesialisasi dan beban kerja. Admin QC mencatat jumlah awal agar perubahan sepanjang hari dapat direkonsiliasi.

### Siang: pemeriksaan dan keputusan

Admin Merchant dan Admin Ojek memproses kasus sesuai urutan prioritas. Kasus dengan dokumen lengkap diproses terlebih dahulu, sedangkan kasus berisiko diberi label dan tidak dipaksa selesai hanya untuk mengejar jumlah.

Setiap pemeriksaan harus menghasilkan salah satu dari tiga keluaran: disetujui untuk keputusan, dikembalikan untuk perbaikan, atau dieskalasikan. Tidak boleh ada kasus yang dibiarkan tanpa status dan catatan.

### Sore: kontrol kualitas

Admin QC mengambil sampel keputusan hari itu. Sampel dapat ditetapkan minimal 10% untuk kasus normal dan 100% untuk kategori risiko tinggi. Temuan QC dikirim kepada koordinator pada hari yang sama.

### Akhir hari: penutupan

Koordinator meninjau daftar kasus yang belum selesai, kasus yang membutuhkan bantuan pemohon, serta kasus yang harus diteruskan kepada admin pusat. Laporan harian mencatat volume masuk, volume selesai, status akhir, alasan penolakan, dan jumlah eskalasi.

## 6. SLA yang disarankan

| Jenis kasus | Target tanggapan awal | Target keputusan |
|---|---:|---:|
| Merchant dengan dokumen lengkap | 4 jam kerja | 1 hari kerja |
| Courier dengan dokumen lengkap | 4 jam kerja | 1 hari kerja |
| Perbaikan dokumen | 1 hari kerja setelah dikirim ulang | 1 hari kerja |
| Kasus risiko tinggi | 4 jam kerja | Maksimal 2 hari kerja atau sesuai admin pusat |
| Eskalasi wilayah atau identitas | 1 hari kerja | Sesuai hasil pemeriksaan bersama |

SLA harus dihitung pada jam operasional tim. Sistem perlu membedakan waktu tunggu internal dari waktu tunggu pemohon agar keterlambatan tidak salah dibebankan kepada admin.

## 7. Aturan pemisahan tugas dan keamanan

Pertama, seorang admin tidak boleh menyetujui pengajuan miliknya sendiri atau pengajuan yang dia buatkan. Kedua, perubahan pada status approval, pemilik kode, rekening payout, dan role anggota harus menghasilkan audit log. Ketiga, anggota hanya dapat melihat data dalam wilayah dan tim yang ditugaskan kepadanya.

Koordinator tidak boleh menggunakan satu akun bersama untuk seluruh tim. Setiap orang harus memiliki akun sendiri agar tindakan, waktu, dan perangkat dapat ditelusuri. Bila seorang anggota berhenti bertugas, aksesnya dinonaktifkan; akun tidak dihapus dari histori audit.

Data rekening dan dokumen identitas harus ditampilkan secara minimum sesuai kebutuhan tugas. Admin QC cukup melihat data termasking apabila pemeriksaan penuh tidak diperlukan. Dokumen private harus tetap dilayani melalui akses sementara, bukan URL publik.

## 8. KPI tim

Kinerja tim sebaiknya dinilai dari kualitas dan ketepatan waktu, bukan hanya jumlah approval. KPI minimum yang disarankan adalah sebagai berikut:

| KPI | Definisi |
|---|---|
| Penyelesaian SLA | Persentase kasus selesai dalam batas waktu |
| Akurasi keputusan | Persentase keputusan yang lolos sampling QC tanpa koreksi |
| Rasio pengembalian | Persentase kasus yang dikembalikan karena alasan yang sah dan jelas |
| Rasio eskalasi | Persentase kasus yang perlu admin pusat |
| Waktu siklus | Waktu dari `PENDING` sampai keputusan final |
| Kelengkapan audit | Persentase perubahan sensitif yang memiliki catatan |
| Keadilan beban kerja | Perbandingan jumlah kasus antar anggota |

Target awal dapat ditetapkan secara konservatif. Setelah satu bulan data terkumpul, koordinator dan admin pusat dapat memperbarui target berdasarkan volume nyata dan tingkat kesulitan wilayah.

## 9. Rencana perubahan sistem

Model saat ini menghubungkan kode referral dengan pemilik verifikator. Untuk mendukung tim, struktur data perlu menambahkan lapisan tim tanpa menghapus kolom lama agar kompatibel dengan data yang sudah ada.

### Tahap 1: struktur organisasi

Tambahkan tabel `verifikator_teams` dengan kolom `id`, `name`, `region_id` atau `village_id`, `lead_verifikator_id`, `is_active`, dan timestamp. Tambahkan tabel `verifikator_team_members` dengan kolom `team_id`, `user_id`, `role`, `is_active`, `joined_at`, dan `ended_at`.

Role anggota sebaiknya menggunakan nilai terkontrol seperti `LEAD`, `MERCHANT_REVIEWER`, `COURIER_REVIEWER`, dan `QUALITY_CONTROL`. Nilai role tersebut berbeda dari role aplikasi utama. Role aplikasi tetap dapat berupa `verifikator`, sedangkan role tim menentukan kewenangan operasional.

### Tahap 2: scope kode dan wilayah

Tambahkan `team_id` pada `verifikator_codes`. Kode lama tetap menyimpan `verifikator_id` sebagai pemilik atau koordinator. Saat kode digunakan, sistem mengisi `team_id` dan `verifikator_id` pada merchant atau courier sesuai aturan yang berlaku.

Tambahkan tabel atau relasi scope wilayah jika satu tim mengelola lebih dari satu desa. Scope sebaiknya memiliki `team_id`, `village_id`, `is_active`, dan timestamp. Policy database kemudian memeriksa keanggotaan aktif serta scope wilayah, bukan hanya role global `verifikator`.

### Tahap 3: antrean dan assignment

Tambahkan kolom `assigned_to`, `assigned_at`, `reviewed_by`, `reviewed_at`, `decision_reason`, dan `risk_level` pada entitas pengajuan atau buat tabel `verification_cases`. Tabel terpisah lebih fleksibel karena dapat menyatukan merchant dan courier tanpa menambah banyak kolom pada tabel domain.

Assignment harus dicatat sebagai event. Perpindahan kasus dari satu anggota ke anggota lain perlu menyimpan siapa yang memindahkan, kapan, alasan, dan anggota tujuan. Koordinator boleh mengambil alih kasus; Admin QC hanya boleh memberi temuan kecuali diberi kewenangan eksplisit.

### Tahap 4: dashboard tim

Dashboard tim perlu memiliki empat tampilan utama. Tampilan pertama adalah antrean pribadi. Tampilan kedua adalah antrean seluruh tim. Tampilan ketiga adalah panel QC dan SLA. Tampilan keempat adalah laporan fee dan pendapatan yang dapat difilter berdasarkan tim, wilayah, anggota, sumber, status, dan rentang tanggal.

Pada dashboard fee, data komisi dapat dikelompokkan berdasarkan `team_id` dan anggota pemeriksa. Pengelompokan tersebut harus dibedakan dari pemilik ekonomi atau pemilik kode agar laporan tidak salah mengartikan “siapa yang memeriksa” sebagai “siapa yang berhak menerima komisi”.

## 10. Rencana pelaksanaan bertahap

### Fase 1 — SOP dan konfigurasi manual

Tetapkan nama wilayah, anggota, koordinator, jam kerja, SLA, dan kategori alasan keputusan. Pada fase ini, assignment dapat dilakukan secara manual oleh koordinator. Tujuannya adalah menguji pembagian tugas tanpa langsung mengubah seluruh struktur database.

### Fase 2 — Team membership dan policy

Implementasikan tabel tim, keanggotaan, role tim, dan scope wilayah. Perbarui policy agar anggota hanya membaca serta memproses kasus di wilayahnya. Tambahkan audit log untuk semua keputusan dan perubahan assignment.

### Fase 3 — Workflow dan dashboard

Implementasikan antrean, assignment, status kasus, eskalasi, notifikasi, dan dashboard KPI. Tambahkan filter berdasarkan tim, anggota, wilayah, status, dan tanggal.

### Fase 4 — Evaluasi dan penguatan kontrol

Setelah empat minggu, evaluasi SLA, akurasi QC, beban antaranggota, dan jumlah eskalasi. Perbaiki jumlah anggota, batas kewenangan, serta aturan sampling berdasarkan data operasional.

## 11. Contoh pembagian kerja untuk empat orang

| Posisi | Fokus harian | Cadangan utama |
|---|---|---|
| Koordinator | Pembagian antrean, eskalasi, approval risiko tinggi, laporan | Admin QC |
| Admin Merchant | Pemeriksaan merchant dan follow-up perbaikan | Koordinator |
| Admin Ojek | Pemeriksaan courier, kendaraan, dan wilayah kerja | Admin Merchant setelah pelatihan |
| Admin QC | Sampling, SLA, rekonsiliasi, dan temuan | Koordinator |

Pada hari ketika satu anggota tidak masuk, koordinator tidak perlu mengambil seluruh beban. Admin QC dapat mengambil alih pemeriksaan normal yang sudah memiliki checklist, sedangkan kasus risiko tinggi tetap ditahan untuk keputusan koordinator atau admin pusat.

## Kesimpulan

Tim beranggotakan empat orang dapat berjalan efektif apabila koordinator tidak menjadi satu-satunya pelaksana, dan tiga admin memiliki fokus yang jelas. Pembagian yang disarankan adalah merchant, ojek atau courier, serta quality control dan monitoring. Kunci implementasinya adalah scope wilayah, assignment yang tercatat, pemisahan pemeriksaan dan persetujuan, serta audit log untuk setiap keputusan sensitif.

Struktur database saat ini dapat dikembangkan secara bertahap. Kolom kepemilikan lama tetap dipertahankan untuk kompatibilitas, sementara `verifikator_teams`, `verifikator_team_members`, scope wilayah, dan assignment kasus ditambahkan sebagai lapisan organisasi baru.

## References

[1]: https://github.com/bonangpanjinur/Sadesa-fix "Repository SaDesa-fix"
