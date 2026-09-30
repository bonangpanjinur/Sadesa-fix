# Ringkasan Audit dan Rencana Perbaikan Keseluruhan SaDesa

**Tanggal:** 11 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** keamanan dan otorisasi, transaksi marketplace, pembayaran dan refund, alur ojek/kurir, rating, chat realtime, UI/UX responsif, cart/checkout, dependency, testing, dan kesiapan deployment.

## 1. Kesimpulan eksekutif

SaDesa memiliki banyak fondasi backend yang sudah benar, tetapi kesiapan sistem belum merata. **Marketplace order dan courier fulfillment** sudah bergerak ke arah server-authoritative. Sebaliknya, **alur ojek penumpang, chat realtime, dan sebagian besar pengalaman mobile** masih memiliki gap yang dapat terlihat langsung oleh pengguna atau berdampak pada integritas transaksi.

Prioritas utama bukan menambah fitur baru. Prioritas utama adalah memastikan setiap aksi penting memiliki satu sumber kebenaran di server, setiap kegagalan memiliki recovery, dan setiap halaman penting dapat digunakan dengan nyaman pada layar kecil.

Tiga risiko tertinggi saat ini adalah sebagai berikut:

1. **Mutasi ride ojek masih dapat dilakukan melalui direct update berbasis RLS**, sehingga state, driver, tarif, timestamp, dan rating belum dikunci oleh state machine server-side.
2. **Chat realtime belum memiliki recovery lifecycle yang lengkap**. Subscription sudah ada, tetapi channel yang gagal tidak otomatis melakukan resubscribe dan gap recovery sehingga pengguna perlu reload.
3. **Booking kurir belum menyelesaikan transaksi**. Halaman telah mengumpulkan data pickup, tujuan, penerima, dan paket, tetapi belum membuat order atau melakukan dispatch.

Selain itu, audit transaksi sebelumnya menemukan risiko deployment dan settlement yang harus dipastikan tertutup di database target, termasuk authoritative distance checkout, idempotensi invoice, serta refund provider/ledger.

> **Keputusan readiness:** SaDesa belum layak mendapat production sign-off penuh untuk alur ojek penumpang. Marketplace courier dapat dilanjutkan ke staging verification setelah migration gate, dynamic RLS test, dan settlement test lulus.

## 2. Status keseluruhan per domain

| Domain | Status | Penilaian |
|---|---|---|
| Auth dan role management | Perlu verifikasi staging | Kontrol source sudah diperketat, tetapi RLS matrix dengan beberapa role belum lengkap. |
| Marketplace checkout/order | Perlu hardening | Checkout authoritative sudah tersedia pada migration terbaru; perlu pembuktian rollback, stok, dan deployment. |
| Payment/invoice | Risiko tinggi bersyarat | Idempotensi invoice dan recovery provider harus diuji concurrency serta rekonsiliasi. |
| Refund/settlement | Risiko tinggi bersyarat | State settlement provider harus benar-benar terhubung sebelum dana dianggap refunded. |
| Courier marketplace | Cukup baik secara desain | Offer, assignment, transisi, rating, dan batas 10 km tersedia; perlu dynamic test. |
| Ojek penumpang | Belum production-ready | Direct update, rating langsung, acceptance parameter, dan batas jarak belum cukup terlindungi. |
| Booking kurir | Belum selesai secara fungsional | UI belum membuat order atau dispatch. |
| Chat realtime | Belum production-ready | Subscription ada, tetapi retry, resubscribe, gap recovery, dan fallback belum lengkap. |
| UI/UX mobile kurir/ojek | Perlu redesign terarah | Fixed/sticky, breakpoint, peta, kartu action, dan safe-area belum seragam. |
| Cart/checkout frontend | Perlu perbaikan prioritas | Audit menemukan risiko multi-merchant, total selection, Buy Now, error state, dan fixed bar. |
| Dependency | Terkendali | Tidak ditemukan High/Critical; lockfile dan package manager perlu dikonsolidasikan. |
| Quality gate | Sebagian lulus | Build dan test lulus; dynamic staging, visual regression, dan concurrency belum cukup. |

