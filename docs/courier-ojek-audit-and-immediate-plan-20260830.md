# Audit Fitur Kurir Ojek dan Rencana Perbaikan Segera

**Tanggal audit:** 30 Agustus 2026  
**Ruang lingkup:** penerimaan permintaan ojek, transisi status perjalanan, pendapatan, penarikan saldo, notifikasi, lokasi, dispatch kurir, RLS, RPC, dan kesiapan pengujian.

## Ringkasan eksekutif

Audit menemukan beberapa risiko **P0/P1** pada jalur finansial dan otorisasi backend. Permintaan ojek memang memiliki RPC `accept_ride` yang melakukan update atomik berdasarkan status `SEARCHING`, sehingga dua kurir tidak seharusnya memenangkan ride yang sama. Namun, RPC tersebut berjalan sebagai `SECURITY DEFINER` dan tidak memvalidasi bahwa `p_courier_id` milik pengguna yang memanggil, berstatus `APPROVED`, `ACTIVE`, dan `is_available = true`. Akibatnya, pengguna terautentikasi berpotensi menerima ride atas nama kurir lain dengan memanggil RPC secara langsung.

Selain itu, perubahan status ride dan pencatatan pendapatan dilakukan dari browser dalam dua operasi terpisah. Nilai `final_fare` dan nominal `courier_earnings` berasal dari state frontend, bukan dihitung dan dicatat oleh transaksi server. Retry, refresh, atau manipulasi request dapat menghasilkan pendapatan ganda atau nominal yang tidak sesuai. Pengajuan withdrawal juga hanya divalidasi di browser; belum terlihat RPC atomik untuk melakukan reservasi saldo, sehingga beberapa pengajuan bersamaan berpotensi melewati saldo tersedia.

Notifikasi in-app untuk ride dibuat melalui trigger database dan realtime, tetapi push notification menggunakan endpoint `/api/*` lama yang menurut dokumentasi deployment tidak tersedia pada aplikasi SPA saat ini. Di sisi operasional, subscription realtime kurir tidak diberi filter `courier_id`, sehingga semua perubahan `ride_requests` dapat memicu invalidasi query pada semua kurir yang sedang membuka halaman. Terdapat pula ketidakkonsistenan status aktif antara dispatch (`ON_DELIVERY`) dan dashboard (`SENT`, `DELIVERING`), yang dapat menyebabkan kapasitas kurir dihitung salah.

## Temuan prioritas

