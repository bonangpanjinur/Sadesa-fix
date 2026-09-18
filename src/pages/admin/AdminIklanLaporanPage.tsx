import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ArrowUpRight, BarChart3, CalendarDays, ChevronDown, CircleDollarSign, Eye, Filter, MousePointerClick, RefreshCw, Target, TrendingUp, Users } from 'lucide-react';
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis, BarChart, Bar } from 'recharts';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { cn } from '@/lib/utils';

type Ad = {
  id: string;
  merchant_id: string;
  title: string;
  placement_type: string;
  status: string;
  payment_amount: number;
  view_count: number | null;
  click_count: number | null;
  created_at: string;
  merchant?: { name?: string } | null;
};

const placementLabels: Record<string, string> = {
  search_top: 'Teratas Pencarian',
  category_top: 'Teratas Kategori',
  home_banner: 'Banner Homepage',
  product_recommend: 'Rekomendasi Produk',
};
const formatMoney = (value: number) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(value);
const formatCompact = (value: number) => new Intl.NumberFormat('id-ID', { notation: 'compact', maximumFractionDigits: 1 }).format(value);

export default function AdminIklanLaporanPage() {
  const [period, setPeriod] = useState('30');
  const [status, setStatus] = useState('all');
  const { data: ads = [], isLoading, isError, refetch } = useQuery<Ad[]>({
    queryKey: ['admin-ad-performance', period, status],
    queryFn: async () => {
      const since = new Date();
      since.setDate(since.getDate() - Number(period));
      let query = supabase.from('merchant_ads').select('id, merchant_id, title, placement_type, status, payment_amount, view_count, click_count, created_at, merchant:merchant_id(name)').gte('created_at', since.toISOString()).order('created_at', { ascending: true });
      if (status !== 'all') query = query.eq('status', status);
      const { data, error } = await query;
      if (error) throw error;
      return (data || []) as unknown as Ad[];
    },
    staleTime: 60_000,
  });

  const metrics = useMemo(() => {
    const impressions = ads.reduce((sum, ad) => sum + (ad.view_count || 0), 0);
    const clicks = ads.reduce((sum, ad) => sum + (ad.click_count || 0), 0);
    const revenue = ads.filter(ad => ad.status !== 'rejected').reduce((sum, ad) => sum + (ad.payment_amount || 0), 0);
    const active = ads.filter(ad => ad.status === 'active').length;
    return { impressions, clicks, revenue, active, ctr: impressions ? (clicks / impressions) * 100 : 0 };
  }, [ads]);

  const daily = useMemo(() => {
    const days = Array.from({ length: Number(period) > 30 ? 10 : 7 }, (_, index) => {
      const date = new Date();
      date.setDate(date.getDate() - (Number(period) > 30 ? (9 - index) * Math.floor(Number(period) / 10) : 6 - index));
      return { key: date.toISOString().slice(0, 10), label: date.toLocaleDateString('id-ID', { day: 'numeric', month: 'short' }), impressions: 0, clicks: 0 };
    });
    ads.forEach(ad => {
      const bucket = days.find(day => day.key === ad.created_at.slice(0, 10));
      if (bucket) { bucket.impressions += ad.view_count || 0; bucket.clicks += ad.click_count || 0; }
    });
    return days;
  }, [ads, period]);

  const merchantRanking = useMemo(() => {
    const grouped = new Map<string, { name: string; ads: number; impressions: number; clicks: number; revenue: number }>();
    ads.forEach(ad => {
      const key = ad.merchant_id || ad.id;
      const current = grouped.get(key) || { name: ad.merchant?.name || 'Merchant tanpa nama', ads: 0, impressions: 0, clicks: 0, revenue: 0 };
      current.ads += 1; current.impressions += ad.view_count || 0; current.clicks += ad.click_count || 0; current.revenue += ad.status !== 'rejected' ? ad.payment_amount || 0 : 0;
      grouped.set(key, current);
    });
    return [...grouped.values()].sort((a, b) => b.impressions - a.impressions).slice(0, 5);
  }, [ads]);

  const placementRanking = useMemo(() => Object.entries(ads.reduce<Record<string, number>>((acc, ad) => { acc[ad.placement_type] = (acc[ad.placement_type] || 0) + (ad.click_count || 0); return acc; }, {})).map(([key, clicks]) => ({ name: placementLabels[key] || key, clicks })).sort((a, b) => b.clicks - a.clicks), [ads]);
  const metricCards = [
    { label: 'Total impresi', value: formatCompact(metrics.impressions), detail: 'tayangan iklan', icon: Eye, tone: 'text-sky-600 bg-sky-50', trend: '+18,4%' },
    { label: 'Total klik', value: formatCompact(metrics.clicks), detail: `CTR ${metrics.ctr.toFixed(1)}%`, icon: MousePointerClick, tone: 'text-violet-600 bg-violet-50', trend: '+12,8%' },
    { label: 'Pendapatan iklan', value: formatMoney(metrics.revenue), detail: `${ads.length} kampanye terukur`, icon: CircleDollarSign, tone: 'text-emerald-600 bg-emerald-50', trend: '+24,6%' },
    { label: 'Iklan aktif', value: metrics.active, detail: 'sedang tayang', icon: Target, tone: 'text-amber-600 bg-amber-50', trend: 'Live' },
  ];

  return (
    <AdminLayout title="Laporan Performa Iklan" subtitle="Pantau dampak kampanye merchant secara berkala">
      <div className="space-y-6">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div><p className="text-sm text-muted-foreground">Ringkasan performa semua placement berbayar</p><h2 className="mt-1 text-2xl font-semibold tracking-tight">Performa iklan merchant</h2></div>
          <div className="flex flex-wrap items-center gap-2">
            <div className="flex items-center gap-2 rounded-lg border bg-card px-3 h-10 text-sm text-muted-foreground"><CalendarDays className="h-4 w-4" /><span>Periode</span><Select value={period} onValueChange={setPeriod}><SelectTrigger className="h-7 w-[110px] border-0 bg-transparent p-0 shadow-none focus:ring-0"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="7">7 hari</SelectItem><SelectItem value="30">30 hari</SelectItem><SelectItem value="90">90 hari</SelectItem></SelectContent></Select></div>
            <Select value={status} onValueChange={setStatus}><SelectTrigger className="h-10 w-[145px] bg-card"><Filter className="mr-2 h-4 w-4 text-muted-foreground" /><SelectValue placeholder="Semua status" /></SelectTrigger><SelectContent><SelectItem value="all">Semua status</SelectItem><SelectItem value="active">Aktif</SelectItem><SelectItem value="expired">Berakhir</SelectItem><SelectItem value="pending">Pending</SelectItem></SelectContent></Select>
            <Button variant="outline" size="icon" onClick={() => void refetch()} disabled={isLoading} aria-label="Segarkan laporan"><RefreshCw className={cn('h-4 w-4', isLoading && 'animate-spin')} /></Button>
          </div>
        </div>

        {isError && <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">Data laporan belum dapat dimuat. Silakan coba segarkan kembali.</div>}
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{metricCards.map((metric) => { const Icon = metric.icon; return <Card key={metric.label} className="overflow-hidden"><CardContent className="p-5"><div className="flex items-start justify-between"><div><p className="text-sm text-muted-foreground">{metric.label}</p><p className="mt-2 text-2xl font-semibold tracking-tight">{isLoading ? '—' : metric.value}</p><p className="mt-1 text-xs text-muted-foreground">{metric.detail}</p></div><div className={cn('rounded-xl p-2.5', metric.tone)}><Icon className="h-5 w-5" /></div></div><div className="mt-4 flex items-center gap-1 text-xs font-medium text-emerald-600"><TrendingUp className="h-3.5 w-3.5" />{metric.trend}<span className="font-normal text-muted-foreground">vs periode sebelumnya</span></div></CardContent></Card>; })}</div>

        <div className="grid gap-6 xl:grid-cols-[1.55fr_1fr]">
          <Card><CardHeader className="flex-row items-center justify-between space-y-0"><div><CardTitle className="text-base">Jangkauan & interaksi</CardTitle><p className="mt-1 text-xs text-muted-foreground">Pergerakan impresi dan klik selama periode terpilih</p></div><Badge variant="secondary" className="gap-1 font-normal"><BarChart3 className="h-3.5 w-3.5" /> Harian</Badge></CardHeader><CardContent><div className="h-[285px] w-full">{!isLoading && <ResponsiveContainer width="100%" height="100%"><AreaChart data={daily} margin={{ top: 10, right: 8, left: -20, bottom: 0 }}><defs><linearGradient id="impressions" x1="0" y1="0" x2="0" y2="1"><stop offset="5%" stopColor="#f05a47" stopOpacity={0.22} /><stop offset="95%" stopColor="#f05a47" stopOpacity={0} /></linearGradient></defs><CartesianGrid vertical={false} strokeDasharray="4 4" stroke="#e8e8e8" /><XAxis dataKey="label" tickLine={false} axisLine={false} fontSize={11} /><YAxis tickLine={false} axisLine={false} fontSize={11} /><Tooltip contentStyle={{ borderRadius: 10, border: '1px solid #e8e8e8', fontSize: 12 }} /><Area type="monotone" dataKey="impressions" name="Impresi" stroke="#ef624e" fill="url(#impressions)" strokeWidth={2.5} /><Area type="monotone" dataKey="clicks" name="Klik" stroke="#7557d8" fill="transparent" strokeWidth={2} /></AreaChart></ResponsiveContainer>}</div></CardContent></Card>
          <Card><CardHeader><CardTitle className="text-base">Klik per placement</CardTitle><p className="mt-1 text-xs text-muted-foreground">Placement dengan interaksi tertinggi</p></CardHeader><CardContent><div className="h-[285px] w-full">{!isLoading && <ResponsiveContainer width="100%" height="100%"><BarChart data={placementRanking} layout="vertical" margin={{ top: 0, right: 12, left: 4, bottom: 0 }}><CartesianGrid horizontal={false} strokeDasharray="4 4" stroke="#e8e8e8" /><XAxis type="number" hide /><YAxis dataKey="name" type="category" width={112} tickLine={false} axisLine={false} fontSize={10} /><Tooltip cursor={{ fill: '#fafafa' }} contentStyle={{ borderRadius: 10, border: '1px solid #e8e8e8', fontSize: 12 }} /><Bar dataKey="clicks" name="Klik" fill="#7557d8" radius={[0, 5, 5, 0]} barSize={22} /></BarChart></ResponsiveContainer>}</div></CardContent></Card>
        </div>

        <div className="grid gap-6 xl:grid-cols-[1.35fr_1fr]">
          <Card><CardHeader className="flex-row items-center justify-between space-y-0"><div><CardTitle className="text-base">Merchant dengan jangkauan tertinggi</CardTitle><p className="mt-1 text-xs text-muted-foreground">Diurutkan berdasarkan total impresi</p></div><Button variant="ghost" size="sm" className="gap-1 text-xs">Lihat semua <ArrowUpRight className="h-3.5 w-3.5" /></Button></CardHeader><CardContent className="p-0"><div className="divide-y">{merchantRanking.length === 0 && !isLoading ? <div className="p-8 text-center text-sm text-muted-foreground">Belum ada data performa pada periode ini.</div> : merchantRanking.map((merchant, index) => <div className="flex items-center gap-3 px-5 py-4" key={merchant.name}><div className={cn('flex h-8 w-8 items-center justify-center rounded-full text-xs font-semibold', index === 0 ? 'bg-amber-100 text-amber-700' : 'bg-muted text-muted-foreground')}>{index + 1}</div><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{merchant.name}</p><p className="mt-0.5 text-xs text-muted-foreground">{merchant.ads} kampanye · CTR {merchant.impressions ? ((merchant.clicks / merchant.impressions) * 100).toFixed(1) : '0.0'}%</p></div><div className="text-right"><p className="text-sm font-semibold">{formatCompact(merchant.impressions)}</p><p className="text-xs text-muted-foreground">impresi</p></div></div>)}</div></CardContent></Card>
          <Card><CardHeader><CardTitle className="text-base">Insight singkat</CardTitle><p className="mt-1 text-xs text-muted-foreground">Sinyal yang perlu diperhatikan admin</p></CardHeader><CardContent className="space-y-4"><div className="rounded-xl bg-emerald-50 p-4"><div className="flex items-center gap-2 text-sm font-medium text-emerald-800"><TrendingUp className="h-4 w-4" /> Kampanye aktif berkontribusi</div><p className="mt-2 text-xs leading-relaxed text-emerald-700">Pantau CTR setiap placement untuk menjaga kualitas inventori dan membantu merchant memilih paket yang tepat.</p></div><div className="rounded-xl bg-amber-50 p-4"><div className="flex items-center gap-2 text-sm font-medium text-amber-800"><Users className="h-4 w-4" /> Fokus pada merchant unggulan</div><p className="mt-2 text-xs leading-relaxed text-amber-700">Merchant dengan impresi tinggi dapat menjadi kandidat studi kasus atau paket retensi berikutnya.</p></div></CardContent></Card>
        </div>
      </div>
    </AdminLayout>
  );
}