## 3. Temuan lintas sistem yang harus menjadi prinsip perbaikan

### 3.1 Server harus menjadi sumber kebenaran

Client hanya boleh mengirim intent dan data input. Server harus menghitung ulang jarak, tarif, status pembayaran, eligibility, stok, refund state, dan role-sensitive transition. Field seperti `distance_km`, `shipping_cost`, `total`, `driver_id`, `status`, dan `rating` tidak boleh dipercaya hanya karena dikirim dari browser.

### 3.2 Setiap state penting harus memiliki transisi eksplisit

Order, ride, courier assignment, payment, invoice, refund, dan chat delivery membutuhkan state machine. Direct table update dari client harus dicabut atau dibatasi dengan grant column-level yang sangat sempit.

### 3.3 Setiap operasi eksternal harus idempotent

Panggilan payment provider, invoice, refund, notification, dispatch, dan message send harus memiliki idempotency key yang durable. Retry tidak boleh membuat invoice, refund, order, atau message duplikat.

### 3.4 Kegagalan harus terlihat dan dapat dipulihkan

UI harus membedakan loading, empty, error, offline, stale, dan success. Chat harus otomatis reconnect. Checkout harus memiliki retry yang aman. Order yang gagal sebagian harus memiliki recovery atau rollback yang dapat dibuktikan.

### 3.5 Deployment harus dibuktikan, bukan diasumsikan

Source migration terbaru tidak cukup. Migration 47, 48, 49, 50, 51, migration chat, privilege revocation, publication Realtime, trigger, dan RPC harus diverifikasi langsung di staging/production target.

## 4. Rencana perbaikan per fase

## Fase 0 — Baseline, freeze scope, dan production gates

**Tujuan:** membuat baseline yang dapat dipercaya sebelum mengubah banyak area sekaligus.

| Pekerjaan | Hasil wajib |
|---|---|
| Tetapkan staging database dengan data fixture dua buyer, merchant, courier, admin, dan provider sandbox | Semua dynamic test dapat dijalankan berulang |
| Catat migration yang sudah diterapkan dan checksum bundle | Tidak ada asumsi antara source dan database target |
| Buat backup dan restore drill sebelum migration kritis | Rollback operasional terbukti |
| Tambahkan environment check untuk Supabase URL/key, Realtime, storage, payment provider, dan notification worker | Konfigurasi incomplete gagal lebih awal |
| Tetapkan satu package manager resmi, yaitu pnpm, dan pisahkan atau hapus lockfile npm setelah review | Instalasi CI reproducible |
| Buat dashboard minimal untuk error checkout, payment, refund, dispatch, chat channel, dan message latency | Masalah dapat dilihat tanpa membaca console pengguna |
| Freeze fitur baru yang menyentuh order/payment/ride/chat sampai P0 selesai | Scope dan risiko terkendali |

**Gate keluar Fase 0:** migration inventory lengkap, restore drill lulus, staging fixture siap, observability dasar aktif, dan CI menggunakan `pnpm install --frozen-lockfile`.

## Fase 1 — Otorisasi dan integritas transaksi

**Tujuan:** menutup jalur manipulasi langsung dan memastikan uang, stok, jarak, dan state tidak dapat dipalsukan dari client.

### Ojek penumpang

1. Cabut direct `UPDATE` `ride_requests` dari buyer dan courier.
2. Implementasikan `create_ride_request` untuk validasi koordinat, jarak, tarif, passenger, dan status awal.
3. Implementasikan `cancel_ride` untuk ownership, status yang diperbolehkan, dan aturan pembatalan.
4. Implementasikan `transition_ride_status` dengan urutan `SEARCHING -> ACCEPTED -> PICKED_UP -> IN_TRANSIT -> COMPLETED`.
5. Ubah `accept_ride` menjadi `accept_ride(p_ride_id)` atau validasi `p_courier_id` terhadap `auth.uid()`, status approved, active, dan available.
6. Tambahkan audit history untuk create, accept, pickup, transit, complete, cancel, dan rating.

