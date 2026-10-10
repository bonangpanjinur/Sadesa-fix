export interface MerchantRegistrationErrorLike {
  code?: unknown;
  message?: unknown;
  details?: unknown;
  hint?: unknown;
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

export function describeMerchantRegistrationError(error: unknown): string {
  const value = error && typeof error === 'object'
    ? error as MerchantRegistrationErrorLike
    : {};
  const code = text(value.code);
  const message = text(value.message);

  if (code === 'PGRST202' || code === '42883') {
    return 'Layanan pendaftaran pedagang belum sinkron dengan database. Pendaftaran belum tersimpan; silakan hubungi admin.';
  }
  if (code === '42501') {
    return 'Sesi atau izin pendaftaran tidak valid. Silakan masuk ulang, lalu coba lagi.';
  }
  if (code === '23505') {
    return message || 'Akun ini sudah memiliki pendaftaran pedagang aktif.';
  }
  if (message) {
    return code ? `Pendaftaran gagal (${code}): ${message}` : `Pendaftaran gagal: ${message}`;
  }
  return 'Gagal mengirim pendaftaran pedagang. Periksa koneksi lalu coba lagi.';
}
