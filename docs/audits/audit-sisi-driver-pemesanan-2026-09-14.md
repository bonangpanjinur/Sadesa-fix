# Audit Alur Pemesanan dari Sisi Driver

**Tanggal:** 14 September 2026  
**Ruang lingkup:** Ojek/ride dan kurir delivery pada aplikasi SaDesa, mencakup order masuk, penerimaan, navigasi, perubahan status, realtime, chat, bukti serah terima, dan histori.

## Ringkasan eksekutif

Fondasi backend sudah memiliki RPC authoritative untuk menerima ride (`accept_ride`), menerima atau menolak tawaran delivery (`respond_delivery_offer`), mengubah status delivery (`courier_transition_order`), dan mengubah status ride (`transition_ride_status`). Namun, pengalaman operasional driver belum menjadi satu alur yang utuh. Informasi yang diperlukan untuk memutuskan sebuah tawaran masih kurang, order pickup dan delivery tersebar di dua permukaan berbeda, dan beberapa tindakan penting—terutama pembatalan/release tugas, navigasi ke titik pickup, expiry yang terlihat, dan pemulihan realtime—belum tersedia atau belum konsisten.

**Kesimpulan audit awal:** alur saat itu cukup untuk demo dan happy path, tetapi belum cukup kuat untuk operasi driver harian tanpa intervensi admin/merchant. Perbaikan prioritas sudah diterapkan pada commit `968feaa` dan perbaikan overlay buyer pada commit `8aadb46`.

**Status implementasi:** audit ini sudah ditindaklanjuti sebagian besar pada sisi driver. Item yang belum selesai atau masih parsial ditandai secara eksplisit di bawah.

## Peta alur yang saat ini tersedia

| Tahap | Ride/ojek | Delivery/kurir | Hasil audit |
|---|---|---|---|
| Order masuk | Daftar ride `SEARCHING`, bunyi notifikasi, tombol Terima | Tawaran `delivery_assignments` berstatus `OFFERED`, polling 15 detik, countdown, tombol Ambil/Tolak | **Selesai untuk informasi utama dan expiry** |
| Driver menerima | RPC `accept_ride` dengan validasi driver aktif | RPC `respond_delivery_offer` | Backend cukup baik |
| Menuju pickup | Status `ACCEPTED`, tombol navigasi pickup | Status `COURIER_ACCEPTED`, navigasi ke toko dengan koordinat pickup bila tersedia | **Selesai** |
| Pickup | Tombol `Sudah Dijemput` mengubah ke `PICKED_UP` | Tombol `Ambil Pesanan` mengubah ke `PICKED_UP` | Ada, belum ada verifikasi pickup/OTP |
| Perjalanan | Tombol `Mulai Perjalanan` mengubah ke `IN_TRANSIT` | Tombol `Mulai Antar` mengubah ke `SENT` | Ada, istilah status tidak seragam |
| Tujuan | Tombol `Selesai` mengubah ke `COMPLETED` | POD/foto lalu `DELIVERED` | Ada, tetapi ride belum memiliki bukti penyelesaian |
| Pembatalan/release | Tombol batal dengan alasan wajib dan RPC authoritative | Tombol lepas tugas dengan alasan wajib, notifikasi, dan pengembalian ke `ASSIGNED` | **Selesai; reassign otomatis belum diterapkan** |
| Histori/pendapatan | Ada halaman histori dan earnings | Ada histori order | Ada, tetapi tidak menjadi bagian dari alur aktif |

## Temuan prioritas

### [Selesai] P0 — Driver tidak melihat informasi pickup yang diperlukan untuk delivery

Pada `src/pages/CourierDashboardPage.tsx`, query assigned order hanya mengambil data tujuan dari `orders`: `delivery_name`, `delivery_phone`, `delivery_address`, `delivery_lat`, dan `delivery_lng`. Kartu aktif hanya menyediakan tombol navigasi ke tujuan delivery. Tidak ada merchant/pickup address, pickup latitude/longitude, nama toko, atau navigasi ke toko.

Pada `respond_delivery_offer`, driver hanya melihat `delivery_address` dan total pesanan. Setelah menerima tawaran, driver dapat berada dalam status `COURIER_ACCEPTED` tanpa cara yang jelas untuk mengetahui lokasi pickup selain mencari konteks di luar layar.

