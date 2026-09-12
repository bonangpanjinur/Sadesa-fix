# Audit Pengelolaan Pesanan Merchant dan Pembeli

**Tanggal:** 12 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** checkout marketplace, daftar dan detail pesanan pembeli, inbox dan fulfillment merchant, transisi status, pembayaran, pembatalan, refund, kurir, ekspedisi, realtime, RLS, dan pengujian.

## Kesimpulan Eksekutif

SaDesa sudah memiliki fondasi arsitektur yang cukup baik pada beberapa bagian penting. Checkout marketplace sudah memiliki RPC authoritative, reservasi stok dipisahkan ke fungsi database, transisi merchant dan kurir sebagian besar memakai RPC, dan migration terbaru sudah menambahkan history status serta hardening review/refund.

Namun, pengelolaan pesanan belum memiliki satu kontrak lifecycle yang dipakai secara konsisten oleh seluruh halaman. Terdapat dua permukaan merchant yang aktif, yaitu `MerchantOrdersPage` dan `OrderStatusManager` di dashboard. Keduanya memiliki implementasi aksi dan representasi status yang berbeda. Di sisi pembeli, pembatalan masih menggunakan direct update dari browser, sedangkan alur refund menggunakan RPC. Perbedaan ini membuat sebagian aturan hanya ditegakkan oleh UI atau RLS, bukan oleh satu service contract yang seragam.

**Prioritas tertinggi** adalah mengunci mutation order buyer melalui RPC, menyatukan dua permukaan merchant ke satu workflow, dan memperbaiki lifecycle pembayaran online multi-merchant sebelum transaksi produksi diperluas.

## Peta Alur Saat Ini

| Tahap | Pembeli | Merchant | Database/backend |
|---|---|---|---|
| Checkout | `CheckoutPage` memilih alamat, metode delivery, payment, dan voucher. | Tidak terlibat. | `create_marketplace_checkout` membuat order per merchant, item, reservation, dan voucher usage. |
| Menunggu | `OrdersPage` membaca order melalui React Query. | `MerchantOrdersPage` dan `OrderStatusManager` membaca order secara terpisah. | Status awal bergantung pada metode pembayaran: `PENDING_CONFIRMATION`, `PENDING_PAYMENT`, atau `NEW`. |
| Konfirmasi | Pembeli melihat status. | Merchant menerima, menolak, memverifikasi transfer, atau memilih fulfillment. | Sebagian aksi melalui `merchant_transition_order`; pembayaran melalui RPC/webhook. |
| Fulfillment | Pembeli melihat timeline dan tracking. | Merchant memilih antar sendiri, kurir desa, pickup, atau ekspedisi. | Assignment dan courier transition memakai RPC; ekspedisi menyimpan provider dan resi pada order. |
| Penyelesaian | Pembeli mengonfirmasi order `DELIVERED` menjadi `DONE`, mengajukan refund, dan memberi rating. | Merchant melihat status selesai/refund. | Refund, review, dan courier rating sudah memiliki RPC hardening pada migration terbaru. |

## Temuan Prioritas

