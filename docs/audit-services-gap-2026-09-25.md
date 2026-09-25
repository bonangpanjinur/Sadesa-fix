# Audit Gap Fitur `/services`

**Tanggal:** 25 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Commit yang diaudit:** `4ec9b1f` (`feat: harden service marketplace operations`)  
**Cakupan:** UI/UX admin, penyedia jasa, penyewa/buyer; pembayaran manual; posting keahlian; tarif minimum; pembagian hasil; dan transfer yang hanya dilakukan admin.  
**Di luar cakupan:** integrasi payment gateway otomatis. Payment gateway diperlakukan sebagai pekerjaan fase berikutnya.

## Ringkasan eksekutif

Fitur `/services` pada commit terbaru sudah memiliki fondasi marketplace transaksi yang cukup lengkap untuk **pilot terbatas dengan operasi manual admin**. Alur yang tersedia meliputi katalog provider, onboarding dan review provider, posting profil serta keahlian, request buyer, negosiasi harga, persetujuan harga, pembayaran manual ke admin dengan upload bukti, verifikasi admin, mulai dan konfirmasi selesai, antrean payout, dispute, refund manual, ledger append-only, notifikasi event, serta sweep SLA.

Namun fitur ini **belum siap untuk transaksi publik berskala besar**. Gap paling penting yang perlu ditutup sebelum pilot diperluas adalah: **harga minimum provider belum divalidasi pada RPC penawaran**, **fee 5% masih hardcoded dan belum menjadi pengaturan finansial yang dikelola admin**, **UI buyer belum menampilkan detail rekening/kanal transfer admin yang authoritative**, **rental baru menyimpan atribut dasar tanpa settlement deposit/serah-terima/pengembalian yang lengkap**, dan **belum ada uji RLS/E2E staging terhadap aktor nyata**.

### Status keseluruhan

| Area | Status | Penilaian |
|---|---|---|
| Katalog dan pencarian provider | Ada | Sudah dapat digunakan, tetapi filter dan informasi detail masih sederhana. |
| Posting keahlian provider | Ada | Atomic melalui RPC dan masuk review admin. |
| Tarif minimum provider | Parsial / berisiko | Disimpan di profil, tetapi belum dipakai sebagai guard saat provider mengirim harga. |
| Request dan negosiasi | Ada | Provider mengirim harga; buyer menerima secara eksplisit. |
| Pembayaran | Ada secara manual | Transfer buyer ke admin dan upload bukti; belum ada gateway, sesuai keputusan saat ini. |
| Verifikasi pembayaran | Ada | RPC atomic dan nominal dicocokkan dengan harga kesepakatan. |
| Payout provider | Ada secara manual | Payout dibuat setelah kedua pihak selesai; admin mencatat transfer aktual dengan referensi. |
| Pembagian hasil | Parsial | Perhitungan tersedia, tetapi kebijakan fee belum configurable/versioned dari UI admin. |
| Dispute/refund | Ada secara manual | Refund baru selesai setelah admin mencatat referensi transfer aktual. |
| Rental | Parsial | Tanggal, deposit, denda, dan kondisi awal ada; lifecycle aset dan settlement deposit belum lengkap. |
| Notifikasi/SLA | Fondasi ada | Trigger dan worker function tersedia, tetapi scheduler dan monitoring operasional masih harus dipastikan. |
| Go-live publik | Belum direkomendasikan | Perlu staging test, hardening finansial, dan penyempurnaan UX. |

## 1. Peta alur aktual

```text
Buyer / penyewa
  -> /services
  -> pilih provider terverifikasi
  -> buat request JOB atau RENTAL
  -> menunggu penawaran provider
  -> setujui harga final
  -> transfer manual ke rekening admin
  -> unggah bukti transfer
  -> menunggu verifikasi admin
  -> provider mulai bekerja
  -> buyer dan provider konfirmasi selesai
  -> admin memproses transfer payout ke provider

Provider
  -> aktifkan role service_provider
  -> isi profil, keahlian, area, dan tarif minimum
  -> menunggu review admin
  -> menerima request
  -> mengirim penawaran harga
  -> berkomunikasi melalui request
  -> mulai setelah pembayaran diverifikasi
  -> konfirmasi pekerjaan selesai
  -> menerima payout melalui transfer yang dilakukan admin

Admin
  -> review provider
  -> review bukti pembayaran
  -> memantau dana ditahan
  -> melakukan transfer payout ke provider
  -> memasukkan referensi transfer aktual
  -> menangani dispute dan refund manual
```