### Rating

1. Buat `submit_ride_rating` melalui RPC.
2. Pastikan hanya passenger yang memiliki ride dapat memberi rating.
3. Izinkan rating hanya setelah status selesai.
4. Batasi nilai 1–5 dan satu rating per ride.
5. Pisahkan rating ride dari rating marketplace courier bila domain datanya berbeda.

### Marketplace checkout dan order

1. Pastikan checkout hanya melalui RPC authoritative.
2. Pastikan jarak dihitung dari koordinat merchant dan tujuan di server.
3. Tolak koordinat null, invalid, atau jarak yang tidak wajar.
4. Pastikan trigger batas internal delivery memakai jarak server-side, bukan nilai client.
5. Uji rollback jika reservation stok gagal setelah order mulai dibuat.
6. Uji multi-merchant dan pastikan order/ongkir tidak menghasilkan partial success yang tidak terdokumentasi.

### Payment, invoice, dan refund

1. Gunakan idempotency key durable pada level order/payment request.
2. Sebelum membuat invoice provider baru, cari dan recovery invoice provider yang sudah tercipta.
3. Pisahkan state `provider_pending`, `provider_paid`, `provider_failed`, dan `provider_unknown`.
4. Pisahkan refund decision dari refund settlement provider.
5. Jangan menandai order `REFUNDED` atau mengurangi saldo merchant sebelum provider mengonfirmasi refund.
6. Buat ledger dan settlement reference yang idempotent.
7. Sinkronkan `payment_status`, `order.status`, refund status, dan webhook reconciliation.

**Gate keluar Fase 1:** seluruh abuse test buyer/courier/admin lulus; dua request concurrent menghasilkan satu order/invoice/acceptance; checkout jarak palsu ditolak atau dihitung ulang; refund pending tidak mengubah status dana selesai.

## Fase 2 — Penyelesaian alur bisnis kurir dan ojek

**Tujuan:** memastikan setiap flow dari pemesanan hingga selesai benar-benar dapat digunakan tanpa dead end.

### Booking kurir

1. Hubungkan `CourierBookingPage` ke RPC create-order yang authoritative.
2. Simpan pickup, tujuan, penerima, paket, berat, COD, dan koordinat tervalidasi.
3. Pilih `INTERNAL` atau `EXPEDITION` berdasarkan batas 10 km dan wilayah.
4. Jalankan dispatch melalui offer/assignment yang idempotent.
5. Tampilkan status `Menunggu dispatch`, `Ditawarkan`, `Diterima`, `Diambil`, `Dalam perjalanan`, dan `Terkirim`.
6. Cegah double submit dan pastikan retry mengembalikan order yang sama.

### Courier fulfillment

1. Pastikan hanya courier yang ditugaskan dapat melihat detail sensitif lengkap.
2. Gunakan RPC untuk accept/reject offer, pickup, sent, delivered, cancel, dan proof of delivery.
3. Pastikan COD reconciliation dan proof of delivery terhubung dengan status order.
4. Tampilkan next action yang jelas pada dashboard courier.
5. Tambahkan aturan timeout offer dan fallback dispatch bila courier menolak atau tidak merespons.

### Batas jarak

1. Terapkan batas 10 km pada internal delivery secara server-side.
2. Terapkan batas jarak ride ojek penumpang sesuai kebijakan operasional yang disepakati.
3. Bandingkan wilayah administratif bila metadata tersedia.
4. Tampilkan alasan penolakan yang jelas dan arahkan ke `EXPEDITION` jika relevan.
5. Simpan `server_distance_km` untuk audit dan rekonsiliasi tarif.

**Gate keluar Fase 2:** buyer dapat membuat ride dan order kurir sampai selesai; courier dapat menerima dan menyelesaikan assignment; pickup, delivery, rating, COD, dan proof of delivery tercatat; tidak ada halaman yang berhenti pada toast “belum tersedia”.

## Fase 3 — Chat realtime, notifikasi, dan komunikasi operasional

**Tujuan:** membuat chat benar-benar realtime dalam kondisi normal dan tahan gangguan koneksi.

