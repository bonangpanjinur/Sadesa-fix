import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CalendarClock, CheckCircle2, Clock3, Package, RefreshCw, Store } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { supabase } from '@/integrations/supabase/client';

type MerchantRelation = {
  id: string;
  name: string;
  user_id: string | null;
  city: string | null;
  district: string | null;
};

type FreeQuotaMerchant = {
  id: string;
  merchant_id: string;
  transaction_quota: number;
  used_quota: number;
  started_at: string;
  expired_at: string;
  merchant: MerchantRelation | null;
};

const formatDate = (value: string) => new Intl.DateTimeFormat('id-ID', {
  dateStyle: 'medium',
  timeZone: 'Asia/Jakarta',
}).format(new Date(value));

const daysRemaining = (value: string) => Math.max(0, Math.ceil((new Date(value).getTime() - Date.now()) / 86_400_000));

export default function AdminFreeQuotaPage() {
  const [merchants, setMerchants] = useState<FreeQuotaMerchant[]>([]);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadMerchants = useCallback(async () => {
    setError(null);
    const { data, error: queryError } = await supabase
      .from('merchant_subscriptions')
      .select(`
        id,
        merchant_id,
        transaction_quota,
        used_quota,
        started_at,
        expired_at,
        merchant:merchants!merchant_subscriptions_merchant_id_fkey(id, name, user_id, city, district),
        package:transaction_packages!merchant_subscriptions_package_id_fkey(name)
      `)
      .eq('status', 'ACTIVE')
      .eq('package.name', 'Paket Gratis 2 Bulan')
      .gte('expired_at', new Date().toISOString())
      .order('expired_at', { ascending: true });

    if (queryError) {
      console.error('Error loading free quota merchants:', queryError);
      setError('Daftar merchant tier gratis belum dapat dimuat. Pastikan migrasi database sudah diterapkan.');
      setMerchants([]);
    } else {
      setMerchants((data ?? []) as unknown as FreeQuotaMerchant[]);
    }
    setLoading(false);
    setRefreshing(false);
  }, []);

  useEffect(() => {
    void loadMerchants();
  }, [loadMerchants]);

  const filteredMerchants = useMemo(() => {
    const term = search.trim().toLowerCase();
    if (!term) return merchants;
    return merchants.filter((item) => {
      const merchant = item.merchant;
      return [merchant?.name, merchant?.city, merchant?.district]
        .filter(Boolean)
        .some((value) => value!.toLowerCase().includes(term));
    });
  }, [merchants, search]);

  const stats = useMemo(() => {
    const totalQuota = merchants.reduce((sum, item) => sum + item.transaction_quota, 0);
    const usedQuota = merchants.reduce((sum, item) => sum + item.used_quota, 0);
    const expiringSoon = merchants.filter((item) => daysRemaining(item.expired_at) <= 7).length;
    return {
      merchantCount: merchants.length,
      totalQuota,
      usedQuota,
      expiringSoon,
    };
  }, [merchants]);

  const refresh = () => {
    setRefreshing(true);
    void loadMerchants();
  };

  return (
    <AdminLayout title="Merchant Tier Gratis" subtitle="Pantau merchant yang sedang memakai kuota gratis 2 bulan">
      <div className="space-y-6">
        <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
          <div>
            <p className="text-sm text-muted-foreground">Paket Gratis 2 Bulan · 100 transaksi · masa aktif 60 hari</p>
          </div>
          <Button variant="outline" onClick={refresh} disabled={refreshing}>
            <RefreshCw className={`mr-2 h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
            Segarkan
          </Button>
        </div>

        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <Card><CardContent className="flex items-center gap-3 p-5"><Store className="h-8 w-8 text-primary" /><div><p className="text-sm text-muted-foreground">Merchant aktif</p><p className="text-2xl font-bold">{stats.merchantCount}</p></div></CardContent></Card>
          <Card><CardContent className="flex items-center gap-3 p-5"><Package className="h-8 w-8 text-blue-600" /><div><p className="text-sm text-muted-foreground">Total kuota</p><p className="text-2xl font-bold">{stats.totalQuota.toLocaleString('id-ID')}</p></div></CardContent></Card>
          <Card><CardContent className="flex items-center gap-3 p-5"><CheckCircle2 className="h-8 w-8 text-emerald-600" /><div><p className="text-sm text-muted-foreground">Sudah terpakai</p><p className="text-2xl font-bold">{stats.usedQuota.toLocaleString('id-ID')}</p></div></CardContent></Card>
          <Card><CardContent className="flex items-center gap-3 p-5"><AlertTriangle className="h-8 w-8 text-amber-600" /><div><p className="text-sm text-muted-foreground">Berakhir ≤ 7 hari</p><p className="text-2xl font-bold">{stats.expiringSoon}</p></div></CardContent></Card>
        </div>

        <Card>
          <CardHeader className="gap-4 sm:flex-row sm:items-center sm:justify-between">
            <CardTitle className="flex items-center gap-2"><CalendarClock className="h-5 w-5" />Daftar penggunaan tier gratis</CardTitle>
            <Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Cari nama atau wilayah..." className="sm:w-72" />
          </CardHeader>
          <CardContent>
            {error && <div className="mb-4 rounded-lg border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">{error}</div>}
            {loading ? (
              <div className="py-12 text-center text-sm text-muted-foreground">Memuat data merchant...</div>
            ) : filteredMerchants.length === 0 ? (
              <div className="py-12 text-center text-sm text-muted-foreground">Belum ada merchant dengan tier kuota gratis aktif.</div>
            ) : (
              <Table>
                <TableHeader><TableRow><TableHead>Merchant</TableHead><TableHead>Lokasi</TableHead><TableHead>Penggunaan</TableHead><TableHead>Masa aktif</TableHead><TableHead>Status</TableHead></TableRow></TableHeader>
                <TableBody>
                  {filteredMerchants.map((item) => {
                    const remaining = Math.max(0, item.transaction_quota - item.used_quota);
                    const days = daysRemaining(item.expired_at);
                    return (
                      <TableRow key={item.id}>
                        <TableCell><p className="font-medium">{item.merchant?.name || 'Merchant tanpa nama'}</p><p className="text-xs text-muted-foreground">{item.merchant?.user_id ? `${item.merchant.user_id.slice(0, 8)}...` : 'Tanpa user'}</p></TableCell>
                        <TableCell>{[item.merchant?.district, item.merchant?.city].filter(Boolean).join(', ') || '-'}</TableCell>
                        <TableCell><p className="font-medium">{item.used_quota} / {item.transaction_quota}</p><p className="text-xs text-muted-foreground">Sisa {remaining} transaksi</p></TableCell>
                        <TableCell><p>{formatDate(item.started_at)} – {formatDate(item.expired_at)}</p><p className="text-xs text-muted-foreground">{days} hari tersisa</p></TableCell>
                        <TableCell>{days <= 7 ? <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100"><Clock3 className="mr-1 h-3 w-3" />Segera berakhir</Badge> : <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Aktif</Badge>}</TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </AdminLayout>
  );
}
