export type ObservabilityDomain = 'payment' | 'upload' | 'realtime' | 'pos_webhook';
export type ObservabilityLevel = 'info' | 'warn' | 'error';

export interface ObservabilityEvent {
  domain: ObservabilityDomain;
  event: string;
  level: ObservabilityLevel;
  at: string;
  context?: Record<string, string | number | boolean | null>;
  error?: { name: string; message: string };
}

function safeError(error: unknown): ObservabilityEvent['error'] | undefined {
  if (error === undefined || error === null) return undefined;
  if (error instanceof Error) return { name: error.name, message: error.message.slice(0, 240) };
  return { name: 'UnknownError', message: String(error).slice(0, 240) };
}

export function reportObservability(
  domain: ObservabilityDomain,
  event: string,
  level: ObservabilityLevel = 'info',
  context?: Record<string, string | number | boolean | null>,
  error?: unknown,
): void {
  const payload: ObservabilityEvent = {
    domain,
    event,
    level,
    at: new Date().toISOString(),
    context,
    error: safeError(error),
  };
  const method = level === 'error' ? console.error : level === 'warn' ? console.warn : console.info;
  method(`[observability] ${domain}.${event}`, payload);
}
