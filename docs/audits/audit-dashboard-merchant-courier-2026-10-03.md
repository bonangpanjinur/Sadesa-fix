# Audit Dashboard Merchant dan Kurir

**Tanggal:** 3 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** `/merchant`, `/courier`, route guard, query Supabase, KPI, realtime, state loading/error/empty, aksi operasional, responsive layout, dan aksesibilitas.

## Ringkasan Eksekutif

Kedua dashboard sudah memakai lazy route, layout role-specific, error boundary, query cache, dan realtime untuk aktivitas operasional. Fokus perbaikan pada audit ini adalah akurasi data serta kejujuran state UI:

- Dashboard merchant sebelumnya mengambil hingga 500 order terbaru tanpa filter periode untuk grafik 14 hari. Ini memboroskan payload dan membuat angka pendapatan bergantung pada data yang tidak relevan.
- Query grafik merchant tidak memilih `subtotal`, sehingga fallback ke `total` dapat memasukkan ongkir/biaya lain ke angka pendapatan.
- Query order aktif kurir mengabaikan error Supabase dan mengembalikan array kosong. Gangguan jaringan dapat terlihat seperti tidak ada order aktif.
- Error tawaran pengiriman kurir tidak menyediakan retry langsung.
- Aksi transisi status order kurir belum memiliki guard busy, sehingga klik berulang berpotensi mengirim mutation ganda.
- Status realtime kurir menggunakan nama channel statis dan dapat berbenturan antar tab.

## Temuan dan Implementasi

| ID | Prioritas | Area | Temuan | Perbaikan |
|---|---|---|---|---|
| MRC-P1-01 | P1 | KPI merchant | Query chart mengambil maksimal 500 order tanpa filter tanggal walaupun hanya menampilkan 14 hari. | Query dibatasi ke periode 14 hari dan limit diturunkan menjadi 250 sebagai safety cap. |
| MRC-P1-02 | P1 | Pendapatan merchant | `subtotal` tidak dipilih, sehingga kalkulasi fallback memakai `total`. | Menambahkan `subtotal` ke select dan tetap memakai subtotal untuk revenue order selesai. |
| CRR-P0-01 | P0 | Error state kurir | Query order aktif tidak memeriksa `error`; kegagalan database/network menjadi daftar kosong. | Query kini melempar error dan state `ordersError` menampilkan retry. |
| CRR-P1-02 | P1 | Payload kurir | Query menggunakan `select('*')`, mengambil kolom order yang tidak dibutuhkan dashboard. | Diganti dengan daftar kolom eksplisit yang sesuai `AssignedOrder`. |
| CRR-P1-03 | P1 | Tawaran pengiriman | Error offers hanya memberi instruksi umum membuka halaman lain. | Menambahkan tombol retry langsung di kartu dashboard. |
| CRR-P1-04 | P1 | Mutation status | Tombol transisi order dapat diklik berulang selama RPC berjalan. | Menambahkan `updatingOrderId`, disable action aktif, dan label `Memproses…`. |
| CRR-P2-05 | P2 | Realtime | Nama channel realtime hard-coded `courier-new-orders`. | Nama channel dibuat unik per courier ID. |
| CRR-P2-06 | P2 | Aksesibilitas | Tombol logout kurir hanya berupa icon. | Menambahkan accessible name dan title. |
| CRR-P2-07 | P2 | Copy refresh | UI menyebut refresh 15 detik, sedangkan query offers berjalan setiap 30 detik. | Copy disamakan menjadi 30 detik. |

## Detail Audit Merchant

### Data dan KPI

- Profile merchant memakai query scoped ke `user.id` dan memiliki loading/error/missing/pending/rejected state.
- Grafik sales hanya dibutuhkan untuk 14 hari terakhir; filter server-side sekarang memakai awal periode tersebut.
- Revenue order selesai menggunakan `subtotal`, bukan total yang berpotensi mencakup ongkir atau biaya layanan.
- Pending order summary menggunakan count server dan limit 5 untuk preview; dashboard menyediakan link menuju pengelolaan order penuh.

