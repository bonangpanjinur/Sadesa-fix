import { describe, expect, it, vi } from 'vitest';
import { getRetryDelayMs } from './posOfflineDB';
import { withPOSSyncLock } from './posOfflineCoordinator';

describe('offline POS coordination', () => {
  it('uses the documented exponential backoff schedule', () => {
    expect([1, 2, 3, 4, 5, 6, 8].map(getRetryDelayMs)).toEqual([
      5_000, 30_000, 120_000, 600_000, 1_800_000, 1_800_000, 1_800_000,
    ]);
  });

  it('serializes work with the compatibility lease when Web Locks is unavailable', async () => {
    const first = vi.fn(async () => 'first');
    const second = vi.fn(async () => 'second');
    const firstResult = await withPOSSyncLock('tenant-a', 'outlet-a', first);
    const secondResult = await withPOSSyncLock('tenant-a', 'outlet-a', second);
    expect(firstResult).toBe('first');
    expect(secondResult).toBe('second');
    expect(first).toHaveBeenCalledOnce();
    expect(second).toHaveBeenCalledOnce();
  });
});