| ID | Prioritas | Area | Temuan | Dampak |
|---|---|---|---|---|
| OJK-01 | **P0** | Otorisasi penerimaan ride | `accept_ride(p_ride_id, p_courier_id)` hanya memeriksa `status = SEARCHING` dan `driver_id IS NULL`; tidak memeriksa hubungan `p_courier_id` dengan `auth.uid()` maupun status kurir. | Pengguna terautentikasi dapat berpotensi menetapkan ride ke kurir lain atau kurir nonaktif melalui pemanggilan RPC langsung. |
| OJK-02 | **P0** | Pendapatan | Saat ride selesai, browser mengubah ride lalu melakukan insert ke `courier_earnings` secara terpisah. `final_fare` dan `amount` menggunakan `estimated_fare` dari frontend. | Manipulasi nominal, pendapatan ganda saat retry, dan ride selesai tanpa ledger atau ledger tanpa ride. |
| OJK-03 | **P0** | Withdrawal/saldo | Validasi saldo dan saldo minimum hanya di `CourierWithdrawalPage.tsx`; insert withdrawal tidak mengunci saldo atau membuat reservasi atomik. | Double spending melalui beberapa request paralel; saldo dan total penarikan dapat tidak konsisten. |
| OJK-04 | **P1** | Transisi status | Policy update ride hanya memiliki `USING` untuk driver lama dan tidak memiliki `WITH CHECK`; frontend mengirim status string secara langsung tanpa enforcement state machine server. | Driver yang sah berpotensi mengubah status ke status ilegal atau mengubah kolom lain melalui direct API; status dapat melompati tahapan. |
| OJK-05 | **P1** | Dispatch | `assign-courier` tidak memvalidasi status order sebagai status yang boleh di-assign. Perhitungan order aktif memakai `ASSIGNED`, `PICKED_UP`, `ON_DELIVERY`, sedangkan dashboard memakai `SENT`/`DELIVERING`. | Order terminal berpotensi di-assign; kapasitas kurir bisa dihitung terlalu rendah dan kurir menerima terlalu banyak pekerjaan. |
| OJK-06 | **P1** | Daftar ride | Query available rides mengambil seluruh `SEARCHING` ride dan hanya mengandalkan RLS; tidak ada filter radius di query/UI selain informasi jarak. | Beban query meningkat dan kurir melihat permintaan yang jauh; keputusan penerimaan menjadi tidak efisien. |
| OJK-07 | **P1** | Notifikasi | Trigger DB membuat notifikasi in-app untuk kurir yang online, tetapi push hook memakai `/api/vapid-public-key`, `/api/subscribe`, dan `/api/unsubscribe`. Dokumentasi deployment menyatakan bridge `/api/*` tidak aktif pada container SPA. | Kurir dapat tidak menerima push saat tab/background tertutup; penerimaan ride hanya bergantung pada realtime dan polling. |
| OJK-08 | **P1** | Realtime | `CourierRidesPage` berlangganan seluruh event `ride_requests` tanpa filter driver/status. | Setiap perubahan ride di sistem meng-invalidasi query semua kurir; noise, beban database, dan potensi stale state. |
| OJK-09 | **P1** | Lokasi & online state | Toggle `is_available` tidak mengaktifkan/menonaktifkan tracking secara terikat. Tracking dipulihkan dari localStorage, sementara checkpoint DB hanya tiap 30 detik. | Dispatch dapat memakai lokasi stale; kurir tampak online tetapi tidak mengirim lokasi, atau lokasi tetap dibagikan setelah offline. |
| OJK-10 | **P2** | Laporan pendapatan | Statistik menjumlahkan seluruh `courier_earnings`, termasuk status selain `PAID`, dan menghitung `totalDeliveries` sebagai jumlah semua ledger sehingga ride dan delivery tercampur. Batas waktu memakai zona waktu browser. | Angka “pendapatan” dapat menampilkan pending/rejected sebagai pendapatan; rekonsiliasi harian berbeda antar zona waktu. |
| OJK-11 | **P2** | Observability | Banyak operasi Supabase mengabaikan `error` dan tidak ada correlation/idempotency key untuk acceptance, completion, earning, dan withdrawal. | Insiden sulit dilacak dan UI dapat menampilkan keadaan sukses parsial. |
| OJK-12 | **P2** | Akses halaman | Sebagian route kurir hanya memakai `ProtectedRoute`; validasi approved dilakukan di halaman masing-masing, bukan satu guard konsisten. | Pengalaman pengguna tidak seragam dan request sensitif tetap dapat dicoba sebelum redirect. |

## Bukti implementasi utama

| Komponen | Bukti | Interpretasi audit |
|---|---|---|
| Penerimaan ride | `src/pages/courier/CourierRidesPage.tsx:183-200` memanggil `accept_ride` dengan `courierId` dari frontend. | RPC harus menjadi sumber otoritas; parameter courier ID dari klien tidak boleh dipercaya. |
| RPC acceptance | `supabase/bootstrap/05_20260220105922_to_20260502035656.sql:1034-1070` melakukan update atomik, tetapi tidak melakukan validasi caller/courier. | Race condition sebagian tertangani, authorization belum tertangani. |
| Status & earning ride | `src/pages/courier/CourierRidesPage.tsx:202-225` update status, lalu insert earnings pada completion. | Dua operasi non-atomik dan nominal berasal dari `activeRide.estimated_fare`. |
| Policy ride | `supabase/bootstrap/05_20260220105922_to_20260502035656.sql:976-988` hanya memakai `USING` untuk driver lama. | Perlu `WITH CHECK` dan fungsi state transition terkontrol. |
| Withdrawal | `src/pages/courier/CourierWithdrawalPage.tsx:93-117` memvalidasi saldo di browser lalu insert request. | Perlu RPC server-side dengan row lock/reservasi saldo dan idempotency. |
| Dispatch | `supabase/functions/assign-courier/index.ts:101-142` tidak memfilter status order yang valid; `:183-219` memakai status aktif yang tidak sama dengan dashboard. | Status order harus dikonsolidasikan dalam enum/konstanta server. |
| Available rides | `src/pages/courier/CourierRidesPage.tsx:101-130` query seluruh `SEARCHING`; `:137-147` realtime tanpa filter. | Perlu filter server dan subscription yang lebih sempit. |
| Notifikasi | `supabase/bootstrap/05_20260220105922_to_20260502035656.sql:1138-1170` membuat in-app notifications; `src/hooks/usePushNotification.ts:51-121` memakai `/api/*`. | Jalur in-app dan push belum memiliki satu delivery contract yang konsisten. |
| Lokasi | `src/components/CourierLocationUpdater.tsx:33-49` update location; `:120-125` checkpoint 30 detik; `:160-169` restore tracking dari localStorage. | Perlu TTL lokasi dan coupling dengan availability. |
| Pendapatan delivery | `supabase/functions/assign-courier/index.ts:279-295` menghitung 80% shipping dan insert pending earning setelah assignment. | Earning dibuat terlalu awal, terpisah dari proof/status completion, dan tidak dijaga idempotensi. |

