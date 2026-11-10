# Audit Upload Foto QRIS Sadesa — 2026-11-03

## Ringkasan

Audit dilakukan pada alur **Pengaturan Toko → QRIS Sadesa** di repository `bonangpanjinur/Sadesa-fix`. Gejala yang dilaporkan adalah halaman putih ketika memilih atau mengunggah foto dokumen QRIS.

## Temuan

1. Komponen `MerchantQrisApplicationCard` mengelola file QRIS dengan handler inline yang hanya menyimpan `File` ke state. Validasi baru dijalankan saat submit, sehingga file invalid tidak memberi umpan balik langsung dan input file yang sama sulit dipilih ulang.
2. Status pengajuan QRIS dimuat dari tabel baru `qris_applications`. Kegagalan query hanya dikirim sebagai toast, tanpa fallback UI di dalam kartu. Jika data/storage tidak siap atau terjadi error runtime pada komponen, halaman pengaturan berisiko terlihat kosong.
3. Upload empat dokumen dilakukan berurutan. Bila upload berhasil tetapi insert/update database gagal, object storage dapat tertinggal sebagai orphan file.
4. Kontrak database sudah mensyaratkan bucket privat `qris-applications`, MIME `image/jpeg`/`image/png`, dan batas 2 MB. Komponen perlu menegakkan kontrak yang sama sebelum request dikirim.

## Perbaikan

File yang diperbarui: `src/components/merchant/MerchantQrisApplicationCard.tsx`.

- Menambahkan error boundary lokal agar error render QRIS tidak mengosongkan seluruh halaman pengaturan.
- Menambahkan fallback UI jika status QRIS gagal dimuat, sementara bagian pengaturan toko lain tetap bisa digunakan.
- Menambahkan validasi langsung saat memilih file: JPG/PNG, file tidak kosong, maksimal 2 MB.
- Menampilkan pesan kesalahan pada field dokumen dan mereset nilai input file agar file yang sama dapat dipilih ulang.
- Menetapkan `type="button"` pada tombol kirim agar tidak memicu submit form induk secara tidak sengaja.
- Menambahkan guard terhadap submit ganda dan menormalkan `documents` yang null/malformed.
- Menghapus object storage yang baru terunggah jika insert/update database gagal.
- Menyederhanakan pesan error storage/network/policy agar pengguna mendapat instruksi yang dapat ditindaklanjuti.
- Mempertahankan bucket privat dan tidak membuat URL publik untuk KTP/selfie.

## Validasi

- Test terarah: **10 test lulus** pada `fileValidation`, `merchantSettingsValidation`, dan `StoreQRCode`.
- Lint file QRIS: **lulus**.
- Production build Vite + service worker: **lulus**.
- `git diff --check`: **lulus**.

## Catatan deployment

Perbaikan frontend tidak menggantikan kebutuhan deployment migration QRIS. Environment Supabase target tetap harus memiliki tabel `qris_applications`, bucket privat `qris-applications`, policy storage merchant, dan policy/RLS yang tercantum pada `supabase/bootstrap/133_20261026120000_qris_merchant_application_workflow.sql`.
