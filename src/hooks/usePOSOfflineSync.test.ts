import { describe, expect, it } from 'vitest';

import { isRetryableStatus } from './usePOSOfflineSync';

describe('offline sync retry policy', () => {
  it('retries transient network and provider responses', () => {
    expect(isRetryableStatus(408)).toBe(true);
    expect(isRetryableStatus(409)).toBe(false);
    expect(isRetryableStatus(429)).toBe(true);
    expect(isRetryableStatus(503)).toBe(true);
  });

  it('treats server conflicts as manual resolution cases', () => {
    expect(isRetryableStatus(409)).toBe(false);
  });

  it('does not retry permanent client validation failures', () => {
    expect(isRetryableStatus(400)).toBe(false);
    expect(isRetryableStatus(404)).toBe(false);
    expect(isRetryableStatus(422)).toBe(false);
  });
});
