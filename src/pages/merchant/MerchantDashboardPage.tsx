import { lazy, Suspense, useCallback, useMemo, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  AlertCircle,
  ArrowUpRight,
  BarChart3,
  Bell,
  CalendarDays,
  CheckCircle,
  CircleCheck,
  Eye,
  Layers,
  Package,
  Percent,
  Receipt,
  Settings,
  Sparkles,
  Star,
  Store,
  TrendingUp,
  Wallet,
  XCircle,
} from 'lucide-react';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { QuickStats } from '@/components/merchant/QuickStats';
import { StockAlerts } from '@/components/merchant/StockAlerts';
import { CustomerReviews } from '@/components/merchant/CustomerReviews';
import { OrderStatusManager } from '@/components/merchant/OrderStatusManager';
import { MerchantGroupCard } from '@/components/merchant/MerchantGroupCard';
import { MerchantKasCard } from '@/components/merchant/MerchantKasCard';
import { DailySummaryCard } from '@/components/merchant/DailySummaryCard';
import { StoreQRCode } from '@/components/merchant/StoreQRCode';
import { MerchantOperatingHoursCard } from '@/components/merchant/MerchantOperatingHoursCard';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { cn, formatPrice } from '@/lib/utils';
import { useRealtimeOrders, type OrderRow } from '@/hooks/useRealtimeOrders';
import { MerchantCardError } from '@/components/merchant/MerchantDataState';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

interface MerchantData {
  id: string;
  name: string;
  is_open: boolean;
  status: string;
  registration_status: string;
  rejection_reason: string | null;
  image_url: string | null;
  slug: string | null;
}

interface OrderData {
  id: string;
  status: string;
  total: number;
  subtotal?: number;
  created_at: string;
}

interface MerchantWalletOverview {
  wallet: { balance_rupiah: number; debt_rupiah: number; is_active: boolean } | null;
  feeEnabled: boolean;
  lowBalanceThreshold: number;
}

const SalesAreaChart = lazy(() =>
  import('@/components/admin/SalesChart').then((module) => ({ default: module.SalesAreaChart })),
);
const OrdersBarChart = lazy(() =>
  import('@/components/admin/SalesChart').then((module) => ({ default: module.OrdersBarChart })),
);

