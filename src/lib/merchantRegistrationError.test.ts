import { describe, expect, it } from 'vitest';
import { describeMerchantRegistrationError } from './merchantRegistrationError';

describe('describeMerchantRegistrationError', () => {
  it('explains an unavailable RPC deployment', () => {
    expect(describeMerchantRegistrationError({ code: 'PGRST202' })).toContain('belum sinkron');
  });

  it('preserves useful database validation errors and codes', () => {
    expect(describeMerchantRegistrationError({ code: '23514', message: 'Kategori usaha tidak valid' }))
      .toBe('Pendaftaran gagal (23514): Kategori usaha tidak valid');
  });

  it('asks the user to reauthenticate for authorization failures', () => {
    expect(describeMerchantRegistrationError({ code: '42501', message: 'not authorized' })).toContain('masuk ulang');
  });

  it('returns a generic recovery hint when the backend gives no message', () => {
    expect(describeMerchantRegistrationError(null)).toContain('Periksa koneksi');
  });
});