## Rencana perbaikan segera

### Fase 0: containment dalam 0–24 jam

Pertama, batasi permukaan serangan finansial dan acceptance. Cabut akses execute publik terhadap RPC lama bila memungkinkan tanpa mematikan operasional, lalu ganti dengan RPC baru yang mengambil courier dari `auth.uid()` dan mengabaikan `p_courier_id` dari klien. RPC harus mengunci row ride dengan `FOR UPDATE`, memvalidasi `SEARCHING`, memvalidasi courier `APPROVED + ACTIVE + is_available`, memastikan belum memiliki active ride melebihi batas, kemudian mengubah driver dan status dalam satu transaksi.

Kedua, hentikan insert `courier_earnings` dari browser. Untuk sementara, earning baru sebaiknya hanya dibuat oleh RPC completion server-side yang memeriksa driver owner, status sebelumnya, proof of delivery atau syarat penyelesaian, menghitung fare dari data server, dan memakai unique idempotency constraint berdasarkan `(type, ride/order reference)`. Ledger lama perlu diperiksa untuk duplikasi sebelum pembayaran diproses.

Ketiga, tahan sementara pengajuan withdrawal apabila belum ada worker/admin flow yang benar-benar memprosesnya. Setelah itu, implementasikan `request_courier_withdrawal` sebagai RPC atomik yang mengunci courier row, memeriksa `available_balance - pending reservations`, membuat request PENDING, mengurangi atau mereservasi saldo, dan menulis `courier_balance_logs`. Semua keputusan admin harus memakai fungsi transaksi yang mengembalikan saldo atau menyelesaikan penarikan satu kali.

### Fase 1: hardening dalam 1–3 hari

Buat satu state machine resmi untuk ride: `SEARCHING → ACCEPTED → PICKED_UP → IN_TRANSIT → COMPLETED`, dengan jalur `SEARCHING/ACCEPTED/PICKED_UP/IN_TRANSIT → CANCELLED` hanya sesuai aktor dan alasan yang sah. Implementasikan RPC `transition_ride_status` dengan pemeriksaan actor, previous status, timestamp, dan final fare. Tambahkan `WITH CHECK` atau tutup direct UPDATE pada `ride_requests` agar client hanya dapat memanggil RPC.

Konsolidasikan status order delivery. Pilih satu istilah canonical—misalnya `ASSIGNED`, `PICKED_UP`, `DELIVERING`, `DELIVERED`, `CANCELLED`—dan gunakan istilah itu di dashboard, dispatch, policy, laporan, dan trigger. Tambahkan pemeriksaan status order yang boleh di-assign di `assign-courier`, serta gunakan update conditional berdasarkan status sebelumnya agar assignment ulang menghasilkan konflik yang dapat ditangani UI.

Perbaiki notifikasi dengan satu jalur resmi. In-app notification harus dibuat idempotent berdasarkan event ID; realtime subscription harus difilter pada user/courier yang relevan; push harus dikirim melalui Edge Function yang tersedia, bukan endpoint `/api/*` legacy. Setiap kegagalan push harus dicatat sebagai delivery failure dan subscription 404/410 harus dibersihkan.

