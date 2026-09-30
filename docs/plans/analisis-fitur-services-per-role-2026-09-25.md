# Analisis Fitur Services/Jasa Berdasarkan Peran

**Tanggal:** 25 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Basis analisis:** source pada commit `d0f643e`, migration marketplace jasa dan state machine, serta halaman UI services.

## Ringkasan eksekutif

Fitur **Services/Jasa** sudah berkembang dari katalog sederhana menjadi marketplace jasa dengan alur transaksi yang cukup lengkap. Pada kondisi repository saat ini, buyer dapat melihat provider, membuat request, bernegosiasi melalui chat, menerima penawaran harga, membayar secara manual melalui transfer ke rekening admin, mengunggah bukti pembayaran, mengonfirmasi pekerjaan selesai, dan membuka sengketa. Provider dapat mengelola profil, melihat request, mengirim harga, berkomunikasi, memulai pekerjaan, dan mengonfirmasi penyelesaian. Admin dapat memverifikasi provider, memverifikasi bukti pembayaran, menangani dispute, mencatat refund, serta melepaskan payout dengan referensi transfer.

Namun fitur ini **belum sepenuhnya siap untuk transaksi publik berskala produksi**. Fondasi server-side sudah membaik melalui RPC/state machine dan operasi payout/refund yang lebih atomic, tetapi masih terdapat risiko penting: pembayaran masih manual, model status masih terlalu terkonsentrasi pada satu kolom `service_requests.status`, belum terlihat ledger immutable dan notifikasi end-to-end, belum ada mekanisme timeout/SLA yang jelas, dan kategori “sewa jasa” belum memiliki aturan rental khusus seperti jadwal, deposit, serah-terima, pengembalian, dan denda.

> **Kesimpulan:** katalog dan transaksi jasa sudah layak untuk pilot terbatas dengan operasi manual yang diawasi. Sebelum go-live publik, perlu ditutup kontrol keuangan, negative test RLS/state transition, observability, notifikasi, dan alur khusus penyewaan.

## Status alur saat ini

| Tahap | Status implementasi | Catatan |
|---|---|---|
| Katalog kategori/subkategori | Ada | Provider aktif dan terverifikasi dapat ditampilkan di katalog setelah migration hardening diterapkan. |
| Pendaftaran provider | Ada | Akun harus memiliki role buyer, kemudian mengaktifkan role `service_provider`. Profil masuk status `PENDING` untuk review admin. |
| Request buyer | Ada | Menggunakan RPC `service_create_request` dengan validasi panjang input dan budget. |
| Negosiasi harga | Ada | Provider mengirim harga melalui RPC; buyer menyetujui harga melalui RPC. Chat request tersedia. |
| Checkout | Parsial | Belum berupa payment gateway/checkout otomatis; pembayaran dilakukan manual ke rekening admin. |
| Upload bukti pembayaran | Ada | Buyer mengunggah file dan metadata melalui RPC; nominal divalidasi sama dengan `agreed_price`. |
| Verifikasi pembayaran | Ada | Admin memverifikasi atau menolak proof melalui RPC dan state transition. |
| Mulai pekerjaan | Ada | Provider hanya dapat mulai setelah payment proof diverifikasi. |
| Penyelesaian pekerjaan | Ada | Buyer dan provider dapat mengonfirmasi selesai; payout queue dibuat ketika syarat terpenuhi. |
| Payout | Ada secara operasional manual | Admin mencatat transfer aktual melalui external reference; belum ada integrasi transfer otomatis. |
| Dispute dan refund | Ada secara manual | Admin memutuskan dispute dan mencatat referensi refund aktual; refund belum dikirim otomatis ke payment provider. |
| Notifikasi/SLA | Belum memadai | Tidak terlihat alur lengkap notifikasi event, deadline pembayaran, auto-cancel, auto-confirmation, dan escalation. |
| Rental khusus | Belum ada | “Jasa sewa” masih mengikuti model request jasa biasa. |

## 1. Perspektif pembeli atau penyewa jasa

### Fitur yang sudah tersedia

Pembeli dapat menemukan provider berdasarkan kategori/subkategori, membuka form pengajuan kebutuhan, mengisi judul, deskripsi, lokasi, dan budget indikatif. Setelah request dibuat, halaman **Request Saya** menampilkan status, harga indikatif, harga kesepakatan, fee admin, nilai provider, bukti pembayaran, percakapan, dan tindakan sesuai status.

