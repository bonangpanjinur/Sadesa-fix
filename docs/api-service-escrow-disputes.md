# Marketplace Jasa: API, Escrow, dan Sengketa

**Versi dokumen:** 2.0.0
**Diperbarui:** 25 September 2026
**Platform:** SaDesa
**Backend:** Supabase Auth, PostgREST, PostgreSQL Row Level Security (RLS)
**Bahasa:** Indonesia

Dokumen ini menjelaskan kontrak implementasi marketplace jasa yang tersedia di repository: katalog dan verifikasi provider, permintaan pekerjaan, negosiasi harga, percakapan, bukti pembayaran manual, penahanan dana oleh admin, konfirmasi pekerjaan, payout, dan sengketa.

> **Batasan pembayaran:** aplikasi tidak memindahkan uang. Buyer mentransfer dana melalui kanal yang diarahkan admin, sedangkan admin melakukan transfer payout atau refund di luar aplikasi. RPC hanya memvalidasi state dan merekam referensi transfer aktual setelah transaksi eksternal dilakukan. Belum ada checkout jasa atau integrasi payment gateway khusus untuk alur ini.

## 1. Arsitektur dan prinsip transaksi

Frontend adalah aplikasi Vite/React dan menggunakan Supabase Client. Otorisasi transaksi dan transisi state dilakukan melalui PostgreSQL RPC `SECURITY DEFINER` dengan pemeriksaan aktor, status request, nominal, serta row lock. RLS tetap membatasi pembacaan data. Kelayakan tombol di UI bukan pengganti validasi database.

Profil provider yang baru dibuat atau diubah masuk status `PENDING`. Perubahan profil yang sudah pernah diverifikasi juga membatalkan verifikasi sebelumnya. Profil baru dapat tampil dan menerima request jika aktif serta berstatus `VERIFIED`.

Buyer menyampaikan kebutuhan dan budget indikatif. Budget tidak menjadi harga final. Provider mengirim harga penawaran, lalu buyer menyetujuinya. Setelah harga disepakati, buyer mentransfer nominal tersebut ke kanal admin dan mengunggah bukti untuk ditinjau. Pekerjaan hanya dapat dimulai sesudah admin memverifikasi bukti. Payout masuk antrean setelah kedua pihak mengonfirmasi pekerjaan selesai.

## 2. Autentikasi, aktor, dan akses

Aplikasi mengambil URL Supabase dan publishable key dari `VITE_SUPABASE_URL` serta `VITE_SUPABASE_PUBLISHABLE_KEY`. Browser menggunakan session user yang aktif. `service_role` key dan secret lain tidak boleh dikirim ke frontend.

| Aktor | Kemampuan utama |
|---|---|
| Pengunjung | Membaca kategori dan profil aktif yang sudah diverifikasi. |
| Buyer | Membuat request, bernegosiasi, menyetujui harga, mengunggah bukti pembayaran, memberi konfirmasi selesai, dan membuka sengketa pada request sendiri. |
| Provider | Mengaktifkan role provider, mengirim profil untuk ditinjau, membaca request yang ditujukan kepadanya, mengajukan harga, bertukar pesan, serta mengonfirmasi mulai dan selesai. |
| Admin | Meninjau provider dan bukti pembayaran, mengelola kategori, menentukan keputusan sengketa, serta merekonsiliasi payout dan refund setelah transfer eksternal. |

Akun perlu terautentikasi dan memiliki role yang sesuai. Role provider diaktifkan melalui `activate_service_provider()`; akun harus lebih dahulu memiliki role `buyer`. Fungsi admin tetap memeriksa `public.is_admin()` meskipun hak `EXECUTE` diberikan kepada role `authenticated`.

## 3. Model data

