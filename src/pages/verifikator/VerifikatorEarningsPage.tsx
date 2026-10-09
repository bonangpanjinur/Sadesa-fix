import { useState } from 'react';
import { VerifikatorLayout } from '@/components/verifikator/VerifikatorLayout';
import { ReferralCommissionPanel } from '@/components/referral/ReferralCommissionPanel';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';
import { TrendingUp, Wallet, Clock, CheckCircle, XCircle, ArrowDownToLine, History, Bike, Store, Database, Link2 } from 'lucide-react';
import { format } from 'date-fns';
import { id } from 'date-fns/locale';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Bar, BarChart, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

interface Earning {
  id: string;
  merchant_id: string;
  subscription_id: string;
  package_id: string;
  package_amount: number;
  commission_percent: number;
  commission_amount: number;
  status: string;
  created_at: string;
  paid_at: string | null;
  merchant?: { name: string; district?: string | null; city?: string | null; registration_status?: string | null };
  package?: { name: string };
  source_type?: string;
  buyer_role?: string | null;
  description?: string | null;
}

interface Withdrawal {
  id: string;
  amount: number;
  bank_name: string;
  account_number: string;
  account_holder: string;
  status: string;
  admin_notes: string | null;
  processed_at: string | null;
  created_at: string;
}

interface CourierEarning {
  id: string;
  courier_id: string;
  amount: number;
  type: string;
  status: string;
  created_at: string;
  courier?: { name: string; verifikator_code: string | null; district?: string | null; city?: string | null; registration_status?: string | null; status?: string | null };
}

interface EarningsData {
  earnings: Earning[];
  courierEarnings: CourierEarning[];
  withdrawals: Withdrawal[];
  codes: Array<{ code: string; trade_group: string; usage_count: number; is_active: boolean }>;
}

const BANKS = [
  'BCA', 'BNI', 'BRI', 'Mandiri', 'CIMB Niaga', 'Danamon',
  'Permata', 'OCBC NISP', 'Maybank', 'BTN', 'Bank Jago',
  'Jenius', 'SeaBank', 'Bank Neo Commerce', 'OVO', 'GoPay', 'DANA', 'ShopeePay',
];