| ID | Prioritas | Area | Temuan | Dampak |
|---|---|---|---|---|
| ORD-P0-01 | **P0** | Pembayaran online multi-merchant | Audit repository menunjukkan checkout online sebelumnya membuat invoice dan melakukan `return` di dalam loop merchant. Migration authoritative yang ada membuat child order per merchant, tetapi kontrak payment masih harus dipastikan mendukung lebih dari satu order. | Cart lintas merchant dapat membuat order/payment parsial atau hanya membayar merchant pertama. Ini berisiko finansial dan harus diblokir atau didesain ulang sebagai parent payment intent. |
| ORD-P1-02 | P1 | Mutation buyer | `OrderCancelDialog` melakukan `orders.update` langsung dengan status dan metadata pembatalan. RLS lama hanya menyediakan update own order berstatus `NEW`, sehingga pembatalan `PENDING_PAYMENT` atau `PENDING_CONFIRMATION` dapat gagal. Jika policy update masih aktif, buyer juga berpotensi mengubah kolom lain selama status tetap `NEW`. | UX pembatalan tidak konsisten dan integritas nominal/alamat/payment dapat terancam. |
| ORD-P1-03 | P1 | Dua workflow merchant | `MerchantOrdersPage` dan `OrderStatusManager` sama-sama aktif. Keduanya memiliki filter status, error handling, aksi fulfillment, dan optimistic update berbeda. | Merchant dapat melihat status/aksi berbeda tergantung masuk melalui dashboard atau halaman Pesanan. Perubahan di satu surface bisa tampak stale di surface lain. |
| ORD-P1-04 | P1 | Canonical status | Kode memakai variasi `CANCELED`/`CANCELLED`, `CONFIRMED`, `READY`, `ASSIGNED`, `COURIER_ASSIGNED`, `COURIER_ACCEPTED`, `SENT`, dan `DELIVERING`. Tidak semua variasi memiliki representasi dan transisi yang sama di setiap komponen. | Filter, progress bar, tombol aksi, dan timeline dapat salah menampilkan status atau menyembunyikan order. |
| ORD-P1-05 | P1 | Checkout atomicity | Checkout multi-merchant membuat order, item, reservation, dan invoice melalui beberapa tahap. RPC checkout sudah lebih authoritative, tetapi reservation/invoice lifecycle tetap perlu compensation atau parent transaction yang eksplisit. | Kegagalan di merchant kedua dapat meninggalkan order/reservation parsial dan perlu rekonsiliasi. |
| ORD-P1-06 | P1 | Payment recovery | Reservation invoice `processing` berisiko macet tanpa lease recovery, dan invoice expired berisiko mengembalikan invoice lama. | Pembeli tidak dapat memulai ulang pembayaran setelah crash atau invoice kedaluwarsa. |
| ORD-P1-07 | P1 | Refund settlement | `create_refund_request` dan `process_refund_decision` sudah memakai RPC dan row lock. Namun proses approval mengurangi `available_balance` dengan `GREATEST(0, balance - amount)` tanpa ledger settlement yang terlihat pada function ini. | Saldo dapat terpotong menjadi nol tanpa representasi kewajiban/shortfall yang jelas; rekonsiliasi refund dan payout merchant menjadi sulit. |
| ORD-P2-08 | P2 | Freshness merchant | `MerchantOrdersPage` memiliki realtime, tetapi `OrderStatusManager` hanya melakukan fetch awal dan tidak terlihat subscription realtime. | Dashboard merchant berpotensi menampilkan status lama sampai refresh atau remount. |
| ORD-P2-09 | P2 | Pagination | Daftar pembeli tidak membatasi query marketplace orders dengan cursor/limit. Merchant pages juga memakai window terbatas atau fetch terpisah. | Akun dengan volume besar dapat mengalami query berat dan order lama tidak dikelola melalui pagination yang eksplisit. |
| ORD-P2-10 | P2 | Notification/realtime completeness | Buyer subscription menangani `UPDATE` order, tetapi alur order baru dan recovery reconnect perlu diuji bersama cache React Query. | Badge/count/detail dapat tidak langsung konsisten setelah checkout, reconnect, atau event yang datang sebelum subscription aktif. |

## Audit dari Sisi Merchant

### Inbox dan aksi order

`MerchantOrdersPage` merupakan workspace operasional utama dengan pencarian, filter tanggal, export, realtime, dan detail dialog. Ini adalah arah yang lebih baik untuk dijadikan surface canonical. Namun, `MerchantDashboardPage` masih merender `OrderStatusManager`, sehingga merchant memiliki dua inbox aktif.

`OrderStatusManager` memanggil `merchant_transition_order` untuk menerima, antar sendiri, dan membatalkan. Untuk kurir desa, komponen memanggil `create_delivery_offer`. `MerchantOrdersPage` menjalankan logika yang mirip dengan handler sendiri. Duplikasi ini meningkatkan risiko bahwa satu perbaikan status hanya masuk ke salah satu halaman.

### Fulfillment

Workflow internal sudah membedakan pickup, antar sendiri, kurir desa, dan ekspedisi. Migration terbaru juga memperkuat handoff ekspedisi dengan nama provider dan nomor resi. Risiko residual berada pada konsistensi status `READY`, `ASSIGNED`, `COURIER_ACCEPTED`, `PICKED_UP`, `DELIVERING`, dan `SENT` antara komponen merchant, halaman kurir, dan fungsi database.

Merchant memerlukan satu action contract yang mengembalikan order terbaru dari server. Optimistic update sebaiknya hanya dilakukan setelah response RPC berhasil, atau cache harus di-reconcile dengan row hasil RPC. Saat ini beberapa handler hanya mengganti `status` lokal dan tidak menggabungkan timestamp, courier, payment status, atau field history dari response server.

### Pembayaran

