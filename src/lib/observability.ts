export type ObservabilityDomain = 'payment' | 'upload' | 'realtime' | 'webhook' | 'pos_webhook' | 'offline_sync' | 'device' | 'navigation' | 'inventory' | 'subscription' | 'security' | 'data' | 'application';
export type ObservabilityLevel = 'info' | 'warn' | 'error';
export type ObservabilityValue = string | number | boolean | null;

export interface ObservabilityEvent {
  domain: ObservabilityDomain;
  event: string;
  level: ObservabilityLevel;
  at: string;
  traceId: string;
  durationMs?: number;
  context?: Record<string, ObservabilityValue>;
  error?: { name: string; message: string };
}

const MAX_EVENTS = 100;
const events: ObservabilityEvent[] = [];
const SENSITIVE_KEY = /(token|secret|password|authorization|cookie|api[-_]?key|signature|proof|phone|email|address|location|latitude|longitude|recipient|payload)/i;
const MAX_CONTEXT_KEYS = 24;

/** Keep diagnostics useful without copying credentials or obvious PII to logs. */
export function sanitizeObservabilityText(value: string): string {
  return value
    .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, '[REDACTED_EMAIL]')
    .replace(/(?:\+?\d[\d\s().-]{7,}\d)/g, '[REDACTED_PHONE]')
    .replace(/(bearer\s+|token[=:]\s*|secret[=:]\s*)[^\s,;]+/gi, '$1[REDACTED]')
    .slice(0, 240);
}

function safeError(error: unknown): ObservabilityEvent['error'] | undefined {
  if (error === undefined || error === null) return undefined;
  if (error instanceof Error) return { name: error.name, message: sanitizeObservabilityText(error.message) };
  if (typeof error === 'object') {
    const details = error as { name?: unknown; message?: unknown; code?: unknown; hint?: unknown };
    const name = typeof details.name === 'string' ? details.name : 'UnknownError';
    const message = typeof details.message === 'string' ? details.message : 'Unknown error';
    const code = typeof details.code === 'string' ? ` [code: ${details.code}]` : '';
    const hint = typeof details.hint === 'string' && details.hint ? ` Hint: ${details.hint}` : '';
    return { name, message: sanitizeObservabilityText(`${message}${code}${hint}`) };
  }
  return { name: 'UnknownError', message: sanitizeObservabilityText(String(error)) };
}

function safeContext(context?: Record<string, ObservabilityValue>): Record<string, ObservabilityValue> | undefined {
  if (!context) return undefined;
  return Object.fromEntries(Object.entries(context).slice(0, MAX_CONTEXT_KEYS).map(([key, value]) => [
    key,
    SENSITIVE_KEY.test(key) ? '[REDACTED]' : typeof value === 'string' ? sanitizeObservabilityText(value) : value,
  ]));
}

export function createTraceId(prefix = 'evt'): string {
  const random = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : Math.random().toString(36).slice(2);
  return `${prefix}-${random}`;
}

export function reportObservability(
  domain: ObservabilityDomain,
  event: string,
  level: ObservabilityLevel = 'info',
  context?: Record<string, ObservabilityValue>,
  error?: unknown,
  options?: { traceId?: string; durationMs?: number },
): ObservabilityEvent {
  const payload: ObservabilityEvent = {
    domain,
    event,
    level,
    at: new Date().toISOString(),
    traceId: options?.traceId ?? createTraceId(domain),
    durationMs: options?.durationMs,
    context: safeContext(context),
    error: safeError(error),
  };
  events.push(payload);
  if (events.length > MAX_EVENTS) events.shift();
  const method = level === 'error' ? console.error : level === 'warn' ? console.warn : console.info;
  method('[observability]', JSON.stringify(payload));
  return payload;
}

export function getObservabilityEvents(): ObservabilityEvent[] {
  return [...events];
}

export function clearObservabilityEvents(): void {
  events.length = 0;
}

export function reportDuration(
  domain: ObservabilityDomain,
  event: string,
  startedAt: number,
  context?: Record<string, ObservabilityValue>,
  level: ObservabilityLevel = 'info',
  traceId?: string,
): ObservabilityEvent {
  return reportObservability(domain, event, level, context, undefined, { traceId, durationMs: Math.max(0, Date.now() - startedAt) });
}

export function getErrorCode(error: unknown): string | null {
  if (!error || typeof error !== 'object') return null;
  const code = (error as { code?: unknown }).code;
  return typeof code === 'string' ? code.slice(0, 32) : null;
}

export function logUnhandledErrors(): () => void {
  const onError = (event: ErrorEvent) => reportObservability('application', 'unhandled_error', 'error', { message: event.message.slice(0, 160) }, event.error);
  const onRejection = (event: PromiseRejectionEvent) => reportObservability('application', 'unhandled_rejection', 'error', {}, event.reason);
  window.addEventListener('error', onError);
  window.addEventListener('unhandledrejection', onRejection);
  return () => {
    window.removeEventListener('error', onError);
    window.removeEventListener('unhandledrejection', onRejection);
  };
}

export async function observe<T>(
  domain: ObservabilityDomain,
  event: string,
  operation: () => Promise<T>,
  context?: Record<string, ObservabilityValue>,
  traceId = createTraceId(domain),
): Promise<T> {
  const startedAt = Date.now();
  reportObservability(domain, `${event}_started`, 'info', context, undefined, { traceId });
  try {
    const result = await operation();
    reportDuration(domain, `${event}_succeeded`, startedAt, context, 'info', traceId);
    return result;
  } catch (error) {
    reportObservability(domain, `${event}_failed`, 'error', { ...context, errorCode: getErrorCode(error) }, error, { traceId, durationMs: Date.now() - startedAt });
    throw error;
  }
}