## 2. Temuan prioritas

| ID | Prioritas | Temuan | Bukti implementasi | Dampak |
|---|---|---|---|---|
| SVC-G01 | **P0** | **Tarif minimum provider tidak dipaksa pada saat penawaran.** Provider mengisi `min_price` melalui `service_publish_profile`, tetapi `service_provider_propose_price` hanya memeriksa harga lebih dari nol; RPC tidak membaca `service_profiles.min_price` dan tidak menolak harga di bawah minimum. | `supabase/bootstrap/40_20260925100000_service_transaction_state_machine.sql:350-378`; `ServicesPage.tsx` menyimpan `p_min_price`. | Aturan “minimal harga/tarif diatur penyedia” dapat dilanggar oleh provider sendiri atau oleh UI/API lain. Nilai minimum hanya menjadi informasi, bukan aturan bisnis. |
| SVC-G02 | **P0** | **Pembagian hasil belum dapat diatur admin.** Fee platform masih dihitung dengan konstanta `5%` di RPC. Tidak terlihat UI/policy version untuk admin mengubah persentase, minimum fee, pembulatan, atau berlaku mulai kapan. | `service_provider_propose_price` menghitung `p_agreed_price * 0.05`; payout memakai `platform_fee` dari request. | Admin tidak dapat mengelola kebijakan finansial secara aman dan historis; perubahan fee mengharuskan migration/function change. Risiko salah hitung dan sengketa pembagian hasil. |
| SVC-G03 | **P0** | **Instruksi rekening/kanal pembayaran admin belum terlihat di UI service.** Buyer hanya diarahkan “Bayar ke rekening admin” dan diminta upload bukti; halaman tidak menampilkan rekening tujuan, nama pemilik, kanal, kode unik, atau instruksi authoritative yang terikat request. | `ServiceRequestsPage.tsx` bagian `WAITING_PAYMENT`; tidak ada data rekening admin pada alur service yang diaudit. | Buyer berisiko mentransfer ke rekening yang salah atau tidak tahu nominal/kanal yang benar. Alur manual dapat berhenti walaupun validasi bukti sudah tersedia. |
| SVC-G04 | **P0** | **Validasi staging/E2E belum terbukti.** Contract test statis tersedia, tetapi belum membuktikan buyer A/B, provider A/B, dan admin terhadap database staging serta retry/negative path. | `src/lib/serviceMarketplaceContract.test.ts`, `serviceEnhancementContract.test.ts`; belum ada bukti dynamic RLS/E2E pada audit ini. | RLS, SECURITY DEFINER, transition guard, trigger ledger, dan rekonsiliasi payout belum tervalidasi terhadap skenario lintas akun.
| SVC-G05 | **P1** | **Payout hanya mencatat transfer manual; belum ada workflow rekonsiliasi yang lebih kuat.** Model sudah benar untuk “transfer hanya admin”, tetapi status `RELEASED` masih bergantung pada admin memasukkan referensi; belum ada bukti rekening tujuan provider yang verified, maker-checker, attachment bukti transfer, atau rekonsiliasi saldo rekening admin. | `service_admin_release_payout` mensyaratkan external reference dan mengisi `released_by`; UI admin menginstruksikan transfer di luar aplikasi. | Kontrol akses dasar sudah ada, tetapi salah transfer, operator tunggal, dan perbedaan saldo bank vs ledger masih mungkin terjadi. |
| SVC-G06 | **P1** | **Rental baru sebagian.** Request menyimpan tanggal, deposit, denda harian, dan kondisi serah-terima, tetapi belum terlihat workflow validasi ketersediaan aset, foto serah-terima/pengembalian, `returned_at`, perhitungan denda aktual, pemisahan deposit dari harga jasa, dan pengembalian deposit. | Migration 41 menambah atribut rental dan constraint tanggal; UI baru meminta sebagian atribut. | “Jasa sewa” belum aman dipakai untuk transaksi aset nyata; risiko sengketa deposit, benturan jadwal, dan status barang. |
| SVC-G07 | **P1** | **Status domain sudah ditambahkan, tetapi UI utama masih banyak bergantung pada `request.status`.** `payment_status`, `work_status`, `dispute_status`, dan `payout_status` belum ditampilkan sebagai timeline/indikator utama pada halaman buyer/provider/admin. | Migration 41: kolom domain status dan trigger sync; halaman utama memetakan `status` lama. | Informasi dana, pekerjaan, dispute, dan payout dapat terasa ambigu, terutama saat status bisnis berkembang atau ada retry/settlement tertunda. |
| SVC-G08 | **P1** | **SLA worker tersedia, tetapi bukan scheduler end-to-end.** `service_run_sla_sweep` hanya function yang harus dipanggil worker service-role/admin; belum ada bukti scheduler aktif, dashboard ageing, assignee, atau escalation. | `service-marketplace-operations.md`; migration 41. | Request dapat tetap menggantung jika worker tidak dikonfigurasi dan dipantau. SLA yang hanya ada di database belum menjadi operasi yang terjamin. |
| SVC-G09 | **P1** | **Inbox provider masih berupa riwayat gabungan.** Provider dapat melihat dan mengoperasikan request, tetapi belum ada filter/queue yang jelas untuk baru, negosiasi, menunggu pembayaran, sedang dikerjakan, dispute, dan selesai; availability/calendar juga belum ada. | `ServiceProviderHistoryPage.tsx`. | Sulit dipakai ketika volume request meningkat; provider berisiko melewatkan request atau jadwal bentrok. |
| SVC-G10 | **P1** | **Admin belum memiliki dashboard finansial yang cukup untuk pembagian hasil.** Ada kartu dana ditahan, payout, fee, dan laporan bulanan, tetapi belum terlihat konfigurasi fee, ledger explorer per event, ageing SLA, reconciliation queue, atau export audit yang lengkap. | `AdminServicesPage.tsx`, `AdminServiceDisputesPage.tsx`. | Admin dapat melakukan operasi inti, tetapi kontrol manajemen keuangan dan audit periodik masih manual/tersebar. |
| SVC-G11 | **P2** | **UX pembayaran dan pasca-submit masih dapat diperjelas.** Request ID dan halaman request sudah tersedia, tetapi buyer belum mendapatkan invoice/summary yang kuat: harga jasa, fee admin, total transfer, rekening tujuan, batas pembayaran, dan status verifikasi dalam satu panel yang mudah dipindai. | `ServiceRequestsPage.tsx`. | Beban support meningkat dan buyer dapat salah memahami bahwa harga provider sama dengan total transfer atau bahwa upload bukti berarti pembayaran sudah final. |
| SVC-G12 | **P2** | **Chat belum realtime/notification UX khusus request.** Query dilakukan saat load/refresh key; notifikasi event memang dibuat oleh trigger, tetapi halaman service tidak menunjukkan unread count atau subscribe realtime khusus request. | `ServiceRequestsPage.tsx`, `ServiceProviderHistoryPage.tsx`, migration 41. | Buyer/provider harus refresh atau membuka notifikasi umum untuk mengetahui counter-offer, bukti ditolak, atau pekerjaan dimulai. |

