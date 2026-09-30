import { useEffect, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { playOrderNotificationSound, stopOrderNotificationSound, unlockOrderNotificationAudio } from '@/lib/orderNotificationSound';
import { vibrateCourierAlarm } from '@/lib/courierNotificationFeedback';

interface CourierState {
  id: string;
  status: string | null;
  registration_status: string | null;
  is_available: boolean | null;
}

interface RideOfferPayload {
  ride_id: string;
  courier_id: string;
  status: string;
}

interface DeliveryOfferPayload {
  order_id: string;
  courier_id: string;
  status: string;
}

/** Plays a short alert for a courier's pending offers from any courier route. */
export function useCourierOrderAlarm(userId: string | null | undefined) {
  const courierRef = useRef<CourierState | null>(null);
  const pendingRideIds = useRef<Set<string>>(new Set());
  const pendingOrderIds = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!userId) return;

    let disposed = false;
    let retryTimer: number | undefined;
    let refreshTimer: number | undefined;
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let hasSeededWork = false;
    let rideOfferTableAvailable: boolean | null = null;

    const isOnline = () => courierRef.current?.status === 'ACTIVE'
      && courierRef.current.registration_status === 'APPROVED'
      && courierRef.current.is_available === true;

    const syncSound = () => {
      if (!isOnline() || (pendingRideIds.current.size === 0 && pendingOrderIds.current.size === 0)) {
        stopOrderNotificationSound('courier');
      }
    };

    const alertNewOffer = () => {
      if (!isOnline()) return;
      vibrateCourierAlarm();
      void playOrderNotificationSound('courier');
    };

    const updatePending = (kind: 'ride' | 'order', id: string, isPending: boolean) => {
      if (!id) return;
      const pendingIds = kind === 'ride' ? pendingRideIds.current : pendingOrderIds.current;
      if (isPending) {
        if (!pendingIds.has(id)) {
          pendingIds.add(id);
          alertNewOffer();
        }
        return;
      }
      pendingIds.delete(id);
      syncSound();
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

    const fetchPendingRideIds = async (courierId: string) => {
      if (rideOfferTableAvailable !== false) {
        const { data, error } = await supabase
          .from('ride_request_offers' as never)
          .select('ride_id')
          .eq('courier_id', courierId)
          .eq('status', 'PENDING')
          .gt('expires_at', new Date().toISOString())
          .limit(100);
        if (!error) {
          rideOfferTableAvailable = true;
          return {
            ids: ((data || []) as unknown as Array<{ ride_id: string }>).map((row) => row.ride_id),
            error: false,
          };
        }

        const dbError = error as { code?: string; message?: string; status?: number };
        const missingTable = dbError.code === 'PGRST205'
          || dbError.code === '42P01'
          || dbError.status === 404
          || (/404/.test(dbError.message || '') && /ride_request_offers/i.test(dbError.message || ''))
          || /ride_request_offers.*(not found|schema cache|does not exist)/i.test(dbError.message || '');
        if (!missingTable) return { ids: null, error: true };
        rideOfferTableAvailable = false;
      }

      // Never fall back to all SEARCHING rides. That legacy query can expose
      // another passenger's pickup to every courier when the targeted-offer
      // migration is missing. Fail closed until the private offer table exists.
      return { ids: null, error: true };
    };

    const seedCurrentWork = async (notifyNew = true) => {
      const courier = courierRef.current;
      if (!courier?.id || !isOnline()) {
        pendingRideIds.current.clear();
        pendingOrderIds.current.clear();
        stopOrderNotificationSound('courier');
        return;
      }

      const [rideResult, { data: offers, error: offerError }, { data: orders, error: orderError }] = await Promise.all([
        fetchPendingRideIds(courier.id),
        supabase.from('delivery_assignments').select('order_id').eq('courier_id', courier.id).eq('status', 'OFFERED').gt('expires_at', new Date().toISOString()).limit(100),
        supabase.from('orders').select('id').eq('courier_id', courier.id).eq('status', 'ASSIGNED').limit(100),
      ]);
      if (disposed) return;

      const nextRideIds = rideResult.error || !rideResult.ids
        ? pendingRideIds.current
        : new Set(rideResult.ids);
      const nextOrderIds = new Set(pendingOrderIds.current);
      if (!offerError && offers) {
        nextOrderIds.clear();
        (offers as unknown as Array<{ order_id: string | null }>).forEach((row) => {
          if (row.order_id) nextOrderIds.add(row.order_id);
        });
      }
      if (!orderError && orders) {
        (orders as Array<{ id: string }>).forEach((row) => nextOrderIds.add(row.id));
      }

      const hasExistingSeed = hasSeededWork;
      const hasNewRide = [...nextRideIds].some((id) => !pendingRideIds.current.has(id));
      const hasNewOrder = [...nextOrderIds].some((id) => !pendingOrderIds.current.has(id));
      pendingRideIds.current = new Set(nextRideIds);
      pendingOrderIds.current = nextOrderIds;
      hasSeededWork = true;
      if (notifyNew && hasExistingSeed && (hasNewRide || hasNewOrder)) alertNewOffer();
      syncSound();
    };

    const subscribe = () => {
      if (disposed || !courierRef.current?.id) return;
      const courierId = courierRef.current.id;
      const channelName = `courier-order-alarm-${userId}-${Math.random().toString(36).slice(2)}`;
      let courierChannel = supabase.channel(channelName);
      if (rideOfferTableAvailable !== false) {
        courierChannel = courierChannel
          .on('postgres_changes', {
          event: 'INSERT', schema: 'public', table: 'ride_request_offers', filter: `courier_id=eq.${courierId}`,
          }, (payload) => {
            const offer = payload.new as RideOfferPayload;
            updatePending('ride', offer.ride_id, offer.status === 'PENDING');
          })
          .on('postgres_changes', {
            event: 'UPDATE', schema: 'public', table: 'ride_request_offers', filter: `courier_id=eq.${courierId}`,
          }, (payload) => {
            const offer = payload.new as RideOfferPayload;
            updatePending('ride', offer.ride_id, offer.status === 'PENDING');
          });
      }
      channel = courierChannel
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'ride_requests',
        }, (payload) => {
          const ride = payload.new as { id: string; status?: string };
          if (ride.status !== 'SEARCHING') updatePending('ride', ride.id, false);
        })
        .on('postgres_changes', {
          event: 'INSERT', schema: 'public', table: 'delivery_assignments', filter: `courier_id=eq.${courierId}`,
        }, (payload) => {
          const offer = payload.new as DeliveryOfferPayload;
          updatePending('order', offer.order_id, offer.status === 'OFFERED');
        })
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'delivery_assignments', filter: `courier_id=eq.${courierId}`,
        }, (payload) => {
          const offer = payload.new as DeliveryOfferPayload;
          updatePending('order', offer.order_id, offer.status === 'OFFERED');
        })
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'orders', filter: `courier_id=eq.${courierId}`,
        }, (payload) => {
          const order = payload.new as { id: string; status?: string };
          updatePending('order', order.id, order.status === 'ASSIGNED');
        })
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'couriers', filter: `user_id=eq.${userId}`,
        }, async (payload) => {
          courierRef.current = payload.new as CourierState;
          if (isOnline()) await seedCurrentWork();
          else {
            pendingRideIds.current.clear();
            pendingOrderIds.current.clear();
            stopOrderNotificationSound('courier');
          }
        });

      channel.subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          void seedCurrentWork();
          return;
        }
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
      await seedCurrentWork(false);
      if (disposed) return;
      subscribe();
      // Polling this small courier-scoped inbox keeps incoming ojek offers reliable
      // when Realtime is unavailable without broadening visibility to all rides.
      refreshTimer = window.setInterval(() => { void seedCurrentWork(); }, 8000);
    };
    void start();

    const unlockOnInteraction = () => unlockOrderNotificationAudio();
    document.addEventListener('pointerdown', unlockOnInteraction, { passive: true });
    document.addEventListener('keydown', unlockOnInteraction);

    return () => {
      disposed = true;
      if (retryTimer) window.clearTimeout(retryTimer);
      if (refreshTimer) window.clearInterval(refreshTimer);
      document.removeEventListener('pointerdown', unlockOnInteraction);
      document.removeEventListener('keydown', unlockOnInteraction);
      if (channel) void supabase.removeChannel(channel);
      stopOrderNotificationSound('courier');
      courierRef.current = null;
      pendingRideIds.current.clear();
      pendingOrderIds.current.clear();
    };
  }, [userId]);
}
