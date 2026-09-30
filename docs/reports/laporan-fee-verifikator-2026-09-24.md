# Laporan Fee Verifikator

## Tujuan

Halaman **Pendapatan** verifikator sekarang menampilkan ringkasan fee yang berasal dari dua sumber operasional: komisi pedagang dan fee ojek. Ringkasan gabungan tidak mengubah saldo yang dapat ditarik. Saldo tarik tetap mengikuti lifecycle `verifikator_earnings` dan withdrawal yang disetujui admin.

## Ringkasan dashboard

| Kartu laporan | Sumber data | Perhitungan |
|---|---|---|
| Total fee terlapor | `verifikator_earnings` + `courier_earnings` | `SUM(commission_amount) + SUM(amount)` |
| Dari pedagang | `verifikator_earnings` | `SUM(commission_amount)` untuk `verifikator_id` pengguna aktif |
| Dari ojek | `courier_earnings` melalui courier dalam scope verifikator | `SUM(amount)` |
| Saldo tersedia | `verifikator_earnings` + `verifikator_withdrawals` | Komisi `PENDING` dikurangi withdrawal `PENDING` |

Rincian fee ojek dapat dilihat pada tab **Fee Ojek**, dengan tanggal, nama courier, jenis fee, nominal, dan status. Data courier dibatasi menggunakan `couriers.verifikator_id` atau kode aktif yang cocok dengan `verifikator_codes.verifikator_id`.

Dashboard juga menyediakan filter **Mulai tanggal** dan **Sampai tanggal**. Filter menggunakan `created_at` pada `verifikator_earnings` dan `courier_earnings`, berlaku pada total fee, jumlah catatan, dan kedua tabel laporan. Jika tanggal mulai lebih besar dari tanggal akhir, dashboard menampilkan validasi dan tidak menghitung catatan periode tersebut. Kartu saldo tersedia dan riwayat withdrawal tetap merepresentasikan saldo operasional saat ini.

Dashboard juga menyediakan grafik **Tren pendapatan** dengan pilihan agregasi harian atau bulanan. Grafik menggabungkan `commission_amount` dari pedagang dan `amount` dari ojek. Panel **Ringkasan komisi** dapat diganti antara kategori wilayah—menggunakan `district` lalu fallback ke `city`—atau status komisi (`PENDING`, `PAID`, `APPROVED`, dan `REJECTED`). Kedua visualisasi mengikuti filter tanggal aktif.

## Struktur `verifikator_codes`

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid` | Primary key |
| `code` | `text` | Kode referral unik yang dipakai saat registrasi |
| `trade_group` | `text` | Nama/identitas kelompok dagang |
| `verifikator_id` | `uuid` | Pemilik kode, mengarah secara logis ke pengguna role `verifikator` |
| `description` | `text`, nullable | Keterangan kode |
| `is_active` | `boolean` | Status kode untuk penggunaan baru |
| `usage_count` | `integer` | Jumlah penggunaan kode |
| `max_usage` | `integer`, nullable | Batas penggunaan bila diatur |
| `created_at` | `timestamptz` | Waktu pembuatan |

> `verifikator_codes` adalah tabel pemetaan referral. Relasinya dengan merchant dan courier saat ini terutama bersifat **logical relationship** melalui nilai `code`; sinkronisasi `verifikator_id` dilakukan oleh trigger/helper saat data merchant atau courier dibuat atau diperbarui.

## Relasi data

```text
verifikator_codes
  ├── code ───────────────► merchants.verifikator_code
  │                           └── merchants.verifikator_id
  │                               └── verifikator_earnings.verifikator_id
  │
  └── code ───────────────► couriers.verifikator_code
                              └── couriers.verifikator_id
                                  └── courier_earnings.courier_id
```

### Pedagang

Merchant menyimpan `verifikator_code` saat mendaftar. Trigger referral mencari kode yang sudah dinormalisasi, lalu mengisi `merchants.verifikator_id`. Saat subscription/penjualan yang memenuhi syarat dibayar, trigger komisi membuat baris `verifikator_earnings` yang menyimpan `merchant_id`, `package_id`, `subscription_id`, `commission_percent`, dan `commission_amount`.

### Ojek

Courier menyimpan `verifikator_code` dan `verifikator_id`. Fee operasional disimpan pada `courier_earnings`, yang memiliki foreign key langsung `courier_id → couriers.id`. Karena `courier_earnings` tidak menyimpan `verifikator_id`, laporan menghubungkan fee melalui tabel `couriers` terlebih dahulu. Migration `34_20260924180000_verifikator_courier_earnings_report.sql` menambahkan policy `SELECT` terbatas agar verifikator hanya dapat membaca fee courier dalam scope kode miliknya.

### Komisi verifikator

Komisi pedagang disimpan terpisah di `verifikator_earnings` dan memiliki foreign key ke `merchants`, `transaction_packages`, dan `merchant_subscriptions`. Dengan demikian, fee ojek dan komisi pedagang dapat dilaporkan berdampingan tanpa mencampur status payout.

## File implementasi

- `src/pages/verifikator/VerifikatorEarningsPage.tsx` — kartu total fee, ringkasan relasi, dan tab rincian fee ojek.
- `supabase/bootstrap/34_20260924180000_verifikator_courier_earnings_report.sql` — policy baca terbatas untuk laporan fee ojek.
- `docs/reports/laporan-fee-verifikator-2026-09-24.md` — dokumentasi struktur dan perhitungan.
