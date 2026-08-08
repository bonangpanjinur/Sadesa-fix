import { useState, useEffect, useRef, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { logRealtimeStatus, type RealtimeStatus } from '@/lib/realtimeTelemetry';

export function useChatNotification() {
  const { user } = useAuth();
  const userId = user?.id;
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [isEnabled, setIsEnabled] = useState(true);
  const [realtimeStatus, setRealtimeStatus] = useState<RealtimeStatus>('idle');
  const isEnabledRef = useRef(isEnabled);
  const channelRef = useRef<RealtimeChannel | null>(null);

  // Keep a ref so the realtime callback reads the latest value without
  // forcing the channel to tear down / re-subscribe on every toggle.
  useEffect(() => {
    isEnabledRef.current = isEnabled;
  }, [isEnabled]);

  // Initialize audio element
  useEffect(() => {
    if (!audioRef.current) {
      audioRef.current = new Audio('/notification.wav');
      audioRef.current.preload = 'auto';
    }
    return () => {
      audioRef.current?.pause();
      audioRef.current = null;
    };
  }, []);

  // Play notification sound
  const playNotificationSound = useCallback(() => {
    if (!isEnabledRef.current || !audioRef.current) return;

    try {
      audioRef.current.currentTime = 0;
      audioRef.current.play().catch((error) => {
        console.warn('Failed to play notification sound:', error);
      });
    } catch (error) {
      console.warn('Error playing notification:', error);
    }
  }, []);

  // Set up real-time listener for incoming messages
  useEffect(() => {
    if (!userId) { setRealtimeStatus('idle'); return; }

    let active = true;

    const channelName = `chat-notification-${userId}-${Math.random().toString(36).slice(2)}`;
    const channel = supabase
      .channel(channelName)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'chat_messages',
          filter: `receiver_id=eq.${userId}`,
        },
        (payload) => {
          if (!active) return;
          // Play sound only for new messages from others (not our own)
          if (payload.new.sender_id !== userId) {
            playNotificationSound();
          }
        }
      );

    channelRef.current = channel;
    channel.subscribe((status, err) => {
      const normalized = logRealtimeStatus(channelName, status, err);
      if (active) setRealtimeStatus(normalized);
    });

    return () => {
      active = false;
      // Detach postgres_changes bindings first, then drop the channel.
      try { channel.unsubscribe(); } catch { /* noop */ }
      supabase.removeChannel(channel);
      if (channelRef.current === channel) channelRef.current = null;
    };
  }, [userId, playNotificationSound]);

  return {
    playNotificationSound,
    isEnabled,
    setIsEnabled,
    realtimeStatus,
  };
}
