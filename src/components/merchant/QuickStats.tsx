import { useCallback, useEffect, useRef, useState } from 'react';
import { Package, Clock, CheckCircle, XCircle, TrendingUp, Wallet } from 'lucide-react';
import { motion, useInView, useSpring, useMotionValue } from 'framer-motion';
import { Card, CardContent } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice } from '@/lib/utils';
import { MerchantCardError } from '@/components/merchant/MerchantDataState';

function AnimatedCounter({ value }: { value: number }) {
  const ref = useRef<HTMLSpanElement>(null);
  const isInView = useInView(ref, { once: true });
  const motionVal = useMotionValue(0);
  const spring = useSpring(motionVal, { duration: 800, bounce: 0 });

  useEffect(() => {
    if (isInView) motionVal.set(value);
  }, [isInView, value, motionVal]);

  useEffect(() => {
    const unsubscribe = spring.on('change', (v) => {
      if (ref.current) ref.current.textContent = Math.round(v).toString();
    });
    return unsubscribe;
  }, [spring]);

  return <span ref={ref}>0</span>;
}

interface QuickStatsProps {
  merchantId: string;
}

interface Stats {
  todayOrders: number;
  pendingOrders: number;
  processingOrders: number;
  completedToday: number;
  canceledToday: number;
  todayRevenue: number;
  pendingBalance: number;
  availableBalance: number;
}

export function QuickStats({ merchantId }: QuickStatsProps) {
  const [stats, setStats] = useState<Stats>({
    todayOrders: 0,
    pendingOrders: 0,
    processingOrders: 0,
    completedToday: 0,
    canceledToday: 0,
    todayRevenue: 0,
    pendingBalance: 0,
    availableBalance: 0,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchStats = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const todayISO = today.toISOString();

      const [todayOrdersRes, pendingOrdersRes, processingOrdersRes, completedTodayRes, canceledTodayRes, merchantRes] = await Promise.all([
        supabase.from('orders').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).gte('created_at', todayISO),
        supabase.from('orders').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).in('status', ['NEW', 'PENDING_CONFIRMATION']),
        supabase.from('orders').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).eq('status', 'PROCESSED'),
        supabase.from('orders').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).eq('status', 'DONE').gte('created_at', todayISO),
        supabase.from('orders').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).eq('status', 'CANCELED').gte('created_at', todayISO),
        supabase
          .from('merchants')
          .select('available_balance, pending_balance')
          .eq('id', merchantId)
          .maybeSingle(),
      ]);
      const queryErrors = [todayOrdersRes.error, pendingOrdersRes.error, processingOrdersRes.error, completedTodayRes.error, canceledTodayRes.error, merchantRes.error];
      const queryError = queryErrors.find(Boolean);
      if (queryError) throw queryError;

      // Sum every completed order from today in bounded pages; never silently
      // treat the API's default row cap as the whole day's revenue.
      const PAGE_SIZE = 1000;
      let offset = 0;
      let todayRevenue = 0;
      while (true) {
        const { data, error: revenueError } = await supabase
          .from('orders')
          .select('id, subtotal, total')
          .eq('merchant_id', merchantId)
          .eq('status', 'DONE')
          .gte('created_at', todayISO)
          .order('created_at', { ascending: true })
          .order('id', { ascending: true })
          .range(offset, offset + PAGE_SIZE - 1);
        if (revenueError) throw revenueError;
        todayRevenue += (data || []).reduce((sum, order) => sum + (order.subtotal || order.total || 0), 0);
        if ((data || []).length < PAGE_SIZE) break;
        offset += PAGE_SIZE;
      }
      
      setStats({
        todayOrders: todayOrdersRes.count || 0,
        pendingOrders: pendingOrdersRes.count || 0,
        processingOrders: processingOrdersRes.count || 0,
        completedToday: completedTodayRes.count || 0,
        canceledToday: canceledTodayRes.count || 0,
        todayRevenue,
        pendingBalance: merchantRes.data?.pending_balance || 0,
        availableBalance: merchantRes.data?.available_balance || 0,
      });
    } catch (error) {
      console.error('Error fetching stats:', error);
      setError(error instanceof Error ? error : new Error('Statistik toko gagal dimuat.'));
    } finally {
      setLoading(false);
    }
  }, [merchantId]);

  useEffect(() => {
    void fetchStats();
    const channel = supabase
      .channel(`merchant-quick-stats-${merchantId}-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: `merchant_id=eq.${merchantId}` }, () => void fetchStats())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'merchants', filter: `id=eq.${merchantId}` }, () => void fetchStats())
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [fetchStats, merchantId]);

  const statItems = [
    { 
      label: 'Pesanan Hari Ini', 
      value: stats.todayOrders, 
      icon: Package,
      color: 'text-primary',
      bgColor: 'bg-primary/10'
    },
    { 
      label: 'Menunggu Proses', 
      value: stats.pendingOrders, 
      icon: Clock,
      color: 'text-warning',
      bgColor: 'bg-warning/10'
    },
    { 
      label: 'Sedang Diproses', 
      value: stats.processingOrders, 
      icon: TrendingUp,
      color: 'text-info',
      bgColor: 'bg-info/10'
    },
    { 
      label: 'Selesai Hari Ini', 
      value: stats.completedToday, 
      icon: CheckCircle,
      color: 'text-success',
      bgColor: 'bg-success/10'
    },
    { 
      label: 'Batal Hari Ini', 
      value: stats.canceledToday, 
      icon: XCircle,
      color: 'text-destructive',
      bgColor: 'bg-destructive/10'
    },
    { 
      label: 'Pendapatan Hari Ini', 
      value: formatPrice(stats.todayRevenue), 
      icon: Wallet,
      color: 'text-success',
      bgColor: 'bg-success/10',
      isPrice: true
    },
  ];

  if (loading) {
    return (
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        {[1, 2, 3, 4, 5, 6].map(i => (
          <Card key={i}>
            <CardContent className="p-4">
              <div className="animate-pulse space-y-2">
                <div className="h-8 w-8 bg-muted rounded" />
                <div className="h-6 bg-muted rounded w-12" />
                <div className="h-4 bg-muted rounded w-20" />
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    );
  }

  if (error) {
    return <MerchantCardError message={error.message || 'Statistik toko gagal dimuat.'} onRetry={() => void fetchStats()} />;
  }

  return (
    <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
      {statItems.map((item) => (
        <Card key={item.label}>
          <CardContent className="p-4">
            <div className={`w-10 h-10 rounded-lg ${item.bgColor} flex items-center justify-center mb-2`}>
              <item.icon className={`h-5 w-5 ${item.color}`} />
            </div>
            <p className="text-2xl font-bold">
              {item.isPrice ? item.value : <AnimatedCounter value={item.value as number} />}
            </p>
            <p className="text-xs text-muted-foreground">{item.label}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
