# Audit Residual Repository

**Tanggal:** 12 September 2026
**Repository:** `bonangpanjinur/Sadesa-fix`
**Commit dasar:** `853acf1`

## Kesimpulan

Audit terbaru tidak menemukan TODO source-code kritis pada scope order marketplace, pagination, refund settlement, atau tracking resi resmi. Sebagian temuan pada audit lama sudah ditutup oleh migration dan commit terbaru. Sisa pekerjaan utama membutuhkan database staging/production dan pengujian concurrency nyata.

## Status pekerjaan

| Area | Status source | Pekerjaan tersisa |
|---|---|---|
| Order marketplace | Selesai | Staging E2E dan concurrency test |
| Pagination buyer | Selesai | Uji volume besar dan performa staging |
| Pagination merchant | Selesai | Uji realtime saat load-more |
| Refund settlement | Selesai | Deploy migration 58 dan SOP rekonsiliasi shortfall |
| Tracking ekspedisi | Selesai | Verifikasi domain resmi dapat dibuka di production |
| Merchant workflow | Selesai | Staging acceptance test |
| Ojek passenger RPC/RLS | Selesai di source | Apply migration 52 dan dynamic RLS/concurrency test |
| Canonical status cleanup | Sebagian | Normalisasi status historis database bila diperlukan |
| Bootstrap manifest | Perlu dirapikan | Sinkronkan manifest jika dijadikan artefak deployment resmi |

## Pekerjaan yang sudah dikerjakan

Pagination menggunakan halaman maksimal 50 record pada buyer dan merchant. Buyer memakai infinite query, sedangkan merchant menggunakan cursor waktu dan deduplication ID.

Refund shortfall menggunakan tabel `merchant_refund_shortfalls`. Settlement provider dapat selesai tanpa menyamarkan kekurangan saldo merchant. Sisa kewajiban dicatat sebagai `OPEN` untuk rekonsiliasi.

Alur ojek passenger sudah memiliki RPC authoritative melalui `create_ride_request`, `accept_ride`, `cancel_ride`, `transition_ride_status`, dan `submit_ride_rating`. Migration tersebut juga mencabut direct insert/update authenticated pada `ride_requests`.

## Pekerjaan staging yang belum dilakukan

Pengujian berikut memerlukan database staging dan akun dengan role berbeda:

1. Passenger tidak dapat mengubah `driver_id`, tarif, koordinat, atau status melalui direct update.
2. Dua courier yang menerima ride yang sama menghasilkan tepat satu acceptance sukses.
3. Dua settlement refund yang sama tidak menghasilkan double deduction.
4. Buyer cancel bersamaan dengan courier acceptance menghasilkan satu state final yang valid.
5. Realtime reconnect tidak menggandakan order atau ride.
6. Migration 52 dan 58 benar-benar aktif pada database target.
7. Radius delivery dan ride diuji pada batas, di bawah batas, dan di atas batas.

## Catatan audit lama

Dokumen audit lama dapat menyebut direct mutation atau workflow ganda karena ditulis sebelum migration dan refactor terakhir. Status source yang menjadi acuan adalah migration terbaru, `MerchantOrdersWorkspace`, pagination implementation, dan `merchant_refund_shortfalls`.

## Prioritas berikutnya

Prioritas P0 adalah menerapkan migration ke staging dan menjalankan dynamic RLS/concurrency test. Prioritas P1 adalah menyusun SOP shortfall refund dan merapikan canonical status historis. Prioritas P2 adalah menyinkronkan manifest deployment dan menambahkan telemetry performa pagination.

## References

[1]: https://supabase.com/docs/guides/database/postgres/row-level-security "Supabase Row Level Security documentation"