export default function MerchantDashboardPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [updatingStatus, setUpdatingStatus] = useState(false);
  const [activeTab, setActiveTab] = useState('overview');

  const {
    data: merchant = null,
    isLoading: merchantLoading,
    isError: merchantQueryError,
    error: merchantError,
    refetch: refetchMerchant,
  } = useQuery<MerchantData | null>({
    queryKey: ['merchant-profile', user?.id],
    queryFn: async () => {
      if (!user) return null;
      const { data, error } = await supabase
        .from('merchants')
        .select('id, name, is_open, status, registration_status, rejection_reason, image_url, slug')
        .eq('user_id', user.id)
        .maybeSingle();
      if (error) throw error;
      return data || null;
    },
    enabled: !!user,
    staleTime: 60_000,
  });

  const {
    data: walletOverview,
    isLoading: walletOverviewLoading,
    isError: walletOverviewError,
    refetch: refetchWalletOverview,
  } = useQuery<MerchantWalletOverview>({
    queryKey: ['merchant-wallet-dashboard', merchant?.id],
    queryFn: async () => {
      if (!merchant?.id) throw new Error('Profil merchant belum tersedia');
      const [walletResult, feeResult, policyResult] = await Promise.all([
        supabase.from('commission_wallets' as never).select('balance_rupiah,debt_rupiah,is_active')
          .eq('owner_type' as never, 'MERCHANT' as never).eq('merchant_id' as never, merchant.id as never).maybeSingle(),
        supabase.from('commission_fee_settings' as never).select('is_enabled')
          .eq('owner_type' as never, 'MERCHANT' as never).maybeSingle(),
        supabase.from('commission_wallet_policy_settings' as never).select('low_balance_threshold_rupiah')
          .eq('id' as never, true as never).maybeSingle(),
      ]);
      if (walletResult.error) throw walletResult.error;
      if (feeResult.error) throw feeResult.error;
      const wallet = walletResult.data as unknown as MerchantWalletOverview['wallet'];
      const fee = feeResult.data as unknown as { is_enabled: boolean } | null;
      const policy = policyResult.data as unknown as { low_balance_threshold_rupiah: number } | null;
      return {
        wallet,
        feeEnabled: Boolean(fee?.is_enabled),
        lowBalanceThreshold: Number(policy?.low_balance_threshold_rupiah ?? 10_000),
      };
    },
    enabled: !!merchant?.id,
    staleTime: 15_000,
    refetchInterval: 30_000,
  });

  const {
    data: orders = [],
    isError: ordersQueryError,
    error: ordersError,
    refetch: refetchOrders,
  } = useQuery<OrderData[]>({
    queryKey: ['merchant-orders-chart', merchant?.id],
    queryFn: async () => {
      if (!merchant?.id) return [];
      const startDate = new Date();
      startDate.setHours(0, 0, 0, 0);
      startDate.setDate(startDate.getDate() - 13);
      const { data, error } = await supabase
        .from('orders')
        .select('id, status, subtotal, total, created_at')
        .eq('merchant_id', merchant.id)
        .gte('created_at', startDate.toISOString())
        .order('created_at', { ascending: false })
        .limit(250);
      if (error) throw error;
      return data || [];
    },
    enabled: !!merchant?.id,
    staleTime: 60_000,
  });

  const {
    data: pendingOrdersSnapshot = { orders: [], count: 0 },
    isLoading: pendingOrdersLoading,
    isError: pendingOrdersError,
    error: pendingOrdersErrorDetails,
    refetch: refetchPendingOrders,
  } = useQuery({
    queryKey: ['merchant-pending-orders-summary', merchant?.id],
    queryFn: async () => {
      if (!merchant?.id) return { orders: [], count: 0 };
      const { data, count, error } = await supabase
        .from('orders')
        .select('id, delivery_name, total, created_at', { count: 'exact' })
        .eq('merchant_id', merchant.id)
        .in('status', ['NEW', 'PENDING_CONFIRMATION'])
        .order('created_at', { ascending: false })
        .limit(5);
      if (error) throw error;
      return { orders: data || [], count: count || 0 };
    },
    enabled: !!merchant?.id,
    staleTime: 30_000,
  });

  const loading = merchantLoading;

  const handleNewOrder = useCallback((_order: OrderRow) => {
    queryClient.invalidateQueries({ queryKey: ['merchant-orders-chart', merchant?.id] });
    queryClient.invalidateQueries({ queryKey: ['merchant-pending-orders-summary', merchant?.id] });
  }, [merchant?.id, queryClient]);

  const { updateOrderStatus } = useRealtimeOrders({
    merchantId: merchant?.id || null,
    onNewOrder: handleNewOrder,
    onOrderUpdate: handleNewOrder,
  });

  const pendingOrders = pendingOrdersSnapshot.orders;
  const pendingOrderCount = pendingOrdersSnapshot.count;

  const salesChartData = useMemo(() => {
    const dateMap = new Map<string, { revenue: number; orders: number }>();

    orders.forEach((order) => {
      const date = order.created_at.split('T')[0];
      const existing = dateMap.get(date) || { revenue: 0, orders: 0 };
      dateMap.set(date, {
        revenue: existing.revenue + (order.status === 'DONE' ? (order.subtotal || order.total) : 0),
        orders: existing.orders + 1,
      });
    });

    const result: { date: string; revenue: number; orders: number }[] = [];
    for (let i = 13; i >= 0; i -= 1) {
      const date = new Date(Date.now() - i * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
      result.push({ date, ...(dateMap.get(date) || { revenue: 0, orders: 0 }) });
    }
    return result;
  }, [orders]);

  const toggleStoreStatus = async (isOpen: boolean) => {
    if (!merchant) return;
    setUpdatingStatus(true);

    try {
      const { error } = await supabase
        .from('merchants')
        .update({ is_open: isOpen })
        .eq('id', merchant.id);

      if (error) throw error;

      queryClient.setQueryData(['merchant-profile', user?.id], { ...merchant, is_open: isOpen });
      toast.success(isOpen ? 'Toko sekarang buka' : 'Toko sekarang tutup');
    } catch (error) {
      toast.error('Gagal mengubah status toko');
    } finally {
      setUpdatingStatus(false);
    }
  };

  if (loading) {
    return (
      <MerchantLayout title="Dashboard" subtitle="Ringkasan toko Anda">
        <div className="space-y-6 pb-8" data-testid="merchant-dashboard-loading">
          <div className="space-y-3">
            <div className="h-3 w-32 animate-pulse rounded bg-muted" />
            <div className="h-9 w-72 animate-pulse rounded-lg bg-muted" />
            <div className="h-4 w-96 max-w-full animate-pulse rounded bg-muted" />
          </div>
          <div className="grid gap-4 lg:grid-cols-[1.4fr_0.6fr]">
            <div className="h-44 animate-pulse rounded-2xl bg-muted" />
            <div className="h-44 animate-pulse rounded-2xl bg-muted" />
          </div>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
            {Array.from({ length: 6 }).map((_, index) => (
              <div key={index} className="h-28 animate-pulse rounded-xl bg-muted" />
            ))}
          </div>
        </div>
      </MerchantLayout>
    );
  }

  if (merchantQueryError) {
    return (
      <MerchantLayout title="Dashboard" subtitle="Ringkasan toko Anda">
        <MerchantCardError
          message={merchantError instanceof Error ? merchantError.message : 'Profil merchant gagal dimuat.'}
          onRetry={() => void refetchMerchant()}
        />
      </MerchantLayout>
    );
  }

  if (!merchant) {
    return (
      <MerchantLayout title="Dashboard" subtitle="Ringkasan toko Anda">
        <div className="flex min-h-[calc(100dvh-12rem)] items-center justify-center py-12" data-testid="merchant-dashboard-missing">
          <div className="w-full max-w-lg rounded-2xl border border-border bg-card p-8 text-center shadow-sm">
            <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
              <Store className="h-7 w-7" />
            </div>
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">Mulai berjualan</p>
            <h2 className="text-2xl font-semibold tracking-tight">Toko belum terdaftar</h2>
            <p className="mx-auto mt-3 max-w-sm text-sm leading-6 text-muted-foreground">
              Daftarkan toko Anda untuk mengelola produk, pesanan, dan performa penjualan dari satu tempat.
            </p>
            <Button className="mt-6" onClick={() => navigate('/register/merchant')} data-testid="button-register-merchant">
              Daftar sebagai merchant
              <ArrowUpRight className="ml-2 h-4 w-4" />
            </Button>
          </div>
        </div>
      </MerchantLayout>
    );
  }

  if (merchant.registration_status === 'PENDING') {
    return (
      <MerchantLayout title="Dashboard" subtitle="Ringkasan toko Anda">
        <div className="flex min-h-[calc(100dvh-12rem)] items-center justify-center py-12" data-testid="merchant-dashboard-pending">
          <div className="w-full max-w-xl rounded-2xl border border-warning/30 bg-card p-8 text-center shadow-sm">
            <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-warning/10 text-warning">
              <AlertCircle className="h-7 w-7" />
            </div>
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-warning">Sedang ditinjau</p>
            <h2 className="text-2xl font-semibold tracking-tight">Menunggu persetujuan</h2>
            <p className="mx-auto mt-3 max-w-md text-sm leading-6 text-muted-foreground">
              Pendaftaran toko Anda sedang dalam proses review. Kami akan memberi tahu Anda setelah keputusan tersedia.
            </p>
            <div className="mx-auto mt-6 flex max-w-sm items-center gap-3 rounded-xl bg-warning/5 p-3 text-left">
              <CalendarDays className="h-4 w-4 shrink-0 text-warning" />
              <p className="text-xs leading-5 text-muted-foreground">Tidak perlu mengirim ulang data selama proses review berlangsung.</p>
            </div>
            <Button variant="outline" className="mt-6" onClick={() => navigate('/')} data-testid="button-pending-home">
              Kembali ke beranda
            </Button>
          </div>
        </div>
      </MerchantLayout>
    );
  }

  if (merchant.registration_status === 'REJECTED') {
    return (
      <MerchantLayout title="Dashboard" subtitle="Ringkasan toko Anda">
        <div className="flex min-h-[calc(100dvh-12rem)] items-center justify-center py-12" data-testid="merchant-dashboard-rejected">
          <div className="w-full max-w-xl rounded-2xl border border-destructive/30 bg-card p-8 text-center shadow-sm">
            <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-destructive/10 text-destructive">
              <AlertCircle className="h-7 w-7" />
            </div>
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-destructive">Perlu diperbaiki</p>
            <h2 className="text-2xl font-semibold tracking-tight">Pendaftaran ditolak</h2>
            <p className="mx-auto mt-3 max-w-md text-sm leading-6 text-muted-foreground">
              {merchant.rejection_reason || 'Pendaftaran toko Anda belum disetujui. Periksa kembali data toko dan kirim pendaftaran baru.'}
            </p>
            <div className="mt-6 flex flex-col justify-center gap-2 sm:flex-row">
              <Button variant="outline" onClick={() => navigate('/')} data-testid="button-rejected-home">
                Beranda
              </Button>
              <Button onClick={() => navigate('/register/merchant')} data-testid="button-reregister-merchant">
                Daftar ulang
                <ArrowUpRight className="ml-2 h-4 w-4" />
              </Button>
            </div>
          </div>
        </div>
      </MerchantLayout>
    );
  }

  const currentHour = new Date().getHours();
  const greeting = currentHour < 12 ? 'Selamat pagi' : currentHour < 17 ? 'Selamat siang' : 'Selamat malam';
  const todayLabel = new Intl.DateTimeFormat('id-ID', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  }).format(new Date());
  const dashboardWallet = walletOverview?.wallet;
  const walletBalance = Number(dashboardWallet?.balance_rupiah ?? 0);
  const walletDebt = Number(dashboardWallet?.debt_rupiah ?? 0);
  const walletThreshold = walletOverview?.lowBalanceThreshold ?? 10_000;
  const quickActions = [
    {
      label: 'Pesanan',
      description: pendingOrdersLoading ? 'Memeriksa pesanan…' : pendingOrderCount > 0 ? `${pendingOrderCount} menunggu konfirmasi` : 'Semua pesanan tertangani',
      icon: Receipt,
      path: '/merchant/orders',
      iconTone: pendingOrderCount > 0 ? 'bg-warning/10 text-warning' : 'bg-primary/10 text-primary',
    },
    { label: 'Produk', description: 'Kelola katalog toko', icon: Package, path: '/merchant/products', iconTone: 'bg-info/10 text-info' },
    { label: 'Stok', description: 'Pantau persediaan', icon: Layers, path: '/merchant/stock', iconTone: 'bg-success/10 text-success' },
    {
      label: 'Saldo',
      description: walletOverviewLoading ? 'Memuat saldo…' : walletOverviewError ? 'Lihat detail saldo' : `${formatPrice(walletBalance)} tersedia`,
      icon: Wallet,
      path: '/merchant/wallet',
      iconTone: 'bg-primary/10 text-primary',
    },
  ];

  return (
    <MerchantLayout title="Dashboard" subtitle="Ringkasan toko Anda">
      <div className="space-y-6 pb-8" data-testid="merchant-dashboard">
        <section className="grid gap-4 lg:grid-cols-[minmax(0,1.45fr)_minmax(280px,0.55fr)]">
          <div className="relative overflow-hidden rounded-2xl border border-primary/15 bg-gradient-to-br from-primary/[0.13] via-card to-card p-5 shadow-sm sm:p-7">
            <div className="pointer-events-none absolute -right-16 -top-20 h-56 w-56 rounded-full bg-primary/10 blur-3xl" />
            <div className="relative">
              <div className="mb-6 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-primary">
                <Sparkles className="h-3.5 w-3.5" />
                Ruang kerja merchant
              </div>
              <div className="max-w-2xl">
                <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">
                  {greeting}, {merchant.name}
                </h2>
                <p className="mt-2 max-w-xl text-sm leading-6 text-muted-foreground">
                  Pantau pesanan dan kelola toko melalui ringkasan operasional hari ini.
                </p>
              </div>
              <div className="mt-7 flex flex-wrap items-center gap-x-5 gap-y-2 text-xs text-muted-foreground">
                <span className="flex items-center gap-2">
                  <CalendarDays className="h-3.5 w-3.5 text-primary" />
                  {todayLabel}
                </span>
                <span className="flex items-center gap-2">
                  <CircleCheck className="h-3.5 w-3.5 text-success" />
                  Data diperbarui otomatis
                </span>
              </div>
              <div className="mt-6 flex flex-wrap items-center gap-2" aria-live="polite">
                {pendingOrdersError ? (
                  <>
                    <Button variant="outline" size="sm" onClick={() => navigate('/merchant/orders')}>
                      <Receipt className="mr-2 h-4 w-4" />Buka daftar pesanan
                    </Button>
                    <Button variant="ghost" size="sm" onClick={() => void refetchPendingOrders()}>
                      Coba lagi
                    </Button>
                  </>
                ) : (
                  <Button
                    variant={pendingOrderCount > 0 ? 'default' : 'outline'}
                    size="sm"
                    className="gap-2"
                    onClick={() => navigate('/merchant/orders')}
                    disabled={pendingOrdersLoading}
                  >
                    {pendingOrdersLoading ? (
                      <span className="h-2 w-2 animate-pulse rounded-full bg-current" aria-hidden="true" />
                    ) : pendingOrderCount > 0 ? (
                      <Bell className="h-4 w-4" />
                    ) : (
                      <Receipt className="h-4 w-4" />
                    )}
                    {pendingOrdersLoading
                      ? 'Memeriksa pesanan…'
                      : pendingOrderCount > 0
                        ? `Tinjau ${pendingOrderCount} pesanan`
                        : 'Lihat daftar pesanan'}
                    {!pendingOrdersLoading && <ArrowUpRight className="h-4 w-4" aria-hidden="true" />}
                  </Button>
                )}
              </div>
            </div>
          </div>

          <div className="flex flex-col justify-between rounded-2xl border border-border bg-card p-5 shadow-sm sm:p-6">
            <div className="flex items-start justify-between gap-3">
              <div className="flex min-w-0 items-center gap-3">
                {merchant.image_url ? (
                  <img src={merchant.image_url} alt={merchant.name} className="h-11 w-11 rounded-xl border border-border object-cover" />
                ) : (
                  <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
                    <Package className="h-5 w-5" />
                  </div>
                )}
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold">{merchant.name}</p>
                  <p className="mt-0.5 text-xs text-muted-foreground">Status operasional</p>
                </div>
              </div>
              <div className={cn(
                'flex h-8 w-8 shrink-0 items-center justify-center rounded-full',
                merchant.is_open ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'
              )}>
                <span className={cn('h-2.5 w-2.5 rounded-full', merchant.is_open ? 'bg-success' : 'bg-muted-foreground')} />
              </div>
            </div>
            <div className="mt-7">
              <p className="text-2xl font-semibold tracking-tight">{merchant.is_open ? 'Toko sedang buka' : 'Toko sedang tutup'}</p>
              <p className="mt-1 text-xs leading-5 text-muted-foreground">
                {merchant.is_open ? 'Pesanan baru dapat masuk seperti biasa.' : 'Buka toko saat Anda siap menerima pesanan.'}
              </p>
            </div>
            <div className="mt-5 flex flex-wrap gap-2">
              <Button
                variant="outline"
                size="sm"
                className="flex-1"
                onClick={() => navigate(`/merchant/${merchant.slug || merchant.id}`)}
                data-testid="button-view-store"
              >
                <Eye className="mr-1.5 h-3.5 w-3.5" />
                Lihat toko
              </Button>
              <StoreQRCode merchantId={merchant.id} merchantName={merchant.name} slug={merchant.slug} />
              <div className="flex w-full items-center justify-between rounded-lg border border-border bg-muted/30 px-3 py-2 sm:w-auto sm:flex-1">
                <Label className="cursor-pointer text-xs font-medium" htmlFor="store-status">
                  {merchant.is_open ? 'Buka' : 'Tutup'}
                </Label>
                <Switch
                  id="store-status"
                  checked={merchant.is_open}
                  onCheckedChange={toggleStoreStatus}
                  disabled={updatingStatus}
                  data-testid="switch-store-status"
                />
              </div>
            </div>
          </div>
        </section>

        <section aria-label="Akses cepat" data-testid="merchant-quick-actions">
          <div className="mb-3 flex items-end justify-between gap-3">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">Mulai dari sini</p>
              <h3 className="mt-1 text-lg font-semibold tracking-tight">Akses cepat</h3>
            </div>
            <span className="hidden text-xs text-muted-foreground sm:block">Pintasan operasional toko</span>
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {quickActions.map((action) => {
              const ActionIcon = action.icon;
              return (
                <button
                  key={action.label}
                  type="button"
                  className="group flex min-w-0 items-center gap-3 rounded-2xl border border-border bg-card p-4 text-left shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                  onClick={() => navigate(action.path)}
                >
                  <span className={cn('flex h-11 w-11 shrink-0 items-center justify-center rounded-xl transition-transform group-hover:scale-105', action.iconTone)}>
                    <ActionIcon className="h-5 w-5" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-semibold">{action.label}</span>
                    <span className="mt-0.5 block truncate text-xs text-muted-foreground">{action.description}</span>
                  </span>
                  <ArrowUpRight className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-primary" aria-hidden="true" />
                </button>
              );
            })}
          </div>
        </section>

        <section aria-label="Saldo toko" className="grid gap-4 lg:grid-cols-[minmax(260px,0.7fr)_minmax(0,1.3fr)]" data-testid="merchant-wallet-overview">
          <Card className="border-primary/20 bg-gradient-to-br from-primary/[0.06] to-card">
            <CardHeader className="pb-2">
              <CardDescription>Saldo</CardDescription>
              <CardTitle className="text-3xl" data-testid="merchant-wallet-balance">
                {walletOverviewLoading ? 'Memuat…' : walletOverviewError ? '—' : dashboardWallet ? formatPrice(walletBalance) : 'Belum tersedia'}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {dashboardWallet ? <>
                <p className="text-sm text-muted-foreground">Tagihan komisi: <strong className={walletDebt > 0 ? 'text-destructive' : 'text-foreground'}>{formatPrice(walletDebt)}</strong></p>
                <p className="text-xs text-muted-foreground">Tarif komisi {walletOverview?.feeEnabled ? 'aktif' : 'belum aktif'} · wallet {dashboardWallet.is_active ? 'aktif' : 'nonaktif'}</p>
              </> : !walletOverviewLoading && !walletOverviewError && <p className="text-sm text-muted-foreground">Wallet belum tersedia. Hubungi admin jika masalah berlanjut.</p>}
              <Button size="sm" variant="outline" onClick={() => navigate('/merchant/wallet')}>
                Kelola saldo <ArrowUpRight className="h-4 w-4" />
              </Button>
            </CardContent>
          </Card>

          <div className="flex flex-col justify-center">
            {walletOverviewLoading ? <div role="status" className="h-28 animate-pulse rounded-xl bg-muted" aria-label="Memuat status saldo" /> : walletOverviewError ? (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertTitle>Saldo belum dapat dimuat</AlertTitle>
                <AlertDescription className="flex flex-wrap items-center justify-between gap-3">
                  <span>Coba muat ulang ringkasan atau buka halaman Saldo untuk detailnya.</span>
                  <Button size="sm" variant="outline" onClick={() => void refetchWalletOverview()}>Coba lagi</Button>
                </AlertDescription>
              </Alert>
            ) : !dashboardWallet ? (
              <Alert>
                <AlertCircle className="h-4 w-4" />
                <AlertTitle>Wallet belum tersedia</AlertTitle>
                <AlertDescription>Hubungi admin untuk memastikan wallet toko sudah dibuat.</AlertDescription>
              </Alert>
            ) : walletDebt > 0 ? (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertTitle>Pesanan baru ditahan sampai tagihan lunas</AlertTitle>
                <AlertDescription className="flex flex-wrap items-center justify-between gap-3">
                  <span>Tagihan {formatPrice(walletDebt)} akan dilunasi lebih dahulu dari top-up; sisanya menjadi saldo tersedia.</span>
                  <Button size="sm" variant="outline" onClick={() => navigate('/merchant/wallet')}>Isi saldo</Button>
                </AlertDescription>
              </Alert>
            ) : walletOverview?.feeEnabled && !dashboardWallet.is_active ? (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertTitle>Wallet tidak aktif</AlertTitle>
                <AlertDescription>Hubungi admin untuk mengaktifkan wallet sebelum tarif komisi berlaku.</AlertDescription>
              </Alert>
            ) : walletOverview?.feeEnabled && walletBalance <= walletThreshold ? (
              <Alert className="border-warning/40 bg-warning/5 [&>svg]:text-warning">
                <AlertCircle className="h-4 w-4" />
                <AlertTitle>{walletBalance > 0 ? 'Saldo mulai menipis' : 'Isi saldo agar toko tetap memenuhi syarat'}</AlertTitle>
                <AlertDescription className="flex flex-wrap items-center justify-between gap-3">
                  <span>{walletBalance > 0 ? `Saldo ${formatPrice(walletBalance)} berada pada/di bawah ambang ${formatPrice(walletThreshold)}. Kekurangan komisi dapat menjadi tagihan dan menahan pesanan berikutnya.` : 'Saat tarif komisi aktif, wallet harus memiliki saldo positif agar toko memenuhi syarat tampil dan menerima pesanan.'}</span>
                  <Button size="sm" variant="outline" onClick={() => navigate('/merchant/wallet')}>Top-up saldo</Button>
                </AlertDescription>
              </Alert>
            ) : walletOverview?.feeEnabled ? (
              <Alert className="border-success/30 bg-success/[0.04] [&>svg]:text-success">
                <CheckCircle className="h-4 w-4" />
                <AlertTitle>Saldo siap digunakan</AlertTitle>
                <AlertDescription>Wallet aktif, saldo di atas ambang, dan tidak ada tagihan komisi tertunggak.</AlertDescription>
              </Alert>
            ) : (
              <Alert>
                <Wallet className="h-4 w-4" />
                <AlertTitle>Saldo wallet toko</AlertTitle>
                <AlertDescription>Tarif komisi belum aktif; saldo tetap dapat dipantau di dashboard ini.</AlertDescription>
              </Alert>
            )}
          </div>
        </section>

        <section className="grid gap-4 md:grid-cols-2" data-testid="merchant-status-cards">
          <MerchantGroupCard />
          <MerchantKasCard merchantId={merchant.id} />
        </section>

        <section aria-label="Ringkasan hari ini" className="max-w-4xl">
          <DailySummaryCard merchantId={merchant.id} />
        </section>

        <section>
          <div className="mb-3 flex items-end justify-between gap-3">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">Detail operasional</p>
              <h3 className="mt-1 text-lg font-semibold tracking-tight">Status pesanan hari ini</h3>
            </div>
            <span className="hidden text-xs text-muted-foreground sm:block">Hari ini</span>
          </div>
          <QuickStats merchantId={merchant.id} />
        </section>

        <Tabs value={activeTab} onValueChange={setActiveTab} className="space-y-5">
          <TabsList className="sticky top-0 z-20 flex h-auto min-h-12 w-full gap-1 overflow-x-auto overflow-y-hidden rounded-xl border border-border bg-background/95 p-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden shadow-sm backdrop-blur supports-[backdrop-filter]:bg-background/80">
            <TabsTrigger value="overview" className="min-w-[7.25rem] flex-1 gap-2 rounded-lg px-3 py-2.5 text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground sm:text-sm" data-testid="tab-overview">
              <TrendingUp className="h-3.5 w-3.5" />
              Overview
            </TabsTrigger>
            <TabsTrigger value="orders" className="min-w-[7.25rem] flex-1 gap-2 rounded-lg px-3 py-2.5 text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground sm:text-sm" data-testid="tab-orders">
              <Receipt className="h-3.5 w-3.5" />
              Pesanan
            </TabsTrigger>
            <TabsTrigger value="stock" className="min-w-[7.25rem] flex-1 gap-2 rounded-lg px-3 py-2.5 text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground sm:text-sm" data-testid="tab-stock">
              <Package className="h-3.5 w-3.5" />
              Stok
            </TabsTrigger>
            <TabsTrigger value="more" className="min-w-[7.25rem] flex-1 gap-2 rounded-lg px-3 py-2.5 text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground sm:text-sm" data-testid="tab-more">
              <BarChart3 className="h-3.5 w-3.5" />
              Lainnya
            </TabsTrigger>
          </TabsList>

          <TabsContent value="overview" className="mt-0 space-y-5">
            {pendingOrdersLoading ? (
              <div role="status" className="rounded-2xl border border-border bg-card p-5 text-sm text-muted-foreground">
                Memuat pesanan yang perlu ditinjau...
              </div>
            ) : pendingOrdersError ? (
              <MerchantCardError
                message={pendingOrdersErrorDetails instanceof Error ? pendingOrdersErrorDetails.message : 'Ringkasan pesanan gagal dimuat.'}
                onRetry={() => void refetchPendingOrders()}
              />
            ) : pendingOrderCount > 0 ? (
              <div className="rounded-2xl border border-warning/30 bg-warning/[0.04] p-4 shadow-sm sm:p-5" data-testid="pending-orders-panel">
                <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div className="flex items-start gap-3">
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-warning/10 text-warning">
                      <Bell className="h-5 w-5" />
                    </div>
                    <div>
                      <h4 className="font-semibold">Pesanan menunggu konfirmasi</h4>
                      <p className="mt-1 text-xs leading-5 text-muted-foreground">
                        {pendingOrders.length < pendingOrderCount
                          ? `Menampilkan ${pendingOrders.length} pesanan terbaru dari ${pendingOrderCount} yang perlu ditinjau.`
                          : 'Tinjau detail lalu terima atau tolak pesanan berikut.'}
                      </p>
                    </div>
                  </div>
                  <span className="w-fit rounded-full bg-warning/10 px-2.5 py-1 text-xs font-semibold text-warning">{pendingOrderCount} pesanan</span>
                </div>
                <div className="space-y-2">
                  {pendingOrders.map(order => (
                    <div key={order.id} className="flex flex-col gap-3 rounded-xl border border-border/70 bg-card p-3 sm:flex-row sm:items-center sm:justify-between" data-testid={`pending-order-${order.id}`}>
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium">{order.delivery_name || 'Pelanggan'}</p>
                        <p className="mt-1 text-xs text-muted-foreground">
                          {formatPrice(order.total)} <span className="mx-1.5 text-border">•</span>
                          {new Date(order.created_at).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' })}
                        </p>
                      </div>
                      <div className="flex gap-2 sm:shrink-0">
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-8 flex-1 text-xs text-destructive hover:bg-destructive/10 hover:text-destructive sm:flex-none"
                          onClick={() => updateOrderStatus(order.id, 'CANCELED', 'Ditolak oleh merchant')}
                          data-testid={`button-reject-order-${order.id}`}
                        >
                          <XCircle className="mr-1 h-3 w-3" />
                          Tolak
                        </Button>
                        <Button
                          size="sm"
                          className="h-8 flex-1 text-xs sm:flex-none"
                          onClick={() => updateOrderStatus(order.id, 'PROCESSED')}
                          data-testid={`button-accept-order-${order.id}`}
                        >
                          <CheckCircle className="mr-1 h-3 w-3" />
                          Terima
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div className="flex items-center gap-4 rounded-2xl border border-success/25 bg-success/[0.04] p-5 shadow-sm" data-testid="orders-clear-state">
                <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-success/10 text-success">
                  <CheckCircle className="h-5 w-5" />
                </div>
                <div>
                  <p className="text-sm font-semibold">Semua pesanan tertangani</p>
                  <p className="mt-1 text-xs text-muted-foreground">Tidak ada pesanan yang menunggu konfirmasi saat ini.</p>
                </div>
              </div>
            )}

            {ordersQueryError ? (
              <MerchantCardError
                message={ordersError instanceof Error ? ordersError.message : 'Data pesanan gagal dimuat.'}
                onRetry={() => void refetchOrders()}
              />
            ) : (
              <div className="space-y-2">
                <p className="text-xs text-muted-foreground">
                Grafik 14 hari memakai data pada periode yang sama; ringkasan angka pesanan di atas menggunakan hitungan server.
                </p>
                <Suspense fallback={
                  <div className="grid gap-4 xl:grid-cols-[minmax(0,1.35fr)_minmax(0,0.65fr)]" aria-label="Memuat grafik">
                    <div className="h-[310px] animate-pulse rounded-2xl bg-muted" />
                    <div className="h-[310px] animate-pulse rounded-2xl bg-muted" />
                  </div>
                }>
                  <div className="grid gap-4 xl:grid-cols-[minmax(0,1.35fr)_minmax(0,0.65fr)]">
                    <div className="overflow-hidden rounded-2xl border border-border bg-card p-1 shadow-sm">
                      <SalesAreaChart data={salesChartData} title="Pendapatan 14 hari terakhir" />
                    </div>
                    <div className="overflow-hidden rounded-2xl border border-border bg-card p-1 shadow-sm">
                      <OrdersBarChart data={salesChartData} title="Pesanan 14 hari terakhir" />
                    </div>
                  </div>
                </Suspense>
              </div>
            )}

            <div className="grid gap-4 xl:grid-cols-2">
              <StockAlerts merchantId={merchant.id} />
              <CustomerReviews merchantId={merchant.id} />
            </div>
          </TabsContent>

          <TabsContent value="orders" className="mt-0">
            <div className="min-h-[400px] rounded-2xl border border-border bg-card p-1 shadow-sm">
              <OrderStatusManager merchantId={merchant.id} />
            </div>
          </TabsContent>

          <TabsContent value="stock" className="mt-0">
            <StockAlerts merchantId={merchant.id} />
          </TabsContent>

          <TabsContent value="more" className="mt-0 space-y-5">
            <MerchantOperatingHoursCard merchantId={merchant.id} />
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              {[
                { label: 'Produk', icon: Package, path: '/merchant/products', tone: 'bg-primary/10 text-primary' },
                { label: 'Analitik', icon: BarChart3, path: '/merchant/analytics', tone: 'bg-info/10 text-info' },
                { label: 'Ulasan', icon: Star, path: '/merchant/reviews', tone: 'bg-warning/10 text-warning' },
                { label: 'Promo', icon: Percent, path: '/merchant/promo', tone: 'bg-destructive/10 text-destructive' },
                { label: 'Penarikan', icon: Wallet, path: '/merchant/withdrawal', tone: 'bg-success/10 text-success' },
                { label: 'Pengaturan', icon: Settings, path: '/merchant/settings', tone: 'bg-muted text-muted-foreground' },
              ].map((item) => (
                <Button
                  key={item.label}
                  variant="outline"
                  className="h-auto min-h-28 flex-col items-center justify-center gap-3 rounded-xl border-border bg-card py-4 transition-colors hover:border-primary/40 hover:bg-primary/[0.03]"
                  onClick={() => navigate(item.path)}
                  data-testid={`button-merchant-${item.label.toLowerCase()}`}
                >
                  <span className={cn('flex h-10 w-10 items-center justify-center rounded-xl', item.tone)}>
                    <item.icon className="h-5 w-5" />
                  </span>
                  <span className="text-xs font-medium">{item.label}</span>
                </Button>
              ))}
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </MerchantLayout>
  );
}
