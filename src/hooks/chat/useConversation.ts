import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { getOrCreateConversation, getOrCreateDirectConversation, listConversationMessages, markConversationRead, sendConversationMessage, subscribeToConversation } from '@/lib/chat/repository';
import { validateMessageBody } from '@/lib/chat/retention';
import { getChatReconnectDelay } from '@/lib/chat/realtime';
import type { ChatConnectionState, ChatCursor, ConversationMessage, ConversationType } from '@/lib/chat/types';

interface ConversationOptions {
  contextType: 'order' | 'ride' | 'direct';
  conversationType: ConversationType;
  orderId?: string;
  rideRequestId?: string;
  merchantId?: string;
  receiverId: string;
}

function cursorFrom(messages: ConversationMessage[]): ChatCursor | null {
  const last = messages.at(-1);
  return last ? { createdAt: last.created_at, id: last.id } : null;
}

export function useConversation(options: ConversationOptions) {
  const { user } = useAuth();
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ConversationMessage[]>([]);
  const [status, setStatus] = useState<ChatConnectionState>('loading');
  const [error, setError] = useState<string | null>(null);
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reconnectAttemptRef = useRef(0);
  const cursorRef = useRef<ChatCursor | null>(null);
  const activeRef = useRef(true);
  const catchUpRef = useRef(false);
  const key = `${options.contextType}:${options.orderId || options.rideRequestId || options.merchantId || ''}:${options.conversationType}:${options.receiverId}`;

  const addMessage = useCallback((message: ConversationMessage) => {
    setMessages((current) => {
      if (current.some((item) => item.id === message.id)) return current;
      const duplicate = message.client_message_id && current.find((item) => item.client_message_id === message.client_message_id);
      const next: ConversationMessage[] = duplicate ? current.map((item) => item.client_message_id === message.client_message_id ? { ...message, deliveryStatus: 'sent' as const } : item) : [...current, message];
      cursorRef.current = cursorFrom(next.filter((item) => !item.id.startsWith('local-')));
      return next.sort((a, b) => a.created_at.localeCompare(b.created_at));
    });
  }, []);

  const catchUp = useCallback(async (id: string) => {
    if (catchUpRef.current) return;
    catchUpRef.current = true;
    try {
      const result = await listConversationMessages(id, 100, cursorRef.current || undefined);
      if (!activeRef.current) return;
      if (result.error) { setError(result.error.message); setStatus('offline'); return; }
      result.messages.forEach(addMessage);
      if (result.messages.length) await markConversationRead(id, result.messages.at(-1)?.id);
    } finally {
      catchUpRef.current = false;
    }
  }, [addMessage]);

  useEffect(() => {
    if (!user) return;
    activeRef.current = true;
    setStatus('loading'); setError(null); setMessages([]); cursorRef.current = null;
    const load = async () => {
      const result = options.contextType === 'direct' && options.merchantId
        ? await getOrCreateDirectConversation(options.merchantId)
        : await getOrCreateConversation({ contextType: options.contextType, orderId: options.orderId, rideRequestId: options.rideRequestId, conversationType: options.conversationType });
      if (!activeRef.current) return;
      if (result.error || !result.conversationId) { setStatus(result.error?.code === 'unauthorized' ? 'closed' : 'offline'); setError(result.error?.message || 'Percakapan belum tersedia'); return; }
      setConversationId(result.conversationId);
      const history = await listConversationMessages(result.conversationId);
      if (!activeRef.current) return;
      if (history.error) { setStatus('offline'); setError(history.error.message); return; }
      setMessages(history.messages); cursorRef.current = cursorFrom(history.messages);
      const last = history.messages.at(-1); if (last) await markConversationRead(result.conversationId, last.id);

      let connect: () => void = () => undefined;
      const scheduleReconnect = () => {
        if (!activeRef.current || reconnectTimerRef.current) return;
        const attempt = reconnectAttemptRef.current;
        const delay = getChatReconnectDelay(attempt);
        reconnectAttemptRef.current = attempt + 1;
        setStatus(attempt >= 4 ? 'offline' : 'reconnecting');
        reconnectTimerRef.current = setTimeout(() => {
          reconnectTimerRef.current = null;
          connect();
        }, delay);
      };

      connect = () => {
        if (!activeRef.current) return;
        if (channelRef.current) void supabase.removeChannel(channelRef.current);
        channelRef.current = subscribeToConversation(result.conversationId!, addMessage, (next) => {
          if (!activeRef.current) return;
          if (next === 'SUBSCRIBED') {
            reconnectAttemptRef.current = 0;
            setStatus('subscribed');
            void catchUp(result.conversationId!);
          } else if (next === 'CHANNEL_ERROR' || next === 'TIMED_OUT' || next === 'CLOSED') {
            scheduleReconnect();
          } else {
            setStatus('reconnecting');
          }
        }, (message) => {
          setMessages((current) => current.map((item) => item.id === message.id ? message : item));
        });
      };
      connect();
    };
    void load();
    return () => {
      activeRef.current = false;
      if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
      reconnectTimerRef.current = null;
      reconnectAttemptRef.current = 0;
      if (channelRef.current) void supabase.removeChannel(channelRef.current);
      channelRef.current = null;
      setConversationId(null);
    };
  }, [addMessage, catchUp, key, options, user]);

  const send = useCallback(async (text: string) => {
    if (!user || !conversationId) return { error: new Error('Percakapan belum siap') };
    const validationError = validateMessageBody(text); if (validationError) return { error: new Error(validationError) };
    const clientMessageId = crypto.randomUUID();
    const optimistic: ConversationMessage = { id: `local-${clientMessageId}`, conversation_id: conversationId, sender_id: user.id, receiver_id: options.receiverId, message: text.trim(), body: text.trim(), is_read: false, created_at: new Date().toISOString(), auto_delete_at: null, soft_delete_at: null, hard_delete_at: null, chat_type: options.conversationType, image_url: null, client_message_id: clientMessageId, deleted_at: null, deleted_reason: null, deliveryStatus: 'sending' };
    addMessage(optimistic);
    const result = await sendConversationMessage({ ...options, conversationId, senderId: user.id, receiverId: options.receiverId, text: text.trim(), clientMessageId });
    if (result.error || !result.message) { setMessages((current) => current.map((item) => item.id === optimistic.id ? { ...item, deliveryStatus: 'failed' } : item)); return { error: result.error || new Error('Pesan gagal dikirim') }; }
    addMessage(result.message); return { message: result.message };
  }, [addMessage, conversationId, options, user]);
  return { conversationId, messages, status, error, send, retry: send };
}
