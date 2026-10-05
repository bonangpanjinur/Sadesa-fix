import { useMemo, useState } from 'react';
import {
  AlertCircle, ArrowDownRight, ArrowUpRight, BarChart3, CalendarDays,
  CheckCircle2, ChevronDown, Eye, Lightbulb, Package, RefreshCw,
  ShoppingCart, TrendingUp
} from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { format, isSameDay, subDays } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { Area, Bar, CartesianGrid, ComposedChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice } from '@/lib/utils';
import { SalesExport } from '@/components/merchant/SalesExport';
import { MerchantCardError } from '@/components/merchant/MerchantDataState';

const DONE_STATUSES = ['DONE', 'DELIVERED'];

type Period = '7' | '30' | '90';

interface OrderRow {
  id: string;
  total: number | null;
  platform_fee: number | null;
  status: string;
  created_at: string;
}

interface ProductRow {
  id: string;
  name: string;
  price: number | null;
  stock: number | null;
  view_count: number | null;
  order_count: number | null;
  is_active: boolean;
}

function Delta({ current, previous, label }: { current: number; previous: number; label: string }) {
  if (previous <= 0) return <p className="text-xs text-muted-foreground">Belum ada pembanding</p>;
  const value = ((current - previous) / previous) * 100;
  const positive = value >= 0;
  return (
    <p className={`flex items-center gap-1 text-xs font-medium ${positive ? 'text-emerald-600' : 'text-red-500'}`}>
      {positive ? <ArrowUpRight className="h-3.5 w-3.5" /> : <ArrowDownRight className="h-3.5 w-3.5" />}
      {Math.abs(value).toFixed(1)}% vs {label}
    </p>
  );
}

function KpiCard({ label, value, icon: Icon, tone, children, definition }: {
  label: string; value: string | number; icon: typeof TrendingUp; tone: string; children: React.ReactNode; definition: string;
}) {
  return (
    <Card className="shadow-sm">
      <CardContent className="p-4 sm:p-5">
        <div className="flex items-start justify-between gap-2">
          <div>
            <p className="text-xs font-medium text-muted-foreground">{label}</p>
            <p className="mt-1 text-xl font-bold tracking-tight sm:text-2xl">{value}</p>
          </div>
          <div className={`rounded-xl p-2.5 ${tone}`}><Icon className="h-4 w-4" /></div>
        </div>
        <div className="mt-2">{children}</div>
        <p className="mt-2 text-[11px] leading-4 text-muted-foreground">{definition}</p>
      </CardContent>
    </Card>
  );
}

