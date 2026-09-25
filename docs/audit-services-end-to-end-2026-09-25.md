# Audit End-to-End `/services`

**Tanggal audit:** 25 September 2026
**Repository:** `bonangpanjinur/Sadesa-fix`
**Cakupan:** alur, UI/UX, alur bisnis, pendaftaran penyedia dan penyewaan jasa, checkout, pembayaran, escrow, payout, dispute, RLS, serta validasi build/lint/test.

## Ringkasan eksekutif

Area `/services` sudah memiliki fondasi katalog jasa, kategori/subkategori, profil penyedia, request pekerjaan, skema escrow, panel admin, payout, dan dispute. Namun implementasinya **belum menjadi alur transaksi end-to-end yang dapat digunakan buyer**. Produk berhenti pada tahap “kirim permintaan” dan belum menyediakan layar atau operasi buyer untuk melihat request, melakukan negosiasi terstruktur, menyepakati harga, membayar, mengunggah bukti transfer, memantau verifikasi, mengonfirmasi pekerjaan selesai, atau membuka sengketa.

Temuan paling kritis adalah **tidak adanya implementasi pembuatan payout dan UI pembayaran buyer**, sehingga antrean pencairan admin secara praktis tidak akan terisi dari alur pengguna. Selain itu, sejumlah perubahan nominal dan status transaksi masih dilakukan melalui update langsung dari browser; RLS membatasi siapa yang boleh mengubah baris, tetapi belum membatasi kolom dan transisi status yang boleh diubah. Ini membuat nominal, fee, status, dan hasil payout tidak authoritative di server.

### Status validasi teknis

| Validasi | Hasil | Catatan |
|---|---|---|
| `pnpm build` | **Lulus** | Bundle `ServicesPage` berhasil dibuat. |
| `pnpm lint` | **Gagal** | 4 error pada file `/services`, 1 warning umum. |
| `pnpm test -- --runInBand` | **Gagal** | Command test pada job audit berakhir exit code 1; log ringkas tidak memuat hasil suite lengkap. Perlu dijalankan ulang terpisah untuk diagnosis suite. |
| Dynamic test database/live | **Belum dilakukan** | Tidak ada kredensial/live DB yang digunakan dalam audit ini. |

## Peta alur aktual

```text
Pengunjung
  -> /services
  -> melihat kategori dan profil provider aktif
  -> klik Hubungi
  -> login bila belum authenticated
  -> isi judul, deskripsi, lokasi, budget opsional
  -> INSERT service_requests
  -> toast “permintaan terkirim”

Provider
  -> klik Daftar sebagai penyedia
  -> wajib sudah memiliki role buyer
  -> activate_service_provider()
  -> isi profil dan pilih subkategori
  -> upsert service_profiles + replace service_skills
  -> tampil di katalog
  -> /services/provider-history hanya membaca request/payout/proof

Admin
  -> /admin/services
  -> review bukti transfer secara manual
  -> update proof + update status request
  -> release payout secara manual bila status request tertentu

Yang belum tersambung di UI buyer:
  negosiasi/chat jasa -> persetujuan harga -> checkout -> instruksi pembayaran
  -> upload bukti -> status pembayaran -> mulai kerja -> konfirmasi selesai
  -> dispute/refund -> notifikasi/riwayat buyer
```

## Temuan prioritas

