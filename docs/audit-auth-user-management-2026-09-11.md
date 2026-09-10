# Audit Keamanan Auth dan Manajemen User

**Tanggal audit:** 11 September 2026
**Cakupan:** session lifecycle, role hydration, route guard, password reset, RLS profiles/user_roles, admin user management, provisioning user, dan multi-tab auth.
**Metode:** inspeksi source code frontend, Edge Function, SQL bootstrap/migration, dan test yang tersedia. Tidak ada pengujian penetrasi atau query pada database produksi.

## Kesimpulan eksekutif

Proteksi route frontend sudah menggunakan `ProtectedRoute`, dan operasi sensitif database umumnya dibatasi RLS berdasarkan `auth.uid()` atau `is_admin()`. `admin-create-user` juga memverifikasi bearer token dan role admin melalui database sebelum memakai service role.

Namun, ditemukan **satu celah kritis pada tabel legacy password reset** serta beberapa bug konsistensi Auth/role yang perlu diperbaiki sebelum audit keamanan dianggap selesai. Celah password reset harus diprioritaskan karena token disimpan sebagai plaintext dan policy database mengizinkan anon/authenticated membaca seluruh isi tabel.

## Matriks temuan

| ID | Prioritas | Area | Temuan | Dampak |
|---|---|---|---|---|
| AUTH-P0-01 | **P0** | Password reset token | `password_reset_tokens.token` disimpan plaintext. Policy `Users can verify their tokens` memakai `USING (true)` untuk `anon, authenticated`, sehingga siapa pun dapat membaca seluruh token, email, expiry, dan status pemakaian. | Jika ada token aktif di tabel, penyerang dapat mengambil token reset akun lain dan mengambil alih akun. Policy insert juga sempat mengizinkan anon membuat token arbitrer. |
| AUTH-P1-02 | P1 | Role hydration race | `AuthContext` memanggil `fetchUserRoles` dari `onAuthStateChange` dan `getSession` secara paralel. Fetch role tidak memakai generation/user guard. Request lama dapat menyelesaikan setelah logout atau setelah user lain login dan menimpa state role. | UI dapat sementara menampilkan role user sebelumnya pada session baru; route guard dapat salah redirect. RLS tetap menjadi kontrol server-side, tetapi state frontend tidak konsisten. |
| AUTH-P1-03 | P1 | Role update atomicity | `AdminUsersPage` menghapus semua role user, lalu melakukan insert role baru sebagai dua request terpisah. Error delete tidak diperiksa. | Kegagalan di tengah proses dapat membuat user kehilangan seluruh role atau menyisakan role lama/baru secara tidak konsisten. Perubahan role admin sendiri juga tidak memiliki guard anti-self-lockout. |
| AUTH-P1-04 | P1 | Password policy inconsistency | Registration memakai password minimum 8 karakter dengan huruf dan angka, sedangkan `ResetPasswordPage` hanya mensyaratkan minimum 6 karakter. | User dapat mengganti password ke password yang lebih lemah daripada policy pendaftaran. |
| AUTH-P1-05 | P1 | Legacy reset flow | Frontend memakai Supabase `resetPasswordForEmail`, tetapi schema/policy `password_reset_tokens` legacy masih aktif dan terbuka. Tidak ada bukti repository bahwa flow legacy sudah dihapus atau tabel dikosongkan. | Jalur reset yang tidak terlihat dapat tetap menjadi attack surface; konfigurasi masa depan dapat menghidupkan kembali flow yang tidak aman tanpa disadari. |
| AUTH-P2-06 | P2 | Blocked session | Admin memblokir user dengan update `profiles.is_blocked`, tetapi tidak ada revocation session/Auth user di flow tersebut. | User yang sedang login mungkin tetap dapat memakai access token sampai token expire/refresh, tergantung policy tiap operasi. Route frontend juga tidak memeriksa `is_blocked` secara global. |
| AUTH-P2-07 | P2 | Admin role self-lockout | Admin dapat menghapus role `admin` milik dirinya sendiri melalui UI role management. Tidak ada validasi agar selalu ada admin tersisa atau confirmation khusus. | Admin dapat kehilangan akses operasional secara tidak sengaja; pemulihan memerlukan service role/database operator. |
| AUTH-P2-08 | P2 | Error and enumeration | Forgot password menampilkan error provider secara langsung. Login hanya menormalkan satu string error (`Invalid login credentials`). | Pesan provider dapat membocorkan detail internal dan perilaku error menjadi tidak konsisten. Respons reset perlu tetap generik untuk mencegah enumeration. |
| AUTH-P2-09 | P2 | Frontend role fallback | Jika query role timeout/error, AuthContext mengatur role menjadi `buyer`. Ini fail-closed untuk admin route, tetapi dapat membuat user merchant tampak sebagai buyer dan memicu state yang membingungkan. | Bug operasional, bukan privilege escalation; perlu state `rolesError` terpisah agar UI dapat meminta retry tanpa mengarang role buyer. |

## Analisis detail

### AUTH-P0-01 — Password reset token dapat dibaca publik

Tabel dibuat dengan kolom `email`, `token`, `expires_at`, dan `used_at`. Komentar awal menyatakan “only service role can access this table”, tetapi migration berikutnya menambahkan policy:

```sql
CREATE POLICY "Users can verify their tokens"
ON public.password_reset_tokens
FOR SELECT TO anon, authenticated
USING (true);
```

Policy ini mengizinkan pembacaan semua baris, bukan hanya token yang diberikan client. Policy update juga mengizinkan anon/authenticated mengubah setiap token yang belum expired tanpa mengikat token ke caller atau request tertentu.

