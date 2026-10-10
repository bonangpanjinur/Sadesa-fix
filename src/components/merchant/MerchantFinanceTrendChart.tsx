import { useMemo, useState } from 'react';
import { BarChart3, CalendarDays, TrendingUp } from 'lucide-react';
import { format, startOfWeek } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { formatPrice } from '@/lib/utils';

type FinanceOrder = { id: string; total: number | null; subtotal: number | null; status: string; payment_status: string | null; created_at: string };
type TrendMode = 'daily' | 'weekly';
const DONE_STATUSES = ['DONE', 'DELIVERED', 'COMPLETED'];
const amount = (value: number | null | undefined) => Number(value ?? 0);

export function MerchantFinanceTrendChart({ orders }: { orders: FinanceOrder[] }) {
  const [mode, setMode] = useState<TrendMode>('daily');
  const trend = useMemo(() => {
    const completed = orders.filter((order) => DONE_STATUSES.includes(order.status) && order.payment_status !== 'REFUNDED');
    const buckets = new Map<string, { label: string; revenue: number; orders: number; sort: number }>();
    completed.forEach((order) => {
      const date = new Date(order.created_at);
      const bucketDate = mode === 'weekly' ? startOfWeek(date, { weekStartsOn: 1 }) : date;
      const key = format(bucketDate, 'yyyy-MM-dd');
      const current = buckets.get(key) ?? { label: '', revenue: 0, orders: 0, sort: bucketDate.getTime() };
      current.label = mode === 'weekly' ? `Minggu ${format(bucketDate, 'd MMM', { locale: idLocale })}` : format(bucketDate, 'd MMM', { locale: idLocale });
      current.revenue += amount(order.subtotal || order.total);
      current.orders += 1;
      buckets.set(key, current);
    });
    return [...buckets.values()].sort((a, b) => a.sort - b.sort);
  }, [mode, orders]);
  const total = trend.reduce((sum, item) => sum + item.revenue, 0);
  const peak = trend.reduce((best, item) => item.revenue > best.revenue ? item : best, { label: '-', revenue: 0, orders: 0, sort: 0 });

  return <Card className="border-border/70 shadow-sm"><CardHeader className="gap-4 md:flex-row md:items-start md:justify-between"><div><div className="flex items-center gap-2"><div className="rounded-xl bg-blue-100 p-2 text-blue-700 dark:bg-blue-950/50 dark:text-blue-300"><BarChart3 className="h-4 w-4" /></div><div><CardTitle className="text-base">Tren pendapatan</CardTitle><CardDescription>Pergerakan omzet produk dari transaksi selesai.</CardDescription></div></div></div><div className="flex items-center gap-1 rounded-lg bg-muted p-1"><Button type="button" size="sm" variant={mode === 'daily' ? 'default' : 'ghost'} className="h-8 px-3" onClick={() => setMode('daily')}><CalendarDays className="mr-1.5 h-3.5 w-3.5" />Harian</Button><Button type="button" size="sm" variant={mode === 'weekly' ? 'default' : 'ghost'} className="h-8 px-3" onClick={() => setMode('weekly')}><CalendarDays className="mr-1.5 h-3.5 w-3.5" />Mingguan</Button></div></CardHeader><CardContent><div className="mb-4 flex flex-wrap items-center gap-3"><Badge variant="secondary">{trend.length} periode</Badge><span className="text-xs text-muted-foreground">Total {formatPrice(total)}</span>{peak.revenue > 0 && <span className="flex items-center gap-1 text-xs text-muted-foreground"><TrendingUp className="h-3.5 w-3.5 text-emerald-600" />Puncak {peak.label}: {formatPrice(peak.revenue)}</span>}</div>{trend.length === 0 ? <div className="flex h-64 items-center justify-center rounded-xl border border-dashed text-sm text-muted-foreground">Belum ada pendapatan selesai pada periode ini.</div> : <ResponsiveContainer width="100%" height={280}><AreaChart data={trend} margin={{ top: 8, right: 8, left: 8, bottom: 4 }}><defs><linearGradient id="merchantRevenueGradient" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#10b981" stopOpacity={0.35} /><stop offset="100%" stopColor="#10b981" stopOpacity={0.03} /></linearGradient></defs><CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-border" /><XAxis dataKey="label" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} /><YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} tickFormatter={(value: number) => value >= 1000000 ? `${(value / 1000000).toFixed(1)}jt` : `${Math.round(value / 1000)}k`} /><Tooltip formatter={(value: number, name: string) => [name === 'Pendapatan' ? formatPrice(value) : `${value} pesanan`, name]} labelFormatter={(label) => `${label}`} contentStyle={{ borderRadius: 12, border: '1px solid hsl(var(--border))', background: 'hsl(var(--card))' }} /><Area type="monotone" dataKey="revenue" name="Pendapatan" stroke="#10b981" strokeWidth={2.5} fill="url(#merchantRevenueGradient)" activeDot={{ r: 5 }} /><Area type="monotone" dataKey="orders" name="Pesanan" stroke="#3b82f6" strokeWidth={1.5} fill="none" strokeDasharray="5 5" yAxisId={0} /></AreaChart></ResponsiveContainer>}</CardContent></Card>;
}