Ikatan availability dan tracking juga perlu diperjelas. Saat kurir offline, hentikan watcher dan hapus/invalidasi lokasi setelah TTL, misalnya 2–5 menit. Dispatch hanya boleh memakai courier yang `is_available = true` dan `last_location_update` masih segar. Saat halaman dimuat dengan state tracking lama, verifikasi kembali status server sebelum memulai tracking.

### Fase 2: rekonsiliasi dalam 3–7 hari

Buat ledger sebagai sumber kebenaran tunggal. `courier_earnings` perlu memiliki referensi wajib ke ride atau order, tipe event yang terbatas, status pembayaran yang tervalidasi, dan constraint unik untuk mencegah duplikasi. `available_balance`, `pending_balance`, dan `total_withdrawn` harus diperbarui hanya melalui fungsi transaksi; jangan mengandalkan kalkulasi frontend.

Pisahkan metrik `gross`, `pending`, `paid`, `reversed`, dan `withdrawn`. Tentukan timezone bisnis, simpan semua timestamp dalam UTC, dan agregasikan laporan dengan timezone bisnis yang eksplisit. Laporan “total perjalanan” harus menghitung ride completed, bukan jumlah semua ledger.

Tambahkan observability untuk setiap event penting: `ride_id`, `courier_id`, `actor_user_id`, previous status, next status, fare, idempotency key, request ID, dan hasil notifikasi. Dashboard admin perlu menyediakan daftar stuck rides, stale couriers, failed notification, pending withdrawals, dan earning entries tanpa reference.

## Desain acceptance criteria

| Skenario | Hasil yang harus diterima |
|---|---|
| Dua kurir menerima ride yang sama | Tepat satu RPC berhasil; satu lagi menerima konflik/idempotent false; hanya satu `driver_id` tercatat. |
| User memanggil RPC memakai courier ID orang lain | Ditolak dengan 403/authorization error; tidak ada perubahan ride. |
| Kurir offline/nonaktif mencoba accept | Ditolak; tidak ada assignment. |
| Completion diulang 5 kali | Tepat satu completion dan tepat satu earning ledger. |
| Completion dengan fare yang dimanipulasi | Server menolak atau menghitung ulang dari server-side fare policy. |
| Dua withdrawal paralel melebihi saldo | Hanya jumlah yang masih memenuhi saldo yang berhasil; sisanya ditolak secara atomik. |
| Driver mengirim status loncat, misalnya SEARCHING → COMPLETED | Ditolak; status tetap sebelumnya. |
| Order `DELIVERING` dihitung kapasitasnya | Dihitung sebagai active order pada dispatch. |
| Lokasi lebih tua dari TTL | Kurir tidak menjadi kandidat dispatch sampai lokasi diperbarui. |
| Push subscription invalid | Delivery ditandai gagal dan subscription 404/410 dibersihkan. |
| Notifikasi realtime pada ride kurir lain | Tidak meng-invalidasi query kurir yang tidak terkait. |
| RLS smoke test | Buyer, courier, merchant, admin, dan anonymous diuji pada SELECT/INSERT/UPDATE tiap tabel sensitif. |

## Urutan eksekusi yang direkomendasikan

Prioritas eksekusi adalah **OJK-01, OJK-02, dan OJK-03** sebelum fitur diperluas atau dipromosikan sebagai sistem pendapatan. Setelah itu kerjakan **OJK-04 sampai OJK-09** untuk menjaga integritas status, kapasitas dispatch, notifikasi, dan lokasi. **OJK-10 sampai OJK-12** dapat dikerjakan bersamaan sebagai fase rekonsiliasi dan quality improvement.

Sebelum rollout, jalankan migration di staging, lakukan concurrency test untuk acceptance dan withdrawal, lakukan RLS/API smoke test dengan role matrix, verifikasi notification delivery pada foreground/background, dan lakukan pilot terbatas dengan akun kurir uji. Jangan menganggap UI validation sebagai kontrol keamanan; seluruh kontrol nominal, ownership, status, dan idempotensi wajib berada di database/RPC atau Edge Function.

## Status audit

Audit ini merupakan audit statis terhadap source frontend, Edge Function, migration/bootstrap SQL, policy, dan konfigurasi route. Belum ada perubahan kode fitur kurir pada audit ini dan belum ada E2E production karena sesi kurir terautentikasi tidak tersedia. Rencana di atas dapat langsung dijadikan backlog P0/P1 untuk implementasi berikutnya.