**Dampak:** driver dapat menerima order tetapi tidak dapat menjalankan langkah pertama—menuju merchant—dengan cepat dan akurat.

**Perbaikan wajib:** sertakan data merchant/pickup pada offer dan assigned order, tampilkan dua CTA terpisah (`Navigasi ke toko` dan `Navigasi ke pelanggan`), serta gunakan koordinat pickup sebagai sumber navigasi utama sebelum status `PICKED_UP`.

### [Parsial] P1 — Nilai yang ditampilkan kepada driver adalah total belanja, bukan estimasi pendapatan driver

Kartu tawaran dan kartu order menampilkan `orders.total`. Total tersebut adalah nilai pesanan pembeli, bukan kompensasi kurir. Pada delivery offer, driver tidak melihat shipping fee, komisi, pendapatan bersih, atau estimasi jarak/waktu.

**Dampak:** driver tidak memiliki informasi ekonomi untuk menerima/menolak tugas; angka yang ditampilkan dapat disalahartikan sebagai penghasilan.

**Status implementasi:** `Estimasi pendapatan kurir` dan `Total pesanan` sekarang dibedakan pada offer dan order aktif. Nilai earning disimpan pada `courier_earning_estimate` dengan dasar `shipping_cost`. Jarak/ETA dan rincian komisi belum sepenuhnya ditambahkan.

### [Selesai dengan batasan] P1 — Tidak ada aksi pembatalan atau pelepasan tugas oleh driver

UI driver hanya menyediakan terima/tolak untuk offer dan maju ke status berikutnya setelah order diterima. `courier_transition_order` hanya mengizinkan transisi maju: `COURIER_ACCEPTED → PICKED_UP → SENT/DELIVERING → DELIVERED`. Pada ride, UI juga hanya maju dari `ACCEPTED → PICKED_UP → IN_TRANSIT → COMPLETED`.

Tidak terlihat workflow untuk driver yang mengalami kendaraan rusak, kecelakaan, merchant tutup, alamat bermasalah, atau pembeli tidak dapat dihubungi.

**Dampak:** tugas macet pada driver yang tidak mampu menyelesaikan; admin/merchant harus melakukan pemulihan manual.

**Status implementasi:** RPC `courier_release_order` dan `driver_cancel_ride` sudah dibuat dengan alasan wajib dan batasan status aman. Release delivery mengirim notifikasi buyer/merchant dan menulis `order_status_history`. Reassign otomatis belum diterapkan karena kebijakan pemilihan kurir belum ditetapkan.

### [Selesai] P1 — Expiry tawaran tidak terlihat jelas

Query hanya memfilter `expires_at > now()` dan melakukan refetch setiap 15 detik. Kartu tidak menampilkan countdown atau waktu kedaluwarsa individual; teks hanya mengatakan “ambil atau tolak sebelum waktu habis”.

**Dampak:** driver dapat menekan tombol pada offer yang sudah kedaluwarsa dan hanya menerima error generik.

**Perbaikan:** tampilkan countdown per offer, ubah tampilan menjadi `Kedaluwarsa`, disable tombol saat habis, dan refresh/invalidate saat `delivery_assignments` berubah menjadi `EXPIRED` atau `REJECTED`.

### [Selesai] P1 — Realtime delivery belum lengkap

Dashboard berlangganan insert `delivery_assignments` dan update `orders`, tetapi belum menangani perubahan assignment menjadi expired/rejected/accepted secara langsung. Perubahan tersebut baru terlihat setelah interval query berikutnya. Pada halaman ojek, realtime melakukan invalidasi ride, tetapi tidak ada mekanisme recovery khusus ketika channel error atau reconnect.

**Perbaikan:** subscribe `INSERT/UPDATE/DELETE` pada assignment yang terkait courier, tampilkan status koneksi, lakukan refetch setelah reconnect, dan gunakan fallback polling dengan interval yang ditampilkan secara jujur.

### [Selesai] P1 — Alur delivery dan ride terpecah di permukaan berbeda

