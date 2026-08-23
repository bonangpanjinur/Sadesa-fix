/**
 * Lightweight telemetry helper for Supabase Realtime channel subscriptions.
 * Logs every status transition with a consistent prefix so failures are easy
 * to spot in the browser console, and keeps a small in-memory ring buffer that
 * UI components can surface to the user.
 */
import { reportObservability } from '@/lib/observability';

export type RealtimeStatus =
  | 'idle'
  | 'SUBSCRIBED'
  | 'TIMED_OUT'
  | 'CHANNEL_ERROR'
  | 'CLOSED';

export interface RealtimeStatusEvent {
  channel: string;
  status: RealtimeStatus;
  at: string;
  error?: string;
}

const MAX_EVENTS = 50;
const events: RealtimeStatusEvent[] = [];

export function getRealtimeStatusLog(): RealtimeStatusEvent[] {
  return [...events];
}

export function logRealtimeStatus(
  channel: string,
  status: string,
  err?: unknown
): RealtimeStatus {
  const normalized = (status as RealtimeStatus) ?? 'idle';
  const error =
    err instanceof Error ? err.message : err ? String(err) : undefined;

  const event: RealtimeStatusEvent = {
    channel,
    status: normalized,
    at: new Date().toISOString(),
    error,
  };

  events.push(event);
  if (events.length > MAX_EVENTS) events.shift();

  const label = `[realtime] ${channel} -> ${normalized}`;
  reportObservability(
    'realtime',
    normalized === 'SUBSCRIBED' ? 'channel_subscribed' : normalized === 'CLOSED' ? 'channel_closed' : 'channel_failed',
    normalized === 'SUBSCRIBED' || normalized === 'CLOSED' ? 'info' : 'error',
    { channel, status: normalized },
    err,
  );
  if (normalized === 'SUBSCRIBED') {
    console.info(label);
  } else if (normalized === 'CLOSED') {
    console.debug(label);
  } else {
    console.error(label, error ?? '(no error detail provided)');
  }

  return normalized;
}

export function isRealtimeFailure(status: RealtimeStatus): boolean {
  return status === 'CHANNEL_ERROR' || status === 'TIMED_OUT';
}
