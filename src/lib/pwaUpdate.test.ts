import { describe, expect, it } from 'vitest';
import { isPendingServiceWorkerUpdate } from './pwaUpdate';

describe('isPendingServiceWorkerUpdate', () => {
  it('shows an update only when a new installed worker is waiting behind an active controller', () => {
    expect(isPendingServiceWorkerUpdate('installed', true, true)).toBe(true);
  });

  it('does not show an update during the first service-worker installation', () => {
    expect(isPendingServiceWorkerUpdate('installed', true, false)).toBe(false);
  });

  it('does not show an update when the worker is not actually waiting', () => {
    expect(isPendingServiceWorkerUpdate('installed', false, true)).toBe(false);
  });

  it('does not show an update while the new worker is still installing', () => {
    expect(isPendingServiceWorkerUpdate('installing', false, true)).toBe(false);
  });
});
