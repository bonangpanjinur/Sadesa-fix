/**
 * Hook untuk notifikasi pesanan QR secara realtime di POS.
 * Subscrib ke channel SSE `pos_qr_orders:{tenantId}` dan mengumpulkan
 * pesanan masuk + membunyikan notifikasi audio.
 */
import { useEffect, useRef, useCallback, useState } from "react";
import { posBridgeFetch } from '@/lib/posBridge';
import { playOrderNotificationSound } from '@/lib/orderNotificationSound';

interface SSEBroadcastDetail {
  type?: string;
  channel?: string;
  event?: string;
  payload?: unknown;
}

export interface QRIncomingOrder {
  order_id: string;
  order_number: string;
  table_id: string;
  table_name: string;
  customer_name: string;
  items: Array<{
    product_name: string;
    qty: number;
    price: number;
    subtotal: number;
    notes?: string | null;
  }>;
  subtotal: number;
  notes: string | null;
  created_at: string;
  read: boolean;
}

async function subscribeToQRChannel(tenantId: string) {
  try {
    const token = localStorage.getItem("session_token");
    if (!token) return;
    await posBridgeFetch("/api/sse/subscribe", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ channel: `pos_qr_orders:${tenantId}` }),
    });
  } catch (err) {
    console.warn('[useQROrderNotifications] gagal berlangganan channel QR order', err);
  }
}

export function useQROrderNotifications(tenantId: string | null | undefined) {
  const [orders, setOrders] = useState<QRIncomingOrder[]>([]);
  const channelName = tenantId ? `pos_qr_orders:${tenantId}` : null;
  const subscribedRef = useRef(false);

  // Subscribe ke server channel saat tenantId tersedia
  useEffect(() => {
    if (!tenantId || subscribedRef.current) return;
    subscribedRef.current = true;
    subscribeToQRChannel(tenantId);
    // Resubscribe setelah SSE reconnect
    const onConnected = (e: Event) => {
      const detail = (e as CustomEvent).detail;
      if (detail?.type === "connected") {
        subscribeToQRChannel(tenantId);
      }
    };
    window.addEventListener("sse_broadcast", onConnected as EventListener);
    return () => {
      window.removeEventListener("sse_broadcast", onConnected as EventListener);
      subscribedRef.current = false;
    };
  }, [tenantId]);

  // Dengarkan broadcast event `new_order` dari channel ini
  useEffect(() => {
    if (!channelName) return;

    const handler = (e: Event) => {
      const detail = (e as CustomEvent<SSEBroadcastDetail>).detail;
      if (
        detail?.type === "broadcast" &&
        detail?.channel === channelName &&
        detail?.event === "new_order" &&
        detail?.payload
      ) {
        const p = detail.payload as Omit<QRIncomingOrder, "read">;
        setOrders((prev) => [{ ...p, read: false }, ...prev]);
        void playOrderNotificationSound('merchant');
      }
    };

    window.addEventListener("sse_broadcast", handler as EventListener);
    return () => window.removeEventListener("sse_broadcast", handler as EventListener);
  }, [channelName]);

  const unreadCount = orders.filter((o) => !o.read).length;

  const markAllRead = useCallback(() => {
    setOrders((prev) => prev.map((o) => ({ ...o, read: true })));
  }, []);

  const markRead = useCallback((orderId: string) => {
    setOrders((prev) =>
      prev.map((o) => (o.order_id === orderId ? { ...o, read: true } : o))
    );
  }, []);

  const dismissOrder = useCallback((orderId: string) => {
    setOrders((prev) => prev.filter((o) => o.order_id !== orderId));
  }, []);

  const clearAll = useCallback(() => setOrders([]), []);

  return { orders, unreadCount, markAllRead, markRead, dismissOrder, clearAll };
}
