import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Bell, Loader2, RefreshCw, Search, Smartphone, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { supabase } from '@/integrations/supabase/client';

interface SubscriptionRow {
  id: string;
  user_id: string;
  timezone: string;
  created_at: string;
  updated_at: string;
}

interface ProfileRow {
  user_id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  is_blocked: boolean | null;
}

interface SubscriberRow extends SubscriptionRow {
  profile: ProfileRow | null;
}

function formatDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '—' : new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' }).format(date);
}

export default function AdminPushSubscribersPage() {
  const [rows, setRows] = useState<SubscriberRow[]>([]);
  const [totalCount, setTotalCount] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data: subscriptions, count, error: subscriptionError } = await supabase
        .from('push_subscriptions')
        .select('id, user_id, timezone, created_at, updated_at', { count: 'exact' })
        .order('updated_at', { ascending: false })
        .limit(1000);
      if (subscriptionError) throw subscriptionError;
      const items = subscriptions ?? [];
      const userIds = [...new Set(items.map((item) => item.user_id))];
      let profiles: ProfileRow[] = [];
      if (userIds.length) {
        const { data, error: profileError } = await supabase
          .from('profiles')
          .select('user_id, full_name, email, phone, is_blocked')
          .in('user_id', userIds);
        if (profileError) throw profileError;
        profiles = data ?? [];
      }
      const profileMap = new Map(profiles.map((profile) => [profile.user_id, profile]));
      setRows(items.map((subscription) => ({ ...subscription, profile: profileMap.get(subscription.user_id) ?? null })));
      setTotalCount(count ?? items.length);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Daftar subscription push belum dapat dimuat.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const filteredRows = useMemo(() => {
    const term = search.trim().toLowerCase();
    if (!term) return rows;
    return rows.filter((row) => [
      row.profile?.full_name,
      row.profile?.email,
      row.profile?.phone,
      row.user_id,
      row.timezone,
    ].some((value) => value?.toLowerCase().includes(term)));
  }, [rows, search]);
  const distinctUsers = new Set(rows.map((row) => row.user_id)).size;

  return (
    <AdminLayout title="Langganan Push Aktif" subtitle="Perangkat pengguna yang saat ini tersimpan untuk menerima Web Push">
      <div className="mx-auto max-w-7xl space-y-6">
        <Alert>
          <Bell className="h-4 w-4" />
          <AlertDescription>“Aktif” di halaman ini berarti subscription masih tersimpan. Push provider/browser dapat menolak endpoint yang sudah kedaluwarsa; kegagalan terdeteksi pada pengiriman dan dapat dilihat di <Link className="font-medium underline" to="/admin/push-monitoring">Monitor Push</Link>. Endpoint serta material kunci subscription tidak ditampilkan.</AlertDescription>
        </Alert>

        {error && <Alert variant="destructive"><AlertDescription>Gagal memuat daftar subscription: {error}</AlertDescription></Alert>}

        <div className="grid gap-4 sm:grid-cols-3">
          <StatCard icon={<Smartphone className="h-5 w-5 text-sky-600" />} label="Subscription tersimpan" value={totalCount?.toLocaleString('id-ID') ?? '—'} />
          <StatCard icon={<Users className="h-5 w-5 text-emerald-600" />} label="Pengguna dalam hasil muat" value={distinctUsers.toLocaleString('id-ID')} />
          <StatCard icon={<Bell className="h-5 w-5 text-violet-600" />} label="Ditampilkan" value={filteredRows.length.toLocaleString('id-ID')} />
        </div>

        <Card>
          <CardContent className="space-y-4 p-4 sm:p-6">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="relative w-full sm:max-w-sm">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input aria-label="Cari subscription atau pengguna" placeholder="Cari nama, email, ID, atau zona waktu" value={search} onChange={(event) => setSearch(event.target.value)} className="pl-9" />
              </div>
              <Button type="button" variant="outline" onClick={() => void load()} disabled={loading}>
                {loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <RefreshCw className="mr-2 h-4 w-4" />}
                Muat ulang
              </Button>
            </div>

            {loading && rows.length === 0 && <p role="status" className="py-10 text-center text-sm text-muted-foreground">Memuat daftar perangkat…</p>}
            {!loading && !error && rows.length === 0 && <p className="py-10 text-center text-sm text-muted-foreground">Belum ada subscription push tersimpan.</p>}
            {!loading && !error && rows.length > 0 && filteredRows.length === 0 && <p className="py-10 text-center text-sm text-muted-foreground">Tidak ada subscription yang cocok dengan pencarian.</p>}

            {filteredRows.length > 0 && (
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Pengguna</TableHead>
                      <TableHead>Status akun</TableHead>
                      <TableHead>Zona waktu</TableHead>
                      <TableHead>Terdaftar</TableHead>
                      <TableHead>Terakhir diperbarui</TableHead>
                      <TableHead className="text-right">Perangkat</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filteredRows.map((row) => {
                      const name = row.profile?.full_name || 'Profil tidak tersedia';
                      return (
                        <TableRow key={row.id}>
                          <TableCell>
                            <div className="flex items-center gap-3">
                              <Avatar className="h-9 w-9"><AvatarFallback>{name.slice(0, 2).toUpperCase()}</AvatarFallback></Avatar>
                              <div className="min-w-0">
                                <p className="font-medium">{name}</p>
                                <p className="text-xs text-muted-foreground">{row.profile?.email || row.profile?.phone || `${row.user_id.slice(0, 8)}…`}</p>
                              </div>
                            </div>
                          </TableCell>
                          <TableCell>{row.profile?.is_blocked ? <Badge variant="destructive">Diblokir</Badge> : <Badge variant="secondary">Subscription tersimpan</Badge>}</TableCell>
                          <TableCell className="whitespace-nowrap text-sm">{row.timezone || 'Asia/Jakarta'}</TableCell>
                          <TableCell className="whitespace-nowrap text-xs text-muted-foreground">{formatDate(row.created_at)}</TableCell>
                          <TableCell className="whitespace-nowrap text-xs text-muted-foreground">{formatDate(row.updated_at)}</TableCell>
                          <TableCell className="text-right font-mono text-xs text-muted-foreground" title={`Subscription ${row.id}`}>{row.id.slice(0, 8)}…</TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
            {totalCount !== null && totalCount > rows.length && <p className="text-xs text-muted-foreground">Menampilkan 1.000 subscription terbaru dari {totalCount.toLocaleString('id-ID')}. Gunakan pencarian dalam hasil yang dimuat.</p>}
            <div className="flex justify-end"><Button asChild variant="link"><Link to="/admin/users">Buka manajemen pengguna</Link></Button></div>
          </CardContent>
        </Card>
      </div>
    </AdminLayout>
  );
}

function StatCard({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return <Card><CardContent className="flex items-center gap-3 p-5"><div className="rounded-lg bg-muted p-2">{icon}</div><div><p className="text-xs text-muted-foreground">{label}</p><p className="text-2xl font-bold tabular-nums">{value}</p></div></CardContent></Card>;
}
