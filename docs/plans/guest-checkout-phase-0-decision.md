# Keputusan Tahap 0 — Guest Checkout Berbasis Access Token

**Tanggal:** 2 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Scope:** Konfirmasi kontrak bisnis sebelum migration dan RPC guest checkout.

## Keputusan

| Pertanyaan tahap 0 | Keputusan | Alasan dan dampak |
|---|---|---|
| Metode pembayaran guest | **Transfer bank dan online payment** | Keduanya sudah merupakan metode checkout marketplace yang didukung aplikasi. Guest tetap tunduk pada validasi server dan payment provider; COD tidak diaktifkan pada fase pertama karena belum termasuk kontrak guest yang diminta dan membutuhkan evaluasi fraud/confirmation tambahan. |
| Masa berlaku link status order | **30 hari sejak order dibuat** | Cukup untuk menyelesaikan transfer atau membuka kembali status order, tetap membatasi jendela akses token. Token mentah hanya dikembalikan saat order dibuat/retry idempotent yang sah dan tidak disimpan di database. |
| Claim order setelah login | **Ditunda; tidak tersedia pada fase 1** | Login tetap dapat ditawarkan untuk fitur akun, tetapi tidak boleh mengubah ownership order secara otomatis. Claim memerlukan flow terpisah dengan verifikasi token + kontak, audit log, dan aturan anti-double-claim. |
| Jumlah merchant per checkout | **Satu merchant per checkout** | Selaras dengan RPC authoritative saat ini dan audit checkout. Ini mencegah ambiguitas ongkir, voucher, payment invoice, reservation, dan rekonsiliasi. Cart multi-merchant harus dipisah sebelum submit. |

## Batasan yang disepakati untuk implementasi berikutnya

- Guest dapat membuat order hanya melalui RPC authoritative; tidak ada insert langsung ke `orders` atau `order_items` dari role `anon`.
- `buyer_id` order guest bernilai `NULL`; order tetap memiliki identitas melalui hash token guest.
- Token minimal 32 byte random, disimpan sebagai hash, memiliki expiry 30 hari, dan tidak dicatat ke log.
- Guest tidak mendapatkan akses ke riwayat akun, chat, review, voucher/account loyalty, refund/dispute berbasis akun, atau data profil tersimpan.
- Guest hanya dapat membaca status melalui RPC token-scoped yang mengembalikan data minimum.
- Pembayaran dan bukti transfer guest akan memakai RPC ownership-scoped terpisah; akses update langsung ke tabel tetap dicabut.

## Catatan implementasi

Repository saat ini menyimpan migration aktif sebagai ordered bootstrap bundle di `supabase/bootstrap/`, bukan direktori `supabase/migrations/`. Tahap 1 harus menambahkan bundle baru secara forward-only, memperbarui `manifest.json`, dan memvalidasi bundle tanpa menjalankannya terhadap production.

Keputusan ini merupakan baseline implementasi tahap 1. Perubahan metode pembayaran, expiry, claim, atau multi-merchant setelah bundle diterapkan harus dibuat sebagai perubahan kontrak/migration lanjutan, bukan mengubah migration historis.
