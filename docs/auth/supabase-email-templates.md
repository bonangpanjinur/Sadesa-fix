
---

## Change email address

Template ini digunakan saat pengguna mengganti alamat email akun.

### Subject

```text
Konfirmasi alamat email baru Anda di SaDesa
```

### Source

```html
<!DOCTYPE html>
<html lang="id">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="color-scheme" content="light">
    <title>Konfirmasi Email Baru SaDesa</title>
  </head>
  <body style="margin:0; padding:0; background-color:#f3f7f4; font-family:Arial, Helvetica, sans-serif; color:#193226;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%; background-color:#f3f7f4; margin:0; padding:32px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%; max-width:600px; background-color:#ffffff; border-radius:18px; overflow:hidden;">
            <tr>
              <td align="center" style="padding:32px 24px 28px; background-color:#e8f5ed; border-bottom:1px solid #d7eadf;">
                <a href="https://www.sadesa.id" target="_blank" style="text-decoration:none;"><img src="https://www.sadesa.id/branding/sadesa-logo.png" alt="Logo SaDesa" width="160" style="display:block; width:160px; max-width:80%; height:auto; margin:0 auto;"></a>
                <p style="margin:14px 0 0; color:#4b6b59; font-size:14px; line-height:1.5;">Platform Ekonomi Desa</p>
              </td>
            </tr>
            <tr>
              <td style="padding:42px 40px 36px;">
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td align="center"><div style="width:64px; height:64px; line-height:64px; border-radius:50%; background-color:#e6f3eb; color:#23834d; font-size:30px; font-weight:bold; text-align:center;">✉</div></td></tr></table>
                <h1 style="margin:26px 0 16px; text-align:center; color:#193226; font-size:27px; line-height:1.3; font-weight:700;">Konfirmasi Email Baru</h1>
                <p style="margin:0 auto 18px; max-width:470px; text-align:center; color:#5f7367; font-size:16px; line-height:1.7;">Kami menerima permintaan untuk mengganti alamat email akun SaDesa Anda.</p>
                <p style="margin:0 auto 24px; max-width:470px; text-align:center; color:#718177; font-size:14px; line-height:1.6;">Alamat email baru Anda:</p>
                <p style="margin:0 auto 26px; text-align:center; color:#193226; font-size:17px; line-height:1.5; font-weight:bold; word-break:break-all;">{{ .NewEmail }}</p>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:28px 0 30px;"><tr><td align="center"><a href="{{ .ConfirmationURL }}" target="_blank" style="display:inline-block; padding:15px 32px; background-color:#23834d; color:#ffffff; font-size:16px; font-weight:bold; line-height:1; text-decoration:none; border-radius:9px;">Konfirmasi Email Baru</a></td></tr></table>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top:1px solid #e5eee8;"><tr><td style="padding-top:22px;"><p style="margin:0 0 8px; color:#718177; font-size:12px; line-height:1.6;">Jika tombol tidak dapat diklik, salin dan buka tautan berikut di browser:</p><p style="margin:0; word-break:break-all; font-size:12px; line-height:1.6;"><a href="{{ .ConfirmationURL }}" target="_blank" style="color:#23834d; text-decoration:underline;">{{ .ConfirmationURL }}</a></p></td></tr></table>
              </td>
            </tr>
            <tr><td style="padding:22px 40px; background-color:#fffaf0; border-top:1px solid #f3ead3; border-bottom:1px solid #f3ead3;"><p style="margin:0 0 7px; color:#745d2d; font-size:13px; line-height:1.5; font-weight:bold;">Bukan Anda yang meminta?</p><p style="margin:0; color:#806f48; font-size:12px; line-height:1.7;">Jika Anda tidak meminta perubahan email, abaikan email ini dan segera amankan akun SaDesa Anda.</p></td></tr>
            <tr><td align="center" style="padding:26px 24px 30px; background-color:#f8fbf9;"><p style="margin:0 0 8px; color:#557163; font-size:13px; line-height:1.5;">Butuh bantuan? <a href="https://www.sadesa.id" target="_blank" style="color:#23834d; text-decoration:none; font-weight:bold;">Kunjungi www.sadesa.id</a></p><p style="margin:0; color:#9aaa9f; font-size:11px; line-height:1.5;">© SaDesa — Platform Ekonomi Desa</p></td></tr>
          </table>
          <p style="margin:16px auto 0; max-width:560px; color:#91a198; text-align:center; font-size:11px; line-height:1.5;">Email ini dikirim secara otomatis. Mohon tidak membalas email ini.</p>
        </td>
      </tr>
    </table>
  </body>
</html>
```

