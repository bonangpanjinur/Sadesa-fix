# Audit Alur Kerja dan Penghasilan Verifikator

## Ringkasan

Verifikator memperoleh pendapatan dari merchant yang terhubung melalui `verifikator_code` dan `verifikator_id`. Ketika pembayaran subscription merchant berubah menjadi `PAID`, trigger database mengambil persentase `group_commission_percent` dari paket transaksi yang dibeli, menghitung komisi berdasarkan `payment_amount`, lalu membuat baris pada `verifikator_earnings` dengan status `PENDING`.

Sebelumnya, pengaturan persentase komisi sudah tersedia secara teknis di halaman paket transaksi admin, tetapi labelnya masih menyebut **Komisi Kas** dan belum tersedia secara jelas dari dashboard **Komisi Verifikator**. Selain itu, halaman penghasilan verifikator menghitung saldo tersedia dari earning berstatus `PAID`, padahal earning baru menjadi `PAID` setelah withdrawal disetujui admin. Kondisi tersebut dapat membuat saldo tersedia tampil nol walaupun terdapat earning pending yang dapat ditarik.

## Alur Kerja Saat Ini

| Tahap | Mekanisme | Sumber data |
|---|---|---|
| Identifikasi verifikator | Merchant menyimpan `verifikator_id`; kode referral disimpan pada `verifikator_codes` | `merchants`, `verifikator_codes` |
| Pembayaran merchant | Subscription merchant disetujui/berubah menjadi `PAID` | `merchant_subscriptions` |
| Pembuatan earning | Trigger `record_verifikator_commission()` menghitung `payment_amount × group_commission_percent / 100` | `transaction_packages`, `verifikator_earnings` |
| Saldo verifikator | Earning baru berstatus `PENDING` | `verifikator_earnings` |
| Pengajuan withdrawal | Verifikator memasukkan nominal dan rekening; status awal `PENDING` | `verifikator_withdrawals` |
| Persetujuan admin | RPC `process_verifikator_withdrawal` mengubah earning yang teralokasi menjadi `PAID` dan memproses withdrawal | RPC/database |

## Sumber dan Kontrol Nilai Penghasilan

Nilai komisi tidak dihitung dari input client. Nilai tersebut dihitung di database menggunakan persentase yang tersimpan pada paket transaksi. Admin memiliki hak `UPDATE` terhadap `transaction_packages` melalui RLS, sehingga persentase dapat dikontrol secara aman oleh admin.

Perubahan persentase berlaku untuk **pembayaran subscription baru** setelah perubahan disimpan. Earning yang sudah tercatat menyimpan `commission_percent` dan `commission_amount` sendiri sehingga histori tidak berubah retroaktif.

## Perubahan yang Diterapkan

Dashboard **Komisi Verifikator** sekarang memiliki panel **Pengaturan Penghasilan Verifikator**. Admin dapat melihat setiap paket transaksi, status paket, nilai paket, dan mengubah persentase komisi dalam rentang 0% sampai 100%. Panel tersebut juga menjelaskan bahwa perubahan hanya berlaku untuk pembayaran baru dan tidak mengubah earning lama.

Form paket transaksi admin juga diperbaiki: label **Komisi Kas (%)** diubah menjadi **Komisi Verifikator (%)**, dengan input desimal, batas minimum 0, dan batas maksimum 100.

Perhitungan saldo tersedia verifikator diperbaiki. Karena earning berstatus `PENDING` sebelum withdrawal disetujui, saldo yang dapat diajukan dihitung sebagai total earning `PENDING` dikurangi withdrawal `PENDING`. Setelah admin menyetujui withdrawal, earning terkait berubah menjadi `PAID` dan tidak dihitung ulang sebagai saldo pending.

## Catatan Risiko yang Masih Perlu Dipantau

RPC persetujuan withdrawal saat ini mengalokasikan earning penuh secara berurutan berdasarkan nominal withdrawal. Karena satu earning tidak mendukung pembayaran parsial, nominal withdrawal idealnya sama dengan kombinasi earning penuh. Pengembangan berikutnya sebaiknya menambahkan tabel alokasi payout atau mewajibkan nominal withdrawal sama dengan saldo pending yang dapat dialokasikan secara utuh.

Pembayaran aktual ke rekening bank belum dilakukan otomatis oleh RPC. Status **APPROVED** berarti admin menyetujui dan mencatat proses payout; bukti transfer dan rekonsiliasi tetap perlu dikelola sesuai prosedur operasional admin.

## File yang Diubah

- `src/pages/admin/AdminVerifikatorCommissionsPage.tsx`
- `src/pages/admin/AdminTransactionQuotaPage.tsx`
- `src/pages/verifikator/VerifikatorEarningsPage.tsx`
- `docs/audit-penghasilan-verifikator-2026-09-24.md`

## Rekomendasi Operasional

Admin sebaiknya mengatur persentase sebelum merchant melakukan pembayaran subscription. Setelah ada transaksi baru, nilai komisi yang tersimpan pada histori earning menjadi sumber kebenaran dan tidak boleh diedit manual tanpa audit koreksi. Withdrawal sebaiknya diproses setelah rekening diverifikasi dan bukti transfer disimpan.

> Kesimpulan: penghasilan verifikator sekarang dapat diatur dari dashboard admin berdasarkan paket transaksi, dihitung server-side saat pembayaran merchant berhasil, dan saldo tersedia di sisi verifikator sudah mengikuti lifecycle earning yang sebenarnya.
