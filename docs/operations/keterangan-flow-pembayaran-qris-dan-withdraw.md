# Keterangan Flow Pembayaran QRIS Perusahaan sampai Withdraw

**Produk:** SaDesa Marketplace  
**Model pembayaran:** Satu QRIS/rekening perusahaan untuk seluruh transaksi  
**Status:** Rancangan alur operasional dan teknis

## 1. Gambaran singkat

Pembeli membayar ke QRIS perusahaan SaDesa. Dana tidak langsung ditransfer ke pedagang. Sistem terlebih dahulu memvalidasi pembayaran, mencatat pembagian dana di ledger internal, menahan bagian pedagang sampai pesanan aman, lalu menyediakan saldo untuk ditarik melalui proses withdraw.

Urutan sederhananya:

```text
Pembeli bayar
  → QRIS perusahaan
  → Webhook payment gateway
  → Validasi pembayaran
  → Ledger internal
  → Saldo pedagang HELD
  → Order selesai dan masa komplain aman
  → Saldo AVAILABLE
  → Withdraw
  → Transfer ke rekening pedagang
```

## 2. Penjelasan setiap tahap

### Tahap 1–2: Checkout dan pembuatan order

Pembeli memilih produk dan menyelesaikan checkout. Server menghitung ulang harga barang, jumlah, diskon, ongkos kirim, biaya layanan, dan total akhir. Sistem kemudian membuat order dengan status `PENDING_PAYMENT` dan pembayaran `UNPAID`.

Nominal dari frontend hanya untuk tampilan. Nominal yang dikirim ke payment gateway wajib berasal dari perhitungan server.

### Tahap 3: Pembuatan QRIS atau invoice

Sistem meminta payment gateway membuat QRIS dinamis atau invoice unik berdasarkan `order_id`. Setiap order sebaiknya memiliki referensi pembayaran yang berbeda agar pembayaran dapat dicocokkan secara otomatis.

Satu QRIS perusahaan boleh digunakan sebagai akun penerima, tetapi sebaiknya bukan satu QRIS statis yang sama tanpa identitas transaksi. QRIS dinamis atau invoice unik lebih aman untuk rekonsiliasi.

Data yang perlu disimpan antara lain:

- `order_id`;
- `external_id` atau nomor referensi gateway;
- `invoice_id`;
- nominal pembayaran;
- waktu kedaluwarsa;
- status pembayaran;
- idempotency key.

### Tahap 4: Pembeli membayar

Pembeli membayar melalui QRIS atau kanal pembayaran yang tersedia pada invoice. Redirect kembali ke aplikasi bukan bukti pembayaran berhasil. Status resmi harus berasal dari webhook payment gateway dan hasil verifikasi server.

### Tahap 5–7: Webhook dan validasi pembayaran

Payment gateway mengirim webhook ke backend SaDesa. Backend harus memeriksa:

1. token atau signature callback;
2. `invoice_id` dan `external_id`;
3. kecocokan order;
4. kecocokan nominal;
5. status transaksi;
6. event key atau idempotency.

Jika data valid, pembayaran ditandai `PAID`. Jika tidak valid, event ditolak dan dicatat untuk rekonsiliasi. Webhook yang sama dikirim ulang tidak boleh menggandakan pembayaran, earning, atau saldo.

## 3. Ledger dan pembagian dana

Walaupun uang masuk ke satu rekening perusahaan, sistem harus mencatat pembagian internal secara terpisah. Contoh:

| Komponen | Nilai |
|---|---:|
| Harga barang | Rp100.000 |
| Ongkos kirim | Rp10.000 |
| Biaya layanan SaDesa | Rp2.000 |
| **Total dibayar pembeli** | **Rp112.000** |
| Hak pedagang | Rp100.000 |
| Bagian kurir/operasional | Rp10.000 |
| Pendapatan SaDesa | Rp2.000 |

Pembagian dana dihitung oleh server, bukan berdasarkan nominal yang dapat diubah dari frontend.

## 4. Status saldo pedagang

| Status | Keterangan |
|---|---|
| `HELD` | Pembayaran sudah diterima, tetapi dana belum boleh ditarik. |
| `AVAILABLE` | Dana sudah memenuhi aturan settlement dan dapat diajukan untuk withdraw. |
| `WITHDRAW_PENDING` | Dana sedang di-hold karena pedagang telah mengajukan withdraw. |
| `PAID_OUT` | Dana berhasil ditransfer ke rekening pedagang. |
| `REFUNDED` | Dana dibatalkan karena refund atau sengketa. |
| `REVERSED` | Dana dikoreksi karena kesalahan rekonsiliasi atau pembatalan. |

