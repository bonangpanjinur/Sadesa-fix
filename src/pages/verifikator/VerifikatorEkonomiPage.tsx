import { useCallback, useState, useEffect } from 'react';
import { VerifikatorLayout } from '@/components/verifikator/VerifikatorLayout';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, LineChart, Line } from 'recharts';
import { TrendingUp, Store, ShoppingBag, RefreshCw } from 'lucide-react';
import { subMonths, format } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { formatPrice } from '@/lib/utils';

interface VillageRef {
  id: string;
  name: string;
}

interface AssignmentRow {
  villages: VillageRef | VillageRef[] | null;
}

interface EconomyOrder {
  total: number | null;
  created_at: string;
  merchant_id: string;
  merchants: { village_id: string | null; villages?: { name: string | null } | { name: string | null }[] | null } | { village_id: string | null; villages?: { name: string | null } | { name: string | null }[] | null }[] | null;
}

interface EconomyMerchant {
  id: string;
  name: string;
  village_id: string | null;
}

export default function VerifikatorEkonomiPage() {
  const { user } = useAuth();
  const [villages, setVillages] = useState<{ id: string; name: string }[]>([]);
  const [selectedVillage, setSelectedVillage] = useState<string>('all');
  const [period, setPeriod] = useState('6');
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({ totalOmzet: 0, totalTransaksi: 0, activeMerchants: 0 });
  const [monthlyData, setMonthlyData] = useState<{ month: string; omzet: number; transaksi: number }[]>([]);
  const [villageRanking, setVillageRanking] = useState<{ name: string; omzet: number; merchants: number }[]>([]);





  const fetchVillages = useCallback(async () => {
    if (!user) return;
    const { data: assignments } = await supabase
      .from('verifikator_assignments')
      .select('villages(id, name)')
      .eq('verifikator_id', user.id);

    const vlist = (assignments as AssignmentRow[] || []).flatMap(a => Array.isArray(a.villages) ? a.villages : a.villages ? [a.villages] : []);
    setVillages(vlist);
  }, [user]);

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const startDate = subMonths(new Date(), Number(period));
      const villageIds = selectedVillage === 'all' ? villages.map(v => v.id) : [selectedVillage];

      if (villageIds.length === 0) { setLoading(false); return; }

      const [merchantsRes, ordersRes] = await Promise.all([
        supabase.from('merchants').select('id, name, village_id').in('village_id', villageIds).eq('registration_status', 'APPROVED'),
        supabase.from('orders').select('total, created_at, merchant_id, merchants(village_id, villages(name))')
          .gte('created_at', startDate.toISOString())
          .eq('status', 'COMPLETED'),
      ] as const);

      const merchants = (merchantsRes.data || []) as EconomyMerchant[];
      const orders = (ordersRes.data as EconomyOrder[] || []).filter(o => {
        const merchant = Array.isArray(o.merchants) ? o.merchants[0] : o.merchants;
        return villageIds.includes(merchant?.village_id ?? '');
      });

      const totalOmzet = orders.reduce((s, o) => s + (o.total || 0), 0);
      setStats({ totalOmzet, totalTransaksi: orders.length, activeMerchants: merchants.length });

      // Monthly data
      const monthly: Record<string, { omzet: number; transaksi: number }> = {};
      for (let i = Number(period) - 1; i >= 0; i--) {
        const key = format(subMonths(new Date(), i), 'MMM yy', { locale: idLocale });
        monthly[key] = { omzet: 0, transaksi: 0 };
      }
      orders.forEach((o) => {
        const key = format(new Date(o.created_at), 'MMM yy', { locale: idLocale });
        if (monthly[key]) { monthly[key].omzet += o.total || 0; monthly[key].transaksi += 1; }
      });
      setMonthlyData(Object.entries(monthly).map(([month, v]) => ({ month, ...v })));

      // Village ranking
      const vMap: Record<string, { name: string; omzet: number; merchants: number }> = {};
      villages.forEach(v => { vMap[v.id] = { name: v.name, omzet: 0, merchants: 0 }; });
      merchants.forEach((m) => { if (vMap[m.village_id]) vMap[m.village_id].merchants += 1; });
      orders.forEach((o) => {
        const merchant = Array.isArray(o.merchants) ? o.merchants[0] : o.merchants;
        const vid = merchant?.village_id;
        if (vid && vMap[vid]) vMap[vid].omzet += o.total || 0;
      });
      setVillageRanking(Object.values(vMap).sort((a, b) => b.omzet - a.omzet));
    } catch (err) {
      console.error('Error:', err);
    } finally {
      setLoading(false);
    }
  }, [period, selectedVillage, villages]);

  useEffect(() => {
    fetchVillages();
  }, [fetchVillages]);
  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return (
    <VerifikatorLayout title="Laporan Ekonomi Desa" subtitle="Monitoring omzet UMKM di wilayah Anda">
      <div className="space-y-5">
        <div className="flex flex-wrap gap-2">
          <Select value={selectedVillage} onValueChange={setSelectedVillage}>
            <SelectTrigger className="w-48 h-9">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Semua Desa</SelectItem>
              {villages.map(v => <SelectItem key={v.id} value={v.id}>{v.name}</SelectItem>)}
            </SelectContent>
          </Select>
          <Select value={period} onValueChange={setPeriod}>
            <SelectTrigger className="w-32 h-9">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="3">3 Bulan</SelectItem>
              <SelectItem value="6">6 Bulan</SelectItem>
              <SelectItem value="12">12 Bulan</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline" size="sm" onClick={fetchData} disabled={loading}>
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </Button>
        </div>

        <div className="grid grid-cols-3 gap-3">
          {[
            { label: 'Total Omzet', value: formatPrice(stats.totalOmzet), icon: TrendingUp },
            { label: 'Total Transaksi', value: stats.totalTransaksi, icon: ShoppingBag },
            { label: 'UMKM Aktif', value: stats.activeMerchants, icon: Store },
          ].map((s, i) => (
            <Card key={i}>
              <CardContent className="p-4 text-center">
                <s.icon className="h-5 w-5 mx-auto mb-1 text-muted-foreground" />
                <p className="text-lg font-bold">{s.value}</p>
                <p className="text-xs text-muted-foreground">{s.label}</p>
              </CardContent>
            </Card>
          ))}
        </div>

        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm">Tren Omzet</CardTitle></CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={200}>
              <LineChart data={monthlyData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="month" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={v => `${(v / 1000000).toFixed(1)}jt`} />
                <Tooltip formatter={(v: number) => [formatPrice(v), 'Omzet']} />
                <Line type="monotone" dataKey="omzet" stroke="#10b981" strokeWidth={2} dot={false} />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        {selectedVillage === 'all' && villageRanking.length > 0 && (
          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-sm">Ranking Desa</CardTitle></CardHeader>
            <CardContent>
              <div className="space-y-3">
                {villageRanking.map((v, i) => (
                  <div key={v.name} className="flex items-center gap-3">
                    <div className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${
                      i === 0 ? 'bg-yellow-100 text-yellow-700' : 'bg-muted text-muted-foreground'
                    }`}>{i + 1}</div>
                    <div className="flex-1">
                      <p className="text-sm font-medium">{v.name}</p>
                      <p className="text-xs text-muted-foreground">{v.merchants} merchant</p>
                    </div>
                    <p className="text-sm font-semibold text-emerald-600">{formatPrice(v.omzet)}</p>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </VerifikatorLayout>
  );
}