Alur negosiasi sudah cukup jelas: budget awal diberi label indikatif, provider mengirim penawaran, buyer melakukan persetujuan eksplisit, kemudian buyer membayar tepat sesuai harga kesepakatan. Buyer juga dapat mengunggah bukti transfer, menunggu verifikasi admin, mengirim pesan, mengonfirmasi pekerjaan selesai, dan membuka dispute.

### Kekuatan

| Area | Penilaian |
|---|---|
| Transparansi status | Baik untuk MVP; status dan status dana ditampilkan pada request. |
| Kontrol harga | Lebih aman karena harga final ditetapkan melalui RPC, bukan update bebas dari browser. |
| Bukti pembayaran | Nominal proof divalidasi terhadap harga kesepakatan dan proof pending ganda ditolak. |
| Perlindungan buyer | Dana diklaim ditahan admin sampai pekerjaan dan payout diproses. |
| Komunikasi | Chat request tersedia untuk buyer dan provider. |
| Dispute | Buyer dapat membuka sengketa selama pekerjaan belum final. |

### Gap dan risiko

1. **Pembayaran masih manual.** Buyer harus mentransfer di luar aplikasi, lalu mengunggah bukti. Ini menambah beban rekonsiliasi, risiko bukti palsu, risiko salah rekening, dan ketidakjelasan deadline.
2. **Belum ada payment reference dari gateway atau invoice authoritative.** `payment_reference` pada proof dapat menjadi referensi aplikasi, tetapi belum menggantikan payment intent, webhook, atau rekonsiliasi bank.
3. **Belum ada deadline dan auto-cancel.** Request yang menunggu penawaran, pembayaran, atau verifikasi dapat menggantung tanpa SLA yang tegas.
4. **Belum ada notifikasi yang dapat diandalkan.** Buyer berpotensi harus membuka halaman secara manual untuk mengetahui counter-offer, proof ditolak, pembayaran diverifikasi, pekerjaan selesai, atau keputusan dispute.
5. **Belum ada detail rental.** Untuk penyewaan barang/jasa, form belum meminta tanggal mulai/selesai, durasi, deposit, kondisi aset, jadwal serah-terima, biaya keterlambatan, dan bukti pengembalian.
6. **Konfirmasi selesai belum memiliki mekanisme auto-confirmation yang jelas.** Model saat ini menunggu konfirmasi kedua pihak sebelum payout; perlu aturan jika salah satu pihak tidak merespons.
7. **Bukti sengketa belum memiliki model evidensi yang kuat.** Perlu batas ukuran file, tipe file, ownership storage, retention, dan audit siapa yang menambahkan bukti.

### Rekomendasi buyer/renter

Prioritaskan invoice/checkout jasa dengan breakdown harga, fee, deadline pembayaran, payment reference, dan status yang jelas. Untuk rental, buat tipe order terpisah atau atribut domain rental sehingga jadwal dan deposit tidak dipaksa masuk ke model pekerjaan biasa. Tambahkan inbox notifikasi dan timeline event agar buyer selalu mengetahui langkah berikutnya.

## 2. Perspektif penyedia jasa

### Fitur yang sudah tersedia

Provider dapat mengaktifkan role jasa setelah memiliki role buyer, mengisi profil, memilih subkategori, menetapkan harga minimum, dan menunggu review admin. Setelah profil aktif dan terverifikasi, provider dapat muncul dalam katalog.

Pada halaman riwayat provider, provider dapat melihat request masuk, harga indikatif, harga deal, fee admin, nilai bersih, status bukti pembayaran, dan status payout. Provider dapat mengirim atau mengubah penawaran ketika status masih negosiasi, berkomunikasi dengan requester, menandai pekerjaan dimulai setelah pembayaran diverifikasi, serta mengonfirmasi pekerjaan selesai.

### Kekuatan

| Area | Penilaian |
|---|---|
| Onboarding | Sudah memiliki role khusus dan review provider oleh admin. |
| Kontrol akses | Operasi utama provider diarahkan melalui RPC dengan validasi provider pemilik request. |
| Informasi pendapatan | Gross, fee, transfer fee, net payout, dan status payout ditampilkan. |
| Perlindungan provider | Pekerjaan baru dapat dimulai setelah payment proof diverifikasi. |
| Operasional request | Provider dapat mengirim harga, chat, start, dan complete. |

### Gap dan risiko

