import { describe, expect, it } from 'vitest';
import { getExpeditionLabel, getExpeditionProvider, getExpeditionTrackingUrl } from './expeditionTracking';

describe('expedition tracking', () => {
  it('resolves common Indonesian expedition aliases', () => {
    expect(getExpeditionProvider('J&T Express')?.key).toBe('jnt');
    expect(getExpeditionLabel('si cepat')).toBe('SiCepat');
  });

  it('builds an encoded tracking URL', () => {
    expect(getExpeditionTrackingUrl('JNE', 'ABC 123/45')).toBe('https://jne.co.id/tracking-package');
  });

  it('does not navigate to an untrusted provider URL', () => {
    expect(getExpeditionTrackingUrl('Ekspedisi Tidak Dikenal', 'ABC123')).toBeNull();
    expect(getExpeditionTrackingUrl('JNE', '')).toBeNull();
  });
});
