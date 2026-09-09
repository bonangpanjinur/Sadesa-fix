import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export function useChatPresence(conversationId: string | null) {
  const [online, setOnline] = useState(false);
  useEffect(() => {
    setOnline(false);
    if (!conversationId) return;
    const channel = supabase.channel(`chat-presence-${conversationId}`);
    const updatePresence = () => setOnline(Object.keys(channel.presenceState()).length > 1);
    channel.on('presence', { event: 'sync' }, updatePresence);
    channel.on('presence', { event: 'join' }, updatePresence);
    channel.on('presence', { event: 'leave' }, updatePresence);
    channel.subscribe(async (status) => {
      if (status === 'SUBSCRIBED') await channel.track({ online: true });
    });
    return () => {
      setOnline(false);
      void supabase.removeChannel(channel);
    };
  }, [conversationId]);
  return { online };
}