1. **Provider history masih terlalu padat dan bersifat dashboard operasional tunggal.** Untuk volume request tinggi, diperlukan inbox dengan filter `baru`, `menunggu penawaran`, `menunggu pembayaran`, `sedang dikerjakan`, `dispute`, dan `selesai`.
2. **Belum ada kalender availability.** Provider belum dapat mengatur jadwal kerja, kapasitas harian, area layanan, blackout date, atau estimasi waktu pengerjaan.
3. **Belum ada kontrak/SLA pekerjaan.** Harga sudah ada, tetapi scope, deliverables, revisi, waktu mulai, target selesai, pembatalan, dan bukti serah-terima belum dimodelkan secara memadai.
4. **Payout masih transfer manual.** Status `RELEASED` seharusnya selalu memiliki external transfer reference, operator, timestamp, dan hasil rekonsiliasi.
5. **Provider belum memiliki workflow rekening/metode pencairan.** Onboarding belum terlihat meminta data payout yang tervalidasi atau status metode payout.
6. **Belum ada metrik reputasi yang terhubung ke transaksi jasa.** Rating/review seharusnya hanya dapat dibuat setelah completion dan tidak boleh dimanipulasi oleh pihak yang tidak terlibat.
7. **Dispute provider belum memiliki response workflow yang seimbang.** Admin dapat meminta menunggu pihak, tetapi perlu batas waktu respons, bukti provider, dan audit trail mediasi.

### Rekomendasi provider

Bangun provider inbox terpisah dari laporan pendapatan, tambahkan kalender/availability dan SLA, lalu kaitkan payout dengan profil rekening atau metode pencairan yang sudah diverifikasi. Tambahkan template penawaran agar provider dapat menyatakan ruang lingkup, estimasi durasi, masa berlaku penawaran, dan jumlah revisi.

## 3. Perspektif admin/operator

### Fitur yang sudah tersedia

Admin memiliki panel services untuk memantau payment proof, payout, provider profile, dan laporan transaksi. Admin dapat menyetujui atau menolak provider, memverifikasi atau menolak bukti transfer, memproses payout dengan referensi transfer, serta menangani dispute. Keputusan dispute dapat berujung pada refund atau payout release. Refund dicatat sebagai selesai hanya setelah admin memasukkan referensi transfer aktual.

### Kekuatan

| Area | Penilaian |
|---|---|
| Provider review | Ada status `PENDING`, `VERIFIED`, dan `REJECTED` dengan catatan admin. |
| Payment review | Validasi nominal payment terhadap harga request dilakukan server-side. |
| Atomic operation | RPC menggunakan row locking dan menggabungkan perubahan proof/request atau payout/request dalam satu operasi database. |
| Idempotency dasar | Beberapa RPC mengembalikan record jika sudah berada pada state final, sehingga retry tidak selalu membuat record ganda. |
| Refund audit | Refund mensyaratkan external reference dan menyimpan operator serta timestamp. |
| Payout creation | Payout queue dibuat saat kedua pihak selesai dan pembayaran terverifikasi, bukan hanya mengandalkan input browser. |

### Gap dan risiko

1. **Belum ada ledger immutable.** Tabel request/proof/payout/refund belum menggantikan ledger transaksi yang mencatat debit, fee, payout, refund, reversal, dan adjustment secara append-only.
2. **Model status terlalu terpusat.** Satu `request.status` mencampur status negosiasi, pembayaran, pekerjaan, dispute, dan settlement. Ini menyulitkan reporting, retry, dan audit.
3. **Fee policy perlu authoritative dan versioned.** Fee dan transfer fee sudah disimpan di request, tetapi harus berasal dari konfigurasi server yang memiliki versi kebijakan, bukan konstanta yang tersebar di client atau migration.
4. **Payout belum terhubung ke transfer provider.** `RELEASED` pada aplikasi berarti operator sudah mencatat transfer; sistem belum dapat membuktikan transfer sukses melalui provider finansial.
5. **Belum ada queue/SLA admin.** Tidak terlihat prioritas, ageing, assignee, escalation, reminder, dan target waktu untuk provider review, payment review, dispute, refund, serta payout.
6. **Observability belum lengkap.** Perubahan status penting memerlukan audit log actor, before/after state, reason, correlation ID, dan sumber perubahan.
7. **RLS perlu diuji dinamis.** Policy dapat terlihat benar secara statis, tetapi harus diuji memakai anon key, buyer A, buyer B, provider A, provider B, dan admin pada staging.
8. **Kategori jasa dan rental belum dipisahkan secara domain.** Admin belum memiliki parameter operasional seperti deposit, denda, cancellation rule, dan asset condition untuk rental.

### Rekomendasi admin/operator

