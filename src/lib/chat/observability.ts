import { supabase } from '@/integrations/supabase/client';
import { reportObservability } from '@/lib/observability';

export type ChatMetricName =
  | 'event_delivery_latency_ms'
  | 'channel_subscribed'
  | 'channel_timeout'
  | 'channel_closed'
  | 'channel_error'
  | 'reconnect_success'
  | 'duplicate_retry_recovered'
  | 'inbox_query_latency_ms'
  | 'history_query_latency_ms'
  | 'unread_notification_delivery'
  | 'retention_cleanup_success'
  | 'retention_cleanup_failure'
  | 'retention_cleanup_lag_seconds'
  | 'active_conversations';

const SAFE_CONTEXT_KEY = /^[a-z][a-z0-9_]{0,31}$/;
const MAX_CONTEXT_KEYS = 8;

type MetricValue = string | number | boolean | null;

function safeContext(context: Record<string, MetricValue> = {}): Record<string, MetricValue> {
  return Object.fromEntries(
    Object.entries(context)
      .filter(([key]) => SAFE_CONTEXT_KEY.test(key))
      .slice(0, MAX_CONTEXT_KEYS)
      .map(([key, value]) => [key, typeof value === 'string' ? value.slice(0, 80) : value]),
  );
}

export function recordChatMetric(
  metric: ChatMetricName,
  value = 1,
  context: Record<string, MetricValue> = {},
): void {
  const normalizedValue = Number.isFinite(value) ? Math.max(-2147483647, Math.min(value, 2147483647)) : 0;
  const sanitizedContext = safeContext(context);
  reportObservability('realtime', `chat_${metric}`, 'info', { ...sanitizedContext, metricValue: normalizedValue });
  void supabase.rpc('record_chat_observability' as never, {
    p_metric_name: metric,
    p_metric_value: normalizedValue,
    p_context: sanitizedContext,
    p_source: 'app',
  } as never).then(({ error }) => {
    if (error) reportObservability('realtime', 'chat_metric_record_failed', 'warn', { metric });
  });
}

export function recordChatQueryLatency(metric: 'inbox_query_latency_ms' | 'history_query_latency_ms', startedAt: number, context?: Record<string, MetricValue>): void {
  recordChatMetric(metric, Math.max(0, Date.now() - startedAt), context);
}

export function recordMessageEventLatency(createdAt: string, conversationId?: string): void {
  const created = Date.parse(createdAt);
  if (!Number.isFinite(created)) return;
  recordChatMetric('event_delivery_latency_ms', Math.max(0, Date.now() - created), conversationId ? { context: conversationId.slice(0, 80) } : {});
}
