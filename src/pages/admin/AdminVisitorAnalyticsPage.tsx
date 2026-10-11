import { useCallback, useEffect, useMemo, useState } from 'react';
import { Activity, CalendarDays, Download, Eye, Globe2, MapPin, RefreshCw, ShieldCheck, Users } from 'lucide-react';
import { Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, Legend, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { endOfDay, format, startOfDay, subDays } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { downloadCsv } from '@/lib/csv';

type EventRow = {
  id: string; occurred_at: string; path: string; visitor_key: string; ip_address: string | null;
  country_name: string | null; region_name: string | null; city_name: string | null;
  device_type: string; browser_name: string | null; os_name: string | null; referrer: string | null;
};
type DailyPoint = { date: string; views: number; unique: number };
type Ranked = { label: string; views: number; unique: number };
type MonthlyPoint = { month: string; views: number; unique: number };
const number = (value: number) => new Intl.NumberFormat('id-ID').format(value);
const locationLabel = (row: EventRow) => [row.city_name, row.region_name, row.country_name].filter(Boolean).join(', ') || 'Tidak diketahui';
const pieChartColor = (index: number) => `hsl(var(--chart-${(index % 5) + 1}))`;
const formatPieTooltip = (value: number, _name: string, item: { payload: { name: string; unique: number } }) => [`${number(value)} kunjungan · ${number(item.payload.unique)} unik`, item.payload.name];
const maskIp = (ip: string | null) => {
  if (!ip) return 'Tidak diketahui';
  if (ip.includes(':')) return `${ip.split(':').slice(0, 3).join(':')}:…`;
  const parts = ip.split('.');
  return parts.length === 4 ? `${parts[0]}.${parts[1]}.${parts[2]}.x` : 'Disamarkan';
};
export default function AdminVisitorAnalyticsPage() {
  const [days, setDays] = useState('30');
  const [customStart, setCustomStart] = useState('');
  const [customEnd, setCustomEnd] = useState('');
  const [events, setEvents] = useState<EventRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [geographyLevel, setGeographyLevel] = useState<'country' | 'location'>('country');
  const from = useMemo(() => {
    if (days === 'custom' && customStart) return startOfDay(new Date(`${customStart}T00:00:00`));
    return subDays(new Date(), Number(days));
  }, [days, customStart]);
  const to = useMemo(() => {
    if (days === 'custom' && customEnd) return endOfDay(new Date(`${customEnd}T00:00:00`));
    return new Date();
  }, [days, customEnd]);
  const periodDays = useMemo(() => days === 'custom' && customStart && customEnd
    ? Math.max(1, Math.floor((startOfDay(new Date(`${customEnd}T00:00:00`)).getTime() - startOfDay(new Date(`${customStart}T00:00:00`)).getTime()) / 86_400_000) + 1)
    : Number(days), [days, customStart, customEnd]);
  const invalidCustomRange = days === 'custom' && (!customStart || !customEnd || customStart > customEnd);
  const refresh = useCallback(async () => {
    setLoading(true); setError(null);
    if (invalidCustomRange) { setEvents([]); setLoading(false); return; }
    const { data, error: queryError } = await supabase.from('visitor_analytics_events')
      .select('id, occurred_at, path, visitor_key, ip_address, country_name, region_name, city_name, device_type, browser_name, os_name, referrer')
      .gte('occurred_at', from.toISOString()).lt('occurred_at', to.toISOString())
      .order('occurred_at', { ascending: false }).limit(10000);
    if (queryError) setError('Data analitik gagal dimuat. Pastikan migration sudah diterapkan dan akun memiliki akses admin.');
    else { setEvents((data || []) as EventRow[]); setLastUpdated(new Date()); }
    setLoading(false);
  }, [from, to, invalidCustomRange]);
  useEffect(() => { void refresh(); }, [refresh]);
  const daily = useMemo<DailyPoint[]>(() => {
    const map = new Map<string, { views: number; visitors: Set<string> }>();
    for (let i = periodDays - 1; i >= 0; i--) { const key = format(subDays(to, i), 'yyyy-MM-dd'); map.set(key, { views: 0, visitors: new Set() }); }
    events.forEach((event) => { const key = format(new Date(event.occurred_at), 'yyyy-MM-dd'); const item = map.get(key); if (item) { item.views++; item.visitors.add(event.visitor_key); } });
    return [...map.entries()].map(([key, item]) => ({ date: format(new Date(key), 'dd MMM', { locale: idLocale }), views: item.views, unique: item.visitors.size }));
  }, [events, periodDays, to]);
  const rank = useCallback((key: (event: EventRow) => string) => {
    const map = new Map<string, { views: number; visitors: Set<string> }>();
    events.forEach((event) => { const label = key(event); const row = map.get(label) || { views: 0, visitors: new Set<string>() }; row.views++; row.visitors.add(event.visitor_key); map.set(label, row); });
    return [...map.entries()].map(([label, row]) => ({ label, views: row.views, unique: row.visitors.size })).sort((a, b) => b.views - a.views).slice(0, 8);
  }, [events]);
  const topPages = useMemo(() => rank((event) => event.path), [rank]);
  const topLocations = useMemo(() => rank(locationLabel), [rank]);
  const topCountries = useMemo(() => rank((event) => event.country_name || 'Tidak diketahui'), [rank]);
  const topReferrers = useMemo(() => rank((event) => {
    if (!event.referrer) return 'Langsung / tanpa referrer';
    try { return new URL(event.referrer).hostname || event.referrer; } catch { return event.referrer; }
  }), [rank]);
  const uniqueVisitors = useMemo(() => new Set(events.map((event) => event.visitor_key)).size, [events]);
  const todayEvents = useMemo(() => events.filter((event) => new Date(event.occurred_at).toDateString() === new Date().toDateString()), [events]);
  const todayUnique = useMemo(() => new Set(todayEvents.map((event) => event.visitor_key)).size, [todayEvents]);
  const devices = useMemo(() => rank((event) => event.device_type), [rank]);
  const monthly = useMemo<MonthlyPoint[]>(() => {
    const map = new Map<string, { views: number; visitors: Set<string> }>();
    events.forEach((event) => {
      const key = format(new Date(event.occurred_at), 'yyyy-MM');
      const row = map.get(key) || { views: 0, visitors: new Set<string>() };
      row.views++;
      row.visitors.add(event.visitor_key);
      map.set(key, row);
    });
    return [...map.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([key, row]) => ({
      month: format(new Date(`${key}-01T00:00:00`), 'MMM yyyy', { locale: idLocale }),
      views: row.views,
      unique: row.visitors.size,
    }));
  }, [events]);
  const geography = useMemo(() => {
    const rows = geographyLevel === 'country' ? topCountries : topLocations;
    return rows.map((row) => ({ name: row.label, value: row.views, unique: row.unique }));
  }, [geographyLevel, topCountries, topLocations]);
  const exportDetails = () => downloadCsv(`analitik-pengunjung-detail-${format(new Date(), 'yyyyMMdd')}.csv`, [['Waktu', 'Halaman', 'Lokasi', 'IP (disamarkan)', 'Perangkat', 'Browser', 'OS', 'Referrer'], ...events.map((event) => [format(new Date(event.occurred_at), 'dd/MM/yyyy HH:mm:ss'), event.path, locationLabel(event), maskIp(event.ip_address), event.device_type, event.browser_name || '-', event.os_name || '-', event.referrer || '-'])]);
  const exportSummary = () => downloadCsv(`analitik-pengunjung-ringkasan-${format(new Date(), 'yyyyMMdd')}.csv`, [
    ['Periode', `${days} hari terakhir`],
    ['Total page view', events.length],
    ['Pengunjung unik', uniqueVisitors],
    ['Page view hari ini', todayEvents.length],
    ['Pengunjung unik hari ini', todayUnique],
    [],
    ['Halaman populer', 'Page view', 'Pengunjung unik'],
    ...topPages.map((row) => [row.label, row.views, row.unique]),
    [],
    ['Lokasi populer', 'Page view', 'Pengunjung unik'],
    ...topLocations.map((row) => [row.label, row.views, row.unique]),
    [],
    ['Perangkat', 'Page view', 'Pengunjung unik'],
    ...devices.map((row) => [row.label, row.views, row.unique]),
    [],
    ['Sumber kunjungan', 'Page view', 'Pengunjung unik'],
    ...topReferrers.map((row) => [row.label, row.views, row.unique]),
  ]);
  return <AdminLayout title="Analitik Pengunjung" subtitle="Pahami trafik, halaman populer, dan asal pengunjung situs">
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2 text-sm text-muted-foreground"><CalendarDays className="h-4 w-4" /> {days === 'custom' ? (customStart && customEnd ? `Periode ${customStart} sampai ${customEnd}` : 'Pilih rentang tanggal') : `Periode ${days} hari terakhir`} {lastUpdated && `· diperbarui ${lastUpdated.toLocaleTimeString('id-ID')}`}</div>
        <div className="flex flex-wrap items-center gap-2"><Select value={days} onValueChange={setDays}><SelectTrigger className="w-44"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="7">7 hari</SelectItem><SelectItem value="30">30 hari</SelectItem><SelectItem value="90">90 hari</SelectItem><SelectItem value="custom">Rentang kustom</SelectItem></SelectContent></Select>{days === 'custom' && <><label className="flex items-center gap-1 text-xs text-muted-foreground">Dari<input type="date" value={customStart} max={customEnd || undefined} onChange={(event) => setCustomStart(event.target.value)} className="h-9 rounded-md border border-input bg-background px-2 text-sm text-foreground" /></label><label className="flex items-center gap-1 text-xs text-muted-foreground">Sampai<input type="date" value={customEnd} min={customStart || undefined} onChange={(event) => setCustomEnd(event.target.value)} className="h-9 rounded-md border border-input bg-background px-2 text-sm text-foreground" /></label></>}<Button variant="outline" size="sm" onClick={() => void refresh()} disabled={loading || invalidCustomRange}><RefreshCw className={loading ? 'mr-2 h-4 w-4 animate-spin' : 'mr-2 h-4 w-4'} />Refresh</Button><Button variant="outline" size="sm" onClick={exportSummary} disabled={!events.length}><Download className="mr-2 h-4 w-4" />Ringkasan CSV</Button><Button size="sm" onClick={exportDetails} disabled={!events.length}><Download className="mr-2 h-4 w-4" />Detail CSV</Button></div>
      </div>
      {invalidCustomRange && <Card className="border-amber-500/50"><CardContent className="p-4 text-sm text-amber-700">Pilih tanggal mulai dan tanggal akhir yang valid. Tanggal mulai tidak boleh melewati tanggal akhir.</CardContent></Card>}
      {error && <Card className="border-destructive/50"><CardContent className="p-4 text-sm text-destructive">{error}</CardContent></Card>}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card><CardContent className="flex items-center gap-4 p-5"><Eye className="h-5 w-5 text-primary" /><div><p className="text-sm text-muted-foreground">Total page view</p><p className="text-2xl font-semibold">{number(events.length)}</p></div></CardContent></Card>
        <Card><CardContent className="flex items-center gap-4 p-5"><Users className="h-5 w-5 text-emerald-600" /><div><p className="text-sm text-muted-foreground">Pengunjung unik</p><p className="text-2xl font-semibold">{number(uniqueVisitors)}</p></div></CardContent></Card>
        <Card><CardContent className="flex items-center gap-4 p-5"><Activity className="h-5 w-5 text-amber-600" /><div><p className="text-sm text-muted-foreground">Hari ini</p><p className="text-2xl font-semibold">{number(todayEvents.length)}</p><p className="text-xs text-muted-foreground">{number(todayUnique)} pengunjung unik</p></div></CardContent></Card>
        <Card><CardContent className="flex items-center gap-4 p-5"><Globe2 className="h-5 w-5 text-sky-600" /><div><p className="text-sm text-muted-foreground">Negara terbanyak</p><p className="truncate text-lg font-semibold">{topCountries[0]?.label || '—'}</p><p className="text-xs text-muted-foreground">{number(topCountries[0]?.views || 0)} kunjungan</p></div></CardContent></Card>
      </div>
      <Card><CardHeader><CardTitle>Tren trafik harian</CardTitle><CardDescription>Page view dan pengunjung unik berdasarkan waktu lokal browser.</CardDescription></CardHeader><CardContent><div className="h-[280px]">{loading ? <div className="flex h-full items-center justify-center text-sm text-muted-foreground">Memuat data…</div> : <ResponsiveContainer width="100%" height="100%"><AreaChart data={daily}><defs><linearGradient id="visitorViews" x1="0" y1="0" x2="0" y2="1"><stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.35}/><stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0}/></linearGradient></defs><CartesianGrid strokeDasharray="3 3" className="stroke-muted"/><XAxis dataKey="date" fontSize={11} tickLine={false}/><YAxis allowDecimals={false} fontSize={11} tickLine={false}/><Tooltip/><Area type="monotone" dataKey="views" name="Page view" stroke="hsl(var(--primary))" fill="url(#visitorViews)" strokeWidth={2}/><Area type="monotone" dataKey="unique" name="Unik" stroke="hsl(var(--chart-2))" fill="transparent" strokeWidth={2}/></AreaChart></ResponsiveContainer>}</div></CardContent></Card>
      <div className="grid gap-6 lg:grid-cols-2">
        <Card><CardHeader><CardTitle>Tren kunjungan bulanan</CardTitle><CardDescription>Bandingkan page view dan pengunjung unik per bulan. Arahkan kursor ke batang untuk melihat detail.</CardDescription></CardHeader><CardContent><div className="h-[300px]">{monthly.length ? <ResponsiveContainer width="100%" height="100%"><BarChart data={monthly} barGap={8}><CartesianGrid strokeDasharray="3 3" className="stroke-muted"/><XAxis dataKey="month" fontSize={11} tickLine={false}/><YAxis allowDecimals={false} fontSize={11} tickLine={false}/><Tooltip cursor={{ fill: 'hsl(var(--muted))' }} formatter={(value: number, name: string) => [number(value), name === 'views' ? 'Page view' : 'Pengunjung unik']} /><Legend formatter={(value) => value === 'views' ? 'Page view' : 'Pengunjung unik'} /><Bar dataKey="views" name="views" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} /><Bar dataKey="unique" name="unique" fill="hsl(var(--chart-2))" radius={[4, 4, 0, 0]} /></BarChart></ResponsiveContainer> : <div className="flex h-full items-center justify-center text-sm text-muted-foreground">Belum ada data bulanan.</div>}</div></CardContent></Card>
        <Card><CardHeader className="flex flex-row items-start justify-between gap-3"><div><CardTitle>Distribusi geografis</CardTitle><CardDescription>Hover sektor untuk melihat jumlah kunjungan dan pengunjung unik.</CardDescription></div><div className="flex rounded-lg border p-1"><Button type="button" size="sm" variant={geographyLevel === 'country' ? 'secondary' : 'ghost'} onClick={() => setGeographyLevel('country')}>Negara</Button><Button type="button" size="sm" variant={geographyLevel === 'location' ? 'secondary' : 'ghost'} onClick={() => setGeographyLevel('location')}>Kota/wilayah</Button></div></CardHeader><CardContent><div className="h-[300px]">{geography.length ? <ResponsiveContainer width="100%" height="100%"><PieChart><Pie data={geography} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={62} outerRadius={100} paddingAngle={2} labelLine={false} label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}>{geography.map((entry, index) => <Cell key={entry.name} fill={pieChartColor(index)} />)}</Pie><Tooltip formatter={formatPieTooltip} /><Legend /></PieChart></ResponsiveContainer> : <div className="flex h-full items-center justify-center text-sm text-muted-foreground">Belum ada data geografis.</div>}</div></CardContent></Card>
      </div>
      <div className="grid gap-6 lg:grid-cols-2">
        <Card><CardHeader><CardTitle>Ringkasan performa halaman</CardTitle><CardDescription>Halaman dengan trafik terbesar dan jumlah pengunjung uniknya. Hover batang untuk membandingkan performa.</CardDescription></CardHeader><CardContent><div className="h-[320px]">{topPages.length ? <ResponsiveContainer width="100%" height="100%"><BarChart data={topPages} layout="vertical" margin={{ left: 12, right: 12 }}><CartesianGrid strokeDasharray="3 3" className="stroke-muted"/><XAxis type="number" allowDecimals={false} fontSize={11}/><YAxis type="category" dataKey="label" width={130} tickLine={false} fontSize={10} tickFormatter={(value) => value.length > 20 ? `${value.slice(0, 20)}…` : value}/><Tooltip formatter={(value: number, name: string) => [number(value), name === 'views' ? 'Page view' : 'Pengunjung unik']} /><Legend formatter={(value) => value === 'views' ? 'Page view' : 'Pengunjung unik'} /><Bar dataKey="views" name="views" fill="hsl(var(--primary))" radius={[0, 4, 4, 0]} /><Bar dataKey="unique" name="unique" fill="hsl(var(--chart-2))" radius={[0, 4, 4, 0]} /></BarChart></ResponsiveContainer> : <div className="flex h-full items-center justify-center text-sm text-muted-foreground">Belum ada data performa halaman.</div>}</div></CardContent></Card>
        <Card><CardHeader><CardTitle>Sumber kunjungan</CardTitle><CardDescription>Distribusi trafik berdasarkan domain referrer atau kunjungan langsung.</CardDescription></CardHeader><CardContent><div className="h-[320px]">{topReferrers.length ? <ResponsiveContainer width="100%" height="100%"><BarChart data={topReferrers} layout="vertical" margin={{ left: 12, right: 12 }}><CartesianGrid strokeDasharray="3 3" className="stroke-muted"/><XAxis type="number" allowDecimals={false} fontSize={11}/><YAxis type="category" dataKey="label" width={150} tickLine={false} fontSize={10} tickFormatter={(value) => value.length > 24 ? `${value.slice(0, 24)}…` : value}/><Tooltip formatter={(value: number) => [number(value), 'Kunjungan']} /><Bar dataKey="views" name="Kunjungan" fill="hsl(var(--chart-3))" radius={[0, 4, 4, 0]} /></BarChart></ResponsiveContainer> : <div className="flex h-full items-center justify-center text-sm text-muted-foreground">Belum ada data sumber kunjungan.</div>}</div></CardContent></Card>
      </div>
      <div className="grid gap-6 lg:grid-cols-2">
        <RankCard title="Halaman paling sering dikunjungi" icon={<Eye className="h-4 w-4" />} rows={topPages} />
        <RankCard title="Lokasi pengunjung" icon={<MapPin className="h-4 w-4" />} rows={topLocations} />
        <RankCard title="Negara" icon={<Globe2 className="h-4 w-4" />} rows={topCountries} />
        <RankCard title="Perangkat" icon={<Activity className="h-4 w-4" />} rows={devices} />
      </div>
      <Card><CardHeader><CardTitle>Aktivitas terbaru</CardTitle><CardDescription>IP ditampilkan tersamarkan di layar dan CSV untuk mengurangi paparan data pribadi. Data mentah dibatasi untuk admin.</CardDescription></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left text-muted-foreground"><th className="p-2">Waktu</th><th className="p-2">Halaman</th><th className="p-2">Lokasi</th><th className="p-2">IP</th><th className="p-2">Perangkat</th></tr></thead><tbody>{events.slice(0, 20).map((event) => <tr key={event.id} className="border-b last:border-0"><td className="whitespace-nowrap p-2 text-xs text-muted-foreground">{new Date(event.occurred_at).toLocaleString('id-ID')}</td><td className="max-w-[260px] truncate p-2 font-medium">{event.path}</td><td className="p-2">{locationLabel(event)}</td><td className="p-2 font-mono text-xs">{maskIp(event.ip_address)}</td><td className="p-2"><Badge variant="secondary">{event.device_type}</Badge></td></tr>)}{!events.length && !loading && <tr><td colSpan={5} className="p-8 text-center text-muted-foreground">Belum ada data dalam periode ini.</td></tr>}</tbody></table></div></CardContent></Card>
      <div className="flex items-start gap-3 rounded-xl border bg-muted/30 p-4 text-xs text-muted-foreground"><ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-primary" /><p><strong className="text-foreground">Catatan privasi:</strong> lokasi dari IP bersifat perkiraan dan tidak sama dengan alamat rumah. IP disimpan untuk kebutuhan keamanan dan analitik, dibatasi retensi 90 hari, serta hanya dapat dibaca oleh admin.</p></div>
    </div>
  </AdminLayout>;
}
function RankCard({ title, icon, rows }: { title: string; icon: React.ReactNode; rows: Ranked[] }) { return <Card><CardHeader className="pb-3"><CardTitle className="flex items-center gap-2 text-base">{icon}{title}</CardTitle></CardHeader><CardContent className="space-y-3">{rows.length ? rows.map((row, index) => <div key={row.label} className="flex items-center gap-3"><span className="w-5 text-xs text-muted-foreground">{index + 1}</span><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{row.label}</p><p className="text-xs text-muted-foreground">{number(row.unique)} unik</p></div><span className="text-sm font-semibold">{number(row.views)}</span></div>) : <p className="py-5 text-center text-sm text-muted-foreground">Belum ada data.</p>}</CardContent></Card>; }
