# Audit dan perbaikan Antar Sendiri

Tanggal audit: **13 Oktober 2026**

## Temuan

1. Pilihan **Antar Sendiri** sudah tersedia pada dialog penerimaan pesanan internal.
2. RPC lama hanya membuat ledger setelah `self_delivery_attempt > 2`, sehingga pengantaran pertama tidak memiliki snapshot fee.
3. RPC lama memakai fallback **10%** ketika pengaturan tidak ditemukan. Ini bertentangan dengan kebijakan awal bahwa fee admin masih gratis.
4. Tidak ada kontrol admin khusus untuk persentase fee antar sendiri; pengaturan lama berada di `app_settings` tetapi tidak ditampilkan di panel yang relevan.
5. Pemanggilan frontend masih mengirim parameter `p_is_self_delivery` ke RPC yang sudah dikonsolidasikan menjadi tiga argumen.

## Aturan setelah perbaikan

- Ketika pedagang memilih **Antar Sendiri**, ongkos kirim tetap menjadi biaya pedagang sesuai nilai `orders.shipping_cost`.
- Fee admin dihitung pada pengantaran pertama menggunakan `shipping_cost × persentase admin`.
- Snapshot disimpan di `merchant_delivery_fee_ledger` dan di order (`self_delivery_fee_amount`, `self_delivery_fee_status`) agar dapat diaudit.
- Default rollout: `percent = 0`, `enabled = false`; status ledger adalah `WAIVED` dan UI menampilkan **Gratis**.
- Admin dapat mengatur persentase 0–100% dan mengaktifkan penagihan dari **Admin → Komisi Saldo Pedagang/Ojek → Antar Sendiri — Fee Admin**.
- Deduplikasi berdasarkan `order_id` mencegah retry RPC membuat tagihan ganda.
- Perubahan tarif hanya berlaku untuk order antar sendiri baru; order lama mempertahankan snapshot-nya.

## Catatan deployment

Migration canonical yang harus diterapkan pada Supabase adalah:

`archive/supabase/migrations/20261013050000_self_delivery_admin_fee.sql`

Setelah migration diterapkan, refresh schema PostgREST. Bootstrap bundle juga diperbarui dari archive agar instalasi baru mendapat perilaku yang sama.
