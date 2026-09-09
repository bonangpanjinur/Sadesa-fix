import type { RealtimeChannel } from '@supabase/supabase-js';
import type { ChatConnectionState } from './types';
import { recordChatMetric, recordMessageEventLatency } from './observability';

export function normalizeConnectionStatus(status: string): ChatConnectionState {
  if (status === 'SUBSCRIBED') return 'subscribed';
  if (status === 'CLOSED') return 'closed';
  if (status === 'CHANNEL_ERROR') return 'offline';
  if (status === 'TIMED_OUT') return 'reconnecting';
  return 'reconnecting';
}

export async function disposeChatChannel(channel: RealtimeChannel | null): Promise<void> {
  if (channel) await channel.unsubscribe();
}

export function recordChatChannelStatus(status: string, wasReconnect = false): void {
  if (status === 'SUBSCRIBED') {
    recordChatMetric(wasReconnect ? 'reconnect_success' : 'channel_subscribed');
  } else if (status === 'TIMED_OUT') {
    recordChatMetric('channel_timeout');
  } else if (status === 'CLOSED') {
    recordChatMetric('channel_closed');
  } else if (status === 'CHANNEL_ERROR') {
    recordChatMetric('channel_error');
  }
}

export { recordMessageEventLatency };
