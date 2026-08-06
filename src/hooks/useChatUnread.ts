import { useState, useEffect, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { logRealtimeStatus, type RealtimeStatus } from '@/lib/realtimeTelemetry';

export function useChatUnread() {
  const { user } = useAuth();
  const [unreadCount, setUnreadCount] = useState(0);
  const [realtimeStatus, setRealtimeStatus] = useState<RealtimeStatus>('idle');
  const channelRef = useRef<RealtimeChannel | null>(null);

  useEffect(() => {
    if (!user) { setUnreadCount(0); setRealtimeStatus('idle'); return; }

    let active = true;

    const fetchUnread = async () => {
      const { count } = await supabase
        .from('chat_messages')
        .select('*', { count: 'exact', head: true })
        .eq('receiver_id', user.id)
        .eq('is_read', false);
      if (!active) return;
      setUnreadCount(count || 0);
    };

    fetchUnread();

    const channelName = `chat-unread-${user.id}-${Math.random().toString(36).slice(2)}`;
    const channel = supabase
      .channel(channelName)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `receiver_id=eq.${user.id}` },
        () => { if (active) fetchUnread(); }
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'chat_messages', filter: `receiver_id=eq.${user.id}` },
        () => { if (active) fetchUnread(); }
      );

    channelRef.current = channel;
    channel.subscribe((status, err) => {
      const normalized = logRealtimeStatus(channelName, status, err);
      if (active) setRealtimeStatus(normalized);
    });

    return () => {
      active = false;
      // Detach postgres_changes callbacks before removing, so a re-subscribe
      // on the next effect run never reuses a stale binding.
      try { channel.unsubscribe(); } catch { /* noop */ }
      supabase.removeChannel(channel);
      if (channelRef.current === channel) channelRef.current = null;
    };
  }, [user?.id]);

  return { unreadCount, realtimeStatus };
}