| Tabel | Fungsi |
|---|---|
| `service_categories`, `service_subcategories` | Taksonomi kategori dan keahlian. Perubahan kategori dikelola admin. |
| `service_profiles`, `service_skills` | Profil provider serta relasi keahlian. Status review tersimpan dalam `verification_status`, `verification_note`, `verified_by`, dan `verified_at`; `is_verified` dipertahankan untuk kompatibilitas. |
| `service_requests` | Kebutuhan pekerjaan, peserta, budget buyer, penawaran/harga final, fee, persetujuan, konfirmasi selesai, dan status lifecycle. |
| `service_messages` | Pesan buyer/provider pada request yang sama. Isi pesan dikirim langsung melalui Supabase Client dan dibatasi policy peserta. |
| `service_payment_proofs` | Bukti transfer buyer. Nominal harus sama dengan harga final. Status: `PENDING`, `VERIFIED`, atau `REJECTED`. |
| `service_payouts` | Satu record antrean payout per request dengan gross, fee, nilai bersih, status, aktor admin, waktu, dan referensi transfer eksternal. |
| `service_disputes` | Alasan, peserta, status mediasi, keputusan, serta status request sebelum sengketa. Satu request hanya memiliki satu record sengketa. |
| `service_refunds` | Record refund yang disetujui dan pencatatannya setelah transfer benar-benar dilakukan. Status: `PENDING` atau `COMPLETED`. |

`requester_budget` bersifat indikatif. `agreed_price` diisi lewat penawaran provider dan tidak dianggap final hingga buyer menerima penawaran. Implementasi saat ini menghitung fee platform sebesar 5% dan biaya transfer default 0 ketika provider mengajukan harga. Tinjau kebijakan bisnis sebelum mengubah persentase ini.

Status request yang tersedia pada constraint database adalah `NEGOTIATING`, `WAITING_PAYMENT`, `PAID_TO_ADMIN`, `APPROVED_TO_START`, `IN_PROGRESS`, `WAITING_CONFIRMATION`, `COMPLETED`, `DISPUTED`, `CANCELLED`, dan `REFUNDED`. Status `PAID_TO_ADMIN` masih tercantum dalam skema; alur RPC yang terdokumentasi menggunakan `APPROVED_TO_START` setelah bukti diverifikasi admin.

Status sengketa mencakup `OPEN`, `IN_REVIEW`, `WAITING_PARTIES`, `REFUND_APPROVED`, `REFUNDED`, `RELEASE_APPROVED`, `RESOLVED`, `CLOSED`, dan `REJECTED`. Keputusan `REFUND_APPROVED` belum berarti uang telah kembali. Refund baru berstatus selesai setelah referensi transfer dicatat melalui RPC rekonsiliasi.

## 4. Katalog dan onboarding provider

Kategori dan keahlian aktif dibaca dari `service_categories` dan `service_subcategories`. Katalog publik hanya boleh menampilkan profil yang `is_active = true` dan `verification_status = 'VERIFIED'`. Pemilik tetap dapat membaca profilnya sendiri untuk melihat status review.

Setelah mengaktifkan role provider, simpan profil dan keahlian dalam satu pemanggilan RPC. Direct `INSERT`, `UPDATE`, atau `DELETE` ke tabel profil dan keahlian tidak diberikan kepada `authenticated`.

```ts
const { data: profile, error } = await supabase.rpc('service_publish_profile', {
  p_provider_name: 'Budi Teknisi',
  p_headline: 'Teknisi elektronik panggilan',
  p_bio: 'Perbaikan TV, kulkas, dan pompa air.',
  p_village: 'Desa Sukamaju',
  p_min_price: 75000,
  p_subcategory_ids: [televisionSubcategoryId, refrigeratorSubcategoryId],
});
```

RPC memvalidasi role, batas panjang kolom, rentang harga, jumlah skill, duplikasi skill, serta status aktif semua subkategori. Profil berstatus `PENDING` harus disetujui admin sebelum kembali terlihat di katalog. Keputusan review dilakukan melalui `service_admin_review_provider(p_profile_id, p_decision, p_note)`, dengan `p_decision` berupa `VERIFIED` atau `REJECTED`. Alasan penolakan wajib diisi.

## 5. Membuat request dan menyepakati harga

