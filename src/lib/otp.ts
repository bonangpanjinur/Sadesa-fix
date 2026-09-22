export const OTP_EXPIRATION_MS = 10 * 60 * 1000;
const OTP_EXPIRATION_PREFIX = 'sadesa:otp-expires:';

export function getOtpExpirationKey(email: string): string {
  return `${OTP_EXPIRATION_PREFIX}${encodeURIComponent(email)}`;
}

export function createOtpExpiration(now = Date.now()): number {
  return now + OTP_EXPIRATION_MS;
}

export function formatOtpTimeRemaining(expiresAt: number, now = Date.now()): string {
  const remainingSeconds = Math.max(0, Math.ceil((expiresAt - now) / 1000));
  const minutes = Math.floor(remainingSeconds / 60).toString().padStart(2, '0');
  const seconds = (remainingSeconds % 60).toString().padStart(2, '0');
  return `${minutes}:${seconds}`;
}

export function isOtpExpired(expiresAt: number, now = Date.now()): boolean {
  return expiresAt <= now;
}