Merchant memiliki aksi verifikasi transfer melalui `merchant_verify_order_payment`, tetapi daftar order juga memiliki status `PENDING_PAYMENT` dan `PENDING_CONFIRMATION` yang diproses berbeda. UI harus selalu mengunci aksi fulfillment sampai payment state memenuhi kontrak server. Pengujian minimum harus mencakup pembayaran transfer terlambat, webhook datang bersamaan dengan verifikasi merchant, dan retry verifikasi.

## Audit dari Sisi Pembeli

### Daftar dan detail order

`OrdersPage` menggunakan React Query dan realtime update untuk status order. Fitur refresh manual tersedia. Detail order dibuka melalui `OrderDetailSheet`, sedangkan tracking penuh menggunakan `OrderTrackingPage`. Pemisahan ini dapat diterima, tetapi kedua komponen harus menggunakan status dictionary dan aturan eligibility yang sama.

Progress order memiliki variasi status yang lebih banyak daripada `ORDER_STEPS`. Status `PENDING_PAYMENT` dan `PENDING_CONFIRMATION` dipetakan ke progress awal, sedangkan status courier tertentu tidak selalu masuk ke urutan progress. Ini dapat membuat progress bar tidak merepresentasikan status backend secara presisi.

### Pembatalan

`OrderCancelDialog` melakukan update langsung ke tabel `orders` dengan `status`, `cancelled_at`, `cancelled_by`, `cancellation_reason`, dan `cancellation_type`. Ini seharusnya diganti dengan RPC `buyer_cancel_order(p_order_id, p_reason)` yang mengunci order, memastikan buyer caller, memvalidasi status yang dapat dibatalkan, memeriksa payment/refund consequence, menulis `order_status_history`, dan memulihkan stock reservation secara atomik.

Kontrak saat ini juga tidak selaras dengan policy update yang hanya menyebut status `NEW`, sementara UI mengirim status untuk tiga kondisi: `NEW`, `PENDING_PAYMENT`, dan `PENDING_CONFIRMATION`. Ini perlu diuji langsung pada staging karena hasil final juga bergantung pada migration policy yang diterapkan.

### Refund dan complaint

Migration hardening terbaru sudah memperbaiki beberapa masalah penting. `create_refund_request` mengunci order buyer, memvalidasi status delivered/done, payment status, nominal, alasan, dan active refund. `process_refund_decision` mengunci refund dan order, hanya memproses status `PENDING`, lalu mengubah refund dan order dalam satu function transaction.

Residual risk berada pada settlement merchant. Pengurangan saldo menggunakan `GREATEST(0, balance - refund amount)` tidak membedakan saldo tersedia, payable, reserve, atau shortfall. Sistem membutuhkan refund ledger dengan idempotency key dan status settlement terpisah dari keputusan refund admin.

### Review dan courier rating

Review produk dan courier rating sudah diarahkan ke RPC authoritative pada migration hardening. Courier rating memvalidasi buyer, order, status selesai, courier assignment, dan rating 1–5. Ini menutup temuan lama yang menyebut mismatch schema rating courier.

Namun, frontend dan migration harus diuji pada database staging yang benar-benar menerapkan bootstrap terbaru. Laporan audit lama yang menyebut direct insert review/refund sudah tidak sepenuhnya merepresentasikan source final, karena migration 49 telah mencabut grant insert authenticated dan menambahkan RPC.

## Matriks State yang Direkomendasikan

| State | Aktor | Aksi sah | Catatan |
|---|---|---|---|
| `NEW` | Merchant | `PROCESSED`, `CANCELED`, `REJECTED` | Untuk order online, payment harus sudah valid sesuai kontrak. |
| `PENDING_PAYMENT` | Buyer/system | Bayar ulang, cancel, expire | Merchant tidak boleh fulfillment sebelum paid. |
| `PENDING_CONFIRMATION` | Merchant | `PROCESSED`, `CANCELED`, `REJECTED` | Umumnya COD menunggu konfirmasi merchant. |
| `PROCESSED` | Merchant | `READY`, `DELIVERING`, `ASSIGNED`, `SENT` untuk ekspedisi | Metode delivery menentukan transition yang sah. |
| `ASSIGNED` | Courier | `COURIER_ACCEPTED`, `CANCELED` | Assignment harus single active offer per order. |
| `COURIER_ACCEPTED` | Courier | `PICKED_UP`, `CANCELED` | Hanya courier assigned yang boleh. |
| `PICKED_UP` | Courier | `DELIVERING` | Set timestamp pickup secara server-side. |
| `DELIVERING`/`SENT` | Courier/merchant | `DELIVERED` | `SENT` ekspedisi memerlukan provider dan resi. |
| `DELIVERED` | Buyer/system | `DONE`, refund request | Auto-complete perlu tercatat dalam history. |
| `DONE` | System/admin | Refund decision atau post-order actions | Tidak boleh kembali ke fulfillment. |
| `CANCELED`/`REFUNDED` | System/admin | Terminal | Tidak boleh diproses ulang tanpa workflow recovery eksplisit. |