Buyer membuat request menggunakan `service_create_request`. Server memastikan aktor memiliki role `buyer`, profil provider aktif dan terverifikasi, subkategori memang terhubung ke profil, serta input berada dalam batas panjang. Request dimulai dengan status `NEGOTIATING`, `agreed_price = NULL`, dan budget tersimpan terpisah.

```ts
const { data: request, error } = await supabase.rpc('service_create_request', {
  p_provider_id: providerId,
  p_profile_id: profileId,
  p_subcategory_id: subcategoryId,
  p_title: 'Perbaikan televisi',
  p_description: 'TV tidak menyala sejak kemarin; mohon diperiksa.',
  p_location: 'Desa Sukamaju',
  p_budget: 250000, // indikatif; gunakan null bila tidak ditentukan
});
```

Provider mengirim atau memperbarui penawaran melalui `service_provider_propose_price(p_request_id, p_agreed_price)`. Harga harus positif dan request masih berada dalam status negosiasi. RPC menghitung fee serta payout indikatif di server dan mengosongkan persetujuan buyer setiap kali penawaran berubah.

Buyer menerima penawaran melalui `service_requester_accept_price(p_request_id)`. Hanya setelah persetujuan ini status berubah menjadi `WAITING_PAYMENT`. Pesan non-harga dikirim langsung ke `service_messages`; RLS memastikan pengirim adalah salah satu peserta dan `sender_id` sama dengan user session.

## 6. Pembayaran dan verifikasi bukti

Buyer mentransfer tepat sebesar `agreed_price` ke rekening atau kanal yang ditetapkan admin. UI mengunggah file ke bucket `payment-proofs`, lalu mendaftarkan bukti melalui RPC berikut:

```ts
const { data: proof, error } = await supabase.rpc('service_submit_payment_proof', {
  p_request_id: requestId,
  p_amount: agreedPrice,
  p_transfer_reference: bankReference,
  p_proof_url: uploadedProofUrl,
});
```

RPC memastikan pemanggil adalah requester, request berstatus `WAITING_PAYMENT`, dan nominal sama persis dengan harga final. Satu bukti berstatus `PENDING` per request dapat diproses pada satu waktu. Setelah bukti ditolak dengan alasan, buyer dapat mengunggah bukti pengganti.

Admin menyetujui atau menolak bukti melalui `service_admin_review_payment(p_proof_id, p_approved, p_note)`. Proses ini mengunci row dan secara atomic memperbarui bukti serta request. Keputusan setuju menjadikan bukti `VERIFIED` dan request `APPROVED_TO_START`; keputusan tolak mengembalikan request ke `WAITING_PAYMENT`. Alasan penolakan wajib diisi.

Bukti transfer dapat berisi data sensitif. Simpan pada bucket privat dan gunakan signed URL atau kontrol akses yang sesuai saat menampilkannya. Jangan menggunakan nominal dari client sebagai satu-satunya dasar verifikasi.

## 7. Pekerjaan, penyelesaian, dan payout

Provider memulai pekerjaan melalui `service_mark_started(p_request_id)`. RPC hanya menerima request yang sudah `APPROVED_TO_START` dengan bukti pembayaran `VERIFIED`. Pemanggilan berulang ketika request sudah `IN_PROGRESS` bersifat aman.

Buyer dan provider masing-masing mengonfirmasi pekerjaan selesai melalui `service_mark_completed(p_request_id)`. Pemanggilan pertama menyimpan konfirmasi pihak tersebut. Setelah kedua pihak mengonfirmasi, RPC membuat satu record payout berstatus `PENDING`; konflik duplikat tidak membuat antrean ganda.

Transfer payout dilakukan di luar aplikasi. Sesudah transfer berhasil, admin mencatatnya melalui `service_admin_release_payout(p_request_id, p_external_transfer_reference, p_note)`. Referensi transfer aktual wajib diisi. RPC memeriksa role admin, konfirmasi kedua pihak, bukti pembayaran yang terverifikasi, serta status request dan payout. Payout menjadi `RELEASED` dan request menjadi `COMPLETED`.

