## Ringkasan

Jelaskan masalah yang diperbaiki dan hasil yang diharapkan.

## Scope dan risiko

- Area/f fitur yang diubah:
- Area/f fitur lain yang mungkin terdampak:
- Alasan perubahan lintas fitur (jika ada):

## Validasi wajib

- [ ] Test regresi untuk bug/fitur ini ditambahkan atau diperbarui.
- [ ] `pnpm validate:change-safety` lulus.
- [ ] Migration validation lulus (jika ada perubahan SQL).
- [ ] Migration sudah diuji pada database bersih (jika ada perubahan SQL).
- [ ] Migration sudah diuji ulang/idempotensi (jika ada perubahan SQL).
- [ ] Smoke test RLS/schema/grant lulus (jika relevan).
- [ ] Staging integration test lulus (untuk checkout/order/payment/auth atau perubahan berisiko).
- [ ] Log staging diperiksa dan tidak ada error baru yang terkait.

## Database dan deployment

- [ ] Tidak ada migration yang dijalankan dari frontend public service.
- [ ] Dependency schema/RPC/grant sudah tersedia sebelum RPC dipakai.
- [ ] Rollback atau repair plan tersedia bila perubahan gagal.

## Catatan reviewer

Tuliskan risiko yang masih tersisa, asumsi, dan langkah verifikasi setelah deploy.
