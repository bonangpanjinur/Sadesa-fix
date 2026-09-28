import { useEffect, useRef } from 'react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { playOrderNotificationSound, unlockOrderNotificationAudio } from '@/lib/orderNotificationSound';

interface MerchantState {
  id: string;
  status: string | null;
}

const PENDING_STATUSES = ['NEW', 'PENDING_CONFIRMATION'];

/** Keeps new-order sound and toast active on every merchant route. */
export function useMerchantOrderAlarm(userId: string | null | undefined) {
  const merchantRef = useRef<MerchantState | null>(null);
  const knownOrderIds = useRef<Set<string> | null>(null);

  useEffect(() => {
    if (!userId) return;

    let disposed = false;
    let retryTimer: number | undefined;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    const isMerchantActive = () => {
      const merchant = merchantRef.current;
      return Boolean(merchant?.id) && merchant.status === 'ACTIVE';
    };

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
      const merchantId = merchantRef.current?.id;
      if (!merchantId) return;
      const { data } = await supabase
        .from('orders')
        .select('id')
        .eq('merchant_id', merchantId)
        .in('status', PENDING_STATUSES)
        .limit(100);
      knownOrderIds.current = new Set((data || []).map((row: { id: string }) => row.id));
    };

    const notifyIfNew = (payload: { id: string; status?: string; delivery_name?: string | null }) => {
      if (!isMerchantActive() || !PENDING_STATUSES.includes(payload.status || '')) return;
      if (!knownOrderIds.current) {
        knownOrderIds.current = new Set([payload.id]);
        return;
      }
      if (knownOrderIds.current.has(payload.id)) return;
      knownOrderIds.current.add(payload.id);
      void playOrderNotificationSound('merchant');
      toast.info('Pesanan baru masuk!', {
        description: `Pesanan dari ${payload.delivery_name || 'Pelanggan'}`,
        action: {
          label: 'Lihat',
          onClick: () => { window.location.assign(`/merchant/orders?orderId=${payload.id}`); },
        },
      });
    };

    const subscribe = () => {
      if (disposed || !merchantRef.current?.id) return;
      const merchantId = merchantRef.current.id;
      const channelName = `merchant-order-alarm-${userId}-${Math.random().toString(36).slice(2)}`;
      channel = supabase
        .channel(channelName)
        .on('postgres_changes', {
          event: 'INSERT', schema: 'public', table: 'orders', filter: `merchant_id=eq.${merchantId}`,
        }, (payload) => notifyIfNew(payload.new as { id: string; status?: string; delivery_name?: string | null }))
        .on('postgres_changes', {
          event: 'UPDATE', schema: 'public', table: 'merchants', filter: `user_id=eq.${userId}`,
        }, async (payload) => {
          merchantRef.current = payload.new as MerchantState;
          if (isMerchantActive()) await seedPendingOrders();
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
      await loadMerchant();
      await seedPendingOrders();
      if (!disposed) subscribe();
    };
    void start();

    // Any click/keypress can unlock Web Audio before a later realtime event.
    const unlockOnInteraction = () => unlockOrderNotificationAudio();
    document.addEventListener('pointerdown', unlockOnInteraction, { passive: true });
    document.addEventListener('keydown', unlockOnInteraction);

    return () => {
      disposed = true;
      if (retryTimer) window.clearTimeout(retryTimer);
      document.removeEventListener('pointerdown', unlockOnInteraction);
      document.removeEventListener('keydown', unlockOnInteraction);
      if (channel) void supabase.removeChannel(channel);
      merchantRef.current = null;
      knownOrderIds.current = null;
    };
  }, [userId]);
}
