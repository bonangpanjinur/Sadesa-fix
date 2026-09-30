# Dokumentasi API Autentikasi

Dokumen ini menjelaskan alur autentikasi email pada SaDesa. Implementasi menggunakan Supabase Auth melalui `@supabase/supabase-js`; aplikasi tidak menyediakan route REST autentikasi custom. Endpoint di bawah ini berada di `${VITE_SUPABASE_URL}/auth/v1` dan dipanggil oleh Supabase client.

> **Keamanan utama:** keberadaan email tidak boleh diungkapkan melalui respons lupa password. Supabase dapat mengembalikan respons sukses yang sama untuk email yang terdaftar maupun tidak terdaftar guna mencegah account enumeration. [1]

## Prasyarat dan header

Semua request memakai URL project Supabase dan publishable/anonymous key. Jangan pernah menaruh `service_role` key di browser.

```text
Authorization: Bearer <VITE_SUPABASE_PUBLISHABLE_KEY>
apikey: <VITE_SUPABASE_PUBLISHABLE_KEY>
Content-Type: application/json
```

Pada aplikasi, client dikonfigurasi di `src/integrations/supabase/client.ts`. Email dinormalisasi dengan `trim().toLowerCase()` sebelum dikirim. Policy email yang dipakai bersama berada di `src/lib/emailValidation.ts`.

## 1. Registrasi akun baru

### Operasi aplikasi

```ts
const { data, error } = await supabase.auth.signUp({
  email: normalizeEmail(email),
  password,
  options: {
    emailRedirectTo: window.location.origin,
    data: { full_name: fullName },
  },
});
```

Implementasi ini berada di `AuthContext.signUp()` dan digunakan oleh `AuthPage`.

### Endpoint Supabase

```http
POST /auth/v1/signup
```

Contoh body:

```json
{
  "email": "user@example.com",
  "password": "PasswordAman123",
  "data": {
    "full_name": "Nama Pengguna"
  },
  "gotrue_meta_security": {},
  "redirect_to": "https://app.example.com"
}
```

Dalam pemanggilan JavaScript, `redirect_to` dikirim melalui `options.emailRedirectTo`.

### Sukses

Jika konfirmasi email diwajibkan, `data.user` tersedia dan `data.session` biasanya `null`. Aplikasi kemudian membuka `/email-confirmation` dan menyimpan batas waktu OTP lokal selama 10 menit.

Jika project dikonfigurasi untuk langsung membuat session, `data.session` dapat tersedia. Konfigurasi production SaDesa tetap mengharuskan email dikonfirmasi sebelum login.

### Error umum

| Kondisi | Perilaku aplikasi |
|---|---|
| Format email tidak valid | Request tidak dikirim; pesan validasi ditampilkan di form. |
| Password tidak memenuhi policy | Request tidak dikirim; pengguna diminta memperbaiki password. |
| Terlalu banyak pendaftaran untuk email yang sama | Request diblok oleh rate limit lokal atau oleh Supabase. |
| Email sudah digunakan | Pesan error dari Supabase ditampilkan tanpa menampilkan informasi sensitif tambahan. |

### Rate limit pengiriman email

Registrasi dibatasi maksimal **3 permintaan email verifikasi per email dalam 10 menit** oleh limiter browser. Supabase tetap menjadi otoritas rate limit server-side. Limiter browser membantu mencegah klik berulang dan menyimpan penghitung di `localStorage`; limiter ini bukan pengganti proteksi server.

## 2. Verifikasi OTP email

### Operasi aplikasi

```ts
const { error } = await supabase.auth.verifyOtp({
  email: normalizeEmail(email),
  token: otp,
  type: 'signup',
});
```

### Endpoint Supabase

```http
POST /auth/v1/verify
```

Contoh body:

```json
{
  "email": "user@example.com",
  "token": "123456",
  "type": "signup"
}
```

`token` harus berupa kode OTP numerik 6 digit. Link konfirmasi dari email tetap didukung oleh Supabase, sehingga pengguna dapat memilih link atau memasukkan kode.

### Masa berlaku

Aplikasi menetapkan masa berlaku tampilan OTP selama **10 menit** sejak email registrasi atau email kirim ulang berhasil diminta. Halaman `/email-confirmation` menampilkan countdown `MM:SS`, menonaktifkan tombol verifikasi setelah waktu habis, dan menyarankan pengguna mengirim ulang email.

Validasi final tetap dilakukan oleh Supabase. Jika konfigurasi Auth Supabase memiliki masa berlaku token yang berbeda, nilai server adalah sumber kebenaran dan dapat menolak token lebih awal.

### Kirim ulang OTP

```ts
const { error } = await supabase.auth.resend({
  type: 'signup',
  email: normalizeEmail(email),
});
```

