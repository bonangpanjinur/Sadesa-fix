import type { RealtimeChannel } from '@supabase/supabase-js';
import type { ChatConnectionState } from './types';

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