## 5. Pesanan, settlement, dan masa komplain

Setelah pembayaran `PAID`, pedagang memproses pesanan. Pesanan kemudian dikirim atau disiapkan untuk pickup sampai diterima pembeli.

Saldo pedagang tidak langsung menjadi `AVAILABLE`. Saldo tetap `HELD` sampai:

- pesanan berstatus selesai atau `DONE`;
- masa komplain berakhir;
- tidak ada refund aktif;
- tidak ada dispute yang belum diselesaikan;
- aturan settlement terpenuhi.

Jika ada komplain atau refund, admin meninjau kasus tersebut. Ledger dapat dikurangi, dikembalikan, atau disesuaikan sesuai keputusan yang dicatat.

## 6. Proses withdraw pedagang

Pedagang dapat mengajukan withdraw hanya jika:

- akun pedagang aktif;
- rekening tujuan sudah terdaftar dan diverifikasi;
- saldo `AVAILABLE` mencukupi;
- nominal memenuhi minimum withdraw;
- tidak ada saldo yang sedang digunakan oleh withdraw lain;
- tidak ada blokir fraud atau dispute.

Alurnya:

1. Pedagang melihat saldo `HELD`, `AVAILABLE`, dan saldo yang sedang diproses.
2. Pedagang mengisi nominal withdraw.
3. Server memvalidasi saldo dan rekening.
4. Sistem membuat withdrawal request berstatus `PENDING`.
5. Saldo di-hold agar tidak dapat ditarik dua kali.
6. Finance memeriksa request.
7. Finance melakukan transfer dari rekening perusahaan.
8. Sistem menyimpan waktu transfer, nominal aktual, bank tujuan, dan `bank_reference`.
9. Jika berhasil, status menjadi `PAID_OUT`.
10. Jika gagal, status menjadi `FAILED` atau masuk review; saldo dikembalikan tepat satu kali.

## 7. Status withdrawal

| Status | Keterangan |
|---|---|
| `PENDING` | Request dibuat dan saldo sedang di-hold. |
| `PROCESSING` | Finance sedang melakukan verifikasi atau transfer. |
| `PAID_OUT` | Transfer berhasil dan referensi bank tersimpan. |
| `REJECTED` | Request ditolak; alasan wajib dicatat dan saldo dikembalikan. |
| `FAILED` | Transfer gagal; saldo dikembalikan atau diproses melalui retry terkontrol. |
| `CANCELLED` | Request dibatalkan sesuai aturan. |

## 8. Rekonsiliasi Admin dan Finance

Finance melakukan pencocokan pada beberapa lapisan:

1. **Pembayaran masuk:** invoice gateway dibandingkan dengan webhook dan mutasi rekening perusahaan.
2. **Order:** pembayaran dibandingkan dengan order dan nominal server.
3. **Ledger:** bagian pedagang, fee, ongkir, refund, dan koreksi dibandingkan dengan transaksi asli.
4. **Settlement:** order selesai dan release saldo dibandingkan dengan aturan settlement.
5. **Withdraw:** request withdraw dibandingkan dengan transfer bank dan `bank_reference`.

Semua selisih harus masuk antrean pengecualian, bukan diperbaiki dengan mengubah saldo langsung.

## 9. Aturan keamanan penting

- Jangan menganggap redirect sukses sebagai bukti pembayaran.
- Jangan mempercayai nominal dari frontend.
- Gunakan webhook yang tervalidasi dan idempotent.
- Jangan membuat earning ganda ketika webhook dikirim ulang.
- Gunakan hold saldo ketika withdraw dibuat.
- Jangan menghapus transaksi keuangan tanpa alasan dan audit log.
- Jangan mengubah saldo secara langsung dari frontend.
- Transfer manual tetap harus menyimpan referensi bank dan bukti sesuai SOP.
- Untuk sesi keuangan yang sudah ditutup, gunakan koreksi atau reversal, bukan penghapusan.

## 10. Rekomendasi tahap implementasi

Untuk tahap awal, finance dapat melakukan transfer withdraw secara manual dari rekening perusahaan. Sistem tetap membuat request, melakukan hold saldo, menyimpan status, dan meminta finance memasukkan `bank_reference` setelah transfer.

Setelah ledger, refund, dispute, dan rekonsiliasi stabil, proses transfer dapat diotomatisasi menggunakan payout API payment gateway atau bank yang dipilih. Otomatisasi harus mempertahankan idempotency, audit log, retry aman, dan rekonsiliasi bank.