### Implementasi client

1. Buat `useChatRealtime` atau `subscribeWithRetry` yang mengelola channel lifecycle.
2. Retry status `CHANNEL_ERROR`, `TIMED_OUT`, dan `CLOSED` dengan exponential backoff.
3. Hentikan channel lama sebelum membuat channel baru.
4. Setelah reconnect, lakukan full sync dari cursor terakhir.
5. Deduplicate berdasarkan message ID dan client message ID.
6. Tambahkan polling fallback 10–15 detik saat Realtime tidak tersambung.
7. Bersihkan timer dan channel ketika conversation berubah atau component unmount.

### Verifikasi backend

1. Pastikan `chat_messages` terdaftar di publication `supabase_realtime`.
2. Pastikan RLS SELECT mengizinkan kedua participant menerima event.
3. Pastikan trigger notification tidak menggagalkan insert message.
4. Pastikan notification idempotent dan deep link benar untuk buyer, merchant, dan courier.
5. Batasi retry agar tidak membuat channel storm.

### UX dan observability

1. Tampilkan `Tersambung`, `Menghubungkan ulang`, dan `Offline` secara jujur.
2. Tampilkan tombol manual `Coba sambungkan lagi` bila retry gagal.
3. Tampilkan pesan pending/failed pada sender.
4. Ukur p95 message latency, reconnect time, channel error rate, dan fallback polling count.
5. Target koneksi normal: pesan tampil di participant lain tanpa reload dengan p95 kurang dari 2 detik.

**Gate keluar Fase 3:** dua akun dapat mengirim pesan tanpa reload; pesan tetap pulih setelah disconnect/reconnect; pesan tidak hilang atau duplikat; staging test publication/RLS lulus.

## Fase 4 — Perbaikan UI/UX responsif kurir dan ojek

**Tujuan:** membuat alur operasional nyaman digunakan di perangkat lapangan.

### Sistem layout

1. Ganti layout viewport kritis dari `h-screen` ke `min-h-[100dvh]` bila sesuai.
2. Satukan token tinggi bottom navigation, floating cart, sticky action, safe-area, dan padding bawah.
3. Pastikan hanya satu container utama yang mengontrol vertical scrolling.
4. Gunakan `env(safe-area-inset-bottom)` pada perangkat dengan home indicator.
5. Hindari `body { overflow-x: hidden }` sebagai solusi umum untuk komponen yang overflow.

### Kartu order dan dashboard courier

1. Pada mobile, susun harga dan status di baris pertama.
2. Susun tombol peta dan accept di baris kedua.
3. Gunakan `flex-wrap`, `min-w-0`, dan `truncate` secara eksplisit.
4. Pastikan target tap minimum 44×44 px.
5. Prioritaskan order aktif dan next action di atas metrik historis.
6. Ubah statistik menjadi `grid-cols-1`, `grid-cols-2`, atau `grid-cols-3` sesuai breakpoint.

### Peta dan tracking

1. Gunakan tinggi peta responsif berbasis `dvh`.
2. Uji peta pada layar pendek dan tinggi.
3. Pastikan panel status tidak menutup peta atau CTA.
4. Tampilkan status GPS, akurasi, last update, dan error secara eksplisit.
5. Pastikan tracking berhenti dan cleanup saat order selesai atau user keluar.

### Device matrix

Uji minimal pada ukuran 320×568, 375×667, 390×844, 414×896, 768×1024, dan desktop 1280 px. Uji portrait dan landscape untuk halaman operasional penting.

**Gate keluar Fase 4:** tidak ada clipping horizontal, CTA tertutup, tombol terpotong, atau peta yang menghilangkan action utama pada device matrix.

## Fase 5 — Cart, checkout frontend, dan konsistensi pengalaman buyer

**Tujuan:** menghilangkan kebingungan nominal, selection, merchant, error, dan fixed action pada pembeli.