```ts
const { data: payout, error } = await supabase.rpc('service_admin_release_payout', {
  p_request_id: requestId,
  p_external_transfer_reference: bankTransferReference,
  p_note: 'Payout manual setelah transfer dikonfirmasi',
});
```

Jangan mengubah `service_requests` atau `service_payouts` secara langsung dari browser. Hak DML langsung untuk tabel transaksi dicabut dari `authenticated`; gunakan RPC berotorisasi. Nilai `RELEASED` berarti transfer eksternal sudah direkonsiliasi, bukan bahwa aplikasi mengeksekusi transfer.

## 8. Sengketa dan refund

Buyer atau provider dapat membuka sengketa pada request yang sudah dibayar dan berada dalam tahap pekerjaan/konfirmasi melalui `service_open_dispute(p_request_id, p_reason, p_amount)`. Alasan harus memiliki panjang yang valid, nominal sengketa harus positif dan tidak melampaui harga final, dan satu request tidak dapat memiliki sengketa duplikat. Request berubah menjadi `DISPUTED`; dana tetap ditahan selama pemeriksaan.

Admin memproses sengketa melalui `service_admin_decide_dispute(p_dispute_id, p_decision, p_note)`. Pilihan pada UI admin saat ini adalah `IN_REVIEW`, `WAITING_PARTIES`, `REFUND_APPROVED`, `RELEASE_APPROVED`, dan `REJECTED`. Keputusan divalidasi terhadap status awal dan syarat penyelesaian. `RELEASE_APPROVED` menyiapkan payout `PENDING` bila kedua pihak sudah menyatakan pekerjaan selesai. Keputusan `REJECTED` memulihkan status pekerjaan sebelumnya.

Untuk refund, admin menyetujui keputusan lebih dahulu. Sistem membuat record refund berstatus `PENDING`, tetapi tidak memindahkan dana dan tidak mengubah request menjadi `REFUNDED`. Setelah refund benar-benar ditransfer secara eksternal, admin mencatat referensinya:

```ts
const { data: refund, error } = await supabase.rpc('service_admin_record_refund', {
  p_dispute_id: disputeId,
  p_external_reference: refundBankReference,
  p_note: 'Refund manual telah dikirim',
});
```

Pencatatan ini menyelesaikan record refund, mengubah sengketa menjadi `REFUNDED`, dan request menjadi `REFUNDED`. Record refund dan payout hanya dapat dibaca peserta terkait atau admin; perubahan dilakukan melalui RPC admin.

## 9. Halaman aplikasi

| Route | Fungsi |
|---|---|
| `/services` | Katalog jasa, onboarding provider, dan formulir request buyer. |
| `/services/requests` | Riwayat/request buyer, negosiasi, penerimaan harga, upload bukti, konfirmasi selesai, dan pembukaan sengketa. |
| `/services/provider-history` | Request provider, pengajuan harga, percakapan, mulai/selesai pekerjaan, dan riwayat payout. |
| `/admin/services` | Review profil provider, review bukti pembayaran, antrean payout, dan laporan operasional. |
| Halaman admin sengketa jasa | Keputusan mediasi dan pencatatan refund setelah transfer eksternal. |

Nominal laporan pada UI merupakan laporan operasional. Rekonsiliasikan payout/refund terhadap mutasi rekening dan jangan menganggap dashboard sebagai ledger akuntansi immutable.

## 10. Keamanan, deployment, dan batasan

Bootstrap migration marketplace jasa harus diterapkan berurutan. Migration state machine terbaru adalah [`40_20260925100000_service_transaction_state_machine.sql`](../supabase/bootstrap/40_20260925100000_service_transaction_state_machine.sql); migration tersebut bergantung pada schema jasa, role provider, dan dispute yang dibuat oleh migration sebelumnya. Ikuti urutan di `supabase/bootstrap/manifest.json` dan jalankan lebih dahulu pada staging. Perubahan di repository tidak otomatis mengubah database Supabase live.

