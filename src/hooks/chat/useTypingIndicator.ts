import { useEffect, useRef, useState } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';

export function useTypingIndicator(conversationId: string | null) {
  const [typing, setTyping] = useState(false);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const debounceRef = useRef<number | null>(null);
  const stopRef = useRef<number | null>(null);

  useEffect(() => {
    if (!conversationId) return;
    const channel = supabase.channel(`chat-typing-${conversationId}`);
    channelRef.current = channel;
    channel.on('broadcast', { event: 'typing' }, ({ payload }) => setTyping(Boolean(payload?.typing)));
    channel.subscribe();
    return () => {
      if (debounceRef.current) window.clearTimeout(debounceRef.current);
      if (stopRef.current) window.clearTimeout(stopRef.current);
      void supabase.removeChannel(channel);
      if (channelRef.current === channel) channelRef.current = null;
    };
  }, [conversationId]);

  const setIsTyping = (value: boolean) => {
    if (!channelRef.current) return;
    if (debounceRef.current) window.clearTimeout(debounceRef.current);
    const broadcast = () => { void channelRef.current?.send({ type: 'broadcast', event: 'typing', payload: { typing: value } }); };
    debounceRef.current = window.setTimeout(broadcast, value ? 400 : 0);
    if (stopRef.current) window.clearTimeout(stopRef.current);
    if (value) stopRef.current = window.setTimeout(() => setIsTyping(false), 3000);
  };

  return { typing, setIsTyping };
}
