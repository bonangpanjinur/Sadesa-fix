# Audit Lanjutan Fitur Kurir Ojek

**Tanggal audit:** 30 Agustus 2026  
**Basis audit:** source repository, migration/bootstrap SQL, Edge Function, serta smoke test browser pada halaman `/courier/rides`.

## Kesimpulan

Hardening tahap pertama sudah masuk ke branch `main` untuk penerimaan ride, transisi status, earning ride, withdrawal, filter realtime, TTL lokasi, dan push subscription. Smoke test browser menunjukkan halaman **Ojek Desa** dapat dimuat, query kurir dan `ride_requests` berhasil, dan halaman menampilkan kondisi kosong tanpa error runtime.

Namun fitur belum siap dinyatakan selesai untuk production karena masih terdapat satu jalur earning yang dibuat saat assignment order, jalur manual assignment yang melakukan update langsung dari client, serta belum ada concurrency/RLS smoke test terhadap database production. Masalah ini harus ditangani sebelum fitur kurir dipromosikan sebagai sistem pendapatan yang final.

## Status item rencana sebelumnya

| Item | Status | Bukti | Penilaian |
|---|---|---|---|
| OJK-01 acceptance ownership | Selesai di kode | RPC `accept_ride` memeriksa `auth.uid()` dan status courier | Perlu concurrency test staging |
| OJK-02 completion dan earning atomik | Selesai di kode untuk ride | RPC `transition_ride_status` menghitung dan mencatat earning secara idempoten | Perlu verifikasi constraint dan data existing |
| OJK-03 withdrawal atomik | Selesai di kode | RPC mengunci row courier dan menghitung reservasi pending | Perlu uji dua request paralel |
| OJK-04 state machine | Selesai di kode untuk ride | Transisi dikontrol RPC | Jalur order masih memiliki update client langsung |
| OJK-05 dispatch status dan kapasitas | Sebagian | Dispatch memvalidasi status dan lokasi stale | Manual assignment belum memakai jalur server terkontrol |
| OJK-06 radius available rides | Belum selesai penuh | UI masih mengambil seluruh `SEARCHING` dan filter jarak terutama di client | Perlu RPC/view berbasis radius |
| OJK-07 push notification | Selesai di kode, belum terverifikasi production | Edge Function `push-subscription` sudah tersedia | Perlu VAPID secret dan foreground/background test |
| OJK-08 realtime filter | Selesai di kode | Subscription dibatasi pada ride searching dan driver aktif | Perlu test antar dua courier |
| OJK-09 lokasi dan availability | Sebagian | Dispatch memakai TTL lima menit | Client masih perlu memastikan tracking hanya mengikuti state server |
| OJK-10 sampai OJK-12 rekonsiliasi/observability/guard | Belum selesai | Belum ada ledger reconciliation dan role matrix test | Prioritas setelah jalur P0/P1 stabil |

## Temuan residual prioritas

### P0 — Earning order masih dibuat saat assignment

`supabase/functions/assign-courier/index.ts` masih melakukan insert ke `courier_earnings` segera setelah order berhasil di-assign. Ini bertentangan dengan aturan bahwa pendapatan hanya boleh tercipta setelah delivery selesai. Jika order dibatalkan, gagal dikirim, atau di-assign ulang, ledger dapat menunjukkan pendapatan yang belum layak dibayar.

**Perbaikan wajib:** hapus insert earning dari `assign-courier`. Pencatatan earning harus dilakukan hanya oleh RPC completion yang memverifikasi status terminal dan referensi order/ride unik.

### P0 — Manual assignment masih direct client update

`src/lib/courierApi.ts` pada `manualAssignCourier` masih melakukan update langsung ke tabel `orders` dan insert notifikasi dari browser. Validasi hanya memeriksa sebagian status courier dan tidak menggunakan transaction yang sama dengan assignment, kapasitas, serta notifikasi.

**Perbaikan wajib:** tambahkan RPC atau Edge Function `assign_specific_courier` yang memvalidasi aktor merchant/admin, status order yang boleh di-assign, status courier `ACTIVE + APPROVED + is_available`, TTL lokasi, kapasitas maksimum, dan update conditional berdasarkan status sebelumnya. Notifikasi harus dibuat dari server setelah assignment berhasil.

### P1 — Daftar permintaan ride belum radius-aware di server

Halaman courier masih mengambil semua ride berstatus `SEARCHING`. Filter radius sebaiknya dilakukan dengan koordinat courier dan pickup ride di server atau melalui query geospatial agar jumlah data dan noise realtime tidak bergantung pada browser.

### P1 — Push notification membutuhkan konfigurasi deployment

Edge Function push sudah dibuat, tetapi belum dapat dianggap aktif sebelum `VAPID_PUBLIC_KEY` dan `VAPID_PRIVATE_KEY` tersedia di environment Supabase. Subscription invalid juga perlu dibersihkan saat provider mengembalikan 404/410.

### P1 — Kontrak status order dan ride masih terpisah

Ride sudah memiliki state machine sendiri, tetapi order delivery masih memakai beberapa istilah (`ASSIGNED`, `SENT`, `DELIVERING`, `ON_DELIVERY`, dan `DELIVERED`) di jalur berbeda. Ini dapat membuat kapasitas dan laporan tidak konsisten.

**Perbaikan wajib:** tetapkan status canonical untuk order delivery dan migrasikan dashboard, dispatch, policy, laporan, serta trigger ke daftar yang sama.

## Urutan perbaikan berikutnya

1. **Hapus earning dari assignment** dan buat constraint/reference unik untuk earning completion.
2. **Implementasikan assignment spesifik melalui RPC/Edge Function**, lalu matikan direct `orders.update` dan direct notification insert dari client.
3. **Konsolidasikan status order delivery** dan tambahkan conditional update pada setiap transisi.
4. **Pindahkan filter radius available rides ke server** dan sempitkan invalidasi realtime.
5. **Aktifkan serta uji push notification** dengan VAPID secret, background browser, subscription invalid, dan cleanup.
6. **Ikat availability dengan tracking server-side**, termasuk invalidasi lokasi ketika offline atau melewati TTL.
7. **Jalankan pengujian concurrency dan RLS** memakai role buyer, courier, merchant, admin, dan anonymous.
8. **Rekonsiliasi ledger existing** untuk mencari earning tanpa completion, duplikat order/ride, status pending yang stale, dan withdrawal yang melebihi saldo.

## Acceptance criteria sebelum rollout

| Skenario | Kriteria lulus |
|---|---|
| Assignment order selesai tetapi delivery batal | Tidak ada earning paid/eligible dari assignment |
| Dua admin/merchant assign courier bersamaan | Tepat satu assignment berhasil |
| Merchant mencoba assign courier milik tenant lain | Ditolak tanpa perubahan order |
| Courier tidak aktif atau lokasi stale | Tidak dapat menerima assignment baru |
| Completion diulang lima kali | Tepat satu ledger earning |
| Dua withdrawal paralel | Total reservation tidak melebihi saldo tersedia |
| Courier melihat ride jauh | Ride di luar radius tidak dikembalikan server |
| Push subscription invalid | Subscription dihapus dan failure tercatat |
| Courier lain menerima ride | Query courier pertama tidak ter-invalidasi oleh event yang tidak relevan |

## Status deliverable

Laporan ini adalah audit lanjutan dan backlog implementasi tahap berikutnya. Perbaikan source tahap pertama telah dipush sebelumnya; temuan residual di atas sebaiknya dikerjakan sebelum deployment production berikutnya.