| ID | Prioritas | Temuan | Dampak |
|---|---|---|---|
| SVC-01 | **P0 Blocker** | Tidak ada UI buyer untuk request inbox/detail, negosiasi, pembayaran, upload payment proof, konfirmasi selesai, atau dispute. Dari seluruh source, tabel service hanya direferensikan oleh `ServicesPage`, `ServiceProviderHistoryPage`, dan dua halaman admin. | Buyer tidak dapat menyelesaikan transaksi jasa dari awal sampai akhir. Fitur hanya dapat maju melalui operasi manual/SQL atau komponen yang belum ada. |
| SVC-02 | **P0 Blocker** | Tidak ditemukan INSERT ke `service_payouts` pada source frontend/backend. `AdminServicesPage` hanya membaca payout yang sudah ada dan mengubahnya menjadi `RELEASED`. | Antrean `readyPayouts` kemungkinan selalu kosong; pencairan tidak memiliki langkah pembuatan record payout yang authoritative. |
| SVC-03 | **P0 High** | Buyer dapat membuat request dengan `agreed_price` langsung dari input budget dan `service_requests` mengizinkan participant melakukan UPDATE atas seluruh row. | Harga, fee, provider payout, status, flag approval, dan identitas bisnis dapat dimanipulasi oleh participant melalui PostgREST selama RLS row-level terpenuhi. RLS saat ini memvalidasi row ownership, bukan field-level authorization atau state transition. |
| SVC-04 | **P0 High** | Perubahan proof dan request dilakukan dalam dua operasi terpisah di `verifyProof`; perubahan payout dan request juga dua operasi terpisah di `releasePayout`. | Kegagalan request kedua dapat meninggalkan proof `VERIFIED` tetapi request belum `APPROVED_TO_START`, atau payout `RELEASED` tetapi request belum `COMPLETED`. Tidak atomic dan tidak idempotent. |
| SVC-05 | **P0 High** | Tidak ada validasi server-side bahwa nominal proof sama dengan nominal transaksi/agreed price; tabel proof juga tidak memiliki constraint satu pembayaran aktif per request atau idempotency. | Underpayment/overpayment, banyak proof aktif, verifikasi proof lama, dan rekonsiliasi manual dapat terjadi. |
| SVC-06 | **P1 High** | `releasePayout` menghitung fee platform di browser dengan konstanta 5%, tidak mengisi `released_by`, dan tidak ada transfer provider/gateway; sistem hanya menandai status. | Risiko salah nominal, audit trail payout tidak lengkap, dan status “sudah dicairkan” dapat berbeda dari transfer bank aktual. |
| SVC-07 | **P1 High** | Keputusan dispute hanya mengubah `service_disputes` dan `service_requests.status`; refund tidak memanggil provider pembayaran atau membuat settlement/refund record. | `REFUND_APPROVED` dapat berarti status aplikasi saja, bukan dana benar-benar kembali. Tidak ada rekonsiliasi refund dan tidak ada partial refund model. |
| SVC-08 | **P1 Medium** | Aktivasi provider bergantung pada role buyer dan belum ada verifikasi/approval provider dalam flow onboarding; profil dapat tampil aktif meski `is_verified` false, sedangkan katalog tetap menampilkan semua profile aktif. | Trust signal “terverifikasi” hanya badge, bukan gate operasional. Provider belum diverifikasi tetap bisa tampil. |
| SVC-09 | **P1 Medium** | Saat menyimpan profil, upsert profile dan delete/insert skills terpisah. Jika insert skills gagal, profil tetap tersimpan; UI hanya memberi toast error. | Profil parsial dapat tampil tanpa keahlian dan perbaikan membutuhkan retry manual. |
| SVC-10 | **P1 Medium** | Lint gagal pada tiga halaman service karena `any` eksplisit dan satu unused expression di `loadData`. | Quality gate CI dapat gagal; error type safety menutupi kontrak data yang penting untuk transaksi. |
| SVC-11 | **P2 UX** | Tombol “Hubungi” hanya membuka form request; setelah sukses hanya toast, tanpa CTA menuju request/chat, tanpa nomor request, tanpa status tracking. | Buyer tidak tahu langkah berikutnya dan mudah menganggap pemesanan sudah selesai. |
| SVC-12 | **P2 UX** | Provider history menampilkan payout dan proof, tetapi tidak memiliki action untuk menerima/menolak request, mengirim pesan, mengubah penawaran, menandai mulai/selesai, atau melihat dispute. | Dashboard provider bersifat read-only dan tidak mendukung operasi inti marketplace. |

## Audit berdasarkan enam area yang diminta

### 1. Alur

**Kondisi baik:** landing `/services` menyampaikan tiga tahap “Cari jasa → Sepakati detail → Bayar aman”, kategori dan pencarian tersedia, provider dapat membuat profil, dan ada pemisahan panel admin escrow.

**Gap utama:** implementasi berhenti setelah `INSERT service_requests`. Tidak ada detail request atau status journey di sisi requester/provider. Status database memiliki 10 state, tetapi UI hanya memetakan status pada `ServiceProviderHistoryPage` dan tidak memiliki mutation untuk menggerakkan sebagian besar state tersebut.

