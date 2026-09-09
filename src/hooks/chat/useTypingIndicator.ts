import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export function useTypingIndicator(conversationId: string | null) {
  const [typing, setTyping] = useState(false); const timeoutRef = useRef<number | null>(null);
  useEffect(() => { if (!conversationId) return; const channel = supabase.channel(`chat-typing-${conversationId}`).on('broadcast', { event: 'typing' }, ({ payload }) => setTyping(Boolean(payload?.typing))); channel.subscribe(); return () => { void supabase.removeChannel(channel); }; }, [conversationId]);
  const setIsTyping = (value: boolean) => { if (!conversationId) return; const channel = supabase.channel(`chat-typing-${conversationId}`); void channel.send({ type: 'broadcast', event: 'typing', payload: { typing: value } }); if (timeoutRef.current) window.clearTimeout(timeoutRef.current); if (value) timeoutRef.current = window.setTimeout(() => setIsTyping(false), 3000); };
  return { typing, setIsTyping };
}
