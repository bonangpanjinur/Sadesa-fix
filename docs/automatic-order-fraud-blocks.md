# Automatic Order Fraud Blocks

Sadesa sekarang memiliki blokir otomatis berbasis sinyal berulang dari order yang tidak dibayar atau gagal. Mekanisme ini dibuat sebagai **risk control sementara**, bukan keputusan final bahwa pengguna melakukan penipuan.

## Ambang blokir

| Target | Sinyal pada jendela 24 jam | Durasi blokir |
| --- | --- | --- |
| User | Order ketiga yang tidak dibayar, expired, atau gagal | 24 jam |
| Device | Order ketiga yang berkaitan dengan device ID yang sama | 24 jam |
| IP | Order ke-12 dari IP yang sama dan minimal 3 user berbeda | 24 jam |

Perhitungan dilakukan sebelum insert order. Dua order sebelumnya yang memenuhi kriteria membuat order ketiga menjadi order pemicu. Order pemicu tidak dibuat sebagai order aktif: trigger database mengubahnya menjadi `CANCELED`, memberi `payment_status = EXPIRED`, dan menulis alasan pada `cancellation_reason`.

## Penyimpanan dan audit

Block disimpan di tabel `public.order_fraud_blocks` dengan target (`user`, `device`, atau `ip`), alasan, jumlah order gagal, jumlah user unik, metadata, waktu pembuatan, dan `blocked_until`. Admin dapat membaca daftar block melalui RLS; data tersebut tidak dapat dibaca oleh anonymous atau pengguna biasa.

Block aktif pada user, device, atau IP diperiksa pada order berikutnya. Block yang sudah kedaluwarsa tidak menghalangi order baru. Konflik pada target yang sama memperpanjang masa block dan memperbarui metrik audit.

## Perlindungan false positive

IP bersama tidak langsung diblokir pada jumlah rendah. Blokir IP membutuhkan minimal 12 order gagal dan 3 user berbeda. IP, device ID, dan user ID juga tidak boleh menjadi satu-satunya dasar keputusan hukum atau tuduhan penipuan, karena jaringan seluler, CGNAT, Wi-Fi publik, VPN, browser reset, dan perangkat bersama dapat menghasilkan sinyal yang menyesatkan.

Admin sebaiknya meninjau block yang berulang dan menggabungkannya dengan bukti pembayaran, riwayat komunikasi, nilai transaksi, dan pola pengiriman. Jalur pemulihan dapat menghapus/menonaktifkan block secara manual melalui prosedur admin yang terkontrol.

## Deployment

Migration canonical:

```text
archive/supabase/migrations/20260923152000_automatic_order_fraud_blocks.sql
```

Bootstrap deployment:

```text
supabase/bootstrap/14_20260923152000_automatic_order_fraud_blocks.sql
```