## 3. Audit per sisi pengguna

### 3.1 Admin/operator

**Yang sudah baik:** admin dapat memverifikasi provider, menolak dengan catatan, memverifikasi atau menolak bukti pembayaran, melihat dana ditahan, memproses payout manual dengan referensi transfer aktual, dan merekonsiliasi refund setelah transfer aktual. Operasi sensitif diarahkan melalui RPC dan log admin.

**Yang masih kurang:** admin belum memiliki pengaturan fee dan pembagian hasil yang dapat diubah dengan audit/versioning; belum ada konfigurasi rekening admin dan rekening payout provider yang tervalidasi; belum ada maker-checker untuk nominal besar; belum ada queue berbasis SLA/assignee; dan belum ada rekonsiliasi harian antara saldo rekening admin, ledger, payment proof, payout, dan refund.

### 3.2 Penyedia jasa

**Yang sudah baik:** provider dapat memposting profil, memilih hingga 30 keahlian, menetapkan `min_price`, masuk review admin, menerima request, mengirim harga, chat, mulai pekerjaan setelah pembayaran diverifikasi, dan mengonfirmasi selesai.

**Yang masih kurang:** `min_price` belum menjadi batas server-side; belum ada harga per keahlian, unit harga, estimasi durasi, availability, area layanan terstruktur, kuota/capacity, template penawaran, masa berlaku penawaran, dan metode payout yang telah diverifikasi. Dashboard juga perlu dipisahkan antara inbox pekerjaan, pendapatan, dan riwayat settlement.

