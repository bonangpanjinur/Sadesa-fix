export function normalizeKtpNumber(value: string): string {
  return value.replace(/\D/g, '').slice(0, 16);
}

export function isValidKtpNumber(value: string | null | undefined): boolean {
  return Boolean(value && /^\d{16}$/.test(value.trim()));
}
