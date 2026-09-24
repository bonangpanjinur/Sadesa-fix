# Audit dan Perluasan Verifikator untuk Ojek

**Tanggal:** 24 September 2026  
**Ruang lingkup:** role `verifikator`, alur approval merchant, registrasi courier/ojek, RLS, RPC, dan storage dokumen.

## Ringkasan

Sebelum perubahan, verifikator telah memiliki halaman dan alur approval merchant melalui kode verifikator. Pada sisi ojek, tabel `couriers` sudah memiliki status `PENDING`, `APPROVED`, dan `REJECTED`, serta fungsi approval yang digunakan admin, tetapi belum tersedia halaman verifikasi ojek untuk verifikator.

Temuan paling penting adalah policy lama `Verifikator can manage couriers` yang memberikan `FOR ALL` kepada setiap pengguna ber-role `verifikator` untuk seluruh baris tabel `couriers`. Selain terlalu luas secara wilayah, policy tersebut secara teori mengizinkan perubahan langsung terhadap field identitas, payout, status operasional, dan data approval. Ini tidak sesuai dengan prinsip least privilege.

## Temuan Audit

| ID | Severity | Temuan | Dampak |
|---|---|---|---|
| VOJ-01 | P0 | Policy `Verifikator can manage couriers` memberikan `FOR ALL` tanpa pembatas desa atau group. | Satu verifikator dapat membaca dan mengubah data ojek di luar kewenangannya. |
| VOJ-02 | P1 | Tidak ada halaman verifikasi ojek pada area verifikator, walaupun status dan dokumen courier sudah tersedia. | Proses verifikasi ojek harus dilakukan melalui admin atau query manual. |
| VOJ-03 | P1 | Tidak ada RPC approval khusus untuk verifikator; pola frontend lama menggunakan update langsung. | Field selain keputusan approval berisiko ikut dapat dimodifikasi. |
| VOJ-04 | P1 | Upload registrasi menyimpan file pada path `ktp/`, `photo/`, dan `vehicle/`, sementara policy owner mengharapkan folder pertama berupa `auth.uid()`. | Pemilik tidak memperoleh akses konsisten ke dokumen sendiri; struktur path juga tidak memiliki namespace user. |
| VOJ-05 | P1 | Registrasi menggunakan `getPublicUrl` untuk bucket private dan policy upload tidak membatasi namespace user. | Kontrak URL dokumen tidak tepat dan upload dapat disalahgunakan jika policy deployment tidak diketatkan. |

## Keputusan Desain

Kewenangan verifikator ojek dipetakan melalui `trade_groups.village_id`. Seorang verifikator dapat melihat dan memproses ojek hanya jika ojek tersebut berada pada desa yang terhubung ke group aktif milik verifikator tersebut. Ojek tanpa desa yang terhubung atau tanpa group aktif tetap diproses oleh admin.

Keputusan approve/reject dilakukan melalui RPC `public.review_courier`. RPC memvalidasi autentikasi, keputusan yang diperbolehkan, keberadaan courier, dan scope desa sebelum hanya mengubah field approval: `registration_status`, `status`, `approved_by`, `approved_at`, `rejection_reason`, dan `updated_at`.

Dokumen tetap berada di bucket private. Registrasi baru menyimpan path dengan format `<user_id>/<jenis>/<filename>`, bukan URL publik. Halaman verifikator membuat signed URL berumur sepuluh menit hanya setelah RLS storage memvalidasi bahwa verifikator ditugaskan pada desa courier tersebut.

## Implementasi

Perubahan yang diterapkan meliputi migrasi `23_20260924104500_courier_verification_scope.sql`, halaman `/verifikator/couriers`, menu sidebar dan badge jumlah pending, helper `reviewCourier`, serta perbaikan path upload pada `RegisterCourierPage`.

Halaman verifikasi menampilkan identitas operasional yang diperlukan, wilayah, kendaraan, status, dan detail dokumen. Dokumen KTP, foto diri, dan kendaraan hanya dimuat melalui signed URL; halaman tidak mengubah field identitas atau payout.

## Acceptance Criteria

1. Verifikator tanpa group aktif pada desa tertentu tidak dapat melihat courier desa tersebut.
2. Verifikator tidak dapat memanggil `review_courier` untuk courier di luar scope.
3. Approve mengaktifkan courier dan mengisi `approved_by` serta `approved_at`.
4. Reject mensyaratkan alasan dan menonaktifkan courier.
5. Buyer biasa tidak mendapatkan akses ke dokumen courier.
6. Upload baru menggunakan namespace user dan bucket tetap private.
7. Admin tetap dapat mengelola semua courier melalui policy admin yang sudah ada.

## Status Verifikasi Kode

`git diff --check` berhasil dan validasi migrasi mengenali 23 file deployment dalam urutan leksikografis. Validasi bundle konsolidasi lama masih melaporkan hash mismatch yang sudah ada pada bundle `01`, `05`, dan `10`; perubahan ini tidak mengedit bundle tersebut. Typecheck/test frontend belum dapat dijalankan pada sandbox karena binary lokal `tsc` dan `vitest` tidak terpasang dan `npx` meminta instalasi interaktif.