export default function MerchantAnalyticsPage() {
  const { merchantId, merchantName, loading: guardLoading } = useMerchantGuard();
  const [period, setPeriod] = useState<Period>('30');
  const [compare, setCompare] = useState(true);
  const days = Number(period);
  const start = subDays(new Date(), days);
  const previousStart = subDays(start, days);

  const { data, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ['merchant-sales-summary', merchantId, period],
    enabled: !!merchantId && !guardLoading,
    staleTime: 60_000,
    retry: false,
    queryFn: async () => {
      const [ordersRes, productsRes] = await Promise.all([
        supabase.from('orders').select('id, total, platform_fee, status, created_at').eq('merchant_id', merchantId!).gte('created_at', previousStart.toISOString()).order('created_at', { ascending: true }),
        supabase.from('products').select('id, name, price, stock, view_count, order_count, is_active').eq('merchant_id', merchantId!).order('order_count', { ascending: false }),
      ]);
      if (ordersRes.error) throw ordersRes.error;
      if (productsRes.error) throw productsRes.error;
      return { orders: (ordersRes.data ?? []) as OrderRow[], products: (productsRes.data ?? []) as ProductRow[] };
    },
  });

  const orders = data?.orders ?? [];
  const products = data?.products ?? [];
  const currentOrders = orders.filter(o => new Date(o.created_at) >= start && DONE_STATUSES.includes(o.status));
  const previousOrders = orders.filter(o => new Date(o.created_at) < start && DONE_STATUSES.includes(o.status));
  const currentRevenue = currentOrders.reduce((sum, order) => sum + (order.total ?? 0), 0);
  const previousRevenue = previousOrders.reduce((sum, order) => sum + (order.total ?? 0), 0);
  const currentAov = currentOrders.length ? currentRevenue / currentOrders.length : 0;
  const previousAov = previousOrders.length ? previousRevenue / previousOrders.length : 0;
  const totalViews = products.reduce((sum, product) => sum + (product.view_count ?? 0), 0);
  const totalProductOrders = products.reduce((sum, product) => sum + (product.order_count ?? 0), 0);
  const conversion = totalViews ? (totalProductOrders / totalViews) * 100 : 0;
  const platformFee = currentOrders.reduce((sum, order) => sum + (order.platform_fee ?? 0), 0);
  const hasSales = currentOrders.length > 0;

  const dailyData = useMemo(() => Array.from({ length: days }, (_, index) => {
    const day = subDays(new Date(), days - 1 - index);
    const dayOrders = currentOrders.filter(order => isSameDay(new Date(order.created_at), day));
    return {
      date: format(day, days > 60 ? 'd MMM' : 'd', { locale: idLocale }),
      omzet: dayOrders.reduce((sum, order) => sum + (order.total ?? 0), 0),
      pesanan: dayOrders.length,
    };
  }), [currentOrders, days]);

  const topProducts = [...products].sort((a, b) => (b.order_count ?? 0) - (a.order_count ?? 0)).slice(0, 3);
  const attentionProducts = [...products]
    .filter(product => product.is_active)
    .sort((a, b) => ((a.order_count ?? 0) / Math.max(a.view_count ?? 1, 1)) - ((b.order_count ?? 0) / Math.max(b.view_count ?? 1, 1)))
    .slice(0, 3);
  const peakDay = dailyData.reduce((peak, day) => day.omzet > peak.omzet ? day : peak, { date: '-', omzet: 0, pesanan: 0 });

  if (guardLoading || isLoading) {
    return <MerchantLayout title="Ringkasan Penjualan" subtitle="Pantau performa toko dan temukan peluang perbaikan"><div className="space-y-4"><div className="grid grid-cols-2 gap-4 lg:grid-cols-4">{[1, 2, 3, 4].map(item => <div key={item} className="h-32 animate-pulse rounded-xl bg-muted" />)}</div><div className="h-80 animate-pulse rounded-xl bg-muted" /></div></MerchantLayout>;
  }

  if (isError) {
    return <MerchantLayout title="Ringkasan Penjualan" subtitle="Pantau performa toko dan temukan peluang perbaikan"><MerchantCardError message="Ringkasan penjualan gagal dimuat. Data lain tetap aman." onRetry={() => void refetch()} /></MerchantLayout>;
  }

  if (!merchantId) {
    return <MerchantLayout title="Ringkasan Penjualan"><div className="flex flex-col items-center justify-center py-20 text-center"><AlertCircle className="mb-4 h-12 w-12 text-muted-foreground" /><p className="text-muted-foreground">Toko tidak ditemukan</p></div></MerchantLayout>;
  }

  return (
    <MerchantLayout title="Ringkasan Penjualan" subtitle="Pantau performa toko dan temukan peluang perbaikan" actions={<SalesExport merchantId={merchantId} merchantName={merchantName} />}>
      <div className="space-y-6">
        <div className="sticky top-0 z-10 -mx-4 flex items-center gap-2 overflow-x-auto border-b bg-background/95 px-4 py-3 backdrop-blur lg:static lg:mx-0 lg:border-0 lg:px-0 lg:pt-0">
          <DropdownMenu><DropdownMenuTrigger asChild><Button variant="outline" size="sm" className="shrink-0"><CalendarDays className="mr-2 h-4 w-4" />{days} hari terakhir<ChevronDown className="ml-2 h-3.5 w-3.5" /></Button></DropdownMenuTrigger><DropdownMenuContent align="start">{(['7', '30', '90'] as Period[]).map(value => <DropdownMenuItem key={value} onClick={() => setPeriod(value)}>{value} hari terakhir{period === value && ' ✓'}</DropdownMenuItem>)}</DropdownMenuContent></DropdownMenu>
          <Button variant={compare ? 'secondary' : 'outline'} size="sm" className="shrink-0" onClick={() => setCompare(value => !value)}><CheckCircle2 className="mr-2 h-4 w-4" />Bandingkan periode</Button>
          <Button variant="ghost" size="sm" className="ml-auto shrink-0" onClick={() => void refetch()} disabled={isFetching}><RefreshCw className={`mr-2 h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />Refresh</Button>
        </div>
        <div className="flex items-center justify-between text-xs text-muted-foreground"><span>Periode: {format(start, 'd MMM yyyy', { locale: idLocale })} – {format(new Date(), 'd MMM yyyy', { locale: idLocale })}</span><span className="hidden sm:inline">Terakhir diperbarui {format(new Date(), 'd MMM yyyy, HH:mm', { locale: idLocale })}</span></div>

        {!hasSales ? <Card className="border-dashed"><CardContent className="flex flex-col items-center p-8 text-center"><ShoppingCart className="mb-3 h-10 w-10 text-muted-foreground" /><h2 className="font-semibold">Belum ada penjualan pada periode ini</h2><p className="mt-1 text-sm text-muted-foreground">Pilih periode yang lebih panjang atau mulai bagikan katalog Anda.</p></CardContent></Card> : null}

        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4 lg:gap-4">
          <KpiCard label="Omzet kotor" value={formatPrice(currentRevenue)} icon={TrendingUp} tone="bg-emerald-100 text-emerald-700" definition="Order selesai sebelum biaya platform."><Delta current={currentRevenue} previous={compare ? previousRevenue : 0} label={`${days} hari sebelumnya`} /></KpiCard>
          <KpiCard label="Pesanan selesai" value={`${currentOrders.length} pesanan`} icon={ShoppingCart} tone="bg-blue-100 text-blue-700" definition="Status DONE atau DELIVERED."><Delta current={currentOrders.length} previous={compare ? previousOrders.length : 0} label={`${days} hari sebelumnya`} /></KpiCard>
          <KpiCard label="Pendapatan bersih" value={formatPrice(currentRevenue - platformFee)} icon={CheckCircle2} tone="bg-violet-100 text-violet-700" definition="Omzet dikurangi biaya platform yang tercatat."><Delta current={currentRevenue - platformFee} previous={compare ? previousRevenue - previousOrders.reduce((sum, order) => sum + (order.platform_fee ?? 0), 0) : 0} label={`${days} hari sebelumnya`} /></KpiCard>
          <KpiCard label="Nilai rata-rata order" value={formatPrice(currentAov)} icon={BarChart3} tone="bg-amber-100 text-amber-700" definition="Omzet kotor dibagi pesanan selesai."><Delta current={currentAov} previous={compare ? previousAov : 0} label={`${days} hari sebelumnya`} /></KpiCard>
        </div>

        <Card className="border-amber-200 bg-amber-50/60 dark:bg-amber-950/20"><CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center"><div className="rounded-full bg-amber-100 p-2 text-amber-700"><Lightbulb className="h-5 w-5" /></div><div className="flex-1"><p className="text-sm font-semibold">Peluang utama</p><p className="text-sm text-muted-foreground">{hasSales ? `Omzet paling tinggi terjadi pada ${peakDay.date}. Pertimbangkan menambah stok produk terlaris sebelum periode tersebut.` : 'Insight jam ramai akan muncul setelah ada minimal 7 hari transaksi.'}</p></div><Button variant="outline" size="sm" className="shrink-0 bg-background">Lihat insight</Button></CardContent></Card>

        <Card><CardHeader className="flex flex-row items-start justify-between space-y-0 pb-2"><div><CardTitle className="text-base">Tren omzet dan pesanan</CardTitle><CardDescription>{hasSales ? 'Omzet kotor dan volume pesanan selesai per hari.' : 'Belum ada data untuk periode ini.'}</CardDescription></div><Badge variant="secondary">Harian</Badge></CardHeader><CardContent><ResponsiveContainer width="100%" height={280}><ComposedChart data={dailyData} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}><CartesianGrid strokeDasharray="3 3" className="stroke-border" vertical={false} /><XAxis dataKey="date" tick={{ fontSize: 11 }} interval={days > 30 ? 6 : 3} /><YAxis yAxisId="revenue" tick={{ fontSize: 11 }} tickFormatter={value => value >= 1000000 ? `${(value / 1000000).toFixed(1)}jt` : `${Math.round(value / 1000)}k`} /><YAxis yAxisId="orders" orientation="right" tick={{ fontSize: 11 }} allowDecimals={false} /><Tooltip formatter={(value: number, name: string) => [name === 'Omzet' ? formatPrice(value) : `${value} pesanan`, name]} /><Area yAxisId="revenue" type="monotone" dataKey="omzet" name="Omzet" stroke="#10b981" fill="#10b981" fillOpacity={0.14} strokeWidth={2} /><Bar yAxisId="orders" dataKey="pesanan" name="Pesanan" fill="#3b82f6" opacity={0.75} barSize={8} radius={[3, 3, 0, 0]} /></ComposedChart></ResponsiveContainer></CardContent></Card>

        <div className="grid gap-4 lg:grid-cols-2"><Card><CardHeader className="pb-3"><CardTitle className="text-base">Produk terlaris</CardTitle><CardDescription>Produk dengan kontribusi order terbesar.</CardDescription></CardHeader><CardContent className="space-y-3">{topProducts.length ? topProducts.map((product, index) => <div key={product.id} className="flex items-center gap-3"><span className="w-5 text-sm font-bold text-muted-foreground">{index + 1}</span><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{product.name}</p><p className="text-xs text-muted-foreground">{product.order_count ?? 0} pesanan · {product.stock ?? 0} stok</p></div><span className="text-sm font-semibold">{formatPrice((product.order_count ?? 0) * (product.price ?? 0))}</span></div>) : <p className="py-4 text-sm text-muted-foreground">Belum ada data produk.</p>}<Button variant="ghost" size="sm" className="w-full">Lihat semua produk</Button></CardContent></Card><Card><CardHeader className="pb-3"><CardTitle className="text-base">Produk yang perlu perhatian</CardTitle><CardDescription>Gabungan sinyal views, konversi, dan stok.</CardDescription></CardHeader><CardContent className="space-y-3">{attentionProducts.length ? attentionProducts.map(product => { const rate = (product.view_count ?? 0) > 0 ? ((product.order_count ?? 0) / (product.view_count ?? 1)) * 100 : 0; return <div key={product.id} className="flex items-center gap-3"><Package className="h-4 w-4 shrink-0 text-amber-600" /><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{product.name}</p><p className="text-xs text-muted-foreground">{product.view_count ?? 0} views · stok {product.stock ?? 0}</p></div><Badge variant={rate < 2 ? 'destructive' : 'secondary'}>{rate.toFixed(1)}%</Badge></div>; }) : <p className="py-4 text-sm text-muted-foreground">Belum ada sinyal perhatian.</p>}<Button variant="ghost" size="sm" className="w-full">Buka katalog</Button></CardContent></Card></div>

        <Card><CardHeader className="pb-3"><CardTitle className="text-base">Funnel penjualan (estimasi)</CardTitle><CardDescription>Counter produk dan order global tidak memiliki join funnel langsung.</CardDescription></CardHeader><CardContent><div className="grid grid-cols-3 gap-2 text-center"><div className="rounded-lg bg-muted/60 p-3"><Eye className="mx-auto mb-1 h-4 w-4 text-muted-foreground" /><p className="text-lg font-bold">{totalViews.toLocaleString('id-ID')}</p><p className="text-xs text-muted-foreground">Dilihat</p></div><div className="rounded-lg bg-blue-50 p-3 dark:bg-blue-950/20"><ShoppingCart className="mx-auto mb-1 h-4 w-4 text-blue-600" /><p className="text-lg font-bold">{totalProductOrders.toLocaleString('id-ID')}</p><p className="text-xs text-muted-foreground">Dipesan · {conversion.toFixed(1)}%</p></div><div className="rounded-lg bg-emerald-50 p-3 dark:bg-emerald-950/20"><CheckCircle2 className="mx-auto mb-1 h-4 w-4 text-emerald-600" /><p className="text-lg font-bold">{currentOrders.length.toLocaleString('id-ID')}</p><p className="text-xs text-muted-foreground">Selesai</p></div></div></CardContent></Card>

      </div>
    </MerchantLayout>
  );
}