### Variabel yang digunakan

- `{{ .NewEmail }}` — alamat email baru.
- `{{ .ConfirmationURL }}` — tautan konfirmasi perubahan email.

---

## Reauthentication

Template ini digunakan saat pengguna perlu membuktikan kembali identitasnya sebelum melakukan tindakan sensitif.

### Subject

```text
Kode verifikasi keamanan SaDesa
```

### Source

```html
<!DOCTYPE html>
<html lang="id">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="color-scheme" content="light">
    <title>Verifikasi Keamanan SaDesa</title>
  </head>
  <body style="margin:0; padding:0; background-color:#f3f7f4; font-family:Arial, Helvetica, sans-serif; color:#193226;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%; background-color:#f3f7f4; margin:0; padding:32px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%; max-width:600px; background-color:#ffffff; border-radius:18px; overflow:hidden;">
            <tr>
              <td align="center" style="padding:32px 24px 28px; background-color:#e8f5ed; border-bottom:1px solid #d7eadf;">
                <a href="https://www.sadesa.id" target="_blank" style="text-decoration:none;"><img src="https://www.sadesa.id/branding/sadesa-logo.png" alt="Logo SaDesa" width="160" style="display:block; width:160px; max-width:80%; height:auto; margin:0 auto;"></a>
                <p style="margin:14px 0 0; color:#4b6b59; font-size:14px; line-height:1.5;">Platform Ekonomi Desa</p>
              </td>
            </tr>
            <tr>
              <td style="padding:42px 40px 36px;">
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td align="center"><div style="width:64px; height:64px; line-height:64px; border-radius:50%; background-color:#e6f3eb; color:#23834d; font-size:30px; font-weight:bold; text-align:center;">✓</div></td></tr></table>
                <h1 style="margin:26px 0 16px; text-align:center; color:#193226; font-size:27px; line-height:1.3; font-weight:700;">Verifikasi Keamanan</h1>
                <p style="margin:0 auto 24px; max-width:470px; text-align:center; color:#5f7367; font-size:16px; line-height:1.7;">Gunakan kode berikut untuk mengonfirmasi bahwa Anda adalah pemilik akun SaDesa.</p>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 30px; background-color:#f7faf8; border:1px solid #e1eee5; border-radius:12px;"><tr><td align="center" style="padding:24px 18px;"><p style="margin:0 0 10px; color:#667a6e; font-size:13px; line-height:1.5;">Kode verifikasi Anda:</p><p style="margin:0; color:#23834d; font-size:32px; line-height:1.2; font-weight:700; letter-spacing:8px;">{{ .Token }}</p><p style="margin:12px 0 0; color:#89988e; font-size:12px; line-height:1.5;">Kode ini hanya dapat digunakan satu kali.</p></td></tr></table>
                <p style="margin:0; text-align:center; color:#718177; font-size:13px; line-height:1.7;">Masukkan kode ini pada halaman SaDesa yang sedang Anda gunakan. Jangan bagikan kode ini kepada siapa pun.</p>
              </td>
            </tr>
            <tr><td style="padding:22px 40px; background-color:#fffaf0; border-top:1px solid #f3ead3; border-bottom:1px solid #f3ead3;"><p style="margin:0 0 7px; color:#745d2d; font-size:13px; line-height:1.5; font-weight:bold;">Bukan Anda yang meminta?</p><p style="margin:0; color:#806f48; font-size:12px; line-height:1.7;">Jika Anda tidak melakukan tindakan ini, abaikan email dan segera amankan akun SaDesa Anda.</p></td></tr>
            <tr><td align="center" style="padding:26px 24px 30px; background-color:#f8fbf9;"><p style="margin:0 0 8px; color:#557163; font-size:13px; line-height:1.5;">Butuh bantuan? <a href="https://www.sadesa.id" target="_blank" style="color:#23834d; text-decoration:none; font-weight:bold;">Kunjungi www.sadesa.id</a></p><p style="margin:0; color:#9aaa9f; font-size:11px; line-height:1.5;">© SaDesa — Platform Ekonomi Desa</p></td></tr>
          </table>
          <p style="margin:16px auto 0; max-width:560px; color:#91a198; text-align:center; font-size:11px; line-height:1.5;">Email ini dikirim secara otomatis. Mohon tidak membalas email ini.</p>
        </td>
      </tr>
    </table>
  </body>
</html>
```

### Variabel yang digunakan

- `{{ .Token }}` — kode verifikasi sekali pakai.

> **Reauthentication** menggunakan kode OTP, bukan `{{ .ConfirmationURL }}`. Jangan menghapus variabel `{{ .Token }}` dari template ini.