**Kesimpulan:** alur konseptual lebih lengkap daripada alur yang benar-benar executable. Journey yang dipromosikan UI belum tersedia seluruhnya.

### 2. UI/UX

**Kekuatan:** visual hierarchy baik, hero jelas, kategori mudah dipindai, empty/loading/error state dasar tersedia, dan copy escrow cukup komunikatif. Dialog onboarding provider juga menjelaskan prasyarat role buyer.

**Masalah:**

- “Hubungi” adalah label komunikasi, tetapi aksi sebenarnya membuat order/request; naming harus konsisten.
- Setelah submit request tidak ada confirmation page, request ID, SLA, status, atau link ke chat.
- Tidak ada visible “Keranjang/Checkout/Total yang harus dibayar” untuk jasa.
- Form budget bersifat opsional, tetapi tidak menjelaskan bahwa nilai itu hanya tawaran awal dan belum harga final.
- Tidak ada validasi panjang minimum/maksimum yang terlihat pada title, description, location, dan budget; angka dapat bernilai negatif/NaN secara client-side sebelum database menolak.
- Link “Riwayat transaksi” mengarah ke riwayat provider dan memaksa protected route, padahal CTA berada pada halaman publik dan dapat diklik buyer biasa.
- Katalog menampilkan provider aktif non-verified; badge verified tidak dijelaskan kriterianya.
- Pada mobile, daftar subkategori onboarding bisa sangat panjang dalam dialog; perlu pencarian/filter atau grouping.
- Aksi payout admin berlabel “Tandai sudah dicairkan”, tetapi copy keseluruhan menempatkan ini sebagai pencairan nyata. Harus dibedakan antara instruksi transfer dan konfirmasi transfer.

### 3. Alur bisnis

Model data sudah mengarah pada escrow: requester membayar admin, admin memverifikasi, provider bekerja, lalu payout setelah konfirmasi. Namun aturan bisnis inti belum dipaksa oleh database/RPC:

- siapa yang boleh menetapkan `agreed_price`;
- kapan request boleh berganti status;
- siapa yang wajib menyetujui harga;
- berapa nominal fee dan sumber kebijakannya;
- kapan payout dibuat;
- syarat refund/dispute;
- timeout auto-confirmation/cancellation;
- notifikasi kepada dua pihak;
- settlement/refund provider.

Dokumentasi sendiri menyatakan perhitungan fee sebaiknya dipindahkan ke RPC/server-side, tetapi implementasi yang diaudit masih menggunakan direct PostgREST update.

### 4. Pendaftaran dan penyewaan

**Pendaftaran provider:** alur role activation cukup aman secara dasar karena `activate_service_provider()` mensyaratkan authenticated user dan role buyer. Namun onboarding tidak membuat approval queue admin, tidak meminta nomor rekening/metode payout, tidak meminta dokumen/verifikasi identitas, dan tidak memberi status “menunggu verifikasi”.

**Penyewaan jasa:** belum ada “rental/order detail” yang dapat dikelola requester. Form hanya membuat `service_requests`; tidak ada pilihan tanggal/jadwal/durasi untuk kategori sewa, deposit, denda keterlambatan, kondisi barang, serah-terima, atau pengembalian aset. Kategori “Jasa Sewa” saat ini diperlakukan sama dengan jasa pekerjaan biasa.

### 5. Checkout

**Status:** belum tersedia untuk `/services`.

Tidak ditemukan route atau komponen service checkout yang mengikat `service_requests` ke `CheckoutPage`, `PaymentConfirmationPage`, invoice, payment intent, atau payment gateway. Checkout produk yang ada di repository tidak otomatis memenuhi checkout jasa karena jasa memerlukan flow negosiasi, harga final, fee, escrow, dan proof/payment state yang berbeda.

Acceptance criteria minimum yang belum ada:

1. requester melihat harga final dan breakdown fee;
2. requester menyetujui penawaran secara eksplisit;
3. server membuat checkout idempotently;
4. nominal dibekukan dari server, bukan dari client;
5. order/request mendapat payment reference;
6. retry tidak membuat transaksi duplikat;
7. buyer dapat melihat instruksi pembayaran dan deadline;
8. callback/webhook atau proof manual mengubah state secara atomic.

