# PWA Device Security Audit

Sadesa sekarang mencatat dua sinyal keamanan pada `public.pwa_device_sessions`: `device_id` dan `ip_address`.

## Data yang dicatat

- `device_id`: UUID acak yang dibuat sekali per browser dan disimpan di `localStorage` dengan key `desamart:pwa-device-id`. Nilai ini bukan MAC address dan bukan identitas permanen; pengguna dapat menghapusnya dengan menghapus data situs.
- `ip_address`: IP publik yang terlihat dari endpoint `https://api.ipify.org` ketika session perangkat terautentikasi diregistrasikan. Nilai bertipe PostgreSQL `inet` dan dapat bernilai null jika endpoint tidak tersedia, jaringan memblokir permintaan, atau perangkat memakai VPN/proxy.
- `user_agent`, platform, jenis perangkat, waktu terakhir terlihat, dan status session tetap dicatat seperti sebelumnya.

## Alur

Pada registrasi session setelah login, frontend mengambil IP publik dengan timeout 2,5 detik. Hasil yang valid dikirim ke RPC `register_pwa_device` sebagai `p_ip_address`. Kegagalan mengambil IP tidak menggagalkan login atau registrasi perangkat; RPC menyimpan `null` atau mempertahankan IP sebelumnya. Device ID tidak pernah diganti otomatis sehingga beberapa login pada browser yang sama dapat dikorelasikan secara internal.

IP ditampilkan hanya pada halaman admin PWA Device Management. Akses tabel tetap dibatasi oleh Row Level Security yang sudah ada; pengguna biasa hanya dapat melihat session miliknya sendiri, sedangkan daftar seluruh perangkat tersedia untuk admin.

## Batasan dan penggunaan yang benar

IP dan device ID adalah **sinyal korelasi**, bukan bukti identitas atau bukti penipuan. IP dapat berubah pada jaringan seluler, dibagi oleh banyak pengguna melalui CGNAT/Wi-Fi publik, atau disamarkan oleh VPN. Permintaan browser juga dapat dimanipulasi, sehingga data ini tidak boleh menjadi satu-satunya dasar pemblokiran atau tindakan hukum.

Gunakan data ini bersama status pembayaran, jumlah order gagal, pola waktu, rate limit, dan review manual. Terapkan prinsip least privilege pada akses admin dan tetapkan kebijakan retensi sesuai kebijakan privasi Sadesa.

## Deployment

Migration canonical:

```text
archive/supabase/migrations/20260923150000_pwa_device_ip_audit.sql
```

Bootstrap deployment:

```text
supabase/bootstrap/13_20260923150000_pwa_device_ip_audit.sql
```
