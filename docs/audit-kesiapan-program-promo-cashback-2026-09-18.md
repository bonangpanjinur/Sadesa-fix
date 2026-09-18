# Audit Kesiapan Program Cashback, Kupon, dan Promo

**Tanggal:** 18 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** admin, pedagang, pembeli, pricing checkout, kupon, promo produk, cashback, RLS, ledger, dan operasional.

## Kesimpulan eksekutif

SaDesa memiliki fondasi fitur promosi yang cukup matang: admin sudah memiliki halaman manajemen cashback, pedagang sudah memiliki promo produk dan voucher/kupon, pembeli sudah memiliki halaman voucher serta cashback, dan checkout marketplace sudah dipindahkan ke RPC authoritative. Dengan demikian, kesiapan produk untuk **pilot terbatas** berada pada level **kuning-hijau**.

Risiko paling penting berasal dari ketergantungan historis pada state client untuk harga dan voucher. Audit checkout sebelumnya telah mencatat temuan P0 terkait manipulasi nominal order dan konsumsi voucher. Implementasi pada perubahan ini menutup sisi cashback dengan ledger server-side yang idempotent, ownership aturan cashback milik merchant, dan saldo pembeli yang mengacu pada `profiles.user_id`.

**Catatan deployment:** migration baru wajib diterapkan ke staging dan production sebelum UI merchant cashback diaktifkan. Trigger cashback hanya membuat ledger `pending` ketika order berubah menjadi `DELIVERED` atau `DONE`; konfirmasi saldo memerlukan pemanggilan `confirm_due_cashback()` oleh job operasional/admin setelah masa dispute tiga hari.

## Matriks kesiapan per aktor

| Aktor | Kapabilitas | Status | Kontrol utama | Risiko tersisa |
|---|---|---:|---|---|
| Admin | Membuat, mengedit, mengaktifkan aturan cashback global | Siap pilot | RLS `is_admin()`, batas 0,1–50%, periode, minimum, maksimum | Belum ada dashboard budget/cost cap per program |
| Admin | Melihat total cashback confirmed dan penerima | Siap pilot | Query ledger terproteksi | Rekonsiliasi settlement masih membutuhkan laporan keuangan |
| Pedagang | Promo harga produk | Sudah tersedia | Workspace promo merchant | Harga promo harus selalu divalidasi checkout authoritative |
| Pedagang | Voucher/kupon | Sudah tersedia | Ownership voucher dan checkout RPC | Perlu staging concurrency test untuk usage limit |
| Pedagang | Cashback khusus toko | Diimplementasikan | `merchant_id`, RLS ownership, trigger award | Belum ada budget harian dan approval admin |
| Pembeli | Melihat promo/voucher | Sudah tersedia | Public active rules dan voucher page | UX pemilihan promo masih dapat dipersatukan |
| Pembeli | Melihat saldo dan riwayat cashback | Diperbaiki | `profiles.user_id`, ledger type/status | Penukaran saldo ke checkout utama masih membutuhkan integrasi RPC checkout |
| Sistem | Award cashback saat order selesai | Diimplementasikan | Trigger + function security definer + unique conflict | Job konfirmasi tiga hari tetap perlu dijadwalkan |
| Sistem | Reversal cashback saat refund | Diimplementasikan | Trigger `REFUNDED`, reversal ledger idempotent | Partial refund masih mengikuti kebijakan konservatif full reversal |
| Sistem | Redeem saldo atomik | Diimplementasikan | RPC `redeem_cashback`, row lock profile | Belum dipanggil dari checkout utama |

## Kontrak bisnis yang diimplementasikan

Aturan cashback dapat bersifat global (`merchant_id` kosong) atau khusus merchant. Aturan hanya berlaku dalam periode aktif, memiliki minimum order, persentase maksimum 50%, dan batas nominal opsional. Ketika order berubah ke `DELIVERED` atau `DONE`, sistem mengunci order, memilih aturan yang relevan, menghitung nominal dari subtotal server, lalu menulis transaksi `pending`. Unique partial index dan `ON CONFLICT DO NOTHING` membuat retry status tidak menggandakan cashback.

Cashback dikonfirmasi setelah tiga hari untuk memberi ruang dispute/refund. Fungsi `confirm_due_cashback()` mengubah transaksi menjadi `confirmed` dan menambah `profiles.cashback_balance` secara server-side. Admin kini memiliki aksi manual untuk menjalankan fungsi tersebut. Jika order direfund, trigger membuat reversal ledger; transaksi pending dibatalkan, sedangkan transaksi confirmed dikembalikan dari saldo secara auditable.

## Rencana pengembangan bertahap

| Fase | Hasil | Prioritas | Kriteria selesai |
|---|---|---:|---|
| 0. Hardening | Terapkan migration, staging RLS, uji trigger dan retry | P0 | Tidak ada award ganda dan merchant tidak dapat mengubah rule toko lain |
| 1. Pilot | Admin global + merchant cashback + buyer history | P0 | Dua merchant, dua buyer, order DONE, saldo dan ledger konsisten |
| 2. Checkout | Panggil `redeem_cashback` dari RPC checkout authoritative | P1 | Saldo terkunci atomik, rollback aman, idempotency key tersedia |
| 3. Kupon unified | Satu model campaign untuk global dan merchant, preview dan apply satu kontrak | P1 | Usage limit, per-user limit, periode, merchant scope diuji paralel |
| 4. Governance | Budget campaign, approval admin, audit log, pause otomatis | P1 | Program over-budget otomatis berhenti dan semua perubahan terlacak |
| 5. Analitik | ROI, redemption rate, incremental sales, merchant funding split | P2 | Laporan periodik dapat direkonsiliasi dengan order dan payout |

## Test matrix minimum sebelum produksi

1. Order berubah ke `DONE` dua kali: hanya satu cashback per aturan.
2. Dua request paralel menyelesaikan order: tidak ada duplicate ledger.
3. Aturan merchant A tidak dapat dibaca/diubah merchant B.
4. Rule global dan merchant-specific yang sama-sama cocok mengikuti prioritas yang disepakati.
5. Order di bawah minimum atau di luar periode tidak menerima cashback.
6. Nominal melebihi `max_cashback` dipotong server-side.
7. Konfirmasi sebelum tiga hari tidak mengubah saldo.
8. Konfirmasi setelah tiga hari menaikkan saldo tepat satu kali.
9. Refund setelah cashback confirmed menghasilkan reversal ledger, bukan pengurangan tanpa jejak. *(fase berikutnya)*
10. Checkout tidak menerima harga/discount dari client sebagai sumber kebenaran.

## Keputusan scope perubahan ini

Perubahan ini tidak menghapus atau menggandakan halaman promo/voucher yang sudah ada. `MerchantPromoPage` menjadi tempat pengelolaan cashback khusus toko di samping promo produk. `/admin/cashback` tetap menjadi workspace admin, sedangkan `/cashback` menjadi workspace pembeli. Integrasi penukaran saldo, budget campaign, notifikasi, dan reversal refund sengaja dipisahkan ke fase berikutnya agar pilot tidak mencampur perubahan finansial yang lebih berisiko.

## Quality gate dan batasan

Baseline quality gate pada checkout awal belum dapat dijalankan karena `node_modules` belum tersedia di sandbox (`tsc`, `eslint`, dan `vitest` tidak ditemukan). Setelah dependensi dipasang, jalankan `pnpm install --frozen-lockfile`, kemudian `pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm test`, dan `pnpm build`. Migration harus divalidasi dengan `pnpm validate:migrations` dan diterapkan melalui alur Supabase terkontrol; jangan menjalankan migration otomatis dari frontend Railway.