### 6. Pembayaran

**Implementasi aktual:** pembayaran masih manual ke rekening/kanal admin melalui upload bukti transfer, sesuai dokumentasi escrow. Tetapi layar upload proof buyer tidak ada. Admin dapat review proof jika record dibuat dari luar UI.

**Risiko keuangan:** proof hanya memiliki `amount > 0`; tidak ada server-side equality dengan `agreed_price`, tidak ada unique active proof, tidak ada expiry, tidak ada anti-replay/idempotency, dan tidak ada ledger. Payout hanya menyimpan agregat, tanpa external transfer reference wajib dan tanpa `released_by` yang diisi oleh frontend.

**Refund/dispute:** status dispute dapat berubah menjadi `REFUND_APPROVED`, tetapi tidak ada aksi refund aktual ke gateway/rekening, tidak ada refund amount yang authoritative, dan `service_requests` hanya diganti menjadi `REFUNDED`.

## Bukti kode utama

| Area | Lokasi | Observasi |
|---|---|---|
| Request creation | `src/pages/ServicesPage.tsx:75-82` | INSERT langsung dengan `agreed_price` dari budget client; selesai dengan toast tanpa detail/request navigation. |
| Provider onboarding | `src/pages/ServicesPage.tsx:63-72,84-92` | Aktivasi role lalu upsert profile dan replace skills dalam operasi terpisah. |
| Buyer/provider UI surface | `src/pages/ServicesPage.tsx`, `src/pages/ServiceProviderHistoryPage.tsx`, `src/pages/admin/AdminServicesPage.tsx`, `src/pages/admin/AdminServiceDisputesPage.tsx` | Tidak ada page buyer request, chat jasa, payment upload, completion confirmation, atau dispute requester. |
| Schema and RLS | `supabase/bootstrap/36_20260925010000_service_marketplace.sql:50-165` | Participant update request terlalu luas; payment proof/payout belum punya invariant nominal/state. |
| Provider role | `supabase/bootstrap/38_20260925020000_service_provider_role.sql:4-39` | Aktivasi role memerlukan buyer; tidak ada provider verification gate. |
| Admin verification | `src/pages/admin/AdminServicesPage.tsx:113-128` | Proof dan request di-update terpisah; tidak memvalidasi amount terhadap agreed price. |
| Admin payout | `src/pages/admin/AdminServicesPage.tsx:130-144` | Hitung fee di browser, update payout dan request terpisah, tidak set `released_by`. |
| Admin dispute | `src/pages/admin/AdminServiceDisputesPage.tsx:43-54` | Refund hanya update status; tidak ada refund/settlement transaction. |
| Provider history | `src/pages/ServiceProviderHistoryPage.tsx:49-80` | Read-only; query `service_payouts` dan `service_payment_proofs` tanpa action operasional. |

## Rekomendasi perbaikan berurutan

### Tahap 1 — Tutup blocker transaksi

1. Buat state machine server-side melalui RPC/Edge Function: `create_service_request`, `propose_service_price`, `accept_service_price`, `create_service_checkout`, `verify_service_payment`, `mark_service_started`, `mark_service_completed`, `open_service_dispute`, `approve_service_refund`, dan `release_service_payout`.
2. Cabut kemampuan participant melakukan unrestricted update pada `service_requests`; ubah menjadi update field yang aman atau RPC dengan validasi actor, state sebelumnya, nominal, dan lock row.
3. Tambahkan buyer request detail/history page dan provider inbox/detail page.
4. Tambahkan checkout jasa dengan harga final, fee, deadline, payment reference, status, dan retry idempotency.
5. Tambahkan buyer payment proof upload dan validasi amount server-side.
6. Buat payout secara atomic setelah syarat completion terpenuhi; simpan `released_by`, external transfer reference, dan timestamps.

### Tahap 2 — Integritas keuangan dan dispute

1. Tambahkan constraint/logic satu proof aktif per request atau status supersession yang jelas.
2. Pisahkan `payment_status`, `escrow_status`, `work_status`, dan `payout_status`; jangan memakai satu `request.status` untuk semua domain.
3. Buat ledger transaksi immutable untuk payment, fee, payout, refund, dan adjustment.
4. Refund harus memanggil provider pembayaran atau menghasilkan task settlement yang jelas; `REFUND_APPROVED` tidak boleh dianggap sebagai dana kembali.
5. Terapkan transition guard dan idempotency key di semua operasi admin.
6. Tambahkan timeout: payment expiry, auto-cancel, auto-confirmation, dan escalation SLA.