1. Kelompokkan cart berdasarkan `merchant_id`, bukan nama merchant.
2. Pastikan “pilih semua” mengikuti scope merchant yang terlihat.
3. Gunakan sumber total yang sama pada cart, floating cart, dan checkout.
4. Pisahkan flow `Buy Now` dari selection cart biasa.
5. Batasi atau definisikan kontrak multi-merchant checkout dengan jelas.
6. Tampilkan state error dan tombol retry pada product, cart, checkout, account, dan discovery.
7. Tampilkan perubahan harga/stok dengan jalur pemulihan.
8. Implementasikan pagination/infinite query untuk katalog yang lebih besar dari batas awal.
9. Pastikan filter dan sort benar-benar memengaruhi hasil.
10. Satukan fixed bar dan safe-area dengan aturan Fase 4.
11. Tambahkan loading guard agar metode pembayaran tidak terlihat valid sebelum konfigurasi selesai.

**Gate keluar Fase 5:** total dan selection konsisten; multi-merchant tidak menghasilkan perilaku ambigu; Buy Now tidak membawa item lain; error dapat dipulihkan; fixed bar tidak menghalangi input.

## Fase 6 — Quality engineering, observability, dan hardening

**Tujuan:** mencegah regresi dan mengubah audit manual menjadi quality gate otomatis.

### Test layer

| Layer | Cakupan minimum |
|---|---|
| Unit | Fee engine, distance, delivery restriction, state transition, rating validation, idempotency key |
| Component | Courier card, status card, sticky action, chat state, error/retry, cart selection |
| Integration | Two-user chat, RLS matrix, concurrent acceptance, checkout rollback, payment retry, refund settlement |
| E2E | Ride penuh, courier order penuh, payment success/failure, COD, rating, reconnect chat |
| Visual regression | Device matrix pada halaman courier, ride, chat, cart, checkout |
| Load/concurrency | Acceptance race, invoice retry, webhook duplicate, message burst, dispatch offer |

### Quality gate CI

CI wajib menjalankan:

```bash
pnpm install --frozen-lockfile
pnpm test -- --run
pnpm run build
pnpm exec eslint . --max-warnings=0
pnpm run validate:package-manager
pnpm audit --audit-level high
```

Audit dependency terakhir tidak menemukan High/Critical. Advisory tooling pada `esbuild` dan `@humanfs/node` telah memiliki remediation pada lockfile menurut laporan dependency, tetapi hasil tersebut harus tetap dipantau berkala.

### Observability

Tambahkan correlation ID untuk order, ride, payment request, provider invoice, refund settlement, dispatch offer, dan chat message. Simpan actor, transition, timestamp, previous state, new state, error code, dan provider reference. Sediakan alert untuk payment mismatch, refund pending terlalu lama, order tanpa courier, channel chat error berulang, dan message latency tinggi.

**Gate keluar Fase 6:** seluruh test kritis berjalan di CI; dynamic staging test lulus; visual regression baseline tersedia; alert operasional dapat ditindaklanjuti.

## Fase 7 — Pilot terbatas dan rollout bertahap

**Tujuan:** memvalidasi perilaku nyata sebelum membuka seluruh traffic.

1. Jalankan pilot dengan jumlah merchant dan courier terbatas.
2. Aktifkan feature flag untuk ride, courier booking, chat retry, dan settlement worker.
3. Pantau success rate checkout, order completion, dispatch acceptance, pickup SLA, delivery SLA, rating submission, chat p95 latency, dan reconnect rate.
4. Lakukan daily reconciliation order-payment-refund dan COD.
5. Kumpulkan feedback courier dan buyer berdasarkan task nyata, bukan hanya screenshot.
6. Rollback feature flag bila metrik kritis turun di bawah threshold.
7. Naikkan traffic bertahap setelah minimal satu siklus operasional lulus tanpa mismatch settlement.

**Gate production penuh:** tidak ada P0 terbuka; seluruh migration gate lulus; dynamic RLS dan concurrency lulus; chat memenuhi target latency/recovery; pilot tidak menghasilkan mismatch uang/stok/order; support runbook tersedia.

## 5. Urutan prioritas implementasi

