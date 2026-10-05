import { useEffect, useRef } from 'react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { playOrderNotificationSound, stopOrderNotificationSound } from '@/lib/orderNotificationSound';

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
    let hasSeededPendingOrders = false;

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

    const seedPendingOrders = async (announceNewOrders = false) => {
      if (!isMerchantActive()) {
        pendingOrderIds.current.clear();
        stopOrderNotificationSound('merchant');
        return;
      }
      const merchantId = merchantRef.current!.id;
      const { data, error } = await supabase
        .from('orders')
        .select('id, status, delivery_name')
        .eq('merchant_id', merchantId)
        .in('status', PENDING_STATUSES)
        .limit(100);
      if (error || disposed) {
        if (error) console.warn('[merchant-order-alarm] pending order refresh failed', error.message);
        return;
      }

      const pendingOrders = (data || []) as OrderAlarmPayload[];
      if (announceNewOrders && hasSeededPendingOrders) {
        pendingOrders.forEach((order) => {
          if (!pendingOrderIds.current.has(order.id)) handleOrderChange(order);
        });
      }

      pendingOrderIds.current = new Set(pendingOrders.map((order) => order.id));
      hasSeededPendingOrders = true;
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

    const reconcilePendingOrders = async (announceNewOrders: boolean) => {
      await loadMerchant();
      if (!disposed) await seedPendingOrders(announceNewOrders);
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
          if (isMerchantActive()) await seedPendingOrders(true);
          else {
            pendingOrderIds.current.clear();
            stopOrderNotificationSound('merchant');
          }
        });

      channel.subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          if (retryTimer !== undefined) window.clearTimeout(retryTimer);
          retryTimer = undefined;
          void reconcilePendingOrders(true);
          return;
        }
        if (!disposed && retryTimer === undefined
          && (status === 'CLOSED' || status === 'CHANNEL_ERROR' || status === 'TIMED_OUT')) {
          retryTimer = window.setTimeout(() => {
            retryTimer = undefined;
            if (channel) void supabase.removeChannel(channel);
            channel = null;
            subscribe();
          }, 2000);
        }
      });
    };

    const reconcileWhenResumed = () => {
      if (!disposed && navigator.onLine) void reconcilePendingOrders(true);
    };
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') reconcileWhenResumed();
    };

    window.addEventListener('online', reconcileWhenResumed);
    document.addEventListener('visibilitychange', handleVisibilityChange);

    const start = async () => {
      await loadMerchant();
      await seedPendingOrders();
      if (!disposed) subscribe();
    };
    void start();

    return () => {
      disposed = true;
      window.removeEventListener('online', reconcileWhenResumed);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      if (retryTimer) window.clearTimeout(retryTimer);
      if (channel) void supabase.removeChannel(channel);
      stopOrderNotificationSound('merchant');
      merchantRef.current = null;
      pendingOrderIds.current.clear();
    };
  }, [userId]);
}
