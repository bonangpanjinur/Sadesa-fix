import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import type { ChatContextType, ChatCursor, ChatInboxItem, ChatPage, ConversationMessage, ConversationType } from './types';
import { toChatError } from './errors';
import { recordChatMetric, recordChatQueryLatency, recordMessageEventLatency } from './observability';
import { recordChatChannelStatus } from './realtime';

const normalizeMessage = (message: Record<string, unknown>): ConversationMessage => ({
  ...message,
  body: typeof message.body === 'string' ? message.body : (message.message as string),
  deliveryStatus: 'sent',
} as ConversationMessage);

export interface ConversationRequest { contextType: ChatContextType; orderId?: string; rideRequestId?: string; conversationType: ConversationType; }
export interface SendMessageRequest extends ConversationRequest { conversationId: string; senderId: string; receiverId: string; text: string; clientMessageId: string; }

export async function getOrCreateConversation(request: ConversationRequest) {
  const { data, error } = await supabase.rpc('get_or_create_chat_conversation', { p_context_type: request.contextType, p_order_id: request.orderId ?? null, p_ride_request_id: request.rideRequestId ?? null, p_conversation_type: request.conversationType });
  return { conversationId: typeof data === 'string' ? data : null, error: error ? toChatError(error) : null };
}

export async function getOrCreateDirectConversation(merchantId: string) {
  const { data, error } = await supabase.rpc('get_or_create_direct_chat' as never, { p_merchant_id: merchantId } as never);
  return { conversationId: typeof data === 'string' ? data : null, error: error ? toChatError(error) : null };
}

export async function getOrCreateAdminDirectConversation(targetUserId: string, targetRole: 'merchant' | 'courier') {
  const { data, error } = await supabase.rpc('get_or_create_admin_direct_chat' as never, {
    p_target_user_id: targetUserId,
    p_target_role: targetRole,
  } as never);
  return { conversationId: typeof data === 'string' ? data : null, error: error ? toChatError(error) : null };
}

export async function listConversationMessages(conversationId: string, limit = 50, cursor?: ChatCursor): Promise<{ messages: ConversationMessage[]; error: Error | null }> {
  const startedAt = Date.now();
  let query = supabase.from('chat_messages').select('*').eq('conversation_id', conversationId).order('created_at', { ascending: true }).order('id', { ascending: true }).limit(limit);
  if (cursor) query = query.or(`created_at.gt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.gt.${cursor.id})`);
  const { data, error } = await query;
  recordChatQueryLatency('history_query_latency_ms', startedAt, { has_cursor: Boolean(cursor) });
  return { messages: (data || []).map((row) => normalizeMessage(row as Record<string, unknown>)), error: error ? toChatError(error) : null };
}

export async function listOlderConversationMessages(conversationId: string, before: ChatCursor, limit = 50): Promise<{ messages: ConversationMessage[]; error: Error | null }> {
  const startedAt = Date.now();
  const { data, error } = await supabase
    .from('chat_messages')
    .select('*')
    .eq('conversation_id', conversationId)
    .or(`created_at.lt.${before.createdAt},and(created_at.eq.${before.createdAt},id.lt.${before.id})`)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(limit);
  recordChatQueryLatency('history_older_query_latency_ms', startedAt, { has_cursor: true });
  return {
    messages: (data || []).map((row) => normalizeMessage(row as Record<string, unknown>)).reverse(),
    error: error ? toChatError(error) : null,
  };
}

export async function listConversationPage(conversationId: string, limit = 50, cursor?: ChatCursor): Promise<{ page: ChatPage; error: Error | null }> {
  const result = await listConversationMessages(conversationId, limit + 1, cursor);
  const messages = result.messages.slice(0, limit);
  const last = messages.at(-1);
  return { page: { messages, nextCursor: result.messages.length > limit && last ? { createdAt: last.created_at, id: last.id } : null }, error: result.error };
}