| Prioritas | Area | Alasan |
|---|---|---|
| P0 | Ride RPC/state machine dan direct-update closure | Risiko manipulasi state dan tarif pada alur penumpang |
| P0 | Chat retry/resubscribe/gap recovery | Dampak langsung terhadap komunikasi dan persepsi aplikasi rusak |
| P0 | Courier booking create-order/dispatch | Fitur saat ini berhenti sebelum transaksi tercipta |
| P0 | Payment invoice/refund settlement | Risiko uang, duplikasi invoice, dan status pembayaran tidak konsisten |
| P1 | Staging migration/RLS/concurrency verification | Source aman hanya jika benar-benar diterapkan |
| P1 | Server-side distance dan batas operasional ojek | Mencegah jarak/tarif palsu dan order di luar cakupan |
| P1 | Responsive courier/ride shell dan card actions | Mendukung penggunaan lapangan pada perangkat kecil |
| P1 | Cart/checkout selection dan multi-merchant contract | Mencegah total/merchant/order yang membingungkan |
| P2 | Visual regression, observability lanjutan, dan accessibility | Mengurangi regresi dan meningkatkan maintainability |
| P2 | Pilot metrics dan rollout automation | Menjamin perubahan aman saat traffic meningkat |

## 6. Definition of Done keseluruhan

Rencana dianggap selesai apabila seluruh kondisi berikut terpenuhi:

1. Semua mutasi ride, order, payment, refund, rating, dan dispatch sensitif berjalan melalui RPC atau endpoint server-authoritative.
2. Buyer atau courier tidak dapat memodifikasi field sensitif melalui direct update.
3. Jarak, tarif, fee, stok, dan payment state dihitung atau diverifikasi di server.
4. Invoice, refund, order, dispatch, dan message retry bersifat idempotent.
5. Booking kurir dapat berjalan dari input sampai order selesai.
6. Ojek dapat berjalan dari pemesanan sampai pickup, completion, dan rating.
7. Chat tampil tanpa reload pada koneksi normal dan pulih setelah disconnect.
8. UI operasional tidak overflow atau menutup CTA pada device matrix.
9. Error state, retry, offline state, dan stale state terlihat jelas bagi pengguna.
10. RLS, concurrency, provider sandbox, visual regression, build, lint, test, dan dependency gate lulus di CI/staging.
11. Rekonsiliasi order-payment-refund-COD tidak menghasilkan mismatch terbuka.
12. Runbook rollback, backup, incident response, dan support tersedia sebelum rollout penuh.

## 7. Rekomendasi langkah pertama

Mulai dengan **Fase 0 dan tiga pekerjaan P0 secara paralel terbatas**: tutup direct update ride, perbaiki lifecycle chat, dan hubungkan booking kurir ke backend authoritative. Jangan memulai redesign visual besar sebelum state dan kontrak data stabil. Setelah tiga area tersebut lulus test staging, lanjutkan ke responsive hardening dan konsistensi cart/checkout.

## References

[1]: ../audits/audit-ojek-kurir-e2e-2026-09-11.md "Audit End-to-End Pemesanan Ojek dan Kurir"
[2]: ../audits/audit-ui-ux-chat-realtime-2026-09-11.md "Audit UI/UX Kurir/Ojek dan Chat Realtime"
[3]: ../audits/audit-frontend-2026-09-10.md "Audit Frontend SaDesa"
[4]: ../audits/audit-order.md "Audit Order SaDesa"
[5]: ../audits/audit-review-rating-refund-2026-09-11.md "Audit Review, Rating, dan Refund"
[6]: ../audits/audit-payment-notification-2026-09-11.md "Audit Payment dan Notification"
[7]: ../audits/audit-product-cart-checkout-2026-09-11.md "Audit Product, Cart, dan Checkout"
[8]: ../audits/audit-auth-user-management-2026-09-11.md "Audit Auth dan User Management"
[9]: ../pentest/pentest-transaksi-e2e-2026-09-11.md "Pentest Transaksi End-to-End"
[10]: ../security/dependency-vulnerability-scan-2026-09-11.md "Dependency Vulnerability Scan"