`CourierDashboardPage` menangani delivery order, sedangkan `CourierRidesPage` menangani ride dan juga menampilkan delivery offer kedua. Ini menciptakan dua lokasi tawaran delivery dengan kontrak UI berbeda. Satu halaman menampilkan merchant pada offer, halaman lain tidak; satu halaman melakukan invalidasi assigned orders setelah accept, halaman lain hanya `refetchOffers`.

**Dampak:** driver dapat melihat data ganda/stale atau tidak tahu halaman mana yang menjadi inbox utama.

**Perbaikan:** pilih satu inbox driver canonical, gunakan komponen `DeliveryOfferCard` dan `AssignedDeliveryCard` bersama, serta satu query/repository untuk status offer dan order aktif.

### [Selesai] P1 — Preview rute ride driver masih garis lurus

Pada `src/pages/courier/CourierRidesPage.tsx`, preview `Lihat Rute` masih menggunakan `Polyline` dengan dua titik pickup dan destination. Ini tidak mengikuti jalan nyata, berbeda dengan komponen `CourierMap` yang sudah memakai route OSRM.

**Perbaikan:** gunakan `getRoadRoute` yang sama pada preview ride dan render polyline geometry jalan; gunakan fallback yang eksplisit bila routing gagal.

### [Selesai dengan batasan] P1 — Verifikasi pickup dan penyelesaian ride

Delivery sudah meminta Proof of Delivery untuk status `DELIVERED`. Ride sekarang meminta catatan konfirmasi driver saat transisi ke `PICKED_UP` dan `COMPLETED`; RPC authoritative menyimpan metode, catatan, dan timestamp verifikasi pada `ride_requests`. PIN/OTP penumpang belum diterapkan karena belum ada sumber PIN atau kebijakan OTP pada alur penumpang.

**Perbaikan:** verifikasi ringan diterapkan melalui konfirmasi wajib dan audit metadata. Implementasi PIN/OTP dapat ditambahkan kemudian tanpa mengubah guard RPC.

### [Parsial] P2 — Detail order yang diterima terlalu minim

Offer delivery tidak menampilkan daftar item, catatan pembeli, nama merchant, titik pickup, biaya antar, jarak, atau ETA. Ride menampilkan alamat dan tarif, tetapi tidak memiliki detail kontak atau instruksi penumpang sebelum diterima.

**Perbaikan:** sediakan detail bertahap: ringkasan pada card dan drawer/detail screen sebelum accept, dengan masking data pribadi sampai status yang sesuai.

### [Selesai] P2 — Handling aksi belum konsisten

Pada `CourierDashboardPage`, tombol offer tidak memiliki state loading per assignment. Double click dapat mengirim dua request sebelum query cache diperbarui. Error ditampilkan sebagai pesan generik “Gagal memproses tawaran”. Pada `CourierRidesPage`, state `accepting` sudah lebih baik, tetapi error accept tetap kehilangan detail penyebab.

**Perbaikan:** gunakan mutation keyed per assignment, disable kedua tombol selama request, tampilkan error domain (`offer expired`, `already assigned`, `courier offline`), dan invalidate semua query terkait setelah sukses.

### [Selesai] P2 — Status delivery dan ride memiliki kamus berbeda

Delivery memakai `COURIER_ACCEPTED`, `PICKED_UP`, `SENT`, `DELIVERING`, `DELIVERED`; ride memakai `ACCEPTED`, `PICKED_UP`, `IN_TRANSIT`, `COMPLETED`. UI memetakan sebagian status ke label yang mirip, tetapi tidak ada satu dictionary/transition matrix frontend yang dipakai bersama.

**Dampak:** label, tombol, analytics, dan notifikasi mudah divergen.

**Perbaikan:** sentralisasi `OrderStatus`/`RideStatus`, label Indonesia, transition map, dan helper action dalam satu modul.

## Hal yang sudah baik

Backend sudah memiliki beberapa kontrol penting. `accept_ride` memvalidasi bahwa caller adalah courier yang sama, sudah approved, aktif, dan available. Penerimaan delivery menggunakan RPC dengan row lock dan memeriksa status `OFFERED` serta expiry. `courier_transition_order` memeriksa bahwa order memang dimiliki courier yang sedang login, membatasi transisi, mengisi timestamp pickup/delivered, dan menulis `order_status_history`. Delivery juga memiliki Proof of Delivery pada langkah akhir.

