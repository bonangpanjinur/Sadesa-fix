import { useMemo, useState } from 'react';
import { BarChart3, Download, Eye, MousePointerClick, RefreshCw, TrendingUp, DollarSign, Megaphone, Users, Target } from 'lucide-react';
import { format, subDays, startOfDay, endOfDay, eachDayOfInterval } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice } from '@/lib/utils';
import { useQuery } from '@tanstack/react-query';

type AdRow = {
  id: string;
  merchant_id: string;
  title: string;
  placement_type: string;
  status: string;
  payment_amount: number;
  view_count: number;
  click_count: number;
  created_at: string;
  start_date: string | null;
  end_date: string | null;
  merchant?: { name: string } | null;
};

const PLACEMENT_LABELS: Record<string, string> = {
  home_banner: 'Banner di Atas Menu',
  search_top: 'Teratas Pencarian',
  category_top: 'Teratas Kategori',
  product_recommend: 'Produk Pilihan',
};
const STATUS_LABELS: Record<string, string> = { active: 'Aktif', pending: 'Pending', expired: 'Berakhir', rejected: 'Ditolak' };
const COLORS = ['hsl(var(--primary))', 'hsl(var(--accent))', 'hsl(142 64% 42%)', 'hsl(220 70% 55%)'];

function getRange(range: string) {
  const end = endOfDay(new Date());
  return { start: startOfDay(subDays(end, range === '30days' ? 30 : range === '90days' ? 90 : 7)), end };
}