Endpoint yang digunakan:

```http
POST /auth/v1/resend
```

Contoh body:

```json
{
  "type": "signup",
  "email": "user@example.com"
}
```

Setiap kirim ulang yang berhasil membuat expiration time baru selama 10 menit. Kirim ulang dibatasi maksimal **3 permintaan per email dalam 10 menit**. Jika batas tercapai, aplikasi tidak mengirim request baru dan menampilkan sisa waktu cooldown.

### Error umum

| Kondisi | Pesan pengguna |
|---|---|
| OTP bukan 6 digit | `Masukkan kode OTP 6 digit dari email Anda.` |
| OTP expired | `Kode OTP sudah kedaluwarsa. Silakan kirim ulang email verifikasi.` |
| OTP salah atau sudah dipakai | Pesan error dari Supabase ditampilkan sebagai kegagalan verifikasi. |
| Batas kirim ulang tercapai | Aplikasi menampilkan waktu tunggu dalam menit. |

## 3. Lupa password

### Operasi aplikasi

```ts
const { error } = await supabase.auth.resetPasswordForEmail(
  normalizeEmail(email),
  {
    redirectTo: `${window.location.origin}/reset-password`,
  },
);
```

### Endpoint Supabase

```http
POST /auth/v1/recover
```

Contoh body:

```json
{
  "email": "user@example.com",
  "redirect_to": "https://app.example.com/reset-password"
}
```

### Respons dan privasi

UI selalu menggunakan pesan netral:

> Jika email terdaftar di SaDesa, kami akan mengirimkan link reset password. Silakan cek inbox atau folder spam Anda.

Pesan ini sengaja tidak menyatakan apakah email tertentu memiliki akun. Client tidak boleh melakukan query langsung ke `auth.users` atau membuat endpoint pengecekan email untuk alur publik.

### Validasi email

Halaman `/forgot-password` menggunakan `signupEmailSchema` yang sama dengan registrasi. Policy tersebut memeriksa email wajib diisi, panjang maksimal 254 karakter, format mailbox, dan domain dengan minimal satu titik. Email kemudian dinormalisasi ke lowercase sebelum dikirim.

### Rate limit

Permintaan reset password dibatasi maksimal **3 email per alamat dalam 15 menit** oleh limiter browser. Supabase tetap menerapkan rate limit server-side. Pengguna yang mencapai batas melihat pesan cooldown tanpa memicu request reset baru.

## Alur reset password setelah link dibuka

1. Pengguna memasukkan email pada `/forgot-password`.
2. Jika email terdaftar, Supabase mengirim link reset ke email tersebut.
3. Link membuka `/reset-password` sesuai `redirect_to`.
4. Supabase membuat recovery session setelah link diproses.
5. Halaman reset memeriksa session dan memanggil `supabase.auth.updateUser({ password })`.
6. Setelah password berhasil diubah, aplikasi melakukan sign out dan mengarahkan pengguna ke `/auth`.

Endpoint perubahan password adalah operasi session-authenticated dan bukan bagian dari endpoint publik lupa password:

```http
PUT /auth/v1/user
```

## Konfigurasi template email Supabase

Agar email konfirmasi menampilkan kedua pilihan, template email konfirmasi perlu menyediakan placeholder `{{ .ConfirmationURL }}` untuk link dan `{{ .Token }}` untuk kode OTP. Redirect URL harus mengizinkan origin aplikasi dan path `/reset-password` untuk alur recovery.

Konfigurasi email dan masa berlaku token dikelola di Supabase Dashboard. Nilai countdown 10 menit di aplikasi harus diselaraskan dengan kebijakan Auth project. Jangan menganggap nilai `localStorage` sebagai bukti keamanan; token hanya sah jika diterima oleh Supabase.

## Referensi implementasi repository

| Komponen | Lokasi |
|---|---|
| Supabase client | `src/integrations/supabase/client.ts` |
| Registrasi dan login | `src/pages/AuthPage.tsx` |
| Konteks Auth | `src/contexts/AuthContext.tsx` |
| Halaman OTP | `src/pages/EmailConfirmationPage.tsx` |
| Halaman lupa password | `src/pages/ForgotPasswordPage.tsx` |
| Masa berlaku OTP | `src/lib/otp.ts` |
| Rate limiting browser | `src/lib/rateLimit.ts` |
| Routing halaman auth | `src/App.tsx` |

## References

[1]: https://supabase.com/docs/guides/auth/passwords "Supabase Password-based Auth"
[2]: https://supabase.com/docs/reference/javascript/auth-resend "Supabase JavaScript auth.resend()"
[3]: https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail "Supabase JavaScript auth.resetPasswordForEmail()"