Authenticated user tidak memiliki DML langsung pada `service_requests`, `service_payment_proofs`, `service_payouts`, `service_disputes`, `service_profiles`, `service_skills`, dan `service_refunds`. Transaksi sensitif menggunakan RPC dengan row lock dan pemeriksaan aktor. Pesan tetap memakai insert langsung yang dibatasi RLS peserta. Fungsi admin memeriksa role admin di database.

Belum tersedia payment gateway jasa, transfer otomatis, refund gateway otomatis, timeout pembayaran, auto-cancel, auto-confirmation, maupun ledger finansial immutable. Kategori `Jasa Sewa` masih memakai alur request yang sama dan belum memiliki jadwal sewa, deposit, serah-terima, atau pengembalian aset khusus. Verifikasi migration dan RLS pada staging tetap diperlukan sebelum aktivasi produksi.

## 11. Laporan dan penanganan error

Tab **Laporan bulanan** di `/admin/services` mengelompokkan bukti `VERIFIED` berdasarkan bulan `created_at`. Payout dikelompokkan berdasarkan `released_at`, atau `created_at` jika belum dilepas. CSV memuat tanggal, request ID, pekerjaan, nominal transaksi, fee admin, biaya transfer, nilai bersih provider, dan status payout. Karena rekap menggabungkan tanggal bukti dengan tanggal payout, gunakan laporan sebagai alat operasional dan rekonsiliasikan setiap pembayaran terhadap catatan transfer eksternal.

Setiap pemanggilan Supabase harus memeriksa `error`. Tampilkan pesan validasi yang relevan kepada pengguna; jangan mengulang operasi transfer akibat timeout. RPC yang diulang hanya aman sesuai guard transaksi masing-masing, dan referensi payout/refund harus menunjuk transaksi eksternal yang benar-benar terjadi. UI admin juga menulis audit action untuk review bukti, provider, payout, serta keputusan dan refund sengketa.

## 12. Referensi implementasi

| Komponen | Lokasi |
|---|---|
| Skema awal marketplace | [`supabase/bootstrap/36_20260925010000_service_marketplace.sql`](../supabase/bootstrap/36_20260925010000_service_marketplace.sql) |
| Sengketa dan role provider | [`supabase/bootstrap/37_20260925011000_service_disputes.sql`](../supabase/bootstrap/37_20260925011000_service_disputes.sql), [`supabase/bootstrap/38_20260925020000_service_provider_role.sql`](../supabase/bootstrap/38_20260925020000_service_provider_role.sql) |
| RPC dan hardening transaksi | [`supabase/bootstrap/39_20260925030000_service_transaction_hardening.sql`](../supabase/bootstrap/39_20260925030000_service_transaction_hardening.sql), [`supabase/bootstrap/40_20260925100000_service_transaction_state_machine.sql`](../supabase/bootstrap/40_20260925100000_service_transaction_state_machine.sql) |
| Katalog dan profil jasa | [`src/pages/ServicesPage.tsx`](../src/pages/ServicesPage.tsx) |
| Riwayat buyer | [`src/pages/ServiceRequestsPage.tsx`](../src/pages/ServiceRequestsPage.tsx) |
| Riwayat provider | [`src/pages/ServiceProviderHistoryPage.tsx`](../src/pages/ServiceProviderHistoryPage.tsx) |
| Admin escrow dan dispute | [`src/pages/admin/AdminServicesPage.tsx`](../src/pages/admin/AdminServicesPage.tsx), [`src/pages/admin/AdminServiceDisputesPage.tsx`](../src/pages/admin/AdminServiceDisputesPage.tsx) |

## References

[1]: https://supabase.com/docs/guides/database/postgres/row-level-security "Supabase Row Level Security"
[2]: https://supabase.com/docs/reference/javascript/rpc "Supabase JavaScript rpc()"
[3]: https://supabase.com/docs/guides/storage/access-control "Supabase Storage Access Control"
[4]: https://supabase.com/docs/guides/auth/sessions "Supabase Auth Sessions"
