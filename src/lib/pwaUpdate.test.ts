import { describe, expect, it, vi } from 'vitest';
import { isPendingServiceWorkerUpdate, requestPwaUpdate, setPwaUpdateHandler } from './pwaUpdate';

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

describe('PWA update action', () => {
  it('requests the registered update flow with page reload enabled', async () => {
    const handler = vi.fn().mockResolvedValue(undefined);
    setPwaUpdateHandler(handler);

    await requestPwaUpdate();

    expect(handler).toHaveBeenCalledExactlyOnceWith(true);
  });

  it('rejects clearly when the service-worker update handler is unavailable', async () => {
    setPwaUpdateHandler(null);
    await expect(requestPwaUpdate()).rejects.toThrow('Handler pembaruan PWA belum siap');
  });
});
