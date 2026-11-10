export interface CheckoutAttempt {
  scope: string;
  key: string;
  guestAccessToken: string | null;
  createdAt: number;
}

type StoredCheckoutAttempt = CheckoutAttempt;

type AttemptStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem' | 'key' | 'length'>;
const STORAGE_PREFIX = 'sadesa:marketplace-checkout-attempt:v1:';
const MAX_ATTEMPT_AGE_MS = 30 * 24 * 60 * 60 * 1000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_PATTERN = /^[0-9a-f]{64}$/i;

function stableSerialize(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableSerialize).join(',')}]`;
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${stableSerialize(record[key])}`).join(',')}}`;
  }
  return JSON.stringify(value) ?? 'null';
}

export async function createCheckoutAttemptScope(identity: string, payload: unknown): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(stableSerialize(payload)));
  const fingerprint = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${identity}:${fingerprint}`;
}

function randomToken(createId: () => string): string {
  return `${createId().replaceAll('-', '')}${createId().replaceAll('-', '')}`.toLowerCase();
}

function scopeStorageKey(scope: string): string {
  return `${STORAGE_PREFIX}${encodeURIComponent(scope)}`;
}

function readAttempt(storage: Pick<Storage, 'getItem'>, storageKey: string, scope: string): StoredCheckoutAttempt | null {
  try {
    const parsed = JSON.parse(storage.getItem(storageKey) || 'null') as Partial<StoredCheckoutAttempt> | null;
    if (!parsed || parsed.scope !== scope || !UUID_PATTERN.test(String(parsed.key))) return null;
    if (!Number.isFinite(parsed.createdAt) || Date.now() - Number(parsed.createdAt) > MAX_ATTEMPT_AGE_MS) return null;
    const token = parsed.guestAccessToken;
    if (token !== null && (typeof token !== 'string' || !TOKEN_PATTERN.test(token))) return null;
    return {
      scope: parsed.scope,
      key: parsed.key,
      guestAccessToken: token ?? null,
      createdAt: Number(parsed.createdAt),
    };
  } catch {
    return null;
  }
}

function pruneExpiredAttempts(storage: AttemptStorage): void {
  const now = Date.now();
  for (let index = storage.length - 1; index >= 0; index -= 1) {
    const key = storage.key(index);
    if (!key?.startsWith(STORAGE_PREFIX)) continue;
    try {
      const parsed = JSON.parse(storage.getItem(key) || 'null') as Partial<StoredCheckoutAttempt> | null;
      if (!parsed || !Number.isFinite(parsed.createdAt) || now - Number(parsed.createdAt) > MAX_ATTEMPT_AGE_MS) {
        storage.removeItem(key);
      }
    } catch {
      storage.removeItem(key);
    }
  }
}

/** Reuse a checkout key after reload so a lost RPC response cannot create another order. */
export function getOrCreateCheckoutAttempt(
  scope: string,
  isGuest: boolean,
  storage: AttemptStorage = window.localStorage,
  createId: () => string = () => crypto.randomUUID(),
): CheckoutAttempt {
  pruneExpiredAttempts(storage);
  const storageKey = scopeStorageKey(scope);
  const current = readAttempt(storage, storageKey, scope);
  if (current && (!isGuest || current.guestAccessToken)) return current;

  const attempt: CheckoutAttempt = {
    scope,
    key: createId(),
    guestAccessToken: isGuest ? randomToken(createId) : null,
    createdAt: Date.now(),
  };
  storage.setItem(storageKey, JSON.stringify(attempt));
  return attempt;
}

export function clearCheckoutAttempt(
  scope: string,
  key: string,
  storage: Pick<Storage, 'getItem' | 'removeItem'> = window.localStorage,
): void {
  const storageKey = scopeStorageKey(scope);
  const current = readAttempt(storage, storageKey, scope);
  if (current?.key === key) storage.removeItem(storageKey);
}