export async function listChatInbox(): Promise<{ items: ChatInboxItem[]; error: Error | null }> {
  const startedAt = Date.now();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) { recordChatQueryLatency('inbox_query_latency_ms', startedAt); return { items: [], error: toChatError(new Error('Unauthorized')) }; }
  const { data: memberships, error: membershipError } = await supabase.from('chat_participants').select('conversation_id, last_read_message_id').eq('user_id', auth.user.id).is('left_at', null);
  if (membershipError) { recordChatQueryLatency('inbox_query_latency_ms', startedAt); return { items: [], error: toChatError(membershipError) }; }
  const ids = (memberships || []).map((row) => row.conversation_id);
  if (!ids.length) { recordChatQueryLatency('inbox_query_latency_ms', startedAt); return { items: [], error: null }; }
  const { data: conversations, error } = await supabase.from('chat_conversations').select('*').in('id', ids).order('last_message_at', { ascending: false, nullsFirst: false });
  if (error) { recordChatQueryLatency('inbox_query_latency_ms', startedAt); return { items: [], error: toChatError(error) }; }
  const { data: participants } = await supabase.from('chat_participants').select('conversation_id, user_id').in('conversation_id', ids).neq('user_id', auth.user.id).is('left_at', null);
  const otherUserIds = [...new Set((participants || []).map((row) => row.user_id))];
  const [{ data: profiles }, { data: merchants }, { data: couriers }] = await Promise.all([
    otherUserIds.length ? supabase.from('profiles').select('user_id, full_name').in('user_id', otherUserIds) : Promise.resolve({ data: [] }),
    otherUserIds.length ? supabase.from('merchants').select('user_id, name').in('user_id', otherUserIds) : Promise.resolve({ data: [] }),
    otherUserIds.length ? supabase.from('couriers').select('user_id, name').in('user_id', otherUserIds) : Promise.resolve({ data: [] }),
  ]);
  const items = (conversations || []).map((row) => {
    const participant = (participants || []).find((item) => item.conversation_id === row.id);
    const profile = profiles?.find((item) => item.user_id === participant?.user_id);
    const merchant = merchants?.find((item) => item.user_id === participant?.user_id);
    const courier = couriers?.find((item) => item.user_id === participant?.user_id);
    return { ...row, other_user_id: participant?.user_id || null, other_user_name: merchant?.name || courier?.name || profile?.full_name || 'Pengguna', last_message_preview: row.last_message_body || (row.last_message_id ? 'Pesan terbaru' : 'Belum ada pesan') } as ChatInboxItem;
  });
  recordChatQueryLatency('inbox_query_latency_ms', startedAt, { conversation_count: items.length });
  recordChatMetric('active_conversations', items.length);
  return { items, error: null };
}

export async function sendConversationMessage(request: SendMessageRequest) {
  const text = request.text.trim();
  if (!request.conversationId || !request.senderId || !request.receiverId || request.senderId === request.receiverId) {
    return { message: null, error: toChatError({ code: '22023', message: 'Peserta percakapan tidak valid' }) };
  }
  if (!text || text.length > 4000) {
    return { message: null, error: toChatError({ code: '22023', message: 'Pesan harus berisi 1 sampai 4000 karakter' }) };
  }

  const { data, error } = await supabase.rpc('send_chat_message' as never, { p_conversation_id: request.conversationId, p_receiver_id: request.receiverId, p_body: text, p_client_message_id: request.clientMessageId } as never);
  if (!error && data) return { message: normalizeMessage(data as Record<string, unknown>), error: null };
  const retry = await supabase.from('chat_messages').select('*').eq('sender_id', request.senderId).eq('client_message_id', request.clientMessageId).maybeSingle();
  if (retry.data) { recordChatMetric('duplicate_retry_recovered'); return { message: normalizeMessage(retry.data as Record<string, unknown>), error: null }; }
  if (error) {
    console.error('[chat] send_chat_message failed', {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
      conversationId: request.conversationId,
    });
  }
  return { message: null, error: error ? toChatError(error) : toChatError(new Error('Pesan belum terkirim')) };
}

export async function markConversationRead(conversationId: string, messageId?: string) { const { error } = await supabase.rpc('mark_chat_conversation_read', { p_conversation_id: conversationId, p_message_id: messageId ?? null }); return error ? toChatError(error) : null; }
export async function getConversationUnreadCount() { const { data, error } = await supabase.rpc('get_chat_unread_count'); return { count: typeof data === 'number' ? data : Number(data || 0), error: error ? toChatError(error) : null }; }

export function subscribeToConversation(conversationId: string, onInsert: (message: ConversationMessage) => void, onStatus: (status: string, error?: unknown) => void, onUpdate?: (message: ConversationMessage) => void): RealtimeChannel {
  let subscribedOnce = false;
  const channel = supabase.channel(`chat-conversation-${conversationId}`).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `conversation_id=eq.${conversationId}` }, (payload) => { const message = normalizeMessage(payload.new as Record<string, unknown>); recordMessageEventLatency(message.created_at, conversationId); onInsert(message); }).on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'chat_messages', filter: `conversation_id=eq.${conversationId}` }, (payload) => onUpdate?.(normalizeMessage(payload.new as Record<string, unknown>)));
  channel.subscribe((status, error) => { recordChatChannelStatus(status, subscribedOnce); if (status === 'SUBSCRIBED') subscribedOnce = true; onStatus(status, error); });
  return channel;
}