### Tahap 3 — UX dan operasional

1. Ganti CTA “Hubungi” menjadi “Ajukan kebutuhan” dan setelah submit arahkan ke detail request/chat.
2. Tampilkan progress stepper: Negosiasi → Harga disepakati → Menunggu pembayaran → Dana diverifikasi → Dikerjakan → Konfirmasi → Selesai.
3. Tampilkan breakdown harga/fee sebelum buyer membayar.
4. Tambahkan notifikasi realtime/email/in-app untuk request baru, counter-offer, proof verified/rejected, pekerjaan mulai, selesai, dispute, dan payout.
5. Tambahkan provider verification workflow dan status profil `Draft`, `Pending review`, `Verified`, `Rejected`.
6. Untuk kategori sewa, tambahkan tanggal mulai/selesai, deposit, kondisi barang, jadwal serah-terima, dan pengembalian.

### Tahap 4 — Quality gate

1. Hilangkan `any` pada tiga file service dan perbaiki unused expression di `AdminServicesPage` agar lint lulus.
2. Tambahkan unit test state machine, amount matching, idempotency, RLS participant isolation, dan rollback atomic.
3. Tambahkan E2E test satu alur lengkap: buyer register/login → request → negosiasi → checkout → payment proof → admin verify → provider start/complete → buyer confirm → admin payout.
4. Tambahkan negative test: provider tidak dapat mengubah price/status; buyer tidak dapat membaca request user lain; proof nominal salah ditolak; payout ganda ditolak; refund tidak dapat diulang.
5. Jalankan dynamic test pada staging Supabase untuk memastikan migration bootstrap 36–38 benar-benar diterapkan dan policy yang diuji sama dengan production.

## Kesimpulan

`/services` **belum siap disebut siap transaksi atau siap production untuk penyewaan jasa**. Katalog dan onboarding provider sudah dapat dipresentasikan sebagai MVP awal, tetapi alur yang diminta—terutama checkout dan pembayaran—belum terimplementasi sebagai journey buyer yang utuh. Prioritas pertama adalah membangun buyer-side transaction surface dan memindahkan seluruh penetapan nominal/status/settlement ke operasi server-side yang atomic dan idempotent. Setelah itu baru optimasi visual, notifikasi, dan fitur sewa khusus layak dikerjakan.

**Gate rekomendasi:** jangan mengaktifkan `/services` sebagai transaksi publik sebelum SVC-01 sampai SVC-07 ditutup dan E2E staging test lulus.

## Batasan audit

Audit ini berbasis source repository dan validasi build/lint/test lokal. Tidak dilakukan login browser, query ke database live, pengujian RLS dengan anon/authenticated key, upload file ke storage, webhook payment, atau transfer/refund aktual. Karena itu, status deployment migration dan policy live harus diverifikasi di staging sebelum go-live.

## Pembaruan implementasi setelah audit

Temuan pada audit di atas menggambarkan repository sebelum hardening marketplace jasa digabungkan. PR [#3](https://github.com/bonangpanjinur/Sadesa-fix/pull/3) telah merged ke `main`. Perubahan tersebut menambahkan halaman request buyer dan riwayat provider, percakapan, persetujuan harga, upload bukti pembayaran, konfirmasi pekerjaan, pembukaan sengketa, review provider oleh admin, serta RPC state machine dan pencatatan payout/refund berbasis referensi transfer aktual. Rincian kontrak terkini terdapat pada [panduan API escrow jasa](api-service-escrow-disputes.md).

Pembayaran, payout, dan refund tetap melibatkan transfer eksternal secara manual; aplikasi tidak menjalankan payment gateway untuk transaksi jasa. Alur khusus penyewaan seperti jadwal, deposit, serah-terima, dan pengembalian barang juga belum tersedia. Addendum ini memperbarui status implementasi kode, bukan hasil audit staging: penerapan migration dan pengujian RLS terhadap Supabase tetap perlu dilakukan sebelum fitur diaktifkan di production.
