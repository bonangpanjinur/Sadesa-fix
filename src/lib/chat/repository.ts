import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import type {
  ChatContextType,
  ChatConversation,
  ConversationMessage,
  ConversationType,
} from './types';

type ChatQueryError = { code?: string; message?: string } | null;

const isSchemaCompatibilityError = (error: ChatQueryError) => {
  if (!error) return false;
  return ['42703', '42P01', 'PGRST204', 'PGRST205'].includes(error.code || '')
    || /column .* does not exist|schema cache|relation .* does not exist/i.test(error.message || '');
};

const normalizeMessage = (message: Record<string, unknown>): ConversationMessage => ({
  ...message,
  body: typeof message.body === 'string' ? message.body : (message.message as string),
} as ConversationMessage);

interface ConversationRequest {
  contextType: ChatContextType;
  orderId?: string;
  rideRequestId?: string;
  conversationType: ConversationType;
}

interface SendMessageRequest extends ConversationRequest {
  conversationId: string;
  senderId: string;
  receiverId: string;
  text: string;
  clientMessageId: string;
}

export async function getOrCreateConversation(
  request: ConversationRequest,
): Promise<{ conversationId: string | null; error: Error | null }> {
  const { data, error } = await supabase.rpc('get_or_create_chat_conversation', {
    p_context_type: request.contextType,
    p_order_id: request.orderId ?? null,
    p_ride_request_id: request.rideRequestId ?? null,
    p_conversation_type: request.conversationType,
  });

  if (error) return { conversationId: null, error };
  return { conversationId: typeof data === 'string' ? data : null, error: null };
}

export async function getOrCreateDirectConversation(
  merchantId: string,
): Promise<{ conversationId: string | null; error: Error | null }> {
  const { data, error } = await supabase.rpc('get_or_create_direct_chat' as never, {
    p_merchant_id: merchantId,
  } as never);

  if (error) return { conversationId: null, error };
  return { conversationId: typeof data === 'string' ? data : null, error: null };
}

export async function listConversationMessages(
  conversationId: string,
  limit = 50,
): Promise<{ messages: ConversationMessage[]; error: Error | null }> {
  const canonical = await supabase
    .from('chat_messages')
    .select('*')
    .eq('conversation_id', conversationId)
    .is('deleted_at', null)
    .order('created_at', { ascending: true })
    .order('id', { ascending: true })
    .limit(limit);
  let data = canonical.data;
  let error = canonical.error;

  if (error && isSchemaCompatibilityError(error)) {
    const compatible = await supabase
      .from('chat_messages')
      .select('*')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: true })
      .order('id', { ascending: true })
      .limit(limit);
    data = compatible.data;
    error = compatible.error;
  }

  return {
    messages: (data || []).map((message) => normalizeMessage(message as Record<string, unknown>)),
    error,
  };
}

export async function sendConversationMessage(
  request: SendMessageRequest,
): Promise<{ message: ConversationMessage | null; error: Error | null }> {
  const payload = {
    conversation_id: request.conversationId,
    order_id: request.orderId ?? null,
    sender_id: request.senderId,
    receiver_id: request.receiverId,
    message: request.text,
    body: request.text,
    message_type: 'text',
    client_message_id: request.clientMessageId,
    chat_type: request.conversationType === 'passenger_courier'
      ? 'buyer_courier'
      : request.conversationType,
  };

  const canonicalInsert = await supabase
    .from('chat_messages')
    .insert(payload)
    .select('*')
    .single();
  let data = canonicalInsert.data;
  let error = canonicalInsert.error;

  // Older/partially migrated databases may have conversation_id but not the
  // newer body/message_type/client_message_id columns. Keep ride chat usable
  // while the additive schema bundle is being applied.
  if (error && isSchemaCompatibilityError(error)) {
    const legacyCompatibleInsert = await supabase
      .from('chat_messages')
      .insert({
        conversation_id: request.conversationId,
        order_id: request.orderId ?? null,
        sender_id: request.senderId,
        receiver_id: request.receiverId,
        message: request.text,
        chat_type: request.conversationType === 'passenger_courier'
          ? 'buyer_courier'
          : request.conversationType,
      })
      .select('*')
      .single();
    data = legacyCompatibleInsert.data;
    error = legacyCompatibleInsert.error;
  }

  if (!error) return { message: normalizeMessage(data as Record<string, unknown>), error: null };

  // A timeout can happen after PostgreSQL committed the insert. The unique
  // client id makes retry safe and lets us recover the committed row.
  if (request.clientMessageId) {
    const retry = await supabase
      .from('chat_messages')
      .select('*')
      .eq('sender_id', request.senderId)
      .eq('client_message_id', request.clientMessageId)
      .maybeSingle();
    if (retry.data) return { message: normalizeMessage(retry.data as Record<string, unknown>), error: null };
  }

  return { message: null, error };
}

export async function markConversationRead(
  conversationId: string,
  messageId?: string,
): Promise<Error | null> {
  const { error } = await supabase.rpc('mark_chat_conversation_read', {
    p_conversation_id: conversationId,
    p_message_id: messageId ?? null,
  });
  return error;
}

export async function getConversationUnreadCount(): Promise<{
  count: number;
  error: Error | null;
}> {
  const { data, error } = await supabase.rpc('get_chat_unread_count');
  return { count: typeof data === 'number' ? data : Number(data || 0), error };
}

export function subscribeToConversation(
  conversationId: string,
  onInsert: (message: ConversationMessage) => void,
  onStatus: (status: string, error?: unknown) => void,
): RealtimeChannel {
  const channelName = `chat-conversation-${conversationId}`;
  const channel = supabase
    .channel(channelName)
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'chat_messages',
        filter: `conversation_id=eq.${conversationId}`,
      },
      (payload) => onInsert(payload.new as ConversationMessage),
    );

  channel.subscribe((status, error) => onStatus(status, error));
  return channel;
}