Pada sisi UX, driver sudah memiliki toggle online/offline, update lokasi GPS, tombol navigasi eksternal, notifikasi bunyi untuk ride baru, preview peta, chat dengan penumpang pada ride aktif, dan halaman histori.

## Rekomendasi urutan implementasi

| Urutan | Pekerjaan | Prioritas |
|---|---|---|
| 1 | ✅ Satukan inbox delivery driver dan hilangkan duplikasi offer pada dua halaman | P0 |
| 2 | ✅ Tambahkan pickup merchant lengkap dan dua navigasi: toko lalu pelanggan | P0 |
| 3 | ◐ Pisahkan pendapatan driver dari total belanja pembeli; jarak/ETA/komisi masih tersisa | P1 |
| 4 | ◐ Tambahkan release/cancel workflow dengan alasan dan reassign; reassign otomatis masih tersisa | P1 |
| 5 | ✅ Tambahkan expiry countdown dan realtime assignment recovery | P1 |
| 6 | ✅ Ganti preview ride garis lurus dengan OSRM road route | P1 |
| 7 | ✅ Tambahkan verifikasi pickup/drop-off untuk ride | P1 |
| 8 | ✅ Sentralisasi status dictionary dan mutation handling | P2 |
| 9 | ◐ Tambahkan detail order, item, catatan, ETA, dan observability | P2 |

## Acceptance criteria minimum

1. ✅ Driver dapat melihat merchant/pickup address dan koordinat sebelum/tepat setelah menerima delivery.
2. ◐ Driver melihat estimasi pendapatan sendiri, bukan hanya total order buyer; rincian jarak/ETA/komisi belum lengkap.
3. ✅ Setiap offer memiliki countdown dan tombol otomatis disabled setelah expiry.
4. ◐ Driver dapat melepaskan tugas secara aman dengan alasan; buyer, merchant, dan sistem menerima notifikasi. Reassign otomatis belum tersedia.
5. ✅ Hanya ada satu inbox delivery canonical dan tidak ada offer ganda antar halaman.
6. ✅ Preview ride memakai rute jalan, bukan garis lurus. Tracking aktif tetap mengikuti mekanisme yang sudah ada.
7. ✅ Status aktif pulih otomatis setelah realtime disconnect tanpa reload manual.
8. ✅ Setiap transisi status menampilkan error domain yang dapat ditindaklanjuti; history delivery tercatat oleh RPC. Pickup dan penyelesaian ride memerlukan catatan konfirmasi yang diaudit.

## Kesimpulan

Kekurangan terbesar pada sisi driver bukan pada kemampuan menerima order, melainkan pada **kelengkapan informasi dan kemampuan menyelesaikan atau memulihkan tugas**. Pickup merchant, inbox canonical, expiry, realtime recovery, release/cancel dasar, serta verifikasi ringan ride sudah ditangani. Risiko yang masih tersisa adalah reassign otomatis, PIN/OTP opsional, serta kelengkapan jarak/ETA/komisi dan detail item.

**Status audit:** diperbarui setelah implementasi; seluruh perbaikan prioritas yang memiliki kontrak kebijakan saat ini sudah diterapkan. Pekerjaan lanjutan adalah reassign otomatis sesuai kebijakan, PIN/OTP opsional, serta pelengkapan jarak/ETA/komisi dan detail item.

## Referensi source

- `src/pages/CourierDashboardPage.tsx`
- `src/pages/courier/CourierRidesPage.tsx`
- `src/pages/courier/CourierHistoryPage.tsx`
- `src/components/courier/NavigationButton.tsx`
- `src/components/courier/ProofOfDelivery.tsx`
- `supabase/bootstrap/44_20260909193000_order_workflow_rpc.sql`
- `supabase/bootstrap/45_20260909201500_fix_delivery_offer_rpc.sql`
- `supabase/bootstrap/33_20260908190000_ride_history_earnings_contract.sql`
- `src/lib/routeCalculation.ts`