### 3.3 Penyewa/buyer

**Yang sudah baik:** buyer dapat memilih provider terverifikasi, membuat request JOB/RENTAL, menyetujui harga, mengunggah bukti transfer, melihat status, chat, mengonfirmasi selesai, dan membuka dispute.

**Yang masih kurang:** halaman pembayaran belum menampilkan instruksi transfer admin yang authoritative; belum ada invoice yang menjelaskan total dan komponen biaya secara kuat; belum ada tombol pembatalan yang terdefinisi per state; dan rental belum menutup alur deposit, pengembalian, kondisi akhir, serta denda aktual. Buyer juga perlu timeline status yang memisahkan status pembayaran, pekerjaan, dispute, dan payout.

## 4. Audit pembayaran dan transfer admin

### Model yang berjalan sekarang

Model saat ini sesuai arahan **tanpa payment gateway**:

1. Provider mengirim harga.
2. Buyer menyetujui harga.
3. Buyer transfer secara manual ke rekening admin.
4. Buyer upload bukti dan metadata transfer.
5. Admin mencocokkan nominal dengan harga kesepakatan serta meninjau bukti.
6. Setelah pembayaran diverifikasi, provider boleh mulai bekerja.
7. Setelah buyer dan provider sama-sama mengonfirmasi selesai, payout dibuat berstatus `PENDING`.
8. Admin melakukan transfer payout kepada provider melalui kanal bank di luar aplikasi.
9. Admin mencatat referensi transfer aktual; barulah payout menjadi `RELEASED`.

Model ini **sudah membatasi transfer operasional pada admin** pada level workflow. RPC payout memeriksa role admin, mewajibkan external transfer reference, mengisi `released_by`, dan menggunakan row lock. Refund juga dipisahkan: `REFUND_APPROVED` belum dianggap `REFUNDED` sampai admin mencatat transfer refund aktual.

### Kontrol yang wajib ditambahkan sebelum pilot diperluas

| Kontrol | Keputusan yang diperlukan |
|---|---|
| Rekening penerimaan admin | Satu sumber data resmi: bank, pemilik rekening, nomor rekening, instruksi, status aktif, dan tanggal berlaku. |
| Fee platform | Pengaturan admin yang versioned: persentase/nominal minimum, pembulatan, transfer fee, dan effective date. |
| Rekening payout provider | Provider harus mendaftarkan metode payout; admin memverifikasi sebelum payout pertama. |
| Maker-checker | Payout/refund di atas ambang tertentu perlu operator kedua atau approval tambahan. |
| Rekonsiliasi | Cocokkan bank statement/manual register dengan ledger payment, fee, payout, refund, dan adjustment. |
| Idempotensi | Semua submit proof, review, payout, refund, dan retry harus aman terhadap pengulangan. |
| Bukti transfer | Simpan referensi, waktu, operator, nominal, kanal, dan jika diperlukan file bukti transfer admin. |

## 5. Rekomendasi implementasi berurutan

### P0 — sebelum pilot aktif

1. Ubah `service_provider_propose_price` agar mengambil profil provider berdasarkan `profile_id` request dan menolak `p_agreed_price < min_price`. Tentukan apakah minimum berlaku per profil, per keahlian, atau per unit/durasi.
2. Buat tabel/policy fee yang dikelola admin, misalnya `service_fee_policies`, dengan `percent`, `minimum_fee`, `maximum_fee`, `transfer_fee`, `effective_from`, `effective_until`, `version`, dan audit actor. RPC harus memilih policy yang berlaku dan menyimpan snapshot policy pada request/payout.
3. Tambahkan konfigurasi dan UI instruksi rekening admin yang hanya dapat diedit admin; tampilkan detailnya pada state `WAITING_PAYMENT` dan ikutkan snapshot instruksi pada invoice/request.
4. Jalankan dynamic staging test: buyer A/B, provider A/B, admin; uji read isolation, mutation denial, harga minimum, nominal proof salah, duplicate proof, payout/refund ganda, retry RPC, dan transition ilegal.
5. Pasang dan monitor scheduler untuk `service_run_sla_sweep`; dokumentasikan owner, interval, alert, dan recovery.