export default function VerifikatorEarningsPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [showWithdrawDialog, setShowWithdrawDialog] = useState(false);
  const [trendMode, setTrendMode] = useState<'daily' | 'monthly'>('daily');
  const [breakdownMode, setBreakdownMode] = useState<'region' | 'status'>('region');
  const [withdrawForm, setWithdrawForm] = useState({
    amount: '', bank_name: '', account_number: '', account_holder: '',
  });
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');

  const { data, isLoading: loading } = useQuery<EarningsData>({
    queryKey: ['verifikator-earnings', user?.id],
    queryFn: async () => {
      const [earningsRes, withdrawalsRes, codesRes, couriersByIdRes] = await Promise.all([
        supabase
          .from('verifikator_earnings')
          .select('*, merchant:merchants(name, district, city, registration_status), package:transaction_packages(name)')
          .eq('verifikator_id', user!.id)
          .order('created_at', { ascending: false }),
        supabase
          .from('verifikator_withdrawals')
          .select('*')
          .eq('verifikator_id', user!.id)
          .order('created_at', { ascending: false }),
        supabase
          .from('verifikator_codes')
          .select('code, trade_group, usage_count, is_active')
          .eq('verifikator_id', user!.id)
          .order('created_at', { ascending: false }),
        supabase
          .from('couriers')
          .select('id, name, verifikator_code, district, city, registration_status, status')
          .eq('verifikator_id', user!.id),
      ]);
      const codes = codesRes.data || [];
      const codeValues = codes.map(code => code.code);
      const couriersByCodeRes = codeValues.length
        ? await supabase.from('couriers').select('id, name, verifikator_code, district, city, registration_status, status').in('verifikator_code', codeValues)
        : { data: [] };
      const courierMap = new Map<string, { id: string; name: string; verifikator_code: string | null; district?: string | null; city?: string | null; registration_status?: string | null; status?: string | null }>();
      [...(couriersByIdRes.data || []), ...(couriersByCodeRes.data || [])].forEach(courier => courierMap.set(courier.id, courier));
      const courierIds = [...courierMap.keys()];
      const courierEarningsRes = courierIds.length
        ? await supabase
          .from('courier_earnings')
          .select('id, courier_id, amount, type, status, created_at')
          .in('courier_id', courierIds)
          .order('created_at', { ascending: false })
        : { data: [] };
      return {
        earnings: earningsRes.data || [],
        courierEarnings: (courierEarningsRes.data || []).map(earning => ({
          ...earning,
          courier: courierMap.get(earning.courier_id),
        })),
        withdrawals: withdrawalsRes.data || [],
        codes,
      };
    },
    enabled: !!user,
    staleTime: 60_000,
  });

  const earnings = data?.earnings ?? [];
  const courierEarnings = data?.courierEarnings ?? [];
  const withdrawals = data?.withdrawals ?? [];
  const codes = data?.codes ?? [];
  const hasInvalidDateRange = Boolean(startDate && endDate && startDate > endDate);
  const isWithinDateRange = (createdAt: string) => {
    const date = format(new Date(createdAt), 'yyyy-MM-dd');
    return (!startDate || date >= startDate) && (!endDate || date <= endDate);
  };
  const filteredEarnings = hasInvalidDateRange ? [] : earnings.filter(earning => isWithinDateRange(earning.created_at));
  const filteredCourierEarnings = hasInvalidDateRange ? [] : courierEarnings.filter(earning => isWithinDateRange(earning.created_at));
  const merchantFeeTotal = filteredEarnings.reduce((sum, earning) => sum + earning.commission_amount, 0);
  const courierFeeTotal = filteredCourierEarnings.reduce((sum, earning) => sum + earning.amount, 0);
  const generatedFeeTotal = merchantFeeTotal + courierFeeTotal;
  const trendMap = new Map<string, number>();
  const addTrendValue = (createdAt: string, amount: number) => {
    const period = trendMode === 'monthly' ? format(new Date(createdAt), 'yyyy-MM') : format(new Date(createdAt), 'yyyy-MM-dd');
    trendMap.set(period, (trendMap.get(period) || 0) + amount);
  };
  filteredEarnings.forEach(earning => addTrendValue(earning.created_at, earning.commission_amount));
  filteredCourierEarnings.forEach(earning => addTrendValue(earning.created_at, earning.amount));
  const trendData = [...trendMap.entries()].sort(([left], [right]) => left.localeCompare(right)).map(([period, total]) => ({
    period: format(new Date(`${period}${trendMode === 'monthly' ? '-01' : ''}T00:00:00`), trendMode === 'monthly' ? 'MMM yyyy' : 'dd MMM', { locale: id }),
    total,
  }));
  const breakdownMap = new Map<string, number>();
  const addBreakdownValue = (category: string | null | undefined, amount: number) => {
    const key = category?.trim() || (breakdownMode === 'region' ? 'Wilayah tidak tersedia' : 'Status tidak tersedia');
    breakdownMap.set(key, (breakdownMap.get(key) || 0) + amount);
  };
  filteredEarnings.forEach(earning => addBreakdownValue(
    breakdownMode === 'region' ? earning.merchant?.district || earning.merchant?.city : earning.status,
    earning.commission_amount,
  ));
  filteredCourierEarnings.forEach(earning => addBreakdownValue(
    breakdownMode === 'region' ? earning.courier?.district || earning.courier?.city : earning.status,
    earning.amount,
  ));
  const statusLabel = (status: string) => ({ PENDING: 'Menunggu', PAID: 'Dibayar', APPROVED: 'Disetujui', REJECTED: 'Ditolak' }[status] || status);
  const breakdownData = [...breakdownMap.entries()].sort(([, left], [, right]) => right - left).map(([category, total]) => ({
    category: breakdownMode === 'status' ? statusLabel(category) : category,
    total,
  }));

  const pendingBalance = earnings.filter(e => e.status === 'PENDING').reduce((sum, e) => sum + e.commission_amount, 0);
  const paidBalance = earnings.filter(e => e.status === 'PAID').reduce((sum, e) => sum + e.commission_amount, 0);
  const pendingWithdrawal = withdrawals.filter(w => w.status === 'PENDING').reduce((sum, w) => sum + w.amount, 0);
  // New earnings are created as PENDING and become PAID only after admin
  // approves a withdrawal. Therefore PENDING is the withdrawable balance;
  // subtract active withdrawal requests to prevent duplicate requests.
  const availableBalance = Math.max(0, pendingBalance - pendingWithdrawal);

  const withdrawMutation = useMutation({
    mutationFn: async () => {
      if (!user) return;
      const amount = parseInt(withdrawForm.amount);
      if (!amount || amount < 10000) throw new Error('Minimum withdrawal Rp 10.000');
      if (amount > availableBalance) throw new Error('Saldo tidak mencukupi');
      if (!withdrawForm.bank_name || !withdrawForm.account_number || !withdrawForm.account_holder)
        throw new Error('Lengkapi semua data rekening');

      const { error } = await supabase.from('verifikator_withdrawals').insert({
        verifikator_id: user.id,
        amount,
        bank_name: withdrawForm.bank_name,
        account_number: withdrawForm.account_number,
        account_holder: withdrawForm.account_holder,
        status: 'PENDING',
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Permintaan withdrawal telah diajukan');
      setShowWithdrawDialog(false);
      setWithdrawForm({ amount: '', bank_name: '', account_number: '', account_holder: '' });
      queryClient.invalidateQueries({ queryKey: ['verifikator-earnings', user?.id] });
    },
    onError: (err: unknown) => toast.error(err instanceof Error ? err.message : 'Gagal mengajukan withdrawal'),
  });

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'PENDING':
        return <Badge variant="outline" className="text-warning border-warning"><Clock className="h-3 w-3 mr-1" /> Pending</Badge>;
      case 'PAID':
      case 'APPROVED':
        return <Badge className="bg-success text-success-foreground"><CheckCircle className="h-3 w-3 mr-1" /> {status === 'PAID' ? 'Dibayar' : 'Disetujui'}</Badge>;
      case 'REJECTED':
        return <Badge variant="destructive"><XCircle className="h-3 w-3 mr-1" /> Ditolak</Badge>;
      default:
        return <Badge variant="secondary">{status}</Badge>;
    }
  };

  if (loading) {
    return (
      <VerifikatorLayout title="Pendapatan Komisi" subtitle="Kelola pendapatan dan withdrawal Anda">
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
        </div>
      </VerifikatorLayout>
    );
  }

  return (
    <VerifikatorLayout title="Pendapatan Komisi" subtitle="Kelola pendapatan dan withdrawal Anda">
      <Card className="mb-6">
        <CardContent className="p-4">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="font-medium">Filter periode laporan</p>
              <p className="text-sm text-muted-foreground">Total fee dan tabel laporan akan mengikuti tanggal yang dipilih.</p>
            </div>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
              <div className="space-y-1">
                <Label htmlFor="earnings-start-date">Mulai tanggal</Label>
                <Input id="earnings-start-date" type="date" value={startDate} onChange={event => setStartDate(event.target.value)} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="earnings-end-date">Sampai tanggal</Label>
                <Input id="earnings-end-date" type="date" value={endDate} onChange={event => setEndDate(event.target.value)} />
              </div>
              <Button type="button" variant="outline" onClick={() => { setStartDate(''); setEndDate(''); }} disabled={!startDate && !endDate}>Reset</Button>
            </div>
          </div>
          {hasInvalidDateRange && <p className="mt-3 text-sm text-destructive">Tanggal mulai tidak boleh lebih besar dari tanggal akhir.</p>}
          {!hasInvalidDateRange && (startDate || endDate) && <p className="mt-3 text-xs text-muted-foreground">Menampilkan {filteredEarnings.length} komisi pedagang dan {filteredCourierEarnings.length} fee ojek.</p>}
        </CardContent>
      </Card>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <Card className="bg-gradient-to-br from-primary/10 to-primary/5">
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-3 rounded-full bg-primary/20">
                <Wallet className="h-6 w-6 text-primary" />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Saldo Tersedia</p>
                <p className="text-2xl font-bold">{formatPrice(availableBalance)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-3 rounded-full bg-warning/20">
                <Clock className="h-6 w-6 text-warning" />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Proses Withdrawal</p>
                <p className="text-2xl font-bold">{formatPrice(pendingWithdrawal)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-3 rounded-full bg-success/20">
                <CheckCircle className="h-6 w-6 text-success" />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Total Dicairkan</p>
                <p className="text-2xl font-bold">{formatPrice(paidBalance)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
        <Card className="border-primary/20 bg-primary/5 lg:col-span-1">
          <CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><TrendingUp className="h-4 w-4 text-primary" />Total fee terlapor</CardTitle></CardHeader>
          <CardContent><p className="text-3xl font-bold">{formatPrice(generatedFeeTotal)}</p><p className="text-xs text-muted-foreground mt-1">Gabungan komisi pedagang dan fee ojek</p></CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><Store className="h-4 w-4 text-emerald-600" />Dari pedagang</CardTitle></CardHeader>
          <CardContent><p className="text-2xl font-bold">{formatPrice(merchantFeeTotal)}</p><p className="text-xs text-muted-foreground mt-1">{filteredEarnings.length} catatan komisi · subscription/penjualan</p></CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><Bike className="h-4 w-4 text-orange-600" />Dari ojek</CardTitle></CardHeader>
          <CardContent><p className="text-2xl font-bold">{formatPrice(courierFeeTotal)}</p><p className="text-xs text-muted-foreground mt-1">{filteredCourierEarnings.length} catatan fee · courier terhubung</p></CardContent>
        </Card>
      </div>

      <Card className="mb-6">
        <CardHeader><CardTitle className="flex items-center gap-2 text-lg"><Database className="h-5 w-5 text-primary" />Struktur relasi kode verifikator</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 md:grid-cols-3">
            <div className="rounded-lg border bg-muted/30 p-3"><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">verifikator_codes</p><p className="mt-1 font-mono text-sm">code → verifikator_id</p><p className="mt-1 text-xs text-muted-foreground">{codes.length} kode milik Anda</p></div>
            <div className="rounded-lg border bg-muted/30 p-3"><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">merchants</p><p className="mt-1 font-mono text-sm">verifikator_code</p><p className="mt-1 text-xs text-muted-foreground">Komisi tercatat di verifikator_earnings</p></div>
            <div className="rounded-lg border bg-muted/30 p-3"><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">couriers</p><p className="mt-1 font-mono text-sm">verifikator_id / code</p><p className="mt-1 text-xs text-muted-foreground">Fee dibaca dari courier_earnings</p></div>
          </div>
          <div className="flex items-start gap-2 text-sm text-muted-foreground"><Link2 className="mt-0.5 h-4 w-4 shrink-0 text-primary" /><p><strong className="text-foreground">Alur laporan:</strong> kode menghubungkan pedagang dan ojek ke verifikator; nilai pedagang berasal dari <code>commission_amount</code>, sedangkan nilai ojek berasal dari <code>courier_earnings.amount</code>. Saldo tarik tetap hanya memakai komisi verifikator.</p></div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 xl:grid-cols-5 gap-4 mb-6">
        <Card className="xl:col-span-3">
          <CardHeader>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div><CardTitle className="text-lg">Tren pendapatan</CardTitle><p className="text-sm text-muted-foreground mt-1">Gabungan komisi pedagang dan fee ojek</p></div>
              <Select value={trendMode} onValueChange={value => setTrendMode(value as 'daily' | 'monthly')}>
                <SelectTrigger className="w-full sm:w-[150px]" aria-label="Periode grafik tren"><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="daily">Harian</SelectItem><SelectItem value="monthly">Bulanan</SelectItem></SelectContent>
              </Select>
            </div>
          </CardHeader>
          <CardContent>
            {trendData.length === 0 ? <div className="h-[280px] flex items-center justify-center text-sm text-muted-foreground">Belum ada data pada periode yang dipilih.</div> : (
              <ResponsiveContainer width="100%" height={280}>
                <LineChart data={trendData} margin={{ top: 8, right: 12, left: 8, bottom: 8 }}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                  <XAxis dataKey="period" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} tickFormatter={value => formatPrice(Number(value))} width={82} />
                  <Tooltip formatter={value => formatPrice(Number(value))} labelClassName="font-medium" />
                  <Line type="monotone" dataKey="total" name="Pendapatan" stroke="hsl(var(--primary))" strokeWidth={3} dot={{ r: 3 }} activeDot={{ r: 5 }} />
                </LineChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
        <Card className="xl:col-span-2">
          <CardHeader>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div><CardTitle className="text-lg">Ringkasan komisi</CardTitle><p className="text-sm text-muted-foreground mt-1">Kelompokkan berdasarkan wilayah atau status</p></div>
              <Select value={breakdownMode} onValueChange={value => setBreakdownMode(value as 'region' | 'status')}>
                <SelectTrigger className="w-full sm:w-[150px]" aria-label="Kategori ringkasan komisi"><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="region">Wilayah</SelectItem><SelectItem value="status">Status komisi</SelectItem></SelectContent>
              </Select>
            </div>
          </CardHeader>
          <CardContent>
            {breakdownData.length === 0 ? <div className="h-[280px] flex items-center justify-center text-sm text-muted-foreground">Belum ada data pada periode yang dipilih.</div> : (
              <ResponsiveContainer width="100%" height={280}>
                <BarChart data={breakdownData} margin={{ top: 8, right: 8, left: 8, bottom: 8 }}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                  <XAxis dataKey="category" tick={{ fontSize: 10 }} interval={0} angle={breakdownData.length > 3 ? -25 : 0} textAnchor={breakdownData.length > 3 ? 'end' : 'middle'} height={breakdownData.length > 3 ? 58 : 30} />
                  <YAxis tick={{ fontSize: 11 }} tickFormatter={value => formatPrice(Number(value))} width={82} />
                  <Tooltip formatter={value => formatPrice(Number(value))} />
                  <Bar dataKey="total" name="Komisi" fill="hsl(var(--chart-2))" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
      </div>
      <div className="mb-6">
        <Button onClick={() => setShowWithdrawDialog(true)} disabled={availableBalance < 10000} className="gap-2">
          <ArrowDownToLine className="h-4 w-4" />
          Tarik Saldo
        </Button>
        {availableBalance < 10000 && (
          <p className="text-sm text-muted-foreground mt-2">Minimum saldo untuk withdrawal adalah Rp 10.000</p>
        )}
      </div>

      <Tabs defaultValue="earnings" className="space-y-4">
        <TabsList>
          <TabsTrigger value="earnings" className="gap-2">
            <TrendingUp className="h-4 w-4" /> Riwayat Komisi
          </TabsTrigger>
          <TabsTrigger value="courier-earnings" className="gap-2">
            <Bike className="h-4 w-4" /> Fee Ojek
          </TabsTrigger>
          <TabsTrigger value="withdrawals" className="gap-2">
            <History className="h-4 w-4" /> Riwayat Withdrawal
          </TabsTrigger>
          <TabsTrigger value="referral" className="gap-2">
            <Store className="h-4 w-4" /> Komisi Referral Merchant
          </TabsTrigger>
        </TabsList>

        <TabsContent value="earnings">
          <Card>
            <CardHeader><CardTitle className="text-lg">Riwayat Komisi</CardTitle></CardHeader>
            <CardContent>
              {filteredEarnings.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">
                  {earnings.length === 0 ? 'Belum ada riwayat komisi. Komisi akan masuk ketika referral Anda melakukan transaksi, membeli kuota, atau membeli produk admin.' : 'Tidak ada komisi pada rentang tanggal yang dipilih.'}
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Tanggal</TableHead>
                      <TableHead>Pedagang</TableHead>
                      <TableHead>Sumber</TableHead>
                      <TableHead className="text-right">Harga Paket</TableHead>
                      <TableHead className="text-right">Komisi</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filteredEarnings.map(earning => (
                      <TableRow key={earning.id}>
                        <TableCell>{format(new Date(earning.created_at), 'dd MMM yyyy', { locale: id })}</TableCell>
                        <TableCell className="font-medium">{earning.merchant?.name || '-'}</TableCell>
                        <TableCell>{earning.source_type === 'ADMIN_PRODUCT_DRIVER' ? 'Produk admin · Driver' : earning.source_type === 'ADMIN_PRODUCT_MERCHANT' ? 'Produk admin · Merchant' : earning.source_type === 'QUOTA_SALE' ? 'Penjualan kuota' : earning.source_type === 'TRANSACTION' ? 'Transaksi' : earning.package?.name || '-'}</TableCell>
                        <TableCell className="text-right">{formatPrice(earning.package_amount)}</TableCell>
                        <TableCell className="text-right font-medium text-success">
                          +{formatPrice(earning.commission_amount)} ({earning.commission_percent}%)
                        </TableCell>
                        <TableCell>{getStatusBadge(earning.status)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="courier-earnings">
          <Card>
            <CardHeader><CardTitle className="text-lg">Rincian Fee Ojek</CardTitle></CardHeader>
            <CardContent>
              {filteredCourierEarnings.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">{courierEarnings.length === 0 ? 'Belum ada fee ojek dari courier yang terhubung dengan kode Anda.' : 'Tidak ada fee ojek pada rentang tanggal yang dipilih.'}</div>
              ) : (
                <Table>
                  <TableHeader><TableRow><TableHead>Tanggal</TableHead><TableHead>Nama Ojek</TableHead><TableHead>Jenis</TableHead><TableHead className="text-right">Fee</TableHead><TableHead>Status</TableHead></TableRow></TableHeader>
                  <TableBody>{filteredCourierEarnings.map(earning => (
                    <TableRow key={earning.id}>
                      <TableCell>{format(new Date(earning.created_at), 'dd MMM yyyy', { locale: id })}</TableCell>
                      <TableCell className="font-medium">{earning.courier?.name || '-'}</TableCell>
                      <TableCell>{earning.type || 'DELIVERY'}</TableCell>
                      <TableCell className="text-right font-medium text-success">+{formatPrice(earning.amount)}</TableCell>
                      <TableCell>{getStatusBadge(earning.status)}</TableCell>
                    </TableRow>
                  ))}</TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="withdrawals">
          <Card>
            <CardHeader><CardTitle className="text-lg">Riwayat Withdrawal</CardTitle></CardHeader>
            <CardContent>
              {withdrawals.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">Belum ada riwayat withdrawal</div>
              ) : (
                <div className="space-y-3">
                  {withdrawals.map(withdrawal => (
                    <div key={withdrawal.id} className="p-4 border rounded-lg">
                      <div className="flex items-start justify-between">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2">
                            <p className="font-medium">{formatPrice(withdrawal.amount)}</p>
                            {getStatusBadge(withdrawal.status)}
                          </div>
                          <p className="text-sm text-muted-foreground">{withdrawal.bank_name} - {withdrawal.account_number}</p>
                          <p className="text-sm text-muted-foreground">a.n. {withdrawal.account_holder}</p>
                          <p className="text-xs text-muted-foreground">
                            {format(new Date(withdrawal.created_at), 'dd MMM yyyy HH:mm', { locale: id })}
                          </p>
                          {withdrawal.admin_notes && (
                            <p className="text-sm text-muted-foreground mt-2 p-2 bg-muted rounded">
                              Catatan: {withdrawal.admin_notes}
                            </p>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      <Dialog open={showWithdrawDialog} onOpenChange={setShowWithdrawDialog}>
        <DialogContent>
          <DialogHeader><DialogTitle>Tarik Saldo</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="p-4 bg-muted rounded-lg">
              <p className="text-sm text-muted-foreground">Saldo Tersedia</p>
              <p className="text-2xl font-bold">{formatPrice(availableBalance)}</p>
            </div>
            <div className="space-y-2">
              <Label>Jumlah Penarikan</Label>
              <Input type="number" placeholder="Minimum Rp 10.000" value={withdrawForm.amount}
                onChange={e => setWithdrawForm(p => ({ ...p, amount: e.target.value }))} />
            </div>
            <div className="space-y-2">
              <Label>Bank / E-Wallet</Label>
              <Select value={withdrawForm.bank_name} onValueChange={v => setWithdrawForm(p => ({ ...p, bank_name: v }))}>
                <SelectTrigger><SelectValue placeholder="Pilih bank atau e-wallet" /></SelectTrigger>
                <SelectContent>
                  {BANKS.map(bank => <SelectItem key={bank} value={bank}>{bank}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Nomor Rekening / HP</Label>
              <Input placeholder="Contoh: 1234567890" value={withdrawForm.account_number}
                onChange={e => setWithdrawForm(p => ({ ...p, account_number: e.target.value }))} />
            </div>
            <div className="space-y-2">
              <Label>Nama Pemilik Rekening</Label>
              <Input placeholder="Nama sesuai rekening" value={withdrawForm.account_holder}
                onChange={e => setWithdrawForm(p => ({ ...p, account_holder: e.target.value }))} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowWithdrawDialog(false)} disabled={withdrawMutation.isPending}>Batal</Button>
            <Button onClick={() => withdrawMutation.mutate()} disabled={withdrawMutation.isPending}>
              {withdrawMutation.isPending ? 'Memproses...' : 'Ajukan Withdrawal'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </VerifikatorLayout>
  );
}
