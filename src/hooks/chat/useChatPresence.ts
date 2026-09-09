import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export function useChatPresence(conversationId: string | null) {
  const [online, setOnline] = useState(false);
  useEffect(() => { if (!conversationId) return; const channel = supabase.channel(`chat-presence-${conversationId}`); channel.on('presence', { event: 'sync' }, () => setOnline(Object.keys(channel.presenceState()).length > 1)).subscribe(async (status) => { if (status === 'SUBSCRIBED') await channel.track({ online_at: new Date().toISOString() }); }); return () => { void supabase.removeChannel(channel); }; }, [conversationId]);
  return { online };
}
