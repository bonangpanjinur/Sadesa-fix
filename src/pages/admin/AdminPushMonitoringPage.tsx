import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Activity, AlertTriangle, CheckCircle2, Clock3, ExternalLink, Loader2, RefreshCw, Smartphone, XCircle } from 'lucide-react';
import { Link } from 'react-router-dom';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import { CartesianGrid, Legend, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import {
  buildPushDeliveryHourlyTrend,
  calculatePushDeliveryKpis,
  type PushDeliveryCounts,
  type PushDeliveryHourlyStat,
} from '@/lib/adminPushMonitoring';

interface PushDeliveryLog {
  id: string;
  created_at: string;
  source: 'admin_test' | 'admin_broadcast' | 'queue';
  recipient_user_id: string | null;
  title: string;
  status: 'sent' | 'failed' | 'expired';
  provider_status_code: number | null;
  error_message: string | null;
}

type TimeRange = '24h' | '7d' | '30d';
type StatusFilter = 'all' | PushDeliveryLog['status'];
type RealtimeStatus = 'connecting' | 'connected' | 'disconnected';

const rangeLabels: Record<TimeRange, string> = {
  '24h': '24 jam terakhir',
  '7d': '7 hari terakhir',
  '30d': '30 hari terakhir',
};

const rangeMilliseconds: Record<TimeRange, number> = {
  '24h': 24 * 60 * 60 * 1000,
  '7d': 7 * 24 * 60 * 60 * 1000,
  '30d': 30 * 24 * 60 * 60 * 1000,
};

const statusLabels: Record<PushDeliveryLog['status'], string> = {
  sent: 'Diterima layanan push',
  failed: 'Gagal',
  expired: 'Subscription kedaluwarsa',
};

const sourceLabels: Record<PushDeliveryLog['source'], string> = {
  admin_test: 'Test admin',
  admin_broadcast: 'Broadcast admin',
  queue: 'Antrean aplikasi',
};

function formatDateTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Waktu tidak tersedia';
  return new Intl.DateTimeFormat('id-ID', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

function formatUtcDateTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Waktu tidak tersedia';
  return new Intl.DateTimeFormat('id-ID', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'UTC',
  }).format(date);
}

function formatCount(value: number | null | undefined): string {
  return typeof value === 'number' ? value.toLocaleString('id-ID') : '—';
}