### Operasional

- Status toko menggunakan mutation dan optimistic cache update.
- Order baru dan perubahan order menginvalidasi query chart dan pending summary melalui realtime hook.
- Aksi terima/tolak memakai RPC `merchant_transition_order`, bukan update status langsung.
- Error chart dan pending summary memiliki retry melalui `MerchantCardError`.

### Responsive dan aksesibilitas

- Layout merchant memakai sidebar desktop dan drawer mobile.
- Tab dashboard dapat di-scroll horizontal pada layar kecil.
- Aksi utama diberi label tekstual; switch status toko memiliki label terhubung melalui `htmlFor`.
- Error boundary layout menyediakan fallback bila komponen kartu gagal.

## Detail Audit Kurir

### Data dan state

- Profile query membedakan error fetch, belum terdaftar, pending, rejected, dan approved.
- Order aktif sekarang memeriksa error Supabase sebelum mengembalikan data.
- Relasi `merchants` dari Supabase dinormalisasi dari array menjadi objek merchant tunggal yang dipakai kartu order.
- Query order aktif memilih field eksplisit untuk pickup, tujuan, status, biaya, dan merchant; data kolom lain tidak lagi dikirim ke dashboard.
- Tawaran pengiriman dan permintaan ojek tetap dibatasi ke courier yang sedang login melalui RPC/query scoped.

### Operasional

- Toggle online tetap mewajibkan GPS ketika kurir menjadi online.
- GPS tracking mengubah status kembali offline jika lokasi wajib tidak tersedia.
- Realtime invalidasi delivery offers dan active orders ketika assignment/order berubah.
- Transisi status order memakai RPC `courier_transition_order`.
- Release task memakai RPC `courier_release_order` dan alasan wajib.
- Proof of delivery tetap diperlukan pada transisi selesai.

### Responsive dan aksesibilitas

- Desktop menggunakan sidebar; mobile memakai drawer dan bottom navigation.
- Konten bawah menyediakan padding untuk bottom navigation dan safe area.
- Tombol refresh order memiliki `aria-label` dan state animasi saat fetching.
- Tombol logout sekarang memiliki accessible name.
- Navigasi pickup/delivery hanya ditampilkan ketika koordinat tersedia.

## Validasi

| Pemeriksaan | Hasil |
|---|---|
| `pnpm exec tsc --noEmit` | Lulus setelah normalisasi relasi merchant |
| `pnpm lint` | Lulus |
| Test merchant/courier terarah | 11 test lulus, 4 skenario integrasi terskip oleh konfigurasi test |
| `pnpm build` | Berhasil |
| `git diff --check` | Bersih |

Test terarah yang dijalankan mencakup kontrak feedback merchant, OrderStatusManager, DeliveryStatusCard, dan courier integration.

## Residual Risk dan Rekomendasi

1. Query pending merchant masih merupakan query terpisah dari daftar order realtime; bila konsistensi absolut diperlukan, pertimbangkan RPC summary atomik atau invalidasi setelah setiap mutation.
2. Dashboard merchant masih memuat beberapa kartu yang melakukan query masing-masing. Untuk jaringan lambat, dapat dibuat endpoint/RPC dashboard summary dengan response teragregasi.
3. Query ride request count masih menampilkan `—` ketika gagal tanpa tombol retry lokal; tambahkan `refetch` dan state error eksplisit pada kartu ojek.
4. Status subscription realtime belum menampilkan retry manual ketika channel offline; monitoring reconnect dapat diperjelas dengan tombol refresh dan telemetry.
5. Validasi browser nyata pada viewport mobile dan device GPS belum dijalankan; build/typecheck tidak menggantikan pengujian permission GPS, background notification, dan reconnect realtime di perangkat.
6. RLS dan RPC tetap merupakan security boundary. Audit ini belum menjalankan query terhadap database production/staging.
