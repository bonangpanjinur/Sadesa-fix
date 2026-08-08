/**
 * Hook untuk Admin Realtime Dashboard.
 * Mengambil agregat pesanan langsung dari database (24 jam terakhir),
 * memakai channel realtime `orders` untuk refresh instan, plus polling
 * ringan sebagai jaring pengaman. Alert otomatis jika ada spike transaksi.
 */
import { useState, useEffect, useCallback, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";

export interface AdminSnapshot {
  todayOrders: number;
  todayRevenue: number;
  thisHourOrders: number;
  prevHourOrders: number;
  spikeRatio: number;
  isSpike: boolean;
  activeUsers: number;
  recentOrders: Array<{
    id: string;
    total: number;
    status: string;
    created_at: string;
  }>;
  ts: string;
}

export interface HourlyPoint {
  hour: string;
  label: string;
  orders: number;
  revenue: number;
  completed: number;
  cancelled: number;
}

export interface MinutelyPoint {
  minute: string;
  label: string;
  orders: number;
  revenue: number;
}

export interface SpikeAlert {
  id: number;
  message: string;
  ratio: number;
  detectedAt: Date;
  dismissed: boolean;
}

interface OrderRow {
  id: string;
  total: number | null;
  status: string;
  created_at: string;
  buyer_id: string | null;
}

const SPIKE_THRESHOLD = 2;
const CANCELLED_STATUSES = ["CANCELED", "CANCELLED", "REJECTED", "REJECTED_BY_BUYER"];

function pad(n: number) {
  return String(n).padStart(2, "0");
}

function buildHourly(rows: OrderRow[]): HourlyPoint[] {
  const points: HourlyPoint[] = [];
  const now = new Date();
  for (let i = 23; i >= 0; i--) {
    const d = new Date(now.getTime() - i * 60 * 60 * 1000);
    d.setMinutes(0, 0, 0);
    const key = d.toISOString().slice(0, 13);
    const bucket = rows.filter((r) => r.created_at.slice(0, 13) === key);
    points.push({
      hour: d.toISOString(),
      label: `${pad(d.getHours())}:00`,
      orders: bucket.length,
      revenue: bucket.reduce((s, r) => s + Number(r.total || 0), 0),
      completed: bucket.filter((r) => r.status === "DONE").length,
      cancelled: bucket.filter((r) => CANCELLED_STATUSES.includes(r.status)).length,
    });
  }
  return points;
}

function buildMinutely(rows: OrderRow[]): MinutelyPoint[] {
  const points: MinutelyPoint[] = [];
  const now = new Date();
  for (let i = 59; i >= 0; i--) {
    const d = new Date(now.getTime() - i * 60 * 1000);
    d.setSeconds(0, 0);
    const key = d.toISOString().slice(0, 16);
    const bucket = rows.filter((r) => r.created_at.slice(0, 16) === key);
    points.push({
      minute: d.toISOString(),
      label: `${pad(d.getHours())}:${pad(d.getMinutes())}`,
      orders: bucket.length,
      revenue: bucket.reduce((s, r) => s + Number(r.total || 0), 0),
    });
  }
  return points;
}

function buildSnapshot(rows: OrderRow[]): AdminSnapshot {
  const now = Date.now();
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);

  const todayRows = rows.filter((r) => new Date(r.created_at) >= startOfToday);
  const thisHour = rows.filter((r) => now - new Date(r.created_at).getTime() <= 3600_000);
  const prevHour = rows.filter((r) => {
    const age = now - new Date(r.created_at).getTime();
    return age > 3600_000 && age <= 7200_000;
  });

  const spikeRatio = prevHour.length > 0 ? thisHour.length / prevHour.length : 0;
  const activeBuyers = new Set(
    rows
      .filter((r) => now - new Date(r.created_at).getTime() <= 15 * 60 * 1000)
      .map((r) => r.buyer_id)
      .filter(Boolean),
  );

  return {
    todayOrders: todayRows.length,
    todayRevenue: todayRows.reduce((s, r) => s + Number(r.total || 0), 0),
    thisHourOrders: thisHour.length,
    prevHourOrders: prevHour.length,
    spikeRatio,
    isSpike: prevHour.length >= 3 && spikeRatio >= SPIKE_THRESHOLD,
    activeUsers: activeBuyers.size,
    recentOrders: rows.slice(0, 10).map((r) => ({
      id: r.id,
      total: Number(r.total || 0),
      status: r.status,
      created_at: r.created_at,
    })),
    ts: new Date().toISOString(),
  };
}

export function useAdminRealtime() {
  const [snapshot, setSnapshot] = useState<AdminSnapshot | null>(null);
  const [hourly, setHourly] = useState<HourlyPoint[]>([]);
  const [minutely, setMinutely] = useState<MinutelyPoint[]>([]);
  const [alerts, setAlerts] = useState<SpikeAlert[]>([]);
  const [isConnected, setIsConnected] = useState(false);
  const [loading, setLoading] = useState(true);
  const alertIdRef = useRef(0);

  const dismissAlert = useCallback((id: number) => {
    setAlerts((prev) => prev.map((a) => (a.id === id ? { ...a, dismissed: true } : a)));
  }, []);

  const refresh = useCallback(async () => {
    const since = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
    const { data, error } = await supabase
      .from("orders")
      .select("id, total, status, created_at, buyer_id")
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(5000);

    if (error) {
      console.warn("[admin-realtime] gagal memuat agregat pesanan:", error.message);
      setLoading(false);
      return;
    }

    const rows = (data || []) as OrderRow[];
    const snap = buildSnapshot(rows);
    setSnapshot(snap);
    setHourly(buildHourly(rows));
    setMinutely(buildMinutely(rows));
    setLoading(false);

    if (snap.isSpike) {
      setAlerts((prev) => {
        const recent = prev.find(
          (a) => !a.dismissed && Date.now() - a.detectedAt.getTime() < 5 * 60 * 1000,
        );
        if (recent) return prev;
        alertIdRef.current += 1;
        return [
          {
            id: alertIdRef.current,
            message: `Lonjakan transaksi terdeteksi! ${snap.thisHourOrders} pesanan/jam (${Math.round(snap.spikeRatio * 100)}% dari jam sebelumnya)`,
            ratio: snap.spikeRatio,
            detectedAt: new Date(),
            dismissed: false,
          },
          ...prev,
        ].slice(0, 10);
      });
    }
  }, []);

  useEffect(() => {
    refresh();

    const channel = supabase
      .channel(`admin-realtime-orders-${Math.random().toString(36).slice(2)}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "orders" }, () => {
        refresh();
      })
      .subscribe((status) => {
        setIsConnected(status === "SUBSCRIBED");
      });

    const interval = setInterval(refresh, 60 * 1000);

    return () => {
      clearInterval(interval);
      supabase.removeChannel(channel);
      setIsConnected(false);
    };
  }, [refresh]);

  return {
    snapshot,
    hourly,
    minutely,
    alerts,
    isConnected,
    loading,
    dismissAlert,
    refresh,
  };
}
