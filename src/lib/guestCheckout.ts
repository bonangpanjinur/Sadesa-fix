export interface GuestOrderAccess {
  orderIds: string[];
  token: string;
  expiresAt: string;
}

const ACCESS_STORAGE_KEY = 'sadesa_guest_order_access';
const SESSION_STORAGE_KEY = 'sadesa_guest_checkout_session';

// Guest access is intentionally scoped to the current browser session. The URL
// token remains the durable shareable credential; storage is only a convenience
// for refresh/re-entry in the same tab and must not become a long-lived profile.
const getSessionStorage = () => typeof window !== 'undefined' ? window.sessionStorage : null;

function readAccess(): GuestOrderAccess[] {
  try {
    const parsed = JSON.parse(getSessionStorage()?.getItem(ACCESS_STORAGE_KEY) || '[]') as GuestOrderAccess[];
    if (!Array.isArray(parsed)) return [];
    const now = Date.now();
    return parsed.filter((entry) => entry && typeof entry.token === 'string' && typeof entry.expiresAt === 'string' && new Date(entry.expiresAt).getTime() > now);
  } catch {
    return [];
  }
}

function persistAccess(entries: GuestOrderAccess[]) {
  try {
    getSessionStorage()?.setItem(ACCESS_STORAGE_KEY, JSON.stringify(entries.slice(-10)));
  } catch {
    // Private browsing or a full storage quota should not block checkout.
  }
}

export function getGuestCheckoutSessionKey(): string {
  try {
    const existing = getSessionStorage()?.getItem(SESSION_STORAGE_KEY);
    if (existing && existing.length >= 16) return existing;
    const next = crypto.randomUUID();
    getSessionStorage()?.setItem(SESSION_STORAGE_KEY, next);
    return next;
  } catch {
    return crypto.randomUUID();
  }
}

export function rememberGuestOrderAccess(access: GuestOrderAccess) {
  const entries = readAccess().filter((entry) => !access.orderIds.some((id) => entry.orderIds.includes(id)));
  entries.push(access);
  persistAccess(entries);
}

export function getGuestOrderAccess(orderId: string, urlToken?: string | null): GuestOrderAccess | null {
  if (urlToken && urlToken.length >= 16) {
    return readAccess().find((entry) => entry.token === urlToken && entry.orderIds.includes(orderId)) || null;
  }
  return readAccess().find((entry) => entry.orderIds.includes(orderId)) || null;
}

export function guestOrderUrl(orderId: string, token: string, mode: 'status' | 'payment' = 'status'): string {
  const path = mode === 'payment' ? `/payment/${orderId}` : `/guest-orders/${orderId}`;
  return `${path}?guest_token=${encodeURIComponent(token)}`;
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
