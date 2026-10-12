import { useNavigate, Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Wallet, TrendingUp, Package, CheckCircle, FileDown, Banknote, AlertTriangle, ClipboardCheck } from 'lucide-react';
import { CourierLayout } from '@/components/courier/CourierLayout';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice } from '@/lib/utils';
import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { toast } from '@/hooks/use-toast';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

interface EarningRecord {
  id: string;
  amount: number;
  type: string;
  status: string;
  order_id: string | null;
  ride_request_id: string | null;
  created_at: string;
  paid_at: string | null;
}

interface CodReconciliation { id: string; order_id: string; expected_cash: number; collected_cash: number; variance: number; status: string; notes: string | null; submitted_at: string; }
interface CodEligibleOrder { id: string; total: number; shipping_cost: number | null; status: string; created_at: string; }
interface CodData { records: CodReconciliation[]; eligibleOrders: CodEligibleOrder[]; }

interface EarningsData {
  earnings: EarningRecord[];
  stats: {
    totalEarnings: number;
    todayEarnings: number;
    weekEarnings: number;
    monthEarnings: number;
    totalDeliveries: number;
    paidEarnings: number;
  };
}

export default function CourierEarningsPage() {
  const navigate = useNavigate();
  const { user, loading: authLoading } = useAuth();

  useEffect(() => {
    if (!authLoading && !user) navigate('/auth');
  }, [user, authLoading, navigate]);

  const [codDialogOpen, setCodDialogOpen] = useState(false);
  const [selectedCodOrder, setSelectedCodOrder] = useState<CodEligibleOrder | null>(null);
  const [collectedCash, setCollectedCash] = useState('');
  const [codNotes, setCodNotes] = useState('');
  const [codSubmitting, setCodSubmitting] = useState(false);

  const { data, isLoading: loading } = useQuery<EarningsData>({
    queryKey: ['courier-earnings', user?.id],
    queryFn: async () => {
      const { data: courier } = await supabase
        .from('couriers')
        .select('id, registration_status')
        .eq('user_id', user!.id)
        .maybeSingle();

      if (!courier || courier.registration_status !== 'APPROVED') {
        navigate('/courier');
        return { earnings: [], stats: { totalEarnings: 0, todayEarnings: 0, weekEarnings: 0, monthEarnings: 0, totalDeliveries: 0, paidEarnings: 0 } };
      }

      const { data: earningsData } = await supabase
        .from('courier_earnings')
        .select('*')
        .eq('courier_id', courier.id)
        .order('created_at', { ascending: false });

      const all: EarningRecord[] = earningsData || [];

      const now = new Date();
      const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const weekStart = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
      const sum = (items: EarningRecord[]) => items.reduce((s, e) => s + e.amount, 0);

      return {
        earnings: all,
        stats: {
          totalEarnings: sum(all),
          todayEarnings: sum(all.filter(e => new Date(e.created_at) >= todayStart)),
          weekEarnings: sum(all.filter(e => new Date(e.created_at) >= weekStart)),
          monthEarnings: sum(all.filter(e => new Date(e.created_at) >= monthStart)),
          totalDeliveries: all.length,
          paidEarnings: sum(all.filter(e => e.status === 'PAID')),
        },
      };
    },
    enabled: !!user && !authLoading,
    staleTime: 60_000,
  });

  const { data: codData, refetch: refetchCod } = useQuery<CodData>({
    queryKey: ['courier-cod-reconciliation', user?.id],
    queryFn: async () => {
      const { data: courier } = await supabase.from('couriers').select('id, registration_status').eq('user_id', user!.id).maybeSingle();
      if (!courier || courier.registration_status !== 'APPROVED') return { records: [], eligibleOrders: [] };
      const [{ data: records }, { data: eligibleOrders }] = await Promise.all([
        supabase.from('courier_cod_reconciliations').select('*').eq('courier_id', courier.id).order('submitted_at', { ascending: false }),
        supabase.from('orders').select('id, total, shipping_cost, status, created_at').eq('courier_id', courier.id).eq('payment_method', 'COD').in('status', ['DONE', 'DELIVERED']).order('created_at', { ascending: false }).limit(50),
      ]);
      const reconciledIds = new Set((records ?? []).map((record) => record.order_id));
      return { records: (records ?? []) as CodReconciliation[], eligibleOrders: ((eligibleOrders ?? []) as CodEligibleOrder[]).filter((order) => !reconciledIds.has(order.id)) };
    },
    enabled: !!user && !authLoading,
    staleTime: 30_000,
  });

  const submitCodReconciliation = async () => {
    if (!selectedCodOrder || !user) return;
    if (!collectedCash.trim()) {
      toast({ title: 'Jumlah tunai wajib diisi', description: 'Masukkan uang tunai yang diterima sebelum mengirim rekonsiliasi.', variant: 'destructive' });
      return;
    }
    const amount = Number(collectedCash);
    if (!Number.isFinite(amount) || amount < 0) {
      toast({ title: 'Jumlah tunai tidak valid', description: 'Masukkan angka nol atau lebih.', variant: 'destructive' });
      return;
    }
    setCodSubmitting(true);
    try {
      const { data: courier } = await supabase.from('couriers').select('id').eq('user_id', user.id).maybeSingle();
      if (!courier) throw new Error('Profil kurir tidak ditemukan');
      const { error } = await supabase.rpc('submit_courier_cod_reconciliation' as never, { p_courier_id: courier.id, p_order_id: selectedCodOrder.id, p_collected_cash: amount, p_notes: codNotes || null } as never);
      if (error) throw error;
      toast({ title: 'Rekonsiliasi COD dikirim', description: 'Setoran akan ditinjau oleh admin.' });
      setCodDialogOpen(false); setSelectedCodOrder(null); setCollectedCash(''); setCodNotes(''); await refetchCod();
    } catch (error) { toast({ title: 'Gagal mengirim rekonsiliasi', description: error instanceof Error ? error.message : 'Silakan coba lagi', variant: 'destructive' }); } finally { setCodSubmitting(false); }
  };

  if (authLoading || loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
      </div>
    );
  }

  const earnings = data?.earnings ?? [];
  const stats = data?.stats ?? { totalEarnings: 0, todayEarnings: 0, weekEarnings: 0, monthEarnings: 0, totalDeliveries: 0, paidEarnings: 0 };
  const pendingEarnings = earnings.filter(e => e.status === 'PENDING');

  return (
    <CourierLayout title="Pendapatan" subtitle="Ringkasan pendapatan dan rekonsiliasi COD">
      <div className="space-y-6">
        <div className="flex justify-end">
          <Button variant="outline" size="sm" onClick={() => navigate('/courier/slip')}>
            <FileDown className="h-4 w-4 mr-1.5" />
            Download Slip PDF
          </Button>
        </div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="grid grid-cols-2 gap-3">
          <Card className="bg-gradient-to-br from-primary to-primary/80 text-primary-foreground">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <Wallet className="h-4 w-4" /> Bulan Ini
              </CardTitle>
            </CardHeader>
            <CardContent><p className="text-2xl font-bold">{formatPrice(stats.monthEarnings)}</p></CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <TrendingUp className="h-4 w-4 text-primary" /> Hari Ini
              </CardTitle>
            </CardHeader>
            <CardContent><p className="text-2xl font-bold text-primary">{formatPrice(stats.todayEarnings)}</p></CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <Package className="h-4 w-4 text-muted-foreground" /> Total Transaksi
              </CardTitle>
            </CardHeader>
            <CardContent><p className="text-2xl font-bold">{stats.totalDeliveries}</p></CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <CheckCircle className="h-4 w-4 text-green-500" /> Sudah Dibayar
              </CardTitle>
            </CardHeader>
            <CardContent><p className="text-2xl font-bold text-green-500">{formatPrice(stats.paidEarnings)}</p></CardContent>
          </Card>
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}>
          <Card>
            <CardHeader><CardTitle className="text-lg">Ringkasan Pendapatan</CardTitle></CardHeader>
            <CardContent className="space-y-3">
              <div className="flex justify-between items-center py-2 border-b border-border">
                <span className="text-muted-foreground">Minggu Ini</span>
                <span className="font-bold">{formatPrice(stats.weekEarnings)}</span>
              </div>
              <div className="flex justify-between items-center py-2 border-b border-border">
                <span className="text-muted-foreground">Bulan Ini</span>
                <span className="font-bold">{formatPrice(stats.monthEarnings)}</span>
              </div>
              <div className="flex justify-between items-center py-2">
                <span className="text-muted-foreground">Total Keseluruhan</span>
                <span className="font-bold text-primary">{formatPrice(stats.totalEarnings)}</span>
              </div>
            </CardContent>
          </Card>
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}>
          <Tabs defaultValue="all" className="w-full">
            <TabsList className="w-full">
              <TabsTrigger value="all" className="flex-1">Semua</TabsTrigger>
              <TabsTrigger value="delivery" className="flex-1">Delivery</TabsTrigger>
              <TabsTrigger value="ride" className="flex-1">Ojek</TabsTrigger>
              <TabsTrigger value="pending" className="flex-1">Pending</TabsTrigger>
              <TabsTrigger value="cod" className="flex-1">COD</TabsTrigger>
            </TabsList>

            <TabsContent value="all" className="mt-4 space-y-3">
              {earnings.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">
                  <Package className="h-12 w-12 mx-auto mb-2 opacity-50" />
                  <p>Belum ada riwayat pendapatan</p>
                </div>
              ) : earnings.map(e => <EarningCard key={e.id} earning={e} />)}
            </TabsContent>
            <TabsContent value="delivery" className="mt-4 space-y-3">
              {earnings.filter(e => e.type === 'DELIVERY').length === 0
                ? <p className="text-center py-8 text-muted-foreground">Tidak ada pendapatan delivery</p>
                : earnings.filter(e => e.type === 'DELIVERY').map(e => <EarningCard key={e.id} earning={e} />)}
            </TabsContent>
            <TabsContent value="ride" className="mt-4 space-y-3">
              {earnings.filter(e => e.type === 'RIDE').length === 0
                ? <p className="text-center py-8 text-muted-foreground">Tidak ada pendapatan ojek</p>
                : earnings.filter(e => e.type === 'RIDE').map(e => <EarningCard key={e.id} earning={e} />)}
            </TabsContent>
            <TabsContent value="pending" className="mt-4 space-y-3">
              {pendingEarnings.length === 0
                ? <p className="text-center py-8 text-muted-foreground">Tidak ada pending</p>
                : pendingEarnings.map(e => <EarningCard key={e.id} earning={e} />)}
            </TabsContent>
            <TabsContent value="cod" className="mt-4 space-y-3">
              <Card><CardHeader><CardTitle className="text-lg flex items-center gap-2"><Banknote className="h-4 w-4 text-primary" />Rekonsiliasi COD</CardTitle></CardHeader><CardContent className="space-y-3"><p className="text-sm text-muted-foreground">Laporkan uang tunai yang diterima dari order COD yang sudah selesai. Nilai expected dihitung server berdasarkan order.</p>{(codData?.eligibleOrders ?? []).map((order) => <div key={order.id} className="flex items-center gap-3 border rounded-lg p-3"><div className="flex-1"><p className="font-mono text-sm">#{order.id.slice(0, 8).toUpperCase()}</p><p className="text-xs text-muted-foreground">{new Date(order.created_at).toLocaleDateString('id-ID')} · Expected {formatPrice(order.total + (order.shipping_cost ?? 0))}</p></div><Button size="sm" onClick={() => { setSelectedCodOrder(order); setCollectedCash(String(order.total + (order.shipping_cost ?? 0))); setCodDialogOpen(true); }}>Setorkan</Button></div>)}{(codData?.eligibleOrders ?? []).length === 0 && <p className="text-sm text-muted-foreground text-center py-4">Tidak ada order COD yang menunggu rekonsiliasi.</p>}{(codData?.records ?? []).map((record) => <div key={record.id} className="border rounded-lg p-3"><div className="flex justify-between gap-3"><div><p className="font-mono text-sm">#{record.order_id.slice(0, 8).toUpperCase()}</p><p className="text-xs text-muted-foreground">Expected {formatPrice(record.expected_cash)} · Disetor {formatPrice(record.collected_cash)}</p></div><Badge variant={record.status === 'matched' || record.status === 'approved' ? 'default' : record.status === 'shortage' ? 'destructive' : 'secondary'}>{record.status}</Badge></div>{record.variance !== 0 && <p className="text-xs text-amber-600 mt-2 flex items-center gap-1"><AlertTriangle className="h-3 w-3" />Selisih {formatPrice(Math.abs(record.variance))}</p>}</div>)}</CardContent></Card>
            </TabsContent>
          </Tabs>
        </motion.div>
      </div>
      <Dialog open={codDialogOpen} onOpenChange={setCodDialogOpen}><DialogContent><DialogHeader><DialogTitle><ClipboardCheck className="inline h-4 w-4 mr-2" />Setor COD #{selectedCodOrder?.id.slice(0, 8).toUpperCase()}</DialogTitle></DialogHeader><div className="space-y-3"><div className="rounded-lg bg-muted p-3 text-sm">Expected cash: <strong>{selectedCodOrder ? formatPrice(selectedCodOrder.total + (selectedCodOrder.shipping_cost ?? 0)) : '-'}</strong></div><div><Label>Uang tunai diterima</Label><Input className="mt-1" type="number" min="0" step="1" value={collectedCash} onChange={(event) => setCollectedCash(event.target.value)} /></div><div><Label>Catatan</Label><Textarea className="mt-1" maxLength={500} value={codNotes} onChange={(event) => setCodNotes(event.target.value)} /></div></div><DialogFooter><Button variant="outline" onClick={() => setCodDialogOpen(false)}>Batal</Button><Button onClick={() => void submitCodReconciliation()} disabled={codSubmitting}>{codSubmitting ? 'Mengirim...' : 'Kirim Rekonsiliasi'}</Button></DialogFooter></DialogContent></Dialog>
    </CourierLayout>
  );
}

function EarningCard({ earning }: { earning: EarningRecord }) {
  const isPaid = earning.status === 'PAID';
  const typeLabel = earning.type === 'DELIVERY' ? 'Pengiriman' : earning.type === 'RIDE' ? 'Ojek' : earning.type;

  return (
    <div className="bg-card rounded-xl p-4 border border-border">
      <div className="flex justify-between items-start mb-2">
        <div>
           <p className="font-mono text-sm font-medium">#{(earning.order_id || earning.ride_request_id || earning.id).slice(0, 8).toUpperCase()}</p>
          <p className="text-xs text-muted-foreground">
            {new Date(earning.created_at).toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
          </p>
        </div>
        <div className="flex items-center gap-1.5">
          <Badge variant="outline">{typeLabel}</Badge>
          <Badge variant={isPaid ? 'default' : 'secondary'} className={isPaid ? 'bg-green-500/10 text-green-600' : ''}>
            {isPaid ? 'Dibayar' : 'Pending'}
          </Badge>
        </div>
      </div>
      <div className="flex justify-between items-center pt-2 border-t border-border">
        <span className="text-sm text-muted-foreground">Komisi</span>
        <span className="font-bold text-primary">+{formatPrice(earning.amount)}</span>
      </div>
    </div>
  );
}
