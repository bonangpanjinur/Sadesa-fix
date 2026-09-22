// Client-side rate limiting utility
interface RateLimitConfig {
  maxRequests: number;
  windowMs: number;
}

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

const rateLimitStore = new Map<string, RateLimitEntry>();
const PERSISTENT_PREFIX = 'sadesa:rate-limit:';

// Cleanup old entries periodically
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of rateLimitStore.entries()) {
    if (entry.resetAt < now) {
      rateLimitStore.delete(key);
    }
  }
}, 60000); // Cleanup every minute

export function checkRateLimit(
  identifier: string,
  action: string,
  config: RateLimitConfig = { maxRequests: 10, windowMs: 60000 }
): { allowed: boolean; remaining: number; resetIn: number } {
  const key = `${identifier}:${action}`;
  const now = Date.now();
  const entry = rateLimitStore.get(key);

  if (!entry || entry.resetAt < now) {
    rateLimitStore.set(key, { count: 1, resetAt: now + config.windowMs });
    return { allowed: true, remaining: config.maxRequests - 1, resetIn: config.windowMs };
  }

  if (entry.count >= config.maxRequests) {
    return { allowed: false, remaining: 0, resetIn: entry.resetAt - now };
  }

  entry.count++;
  return { allowed: true, remaining: config.maxRequests - entry.count, resetIn: entry.resetAt - now };
}

/**
 * Rate limit an action across reloads in the same browser. Supabase remains
 * the authoritative server-side protection; this prevents duplicate requests
 * and gives users immediate feedback before a request is sent.
 */
export function checkPersistentRateLimit(
  identifier: string,
  action: string,
  config: RateLimitConfig,
): { allowed: boolean; remaining: number; resetIn: number } {
  const key = `${PERSISTENT_PREFIX}${encodeURIComponent(identifier)}:${action}`;
  const now = Date.now();
  let entry: RateLimitEntry | undefined;

  try {
    const raw = window.localStorage.getItem(key);
    if (raw) entry = JSON.parse(raw) as RateLimitEntry;
  } catch {
    // Fall back to the in-memory limiter when storage is unavailable.
  }

  if (!entry || entry.resetAt <= now || entry.count < 0) {
    entry = { count: 1, resetAt: now + config.windowMs };
  } else if (entry.count >= config.maxRequests) {
    return { allowed: false, remaining: 0, resetIn: entry.resetAt - now };
  } else {
    entry.count += 1;
  }

  try {
    window.localStorage.setItem(key, JSON.stringify(entry));
  } catch {
    // Private browsing or a full quota should not block the auth flow.
  }

  return {
    allowed: true,
    remaining: Math.max(0, config.maxRequests - entry.count),
    resetIn: entry.resetAt - now,
  };
}

export const RATE_LIMITS = {
  login: { maxRequests: 5, windowMs: 300000 }, // 5 attempts per 5 minutes
  register: { maxRequests: 3, windowMs: 600000 }, // 3 attempts per 10 minutes
  signupOtp: { maxRequests: 3, windowMs: 600000 }, // 3 verification emails per 10 minutes/email
  resendOtp: { maxRequests: 3, windowMs: 600000 }, // 3 resend attempts per 10 minutes/email
  passwordReset: { maxRequests: 3, windowMs: 900000 }, // 3 reset emails per 15 minutes/email
  checkout: { maxRequests: 10, windowMs: 60000 }, // 10 per minute
  addToCart: { maxRequests: 30, windowMs: 60000 }, // 30 per minute
  search: { maxRequests: 20, windowMs: 60000 }, // 20 per minute
  review: { maxRequests: 5, windowMs: 300000 }, // 5 per 5 minutes
  voucherApply: { maxRequests: 10, windowMs: 60000 },
};

export function useRateLimit(action: keyof typeof RATE_LIMITS) {
  const config = RATE_LIMITS[action];
  const checkLimit = (identifier: string = 'anonymous') => checkRateLimit(identifier, action, config);
  return { checkLimit };
}