### P1 — sebelum volume transaksi meningkat

1. Lengkapi workflow rekening payout provider dan verifikasi rekening.
2. Pisahkan UI menjadi provider inbox, pekerjaan berjalan, pendapatan, dan settlement history.
3. Tampilkan timeline dan status domain pada buyer/provider/admin.
4. Lengkapi rental: availability, booking conflict, deposit ledger, handover/return evidence, late fee calculation, dan refund deposit.
5. Tambahkan reconciliation dashboard dan export ledger/audit.
6. Tambahkan notifikasi unread, realtime refresh, reminder deadline, dan escalation.

### P2 — peningkatan UX dan trust

1. Tambahkan invoice ringkas dengan breakdown: harga jasa, fee admin, deposit, denda potensial, total transfer, dan nominal payout provider.
2. Tambahkan rating/review yang hanya bisa dibuat setelah completion yang valid.
3. Tambahkan filter, search, pagination, dan ageing pada semua dashboard.
4. Tambahkan template scope pekerjaan, deliverable, revisi, estimasi waktu, dan masa berlaku penawaran.

## 6. Acceptance criteria

Fitur `/services` dapat dianggap siap untuk pilot terbatas jika semua kriteria berikut lulus:

1. Provider tidak dapat mengirim penawaran di bawah `min_price` melalui RPC, PostgREST, maupun retry.
2. Buyer melihat rekening admin, nominal final, fee, deposit jika ada, dan deadline pembayaran sebelum transfer.
3. Fee dan pembagian hasil berasal dari policy admin yang versioned, bukan konstanta yang tersebar.
4. Buyer A tidak dapat membaca atau memutasi request buyer B; provider A tidak dapat melihat request provider B.
5. Bukti transfer dengan nominal berbeda selalu ditolak server-side; proof aktif ganda tidak dapat dibuat.
6. Payment verification, domain status, ledger, dan notifikasi berubah atomic dalam satu operasi bisnis.
7. Payout hanya dapat dirilis admin, wajib memiliki transfer reference, operator, nominal, timestamp, dan audit event.
8. Refund baru berstatus selesai setelah transfer aktual direkonsiliasi.
9. SLA sweep berjalan terjadwal dan request yang timeout dapat ditelusuri melalui `service_sla_events`.
10. Untuk RENTAL, tanggal, deposit, serah-terima, pengembalian, kondisi akhir, denda, dan pembatalan mempunyai aturan server-side.
11. Test staging request → proposal → accept → payment proof → verify → start → complete → payout lulus untuk jalur normal, rejection, retry, dispute, refund, dan akses lintas pengguna.

## 7. Kesimpulan keputusan

**Rekomendasi:** lanjutkan `/services` sebagai **pilot terbatas dengan transfer manual terpusat di admin**, bukan sebagai marketplace publik penuh. Jangan mengintegrasikan payment gateway pada tahap audit ini; rapikan dahulu fondasi kontrol tarif, fee policy, rekening admin, rekonsiliasi, dan pengujian akses. Setelah P0 lulus, payment gateway dapat ditambahkan sebagai kanal pembayaran baru yang tetap memakai state machine dan ledger yang sama, bukan mengganti aturan bisnis yang sudah dibangun.

**Prioritas paling mendesak:**

1. Guard tarif minimum provider di server.
2. Fee/pembagian hasil yang dapat dikonfigurasi admin dan memiliki snapshot policy.
3. Detail rekening admin dan instruksi transfer yang tampil jelas di buyer.
4. Dynamic RLS/E2E staging test.
5. Rekonsiliasi payout/refund dan scheduler SLA yang benar-benar aktif.