## Rencana Perbaikan Prioritas

| Fase | Perbaikan | Prioritas |
|---|---|---|
| 1 | Blokir online multi-merchant atau implementasikan parent checkout/payment intent. | P0 |
| 2 | Buat RPC `buyer_cancel_order` dan cabut direct update buyer pada `orders`. | P1 |
| 3 | Tetapkan satu `OrderStatus` dictionary dan satu transition matrix untuk TypeScript, UI, dan SQL. | P1 |
| 4 | Jadikan `MerchantOrdersPage` sebagai inbox canonical dan hapus atau ubah `OrderStatusManager` menjadi wrapper komponen yang sama. | P1 |
| 5 | Tambahkan payment invoice lease, expired invoice regeneration, dan recovery worker. | P1 |
| 6 | Tambahkan refund ledger idempotent dengan status decision dan settlement terpisah. | P1 |
| 7 | Tambahkan cursor pagination dan server-side unread/order summary. | P2 |
| 8 | Jalankan staging E2E dua buyer, dua merchant, dan dua courier dengan test concurrency. | P0 sebelum production |

## Test Matrix Minimum

| Skenario | Expected result |
|---|---|
| Buyer mencoba mengubah total/alamat/payment pada order `NEW` | Ditolak; hanya cancel RPC yang tersedia. |
| Buyer cancel `PENDING_PAYMENT` | Berhasil hanya jika state dan reservation memenuhi aturan. |
| Buyer cancel setelah `PROCESSED` | Ditolak atau diarahkan ke refund sesuai kebijakan. |
| Merchant menerima order dua kali secara paralel | Satu transition sukses; request lain ditolak/idempotent. |
| Dua merchant surface terbuka bersamaan | Keduanya menerima realtime state yang sama. |
| Courier accept dua offer aktif | Hanya satu courier menjadi assigned. |
| Handoff ekspedisi tanpa resi | RPC menolak. |
| Webhook payment bersamaan dengan aksi merchant | Tidak ada downgrade atau fulfillment sebelum payment valid. |
| Online checkout dua merchant | Ditolak sebelum order dibuat atau memakai satu parent payment. |
| Invoice expired dibayar ulang | Invoice aktif baru dibuat. |
| Refund approval dua kali | Satu keputusan sukses; satu request ditolak tanpa double deduction. |
| Buyer membuka lebih dari 100 order | Pagination/cursor dapat mengambil order lama. |

## Validasi Lokal

Quality gate yang dijalankan selama audit:

```text
pnpm exec tsc --noEmit  -> lulus
pnpm lint               -> lulus

Focused order/payment tests:
6 test files, 17 tests passed
- marketplaceOrderContract
- deliveryRestriction
- paymentApi
- paymentProof
- useReorder
- OrderStatusManager
```

Test ini membuktikan kontrak lokal dan komponen yang tersedia, tetapi belum menggantikan staging E2E dengan dua atau lebih akun. Belum ada transaksi staging/production yang dijalankan selama audit ini.

## Kesimpulan Akhir

Fondasi keamanan order telah meningkat secara signifikan dibanding audit historis, terutama karena checkout dan refund/review kini memiliki RPC authoritative. Risiko terbesar yang tersisa bukan sekadar tampilan, melainkan **duplikasi workflow merchant, direct mutation buyer untuk cancel, canonical status yang belum tunggal, dan payment multi-merchant yang belum memiliki kontrak parent payment**.

Urutan implementasi yang disarankan adalah mengamankan payment multi-merchant dan buyer cancellation terlebih dahulu, kemudian menghapus duplikasi merchant workflow, lalu menyempurnakan pagination, realtime recovery, dan settlement ledger.

## References

[1]: https://supabase.com/docs/guides/database/postgres/row-level-security "Supabase Row Level Security documentation"
[2]: https://supabase.com/docs/guides/database/functions "Supabase database functions documentation"
[3]: https://tanstack.com/query/latest/docs/framework/react/overview "TanStack Query documentation"