export default function AdminIklanLaporanPage() {
  const [range, setRange] = useState('30days');
  const [status, setStatus] = useState('all');
  const { start, end } = getRange(range);
  const { data: ads = [], isLoading, isError, refetch } = useQuery<AdRow[]>({
    queryKey: ['admin-ad-performance-report', range, status],
    queryFn: async () => {
      let query = supabase
        .from('merchant_ads')
        .select('id, merchant_id, title, placement_type, status, payment_amount, view_count, click_count, created_at, start_date, end_date, merchant:merchant_id(name)')
        .gte('created_at', start.toISOString())
        .lte('created_at', end.toISOString())
        .order('created_at', { ascending: false });
      if (status !== 'all') query = query.eq('status', status);
      const { data, error } = await query;
      if (error) throw error;
      return (data || []) as unknown as AdRow[];
    },
    staleTime: 60_000,
  });

  const metrics = useMemo(() => {
    const active = ads.filter(a => a.status === 'active');
    const views = ads.reduce((sum, ad) => sum + (ad.view_count || 0), 0);
    const clicks = ads.reduce((sum, ad) => sum + (ad.click_count || 0), 0);
    return {
      revenue: ads.filter(a => a.status !== 'rejected').reduce((sum, ad) => sum + Number(ad.payment_amount || 0), 0),
      active: active.length,
      merchants: new Set(ads.map(ad => ad.merchant_id)).size,
      views,
      clicks,
      ctr: views ? (clicks / views) * 100 : 0,
    };
  }, [ads]);

  const trend = useMemo(() => {
    const days = eachDayOfInterval({ start, end });
    return days.map(day => {
      const key = format(day, 'yyyy-MM-dd');
      const dayAds = ads.filter(ad => format(new Date(ad.created_at), 'yyyy-MM-dd') === key);
      return { date: format(day, 'dd MMM', { locale: idLocale }), submissions: dayAds.length, revenue: dayAds.reduce((sum, ad) => sum + Number(ad.payment_amount || 0), 0) };
    });
  }, [ads, start, end]);

  const placements = useMemo(() => Object.entries(ads.reduce<Record<string, number>>((acc, ad) => { acc[ad.placement_type] = (acc[ad.placement_type] || 0) + 1; return acc; }, {})).map(([name, value]) => ({ name: PLACEMENT_LABELS[name] || name, value })), [ads]);

  const topAds = useMemo(() => [...ads].sort((a, b) => ((b.click_count || 0) / Math.max(b.view_count || 0, 1)) - ((a.click_count || 0) / Math.max(a.view_count || 0, 1))).slice(0, 8), [ads]);
  const topMerchants = useMemo(() => {
    const grouped = new Map<string, { name: string; ads: number; views: number; clicks: number; revenue: number }>();
    ads.forEach(ad => {
      const current = grouped.get(ad.merchant_id) || { name: ad.merchant?.name || 'Merchant', ads: 0, views: 0, clicks: 0, revenue: 0 };
      current.ads += 1; current.views += ad.view_count || 0; current.clicks += ad.click_count || 0; current.revenue += Number(ad.payment_amount || 0);
      grouped.set(ad.merchant_id, current);
    });
    return [...grouped.values()].sort((a, b) => b.clicks - a.clicks).slice(0, 8);
  }, [ads]);

  const exportCsv = () => {
    const headers = ['Merchant', 'Judul Iklan', 'Placement', 'Status', 'Pendapatan', 'Impresi', 'Klik', 'CTR', 'Dibuat'];
    const rows = ads.map(ad => [ad.merchant?.name || 'Merchant', ad.title, PLACEMENT_LABELS[ad.placement_type] || ad.placement_type, STATUS_LABELS[ad.status] || ad.status, ad.payment_amount, ad.view_count || 0, ad.click_count || 0, `${(((ad.click_count || 0) / Math.max(ad.view_count || 0, 1)) * 100).toFixed(2)}%`, format(new Date(ad.created_at), 'dd/MM/yyyy')]);
    const csv = [headers, ...rows].map(row => row.map(value => `"${String(value).replaceAll('"', '""')}"`).join(',')).join('\n');
    const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); link.download = `laporan-iklan-${format(new Date(), 'yyyyMMdd')}.csv`; link.click(); URL.revokeObjectURL(link.href);
  };

  return (
    <AdminLayout title="Laporan Performa Iklan" subtitle="Pantau pendapatan, jangkauan, dan efektivitas iklan merchant">
      <div className="space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap gap-2">
            <Select value={range} onValueChange={setRange}><SelectTrigger className="w-[150px]"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="7days">7 hari terakhir</SelectItem><SelectItem value="30days">30 hari terakhir</SelectItem><SelectItem value="90days">90 hari terakhir</SelectItem></SelectContent></Select>
            <Select value={status} onValueChange={setStatus}><SelectTrigger className="w-[140px]"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="all">Semua status</SelectItem><SelectItem value="active">Aktif</SelectItem><SelectItem value="pending">Pending</SelectItem><SelectItem value="expired">Berakhir</SelectItem><SelectItem value="rejected">Ditolak</SelectItem></SelectContent></Select>
          </div>
          <div className="flex gap-2"><Button variant="outline" size="sm" onClick={() => refetch()}><RefreshCw className="mr-2 h-4 w-4" />Refresh</Button><Button size="sm" onClick={exportCsv} disabled={ads.length === 0}><Download className="mr-2 h-4 w-4" />Export CSV</Button></div>
        </div>
        {isError && <Alert variant="destructive"><AlertDescription>Data laporan iklan gagal dimuat. Silakan refresh.</AlertDescription></Alert>}
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-6">
          {[
            { label: 'Pendapatan', value: formatPrice(metrics.revenue), icon: DollarSign, tone: 'text-green-600' },
            { label: 'Iklan Aktif', value: metrics.active, icon: Megaphone, tone: 'text-primary' },
            { label: 'Merchant', value: metrics.merchants, icon: Users, tone: 'text-blue-600' },
            { label: 'Impresi', value: metrics.views.toLocaleString(), icon: Eye, tone: 'text-purple-600' },
            { label: 'Klik', value: metrics.clicks.toLocaleString(), icon: MousePointerClick, tone: 'text-orange-600' },
            { label: 'CTR', value: `${metrics.ctr.toFixed(2)}%`, icon: Target, tone: 'text-teal-600' },
          ].map(({ label, value, icon: Icon, tone }) => <Card key={label}><CardContent className="p-4"><Icon className={`mb-2 h-4 w-4 ${tone}`} /><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 text-xl font-bold">{isLoading ? '—' : value}</p></CardContent></Card>)}
        </div>
        <div className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
          <Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><TrendingUp className="h-4 w-4 text-primary" />Tren pengajuan & pendapatan</CardTitle></CardHeader><CardContent><div className="h-[280px] w-full"><ResponsiveContainer><AreaChart data={trend}><defs><linearGradient id="adRevenue" x1="0" y1="0" x2="0" y2="1"><stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.35}/><stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0}/></linearGradient></defs><CartesianGrid strokeDasharray="3 3" className="stroke-muted"/><XAxis dataKey="date" fontSize={11} tickLine={false} axisLine={false}/><YAxis fontSize={11} tickLine={false} axisLine={false}/><Tooltip formatter={(value: number, name: string) => [name === 'revenue' ? formatPrice(value) : value, name === 'revenue' ? 'Pendapatan' : 'Pengajuan']}/><Area type="monotone" dataKey="revenue" stroke="hsl(var(--primary))" fill="url(#adRevenue)" strokeWidth={2}/><Area type="monotone" dataKey="submissions" stroke="hsl(var(--accent))" fill="transparent" strokeWidth={2}/></AreaChart></ResponsiveContainer></div></CardContent></Card>
          <Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><BarChart3 className="h-4 w-4 text-primary" />Distribusi penempatan</CardTitle></CardHeader><CardContent><div className="h-[280px] w-full"><ResponsiveContainer><PieChart><Pie data={placements} dataKey="value" nameKey="name" innerRadius={55} outerRadius={90} paddingAngle={3}>{placements.map((entry, index) => <Cell key={entry.name} fill={COLORS[index % COLORS.length]} />)}</Pie><Tooltip /></PieChart></ResponsiveContainer></div>{placements.length === 0 && <p className="text-center text-sm text-muted-foreground">Belum ada data penempatan.</p>}</CardContent></Card>
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          <Card><CardHeader><CardTitle className="text-base">Iklan dengan CTR terbaik</CardTitle></CardHeader><CardContent><div className="space-y-3">{topAds.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Belum ada iklan pada periode ini.</p> : topAds.map(ad => <div key={ad.id} className="flex items-center gap-3"><div className="min-w-0 flex-1"><p className="truncate text-sm font-semibold">{ad.title}</p><p className="truncate text-xs text-muted-foreground">{ad.merchant?.name || 'Merchant'} · {PLACEMENT_LABELS[ad.placement_type] || ad.placement_type}</p></div><div className="text-right"><p className="text-sm font-bold text-primary">{(((ad.click_count || 0) / Math.max(ad.view_count || 0, 1)) * 100).toFixed(2)}%</p><p className="text-[10px] text-muted-foreground">{(ad.click_count || 0).toLocaleString()} klik</p></div></div>)}</div></CardContent></Card>
          <Card><CardHeader><CardTitle className="text-base">Merchant paling efektif</CardTitle></CardHeader><CardContent><div className="space-y-3">{topMerchants.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Belum ada merchant pada periode ini.</p> : topMerchants.map(merchant => <div key={merchant.name} className="flex items-center gap-3"><div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-bold text-primary">{merchant.name.slice(0, 1).toUpperCase()}</div><div className="min-w-0 flex-1"><p className="truncate text-sm font-semibold">{merchant.name}</p><p className="text-xs text-muted-foreground">{merchant.ads} iklan · {merchant.views.toLocaleString()} impresi</p></div><div className="text-right"><p className="text-sm font-bold">{merchant.clicks.toLocaleString()}</p><p className="text-[10px] text-muted-foreground">klik</p></div></div>)}</div></CardContent></Card>
        </div>
        <Card><CardHeader><CardTitle className="text-base">Ringkasan semua iklan</CardTitle></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left text-xs text-muted-foreground"><th className="p-2">Iklan</th><th className="p-2">Merchant</th><th className="p-2">Status</th><th className="p-2 text-right">Impresi</th><th className="p-2 text-right">Klik</th><th className="p-2 text-right">CTR</th><th className="p-2 text-right">Pendapatan</th></tr></thead><tbody>{ads.map(ad => <tr key={ad.id} className="border-b last:border-0"><td className="max-w-[200px] truncate p-2 font-medium">{ad.title}</td><td className="p-2 text-muted-foreground">{ad.merchant?.name || '-'}</td><td className="p-2"><Badge variant={ad.status === 'active' ? 'default' : ad.status === 'rejected' ? 'destructive' : 'secondary'}>{STATUS_LABELS[ad.status] || ad.status}</Badge></td><td className="p-2 text-right">{(ad.view_count || 0).toLocaleString()}</td><td className="p-2 text-right">{(ad.click_count || 0).toLocaleString()}</td><td className="p-2 text-right font-semibold">{(((ad.click_count || 0) / Math.max(ad.view_count || 0, 1)) * 100).toFixed(2)}%</td><td className="p-2 text-right font-medium">{formatPrice(ad.payment_amount)}</td></tr>)}</tbody></table></div></CardContent></Card>
      </div>
    </AdminLayout>
  );
}
