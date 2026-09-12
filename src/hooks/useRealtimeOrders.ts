import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export interface OrderRow {
  id: string;
  buyer_id?: string | null;

  status: string;
  payment_status: string | null;
  payment_method: string | null;
  delivery_type: string;
  delivery_name: string | null;
  delivery_phone: string | null;
  delivery_address: string | null;
  delivery_lat?: number | null;
  delivery_lng?: number | null;
  subtotal: number;
  shipping_cost: number;
  total: number;
  cod_service_fee?: number | null;
  notes: string | null;
  created_at: string;
  courier_id: string | null;
  merchants?: { name: string; location_lat?: number | null; location_lng?: number | null } | null;
  is_self_delivery?: boolean;
  payment_proof_url?: string | null;
  expedition_name?: string | null;
  tracking_number?: string | null;
}

interface UseRealtimeOrdersOptions {
  merchantId: string | null;
  onNewOrder?: (order: OrderRow) => void;
  onOrderUpdate?: (order: OrderRow) => void;
}

const ORDER_PAGE_SIZE = 50;

export function useRealtimeOrders({ 
  merchantId, 
  onNewOrder,
  onOrderUpdate 
}: UseRealtimeOrdersOptions) {
  const [orders, setOrders] = useState<OrderRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  
  const onNewOrderRef = useRef(onNewOrder);
  const onOrderUpdateRef = useRef(onOrderUpdate);
  
  useEffect(() => { onNewOrderRef.current = onNewOrder; }, [onNewOrder]);
  useEffect(() => { onOrderUpdateRef.current = onOrderUpdate; }, [onOrderUpdate]);

  const fetchOrders = useCallback(async () => {
    if (!merchantId) {
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('orders')
        .select('*, merchants(name, location_lat, location_lng)')
        .eq('merchant_id', merchantId)
        .order('created_at', { ascending: false })
        .limit(ORDER_PAGE_SIZE);

      if (error) throw error;
      setOrders(data || []);
      setHasMore((data || []).length === ORDER_PAGE_SIZE);
    } catch (error) {
      console.error('Error fetching orders:', error);
      toast.error('Gagal memuat pesanan');
    } finally {
      setLoading(false);
    }
  }, [merchantId]);

  useEffect(() => {
    fetchOrders();
  }, [fetchOrders]);

  const loadMore = useCallback(async () => {
    if (!merchantId || loadingMore || !hasMore || orders.length === 0) return;
    const cursor = orders[orders.length - 1];
    try {
      setLoadingMore(true);
      const { data, error } = await supabase
        .from('orders')
        .select('*, merchants(name, location_lat, location_lng)')
        .eq('merchant_id', merchantId)
        .lt('created_at', cursor.created_at)
        .order('created_at', { ascending: false })
        .limit(ORDER_PAGE_SIZE);
      if (error) throw error;
      setOrders((previous) => {
        const known = new Set(previous.map((order) => order.id));
        return [...previous, ...(data || []).filter((order) => !known.has(order.id))];
      });
      setHasMore((data || []).length === ORDER_PAGE_SIZE);
    } catch (error) {
      console.error('Error loading older orders:', error);
      toast.error('Gagal memuat pesanan lama');
    } finally {
      setLoadingMore(false);
    }
  }, [merchantId, loadingMore, hasMore, orders]);

  // Real-time subscription
  useEffect(() => {
    if (!merchantId) return;

    const channel = supabase
      .channel(`merchant-orders-${merchantId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'orders',
          filter: `merchant_id=eq.${merchantId}`,
        },
        (payload) => {
          const newOrder = payload.new as OrderRow;
          setOrders((prev) => [newOrder, ...prev]);
          
          // Play notification sound for new orders
          playNotificationSound();
          
          toast.info('Pesanan baru masuk!', {
            description: `Pesanan dari ${newOrder.delivery_name || 'Pelanggan'}`,
            action: {
              label: 'Lihat',
              onClick: () => onNewOrderRef.current?.(newOrder),
            },
          });
          
          onNewOrderRef.current?.(newOrder);
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'orders',
          filter: `merchant_id=eq.${merchantId}`,
        },
        (payload) => {
          const updatedOrder = payload.new as OrderRow;
          setOrders((prev) =>
            prev.map((order) =>
              order.id === updatedOrder.id ? { ...order, ...updatedOrder } : order
            )
          );
          
          onOrderUpdateRef.current?.(updatedOrder);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [merchantId]);

  const updateOrderStatus = async (orderId: string, newStatus: string, reason?: string) => {
    const currentOrder = orders.find(order => order.id === orderId);
    if (currentOrder?.status === newStatus) {
      return true;
    }
    try {
      const { error } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: orderId,
        p_to_status: newStatus,
        p_reason: reason ?? null,
      } as never);

      if (error) throw error;
      
      // Reconcile from the server so timestamps, payment fields, courier fields,
      // and trigger-generated values cannot remain stale in the merchant UI.
      await fetchOrders();

      // Kirim push notification ke pembeli secara background (fire-and-forget)
      const order = orders.find((o) => o.id === orderId);
      if (order?.buyer_id) {
        supabase.functions
          .invoke('send-push-notification', {
            body: {
              user_id: order.buyer_id,
              title: 'Status Pesanan Diperbarui',
              body: `Pesanan #${orderId.slice(0, 8)} sekarang: ${newStatus}`,
              url: `/orders?orderId=${orderId}`,
            },
          })
          .catch(() => { /* push gagal tidak memblokir UX */ });
      }

      
      toast.success('Status pesanan diperbarui');
      return true;
    } catch (error) {
      toast.error('Gagal mengubah status');
      return false;
    }
  };

  return {
    orders,
    loading,
    updateOrderStatus,
    refetch: fetchOrders,
    loadMore,
    loadingMore,
    hasMore,
  };
}

// Simple notification sound
function playNotificationSound() {
  try {
    const audioContext = new (window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext)();
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();
    
    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);
    
    oscillator.frequency.value = 800;
    oscillator.type = 'sine';
    gainNode.gain.value = 0.1;
    
    oscillator.start(audioContext.currentTime);
    oscillator.stop(audioContext.currentTime + 0.2);
    
    // Second beep
    setTimeout(() => {
      const osc2 = audioContext.createOscillator();
      osc2.connect(gainNode);
      osc2.frequency.value = 1000;
      osc2.type = 'sine';
      osc2.start(audioContext.currentTime);
      osc2.stop(audioContext.currentTime + 0.2);
    }, 250);
  } catch (e) {
    // Audio not supported or blocked
  }
}