Walaupun frontend saat ini menggunakan Supabase Auth built-in reset, tabel legacy tetap ada di schema dan tidak dibuktikan telah dihapus atau dikosongkan. Karena token adalah credential bearer, keberadaan satu row aktif cukup untuk membuat risiko account takeover.

**Perbaikan wajib:** drop seluruh policy SELECT/UPDATE/INSERT publik, revoke table privilege dari anon/authenticated, dan gunakan hanya service role/Edge Function. Jika flow legacy sudah tidak diperlukan, drop table setelah memastikan tidak ada consumer. Jika masih diperlukan, simpan hash token, gunakan lookup by hash, single-use atomic consume, expiry pendek, dan respons generic.

### AUTH-P1-02 — Race role hydration

`AuthContext` memasang listener `onAuthStateChange` dan secara terpisah menjalankan `getSession()` saat mount. Keduanya dapat memanggil `fetchUserRoles` untuk user yang sama. Fungsi tersebut tidak menerima session generation dan tidak mengecek apakah `userId` masih merupakan user aktif sebelum `setRoles`.

Skenario race: user A logout/login user B dengan cepat; query role A tertunda; query role B selesai; kemudian query role A selesai dan menimpa roles menjadi role A. `ProtectedRoute` memang tetap melihat `user` B, dan RLS database seharusnya menolak data A, tetapi UI dapat menampilkan navigasi/redirect yang salah.

**Perbaikan:** gunakan monotonically increasing request ID atau `activeUserIdRef`; sebelum `setRoles`, pastikan request masih aktif dan `supabase.auth.getUser()`/current session cocok. Hindari memulai hydration ganda saat initial auth event dan `getSession` sudah menghasilkan session yang sama.

### AUTH-P1-03 — Role update tidak atomic

`AdminUsersPage.handleSaveRoles` melakukan delete semua role, kemudian insert role pilihan. Hasil delete tidak diperiksa. Tidak ada RPC transaction yang melakukan validasi target, mencegah penghapusan admin terakhir, dan mengaudit perubahan dalam satu unit.

**Perbaikan:** buat RPC `admin_replace_user_roles(target_user_id, roles)` dengan `SECURITY DEFINER`, validasi caller admin, lock target, validasi role enum, larangan menghapus admin terakhir, delete/insert dalam satu transaction, dan audit event. Frontend hanya memanggil RPC.

### AUTH-P1-05 — Legacy reset surface

Tabel legacy bertentangan dengan flow frontend saat ini. Dua sistem reset password membuat kontrak keamanan sulit dipastikan. Supabase built-in reset harus menjadi satu-satunya flow, atau flow custom harus dipindahkan ke Edge Function yang tidak mengekspos token melalui PostgREST.

## Kontrol yang sudah baik

`ProtectedRoute` menunggu `authLoading` dan `rolesLoading` sebelum evaluasi role. Admin routes di `App.tsx` secara eksplisit memakai `allowedRoles={['admin']}`. `admin-create-user` memeriksa bearer token melalui `auth.getUser()`, melakukan lookup `user_roles` pada service-role client, memvalidasi email/password/nama/role, dan menghapus user Auth jika provisioning profile/role gagal.

Policy `profiles` membatasi user membaca profil sendiri atau admin; policy `user_roles` membatasi user membaca role sendiri dan admin mengelola role. User blocked dibatasi oleh policy update profil. Perbaikan selanjutnya tetap harus mempertahankan kontrol server-side ini dan tidak mengandalkan route guard sebagai security boundary.

## Urutan perbaikan

| Tahap | Pekerjaan | Prioritas |
|---|---|---|
| 1 | Tutup policy publik `password_reset_tokens`; revoke privilege; audit/drop tabel legacy. | P0 |
| 2 | Tambahkan test query policy bahwa anon/authenticated tidak dapat SELECT/UPDATE token. | P0 |
| 3 | Buat RPC atomic replace roles dan larang menghapus admin terakhir. | P1 |
| 4 | Tambahkan request generation guard pada role hydration dan `rolesError` yang dapat di-retry. | P1 |
| 5 | Samakan password policy reset dengan registration (minimal 8 + huruf + angka, atau policy resmi Auth). | P1 |
| 6 | Tetapkan blocked-user session revocation/refresh policy. | P2 |
| 7 | Normalisasi error reset/login dan tambahkan rate-limit/monitoring Auth. | P2 |

## Test case minimum

1. Anonymous client tidak dapat `SELECT` atau `UPDATE` `password_reset_tokens`.
2. Authenticated user A tidak dapat membaca, mengubah, atau mengonsumsi token user B.
3. Token reset yang sama hanya dapat dipakai sekali melalui operasi atomic.
4. Logout user A lalu login user B dengan query role A tertunda tidak boleh menghasilkan role A pada user B.
5. Replace roles gagal seluruhnya bila target adalah admin terakhir.
6. Kegagalan insert role tidak boleh meninggalkan target tanpa role karena transaksi harus rollback.
7. Password reset menolak password di bawah policy registration.
8. User blocked dengan session aktif ditolak pada endpoint sensitif dan session dicabut sesuai kebijakan.
9. Forgot password memberikan respons generik untuk email ada maupun tidak ada.
10. Admin create user gagal secara aman bila role tidak valid atau provisioning profile gagal.

## Batasan audit

Audit ini belum melakukan query terhadap database live, belum menguji PostgREST dengan anon key, dan belum menjalankan simulasi multi-tab/browser. Temuan P0 terkait token perlu diverifikasi segera pada staging/production dengan query policy, jumlah row aktif, dan audit log akses tabel.
