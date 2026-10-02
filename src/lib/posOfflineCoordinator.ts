/**
 * Coordinates one offline-sale sync worker per tenant/outlet scope.
 *
 * Web Locks is the preferred primitive. The localStorage lease is only a
 * compatibility fallback for browsers without Web Locks; it expires so a
 * crashed tab cannot block the queue forever.
 */

const LEASE_TTL_MS = 30_000;
const LEASE_PREFIX = 'desamart:pos-sync-lease:';

type LockNavigator = Navigator & {
  locks?: {
    request<T>(name: string, options: { ifAvailable: true }, callback: (lock: unknown) => Promise<T>): Promise<T | undefined>;
  };
};

function leaseKey(scope: string): string {
  return `${LEASE_PREFIX}${scope}`;
}

function randomOwner(): string {
  return typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;
}

async function withLease<T>(scope: string, work: () => Promise<T>): Promise<T | undefined> {
  if (typeof localStorage === 'undefined') return work();
  const key = leaseKey(scope);
  const owner = randomOwner();
  const now = Date.now();
  try {
    const current = JSON.parse(localStorage.getItem(key) || 'null') as { owner?: string; expiresAt?: number } | null;
    if (current?.expiresAt && current.expiresAt > now) return undefined;
    localStorage.setItem(key, JSON.stringify({ owner, expiresAt: now + LEASE_TTL_MS }));
    const claimed = JSON.parse(localStorage.getItem(key) || 'null') as { owner?: string } | null;
    if (claimed?.owner !== owner) return undefined;
    return await work();
  } finally {
    try {
      const current = JSON.parse(localStorage.getItem(key) || 'null') as { owner?: string } | null;
      if (current?.owner === owner) localStorage.removeItem(key);
    } catch {
      // Storage can become unavailable while a tab is closing; the TTL handles it.
    }
  }
}

export async function withPOSSyncLock<T>(tenantId: string, outletId: string, work: () => Promise<T>): Promise<T | undefined> {
  const scope = `${tenantId}:${outletId}`;
  const locks = typeof navigator !== 'undefined' ? (navigator as LockNavigator).locks : undefined;
  if (locks) {
    return locks.request(`pos-sync:${scope}`, { ifAvailable: true }, async (lock) => {
      if (!lock) return undefined;
      return work();
    });
  }
  return withLease(scope, work);
}
