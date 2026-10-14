# Contributing dan Aturan No-Regression

Perubahan fitur harus memperbaiki masalah yang dituju tanpa menimbulkan error pada fitur lain.

## Definition of Done

Perubahan **belum siap di-merge atau deploy** sampai seluruh gate berikut lulus:

- [ ] Scope perubahan dan risiko lintas fitur dijelaskan.
- [ ] Test regresi untuk bug/fitur baru ditambahkan atau diperbarui.
- [ ] `pnpm validate:change-safety` lulus.
- [ ] Migration diuji pada database bersih.
- [ ] Migration dijalankan ulang untuk membuktikan idempotensi.
- [ ] Smoke test schema, grant, RLS, dan alur terkait lulus.
- [ ] Jika menyentuh checkout/order/payment, staging integration test dijalankan.
- [ ] Tidak ada error baru pada log staging.
- [ ] Perubahan migration dan dependency deployment sudah terdokumentasi.

## Perintah lokal wajib

```bash
pnpm install --frozen-lockfile
pnpm validate:change-safety
```

Safety gate mencakup package-manager alignment, validasi migration, bootstrap manifest, audit RLS, TypeScript, lint, seluruh unit/component test, dan production build.

## Aturan migration

1. Migration harus memiliki nama timestamp dan aman dijalankan ulang.
2. Gunakan `IF NOT EXISTS`, `CREATE OR REPLACE`, atau guard yang setara jika memang idempotensi diperlukan.
3. Jangan mengandalkan urutan migration yang tidak terdokumentasi.
4. Perubahan RPC harus disertai validasi fungsi, parameter, grant, dan schema dependency.
5. Jangan menjalankan migration production dari frontend public service.
6. Terapkan migration di staging lebih dahulu, lalu jalankan smoke test sebelum production.

## Aturan pull request

- Satu PR sebaiknya memiliki satu tujuan perubahan yang jelas.
- Perubahan lintas fitur harus menjelaskan alasan dan dampaknya.
- PR tidak boleh di-merge jika required check gagal atau tidak berjalan.
- Jika CI gagal sebelum job dimulai, PR dianggap **belum tervalidasi** dan harus diperbaiki/diulang.
- Commit hanya setelah test lokal relevan lulus; push bukan pengganti validasi staging.

## Urutan promosi

```text
branch fitur → test lokal → pull request → CI/regression gate
→ database staging → integration/smoke test → review → production
```

Untuk perubahan yang menyentuh database, keberhasilan build frontend saja tidak cukup.
