import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { getOrCreateConversation, getOrCreateDirectConversation, listConversationMessages, markConversationRead, sendConversationMessage, subscribeToConversation } from '@/lib/chat/repository';
import { validateMessageBody } from '@/lib/chat/retention';
import type { ChatConnectionState, ConversationMessage, ConversationType } from '@/lib/chat/types';

export function useConversation(options: { contextType: 'order' | 'ride' | 'direct'; conversationType: ConversationType; orderId?: string; rideRequestId?: string; merchantId?: string; receiverId: string }) {
  const { user } = useAuth();
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ConversationMessage[]>([]);
  const [status, setStatus] = useState<ChatConnectionState>('loading');
  const [error, setError] = useState<string | null>(null);
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);
  const key = `${options.contextType}:${options.orderId || options.rideRequestId || options.merchantId || ''}:${options.conversationType}`;

  const addMessage = useCallback((message: ConversationMessage) => setMessages((current) => current.some((item) => item.id === message.id || (item.client_message_id && item.client_message_id === message.client_message_id)) ? current.map((item) => item.client_message_id === message.client_message_id ? { ...message, deliveryStatus: 'sent' } : item) : [...current, message].sort((a, b) => a.created_at.localeCompare(b.created_at))), []);

  useEffect(() => {
    if (!user) return;
    let active = true;
    setStatus('loading'); setError(null); setMessages([]);
    const load = async () => {
      const result = options.contextType === 'direct' && options.merchantId ? await getOrCreateDirectConversation(options.merchantId) : await getOrCreateConversation({ contextType: options.contextType, orderId: options.orderId, rideRequestId: options.rideRequestId, conversationType: options.conversationType });
      if (!active) return;
      if (result.error || !result.conversationId) { setStatus(result.error?.code === 'unauthorized' ? 'closed' : 'offline'); setError(result.error?.message || 'Percakapan belum tersedia'); return; }
      setConversationId(result.conversationId);
      const history = await listConversationMessages(result.conversationId);
      if (!active) return;
      if (history.error) { setStatus('offline'); setError(history.error.message); return; }
      setMessages(history.messages); const last = history.messages.at(-1); if (last) await markConversationRead(result.conversationId, last.id);
      channelRef.current = subscribeToConversation(result.conversationId, addMessage, (next) => { if (active) setStatus(next === 'SUBSCRIBED' ? 'subscribed' : next === 'CLOSED' ? 'closed' : 'reconnecting'); }, (message) => setMessages((current) => current.map((item) => item.id === message.id ? message : item)));
    };
    void load();
    return () => { active = false; if (channelRef.current) void supabase.removeChannel(channelRef.current); channelRef.current = null; setConversationId(null); };
  }, [addMessage, key, options, user]);

  const send = useCallback(async (text: string) => {
    if (!user || !conversationId) return { error: new Error('Percakapan belum siap') };
    const validationError = validateMessageBody(text); if (validationError) return { error: new Error(validationError) };
    const clientMessageId = crypto.randomUUID(); const optimistic: ConversationMessage = { id: `local-${clientMessageId}`, conversation_id: conversationId, sender_id: user.id, receiver_id: options.receiverId, message: text.trim(), body: text.trim(), is_read: false, created_at: new Date().toISOString(), auto_delete_at: null, soft_delete_at: null, hard_delete_at: null, chat_type: options.conversationType, image_url: null, client_message_id: clientMessageId, deleted_at: null, deleted_reason: null, deliveryStatus: 'sending' };
    addMessage(optimistic);
    const result = await sendConversationMessage({ ...options, conversationId, senderId: user.id, receiverId: options.receiverId, text: text.trim(), clientMessageId });
    if (result.error || !result.message) { setMessages((current) => current.map((item) => item.id === optimistic.id ? { ...item, deliveryStatus: 'failed' } : item)); return { error: result.error || new Error('Pesan gagal dikirim') }; }
    addMessage(result.message); return { message: result.message };
  }, [addMessage, conversationId, options, user]);
  return { conversationId, messages, status, error, send, retry: send };
}
