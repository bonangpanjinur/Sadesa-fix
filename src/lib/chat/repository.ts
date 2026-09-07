import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import type {
  ChatContextType,
  ChatConversation,
  ConversationMessage,
  ConversationType,
} from './types';

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

export async function listConversationMessages(
  conversationId: string,
  limit = 50,
): Promise<{ messages: ConversationMessage[]; error: Error | null }> {
  const { data, error } = await supabase
    .from('chat_messages')
    .select('id, conversation_id, sender_id, receiver_id, message, body, is_read, created_at, auto_delete_at, chat_type, image_url, client_message_id, deleted_at')
    .eq('conversation_id', conversationId)
    .is('deleted_at', null)
    .order('created_at', { ascending: true })
    .order('id', { ascending: true })
    .limit(limit);

  return {
    messages: (data || []) as ConversationMessage[],
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

  const { data, error } = await supabase
    .from('chat_messages')
    .insert(payload)
    .select('id, conversation_id, sender_id, receiver_id, message, body, is_read, created_at, auto_delete_at, chat_type, image_url, client_message_id, deleted_at')
    .single();

  if (!error) return { message: data as ConversationMessage, error: null };

  // A timeout can happen after PostgreSQL committed the insert. The unique
  // client id makes retry safe and lets us recover the committed row.
  if (request.clientMessageId) {
    const retry = await supabase
      .from('chat_messages')
      .select('id, conversation_id, sender_id, receiver_id, message, body, is_read, created_at, auto_delete_at, chat_type, image_url, client_message_id, deleted_at')
      .eq('sender_id', request.senderId)
      .eq('client_message_id', request.clientMessageId)
      .maybeSingle();
    if (retry.data) return { message: retry.data as ConversationMessage, error: null };
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