export default function AdminPushMonitoringPage() {
  const [timeRange, setTimeRange] = useState<TimeRange>('24h');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [counts, setCounts] = useState<PushDeliveryCounts | null>(null);
  const [hourlyStats, setHourlyStats] = useState<PushDeliveryHourlyStat[]>([]);
  const [hourlyWindow, setHourlyWindow] = useState<{ since: Date; until: Date } | null>(null);
  const [hourlyError, setHourlyError] = useState<string | null>(null);
  const [subscriberCount, setSubscriberCount] = useState<number | null>(null);
  const [logs, setLogs] = useState<PushDeliveryLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [realtimeStatus, setRealtimeStatus] = useState<RealtimeStatus>('connecting');
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    const until = new Date();
    const since = new Date(until.getTime() - rangeMilliseconds[timeRange]);
    const from = since.toISOString();
    try {
      const [totalResult, sentResult, failedResult, expiredResult, subscriberResult, logsResult, hourlyResult] = await Promise.all([
        supabase.from('push_delivery_logs').select('id', { count: 'exact', head: true }).gte('created_at', from),
        supabase.from('push_delivery_logs').select('id', { count: 'exact', head: true }).gte('created_at', from).eq('status', 'sent'),
        supabase.from('push_delivery_logs').select('id', { count: 'exact', head: true }).gte('created_at', from).eq('status', 'failed'),
        supabase.from('push_delivery_logs').select('id', { count: 'exact', head: true }).gte('created_at', from).eq('status', 'expired'),
        supabase.from('push_subscriptions').select('id', { count: 'exact', head: true }),
        supabase.from('push_delivery_logs')
          .select('id, created_at, source, recipient_user_id, title, status, provider_status_code, error_message')
          .gte('created_at', from)
          .order('created_at', { ascending: false })
          .limit(100),
        supabase.rpc('get_push_delivery_hourly_stats', { p_since: from, p_until: until.toISOString() }),
      ]);

      const failedRequest = [totalResult, sentResult, failedResult, expiredResult, logsResult]
        .find((result) => result.error);
      if (failedRequest?.error) throw failedRequest.error;

      setCounts({
        total: totalResult.count ?? 0,
        sent: sentResult.count ?? 0,
        failed: failedResult.count ?? 0,
        expired: expiredResult.count ?? 0,
      });
      setSubscriberCount(subscriberResult.error ? null : subscriberResult.count ?? 0);
      setLogs((logsResult.data ?? []) as PushDeliveryLog[]);
      if (hourlyResult.error) {
        setHourlyStats([]);
        setHourlyWindow(null);
        setHourlyError('Agregasi grafik belum tersedia. Pastikan migration statistik per jam sudah diterapkan.');
      } else {
        setHourlyStats((hourlyResult.data ?? []) as PushDeliveryHourlyStat[]);
        setHourlyWindow({ since, until });
        setHourlyError(null);
      }
      setLastUpdated(new Date());
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Data pemantauan push belum dapat dimuat.');
    } finally {
      setLoading(false);
    }
  }, [timeRange]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    const channel = supabase
      .channel('admin-push-monitoring')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'push_delivery_logs',
      }, (payload) => {
        const incoming = payload.new as PushDeliveryLog;
        setLogs((current) => [incoming, ...current.filter((row) => row.id !== incoming.id)]
          .sort((left, right) => Date.parse(right.created_at) - Date.parse(left.created_at))
          .slice(0, 100));
        void refresh();
      })
      .subscribe((status) => {
        const connected = status === 'SUBSCRIBED';
        const disconnected = status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED';
        setRealtimeStatus(connected ? 'connected' : disconnected ? 'disconnected' : 'connecting');
        if (connected) void refresh();
      });

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [refresh]);

  const kpis = useMemo(() => counts ? calculatePushDeliveryKpis(counts) : null, [counts]);
  const visibleLogs = useMemo(() => statusFilter === 'all'
    ? logs
    : logs.filter((log) => log.status === statusFilter), [logs, statusFilter]);
  const hourlyTrend = useMemo(() => hourlyWindow
    ? buildPushDeliveryHourlyTrend(hourlyStats, hourlyWindow.since, hourlyWindow.until)
    : [], [hourlyStats, hourlyWindow]);
  const hourlyChartData = useMemo(() => hourlyTrend.map((point) => ({
    ...point,
    tickLabel: new Intl.DateTimeFormat('id-ID', timeRange === '24h'
      ? { hour: '2-digit', timeZone: 'UTC', hourCycle: 'h23' }
      : { day: '2-digit', month: 'short', hour: '2-digit', timeZone: 'UTC', hourCycle: 'h23' }).format(new Date(point.hour)),
  })), [hourlyTrend, timeRange]);
  const chartTickInterval = timeRange === '24h' ? 3 : timeRange === '7d' ? 12 : 48;
  const maxCount = Math.max(counts?.sent ?? 0, counts?.failed ?? 0, counts?.expired ?? 0, 1);

  return (
    <AdminLayout title="Monitor Push" subtitle="Pantau status dan kesehatan pengiriman notifikasi push">
      <div className="mx-auto max-w-7xl space-y-6">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant={realtimeStatus === 'connected' ? 'default' : 'secondary'} className="gap-1.5">
              <span className={`h-2 w-2 rounded-full ${realtimeStatus === 'connected' ? 'bg-emerald-400' : realtimeStatus === 'disconnected' ? 'bg-destructive' : 'animate-pulse bg-amber-400'}`} />
              {realtimeStatus === 'connected' ? 'Realtime aktif' : realtimeStatus === 'disconnected' ? 'Realtime terputus' : 'Menghubungkan realtime'}
            </Badge>
            <span className="text-xs text-muted-foreground">
              {lastUpdated ? `Diperbarui ${formatDateTime(lastUpdated.toISOString())}` : 'Belum diperbarui'}
            </span>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <label className="sr-only" htmlFor="push-monitor-range">Periode pemantauan</label>
            <select
              id="push-monitor-range"
              value={timeRange}
              onChange={(event) => {
                setCounts(null);
                setHourlyStats([]);
                setHourlyWindow(null);
                setHourlyError(null);
                setLogs([]);
                setTimeRange(event.target.value as TimeRange);
              }}
              className="h-9 rounded-md border border-input bg-background px-3 text-sm"
            >
              {(Object.keys(rangeLabels) as TimeRange[]).map((range) => <option key={range} value={range}>{rangeLabels[range]}</option>)}
            </select>
            <Button type="button" variant="outline" size="sm" onClick={() => void refresh()} disabled={loading}>
              {loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <RefreshCw className="mr-2 h-4 w-4" />}
              Segarkan
            </Button>
            <Button asChild size="sm" variant="outline">
              <Link to="/admin/push-notification"><ExternalLink className="mr-2 h-4 w-4" />Pengaturan Push</Link>
            </Button>
          </div>
        </div>

        {error && (
          <div role="alert" className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
            <div><p className="font-medium">Gagal memuat status pengiriman</p><p className="mt-1 break-words">{error}</p></div>
          </div>
        )}

        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <MetricCard icon={<Activity className="h-5 w-5 text-sky-600" />} label={`Total percobaan · ${rangeLabels[timeRange]}`} value={formatCount(counts?.total)} detail="Percobaan Web Push yang tercatat" />
          <MetricCard icon={<CheckCircle2 className="h-5 w-5 text-emerald-600" />} label="Diterima layanan push" value={formatCount(counts?.sent)} detail={kpis ? `${kpis.successRate}% dari total percobaan` : 'Menghitung rasio keberhasilan'} />
          <MetricCard icon={<XCircle className="h-5 w-5 text-rose-600" />} label="Gagal / subscription kedaluwarsa" value={formatCount(kpis?.issueCount)} detail={counts ? `${formatCount(counts.failed)} gagal · ${formatCount(counts.expired)} kedaluwarsa` : 'Menunggu data status'} />
          <MetricCard icon={<Smartphone className="h-5 w-5 text-violet-600" />} label="Perangkat berlangganan" value={formatCount(subscriberCount)} detail="Subscription push yang tersimpan" />
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Activity className="h-5 w-5 text-primary" />Tren pengiriman per jam</CardTitle>
            <CardDescription>Jumlah percobaan push per jam selama {rangeLabels[timeRange]}, berdasarkan waktu UTC pada log server.</CardDescription>
          </CardHeader>
          <CardContent>
            {hourlyError && <p role="alert" className="mb-3 rounded-md border border-amber-500/30 bg-amber-500/5 p-3 text-sm text-amber-800">{hourlyError}</p>}
            {!hourlyError && hourlyChartData.length === 0 && (
              <p role="status" className="py-12 text-center text-sm text-muted-foreground">{loading ? 'Memuat tren per jam...' : 'Data grafik belum tersedia.'}</p>
            )}
            {!hourlyError && hourlyChartData.length > 0 && (
              <>
                {counts?.total === 0 && !loading && <p className="mb-3 text-sm text-muted-foreground">Belum ada percobaan pengiriman pada periode ini; grafik menunjukkan nol per jam.</p>}
                <div className="h-[320px] w-full" aria-label="Grafik tren pengiriman push per jam">
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={hourlyChartData} margin={{ top: 8, right: 16, left: 0, bottom: 4 }}>
                      <CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-muted" />
                      <XAxis dataKey="tickLabel" interval={chartTickInterval} minTickGap={12} tickLine={false} axisLine={false} fontSize={11} className="fill-muted-foreground" />
                      <YAxis allowDecimals={false} width={40} tickLine={false} axisLine={false} fontSize={11} className="fill-muted-foreground" />
                      <Tooltip
                        labelFormatter={(_, payload) => {
                          const hour = payload?.[0]?.payload?.hour;
                          return typeof hour === 'string' ? formatUtcDateTime(hour) : '';
                        }}
                        formatter={(value, name) => [Number(value).toLocaleString('id-ID'), statusLabels[String(name) as PushDeliveryLog['status']] ?? String(name)]}
                        contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))', borderRadius: '8px' }}
                      />
                      <Legend formatter={(value) => statusLabels[String(value) as PushDeliveryLog['status']] ?? String(value)} />
                      <Line type="monotone" dataKey="sent" name="sent" stroke="hsl(var(--chart-2))" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                      <Line type="monotone" dataKey="failed" name="failed" stroke="hsl(var(--destructive))" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                      <Line type="monotone" dataKey="expired" name="expired" stroke="hsl(var(--chart-4))" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              </>
            )}
          </CardContent>
        </Card>

        <div className="grid gap-6 xl:grid-cols-[minmax(0,1.3fr)_minmax(320px,0.7fr)]">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2"><Activity className="h-5 w-5 text-primary" />Ringkasan status</CardTitle>
              <CardDescription>Rincian status pengiriman pada {rangeLabels[timeRange]}.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
              <StatusSummary label="Diterima layanan push" value={counts?.sent ?? null} max={maxCount} color="bg-emerald-500" />
              <StatusSummary label="Gagal" value={counts?.failed ?? null} max={maxCount} color="bg-rose-500" />
              <StatusSummary label="Subscription kedaluwarsa" value={counts?.expired ?? null} max={maxCount} color="bg-amber-500" />
              <p className="rounded-md bg-muted/50 p-3 text-xs leading-relaxed text-muted-foreground">
                “Diterima layanan push” berarti provider browser menerima permintaan pengiriman; status ini tidak membuktikan notifikasi tampil atau dibaca di perangkat pengguna.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2"><Clock3 className="h-5 w-5 text-primary" />Kesehatan pemantauan</CardTitle>
              <CardDescription>Indikator operasional untuk administrator.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <HealthRow label="Koneksi log realtime" value={realtimeStatus === 'connected' ? 'Terhubung' : realtimeStatus === 'disconnected' ? 'Terputus' : 'Menghubungkan'} healthy={realtimeStatus === 'connected'} />
              <HealthRow label="Rasio diterima provider" value={counts?.total ? `${kpis?.successRate ?? 0}%` : 'Belum ada data'} healthy={!counts?.total || (kpis?.successRate ?? 0) >= 90} />
              <HealthRow label="Subscription kedaluwarsa" value={formatCount(counts?.expired)} healthy={counts === null || counts.expired === 0} />
              {counts && counts.total === 0 && !loading && !error && (
                <p className="rounded-md border border-dashed p-3 text-sm text-muted-foreground">Belum ada percobaan pengiriman dalam periode ini.</p>
              )}
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <CardTitle className="flex items-center gap-2"><Activity className="h-5 w-5 text-primary" />Percobaan pengiriman terbaru</CardTitle>
              <CardDescription>Hingga 100 percobaan terbaru dalam periode yang dipilih. Data mengikuti kebijakan akses admin database.</CardDescription>
            </div>
            <label className="sr-only" htmlFor="push-monitor-status">Filter status</label>
            <select
              id="push-monitor-status"
              value={statusFilter}
              onChange={(event) => setStatusFilter(event.target.value as StatusFilter)}
              className="h-9 rounded-md border border-input bg-background px-3 text-sm"
            >
              <option value="all">Semua status</option>
              <option value="sent">Diterima layanan push</option>
              <option value="failed">Gagal</option>
              <option value="expired">Kedaluwarsa</option>
            </select>
          </CardHeader>
          <CardContent>
            {loading && logs.length === 0 && <p role="status" className="py-8 text-center text-sm text-muted-foreground">Memuat riwayat pengiriman...</p>}
            {!loading && !error && visibleLogs.length === 0 && (
              <p className="py-8 text-center text-sm text-muted-foreground">
                {logs.length === 0 ? 'Belum ada percobaan pengiriman push dalam periode ini.' : 'Tidak ada percobaan dengan status tersebut.'}
              </p>
            )}
            {visibleLogs.length > 0 && (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[760px] text-left text-sm">
                  <thead>
                    <tr className="border-b text-xs text-muted-foreground">
                      <th className="px-3 py-2 font-medium">Waktu</th>
                      <th className="px-3 py-2 font-medium">Notifikasi</th>
                      <th className="px-3 py-2 font-medium">Sumber</th>
                      <th className="px-3 py-2 font-medium">Penerima</th>
                      <th className="px-3 py-2 font-medium">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {visibleLogs.map((log) => (
                      <tr key={log.id} className="border-b last:border-0 align-top">
                        <td className="whitespace-nowrap px-3 py-3 text-xs text-muted-foreground">{formatDateTime(log.created_at)}</td>
                        <td className="max-w-[280px] px-3 py-3">
                          <p className="break-words font-medium">{log.title}</p>
                          {log.error_message && <p className="mt-1 break-words text-xs text-destructive">{log.error_message}</p>}
                        </td>
                        <td className="whitespace-nowrap px-3 py-3 text-xs">{sourceLabels[log.source]}</td>
                        <td className="px-3 py-3 font-mono text-xs text-muted-foreground">{log.recipient_user_id ? `${log.recipient_user_id.slice(0, 8)}…` : '—'}</td>
                        <td className="px-3 py-3">
                          <Badge variant={log.status === 'sent' ? 'default' : log.status === 'expired' ? 'secondary' : 'destructive'}>
                            {statusLabels[log.status]}
                          </Badge>
                          {log.provider_status_code !== null && <p className="mt-1 text-xs text-muted-foreground">HTTP {log.provider_status_code}</p>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </AdminLayout>
  );
}

function MetricCard({ icon, label, value, detail }: { icon: ReactNode; label: string; value: string; detail: string }) {
  return (
    <Card>
      <CardContent className="flex min-h-32 items-start gap-3 p-5">
        <div className="rounded-lg bg-muted/70 p-2">{icon}</div>
        <div className="min-w-0">
          <p className="text-xs text-muted-foreground">{label}</p>
          <p className="mt-1 text-2xl font-bold tabular-nums">{value}</p>
          <p className="mt-1 text-xs text-muted-foreground">{detail}</p>
        </div>
      </CardContent>
    </Card>
  );
}

function StatusSummary({ label, value, max, color }: { label: string; value: number | null; max: number; color: string }) {
  const width = value === null ? 0 : Math.min(100, Math.round((value / max) * 100));
  return (
    <div>
      <div className="mb-2 flex items-center justify-between gap-3 text-sm">
        <span>{label}</span>
        <span className="font-semibold tabular-nums">{formatCount(value)}</span>
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-muted" role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={width}>
        <div className={`h-full rounded-full ${color} transition-all`} style={{ width: `${width}%` }} />
      </div>
    </div>
  );
}

function HealthRow({ label, value, healthy }: { label: string; value: string; healthy: boolean }) {
  return (
    <div className="flex items-center justify-between gap-3 border-b pb-3 last:border-0 last:pb-0">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span className={`inline-flex items-center gap-1.5 text-sm font-medium ${healthy ? 'text-emerald-700 dark:text-emerald-400' : 'text-amber-700 dark:text-amber-400'}`}>
        {healthy ? <CheckCircle2 className="h-4 w-4" /> : <AlertTriangle className="h-4 w-4" />}
        {value}
      </span>
    </div>
  );
}
