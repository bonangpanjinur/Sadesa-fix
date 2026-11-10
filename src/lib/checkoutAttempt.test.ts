import { describe, expect, it } from 'vitest';
import { clearCheckoutAttempt, createCheckoutAttemptScope, getOrCreateCheckoutAttempt } from './checkoutAttempt';

function createStorage(): Storage {
  const values = new Map<string, string>();
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => { values.delete(key); },
    clear: () => values.clear(),
    key: (index) => [...values.keys()][index] ?? null,
    get length() { return values.size; },
  } as Storage;
}

const ids = [
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  '44444444-4444-4444-8444-444444444444',
];

describe('checkout attempt persistence', () => {
  it('creates a stable non-plaintext scope for the exact checkout payload', async () => {
    const first = await createCheckoutAttemptScope('user:buyer-1', { delivery: { address: 'Alamat Rahasia', phone: '08123456789' }, method: 'TRANSFER' });
    const reordered = await createCheckoutAttemptScope('user:buyer-1', { method: 'TRANSFER', delivery: { phone: '08123456789', address: 'Alamat Rahasia' } });
    const changed = await createCheckoutAttemptScope('user:buyer-1', { method: 'TRANSFER', delivery: { phone: '08123456789', address: 'Alamat Lain' } });

    expect(first).toBe(reordered);
    expect(first).not.toBe(changed);
    expect(first).not.toContain('Alamat Rahasia');
  });

  it('reuses the same key and guest access token after a reload', () => {
    const storage = createStorage();
    let index = 0;
    const createId = () => ids[index++];
    const first = getOrCreateCheckoutAttempt('guest:session-1', true, storage, createId);
    const retry = getOrCreateCheckoutAttempt('guest:session-1', true, storage, () => {
      throw new Error('should reuse persisted attempt');
    });

    expect(retry).toEqual(first);
    expect(first.key).toBe(ids[0]);
    expect(first.guestAccessToken).toBe(`${ids[1].replaceAll('-', '')}${ids[2].replaceAll('-', '')}`);
  });

  it('keeps concurrent checkout scopes isolated and clears only the matching key', () => {
    const storage = createStorage();
    const first = getOrCreateCheckoutAttempt('user:buyer-1:payload-a', false, storage, () => ids[0]);
    const second = getOrCreateCheckoutAttempt('user:buyer-2:payload-b', false, storage, () => ids[1]);

    expect(getOrCreateCheckoutAttempt('user:buyer-1:payload-a', false, storage, () => ids[2])).toEqual(first);
    clearCheckoutAttempt('user:buyer-1:payload-a', first.key, storage);
    expect(getOrCreateCheckoutAttempt('user:buyer-2:payload-b', false, storage, () => ids[3])).toEqual(second);
    expect(getOrCreateCheckoutAttempt('user:buyer-1:payload-a', false, storage, () => ids[2]).key).toBe(ids[2]);
  });
});
