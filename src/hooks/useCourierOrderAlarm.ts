import { useEffect, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { playOrderNotificationSound, unlockOrderNotificationAudio } from '@/lib/orderNotificationSound';

interface CourierState {
  id: string;
  status: string | null;
  registration_status: string | null;
  is_available: boolean | null;
}

/**
 * Keeps the courier alarm alive across route changes. The server only fans out
 * new work to active couriers. The client follows the same user-facing online
 * control (`is_available`) and does not depend on the legacy `status` field,
 * which can remain INACTIVE after the toggle is changed.
 */
export function useCourierOrderAlarm(userId: string | null | undefined) {
  const courierRef = useRef<CourierState | null>(null);
  const knownRideIds = useRef<Set<string> | null>(null);
  const knownOfferIds = useRef<Set<string> | null>(null);
  const knownOrderIds = useRef<Set<string> | null>(null);

  useEffect(() => {
    if (!userId) return;

    let disposed = false;
    let retryTimer: number | undefined;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    const isOnline = () => {
      const courier = courierRef.current;
      return courier?.registration_status === 'APPROVED'
        && courier.is_available === true;
    };

    const loadCourierState = async () => {
      const { data, error } = await supabase
        .from('couriers')
        .select('id, status, registration_status, is_available')
        .eq('user_id', userId)
        .maybeSingle();
      if (error || !data) {
        courierRef.current = null;
        return;
      }
      courierRef.current = data as CourierState;
    };

    const seedCurrentWork = async () => {
      const courier = courierRef.current;
      if (!courier?.id) return;
      const [{ data: rides }, { data: offers }, { data: orders }] = await Promise.all([
        supabase.from('ride_requests').select('id').eq('status', 'SEARCHING').limit(100),
        supabase.from('delivery_assignments').select('id').eq('courier_id', courier.id).in('status', ['OFFERED', 'PENDING']).limit(100),
        supabase.from('orders').select('id').eq('courier_id', courier.id).eq('status', 'COURIER_ACCEPTED').limit(100),
      ]);
      knownRideIds.current = new Set((rides || []).map((row: { id: string }) => row.id));
      knownOfferIds.current = new Set((offers || []).map((row: { id: string }) => row.id));
      knownOrderIds.current = new Set((orders || []).map((row: { id: string }) => row.id));
    };

    const ringIfNew = (kind: 'ride' | 'offer' | 'order', id: string) => {
      if (!isOnline()) return;
      const ids = kind === 'ride'
        ? knownRideIds.current
        : kind === 'offer' ? knownOfferIds.current : knownOrderIds.current;
      if (!ids) {
        if (kind === 'ride') knownRideIds.current = new Set([id]);
        else if (kind === 'offer') knownOfferIds.current = new Set([id]);
        else knownOrderIds.current = new Set([id]);
        return;
      }
      if (ids.has(id)) return;
      ids.add(id);
      void playOrderNotificationSound('courier');
    };

    const subscribe = () => {
      if (disposed) return;
      const channelName = `courier-order-alarm-${userId}-${Math.random().toString(36).slice(2)}`;
      channel = supabase
        .channel(channelName)
        .on('postgres_changes', {
          event: 'INSERT', schema: 'public', table: 'ride_requests', filter: 'status=eq.SEARCHING',
        }, (payload) => ringIfNew('ride', String((payload.new as { id: string }).id)))
        .on('postgres_changes', {
          event: 'INSERT', schema: 'public', table: 'delivery_assignments', filter: `courier_id=eq.${courierRef.current?.id || '00000000-0000-0000-0000-000000000000'}`,
        }, (payload) => ringIfNew('offer', String((payload.new as { id: string }).id)))
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'orders', filter: `courier_id=eq.${courierRef.current?.id || '00000000-0000-0000-0000-000000000000'}`,
        }, (payload) => {
          const order = payload.new as { id: string; status?: string };
          if (order.status === 'COURIER_ACCEPTED') ringIfNew('order', String(order.id));
        })
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'couriers', filter: `user_id=eq.${userId}`,
        }, async (payload) => {
          courierRef.current = payload.new as CourierState;
          if (isOnline()) await seedCurrentWork();
        });

      channel.subscribe((status) => {
        if (status === 'SUBSCRIBED') return;
        if (!disposed && (status === 'CLOSED' || status === 'CHANNEL_ERROR' || status === 'TIMED_OUT')) {
          retryTimer = window.setTimeout(() => {
            if (channel) void supabase.removeChannel(channel);
            channel = null;
            subscribe();
          }, 2000);
        }
      });
    };

    const start = async () => {
      await loadCourierState();
      await seedCurrentWork();
      if (!disposed) subscribe();
    };
    void start();

    // The online toggle is a user gesture and unlocks Web Audio for subsequent
    // realtime callbacks without requiring the rides menu to be opened.
    const unlockOnInteraction = () => unlockOrderNotificationAudio();
    document.addEventListener('pointerdown', unlockOnInteraction, { passive: true });
    document.addEventListener('keydown', unlockOnInteraction);

    return () => {
      disposed = true;
      if (retryTimer) window.clearTimeout(retryTimer);
      document.removeEventListener('pointerdown', unlockOnInteraction);
      document.removeEventListener('keydown', unlockOnInteraction);
      if (channel) void supabase.removeChannel(channel);
      courierRef.current = null;
      knownRideIds.current = null;
      knownOfferIds.current = null;
      knownOrderIds.current = null;
    };
  }, [userId]);
}