Bangun dashboard queue berbasis SLA dan status domain. Tambahkan ledger serta audit event sebelum volume transaksi meningkat. Jadikan semua nominal, fee, payout, refund, dan state transition berasal dari RPC yang tervalidasi dan dapat diulang secara idempotent. Pisahkan aksi “buat instruksi transfer”, “transfer berhasil”, dan “rekonsiliasi transfer” agar label admin tidak menimbulkan salah persepsi.

## 4. Matriks prioritas perbaikan

| Prioritas | Pekerjaan | Alasan |
|---|---|---|
| P0 | Uji dan kunci state transition/RLS di staging | Mencegah buyer/provider mengubah status atau nominal milik pihak lain. |
| P0 | Tambahkan ledger immutable dan audit event | Menjamin rekonsiliasi pembayaran, fee, payout, refund, dan adjustment. |
| P0 | Tegaskan idempotency key untuk semua operasi finansial | Mencegah duplicate proof, payout, refund, dan retry berbahaya. |
| P0 | Integrasikan payment gateway atau prosedur rekonsiliasi manual formal | Mengurangi risiko bukti transfer palsu dan status dana yang tidak sinkron. |
| P1 | Pisahkan `payment_status`, `work_status`, `dispute_status`, dan `payout_status` | Menghindari ambiguitas satu kolom status. |
| P1 | Notifikasi in-app/realtime/email dan deadline | Menjaga buyer/provider/admin tidak kehilangan event operasional. |
| P1 | Provider availability, SLA, dan metode payout | Membuat marketplace dapat dipakai secara nyata, bukan hanya per-request. |
| P1 | Workflow rental khusus | Diperlukan jika “penyewa jasa” mencakup barang/aset yang disewakan. |
| P2 | Rating/review pasca-completion | Membangun trust setelah kontrol transaksi stabil. |
| P2 | Optimasi dashboard, filter, search, dan laporan | Meningkatkan efisiensi saat jumlah transaksi bertambah. |

## 5. Acceptance criteria sebelum go-live publik

1. Buyer A tidak dapat membaca atau memutasi request milik buyer B.
2. Provider tidak dapat mengubah `agreed_price`, fee, requester, status, atau payout secara langsung melalui PostgREST.
3. Harga final hanya dapat berubah melalui RPC yang memeriksa actor, state sebelumnya, batas nominal, dan status persetujuan buyer.
4. Proof dengan nominal berbeda dari harga final selalu ditolak server-side.
5. Upload ulang atau retry request yang sama tidak membuat payment proof aktif ganda.
6. Payment verification mengubah proof dan request secara atomic.
7. Payout hanya dibuat sekali ketika syarat completion dan payment terpenuhi.
8. Payout release wajib menyimpan `released_by`, external transfer reference, nominal, waktu, dan audit event.
9. Refund approved tidak disebut sebagai refund selesai sebelum transfer aktual direkonsiliasi.
10. Dispute memiliki batas waktu respons, bukti, keputusan, dan audit trail.
11. Buyer dan provider menerima notifikasi untuk request baru, offer, acceptance, proof verified/rejected, start, completion, dispute, refund, dan payout.
12. E2E staging test lulus dari request sampai payout, termasuk jalur rejection, retry, dispute, refund, dan akses lintas pengguna.
13. Untuk rental: tanggal, durasi, deposit, kondisi aset, serah-terima, pengembalian, denda, dan pembatalan harus tersimpan serta tervalidasi.

## Validasi teknis yang dilakukan

Source review dilakukan terhadap `ServicesPage`, `ServiceRequestsPage`, `ServiceProviderHistoryPage`, `AdminServicesPage`, `AdminServiceDisputesPage`, serta migration marketplace dan state machine. Repository berada pada commit `d0f643e` dan working tree bersih saat diperiksa.

Validasi `pnpm lint` dan `pnpm test -- --runInBand` belum menghasilkan validasi aplikasi karena dependency lokal belum terpasang (`node_modules` tidak tersedia; `vitest: not found`). Oleh sebab itu, laporan ini tidak menyatakan lint/test lulus. Sebelum merge atau deploy, jalankan instalasi dependency dengan lockfile yang benar, lalu ulangi lint, unit test, migration validation, RLS test, dan E2E staging.

## Rekomendasi keputusan produk

Aktifkan fitur ini sebagai **pilot terbatas dengan review admin manual**, bukan sebagai marketplace transaksi publik penuh. Batasi kategori dan jumlah provider pada fase awal, sediakan SOP rekonsiliasi payment/payout/refund, dan monitor semua state transition. Go-live publik sebaiknya menunggu P0 selesai serta E2E staging membuktikan bahwa nominal, akses, status, payout, dan refund tidak dapat menyimpang dari aturan bisnis.
