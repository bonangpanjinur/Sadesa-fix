import { useEffect, useRef } from 'react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { playOrderNotificationSound, stopOrderNotificationSound, unlockOrderNotificationAudio } from '@/lib/orderNotificationSound';

interface MerchantState {
  id: string;
  status: string | null;
}

interface OrderAlarmPayload {
  id: string;
  status?: string;
  delivery_name?: string | null;
}

const PENDING_STATUSES = ['NEW', 'PENDING_CONFIRMATION'];

/** Plays a short alert on any merchant route when an order starts waiting. */
export function useMerchantOrderAlarm(userId: string | null | undefined) {
  const merchantRef = useRef<MerchantState | null>(null);
  const pendingOrderIds = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!userId) return;

    let disposed = false;
    let retryTimer: number | undefined;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    const isMerchantActive = () => Boolean(merchantRef.current?.id) && merchantRef.current?.status === 'ACTIVE';

    const loadMerchant = async () => {
      const { data, error } = await supabase
        .from('merchants')
        .select('id, status')
        .eq('user_id', userId)
        .maybeSingle();
      if (error || !data) {
        merchantRef.current = null;
        return;
      }
      merchantRef.current = data as MerchantState;
    };

    const seedPendingOrders = async () => {
      if (!isMerchantActive()) {
        pendingOrderIds.current.clear();
        stopOrderNotificationSound('merchant');
        return;
      }
      const merchantId = merchantRef.current!.id;
      const { data, error } = await supabase
        .from('orders')
        .select('id')
        .eq('merchant_id', merchantId)
        .in('status', PENDING_STATUSES)
        .limit(100);
      if (error || disposed) return;
      pendingOrderIds.current = new Set((data || []).map((row: { id: string }) => row.id));
      if (pendingOrderIds.current.size === 0) stopOrderNotificationSound('merchant');
    };

    const handleOrderChange = (order: OrderAlarmPayload) => {
      if (!isMerchantActive()) return;
      const isPending = PENDING_STATUSES.includes(order.status || '');
      const wasPending = pendingOrderIds.current.has(order.id);

      if (isPending) {
        pendingOrderIds.current.add(order.id);
        if (!wasPending) {
          void playOrderNotificationSound('merchant');
          toast.info('Pesanan baru masuk!', {
            description: `Pesanan dari ${order.delivery_name || 'Pelanggan'}`,
            action: {
              label: 'Lihat',
              onClick: () => { window.location.assign(`/merchant/orders?orderId=${order.id}`); },
            },
          });
        }
        return;
      }

      pendingOrderIds.current.delete(order.id);
      if (pendingOrderIds.current.size === 0) stopOrderNotificationSound('merchant');
    };

    const subscribe = () => {
      if (disposed || !merchantRef.current?.id) return;
      const merchantId = merchantRef.current.id;
      const channelName = `merchant-order-alarm-${userId}-${Math.random().toString(36).slice(2)}`;
      channel = supabase
        .channel(channelName)
        .on('postgres_changes', {
          event: 'INSERT', schema: 'public', table: 'orders', filter: `merchant_id=eq.${merchantId}`,
        }, (payload) => handleOrderChange(payload.new as OrderAlarmPayload))
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'orders', filter: `merchant_id=eq.${merchantId}`,
        }, (payload) => handleOrderChange(payload.new as OrderAlarmPayload))
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'merchants', filter: `user_id=eq.${userId}`,
        }, async (payload) => {
          merchantRef.current = payload.new as MerchantState;
          if (isMerchantActive()) await seedPendingOrders();
          else {
            pendingOrderIds.current.clear();
            stopOrderNotificationSound('merchant');
          }
        });

      channel.subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          void seedPendingOrders();
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
      await loadMerchant();
      await seedPendingOrders();
      if (!disposed) subscribe();
    };
    void start();

    // Any interaction unlocks Web Audio before a realtime event needs to alert.
    const unlockOnInteraction = () => unlockOrderNotificationAudio();
    document.addEventListener('pointerdown', unlockOnInteraction, { passive: true });
    document.addEventListener('keydown', unlockOnInteraction);

    return () => {
      disposed = true;
      if (retryTimer) window.clearTimeout(retryTimer);
      document.removeEventListener('pointerdown', unlockOnInteraction);
      document.removeEventListener('keydown', unlockOnInteraction);
      if (channel) void supabase.removeChannel(channel);
      stopOrderNotificationSound('merchant');
      merchantRef.current = null;
      pendingOrderIds.current.clear();
    };
  }, [userId]);
}
