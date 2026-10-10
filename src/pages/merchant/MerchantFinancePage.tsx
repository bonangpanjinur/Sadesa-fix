import { useMemo, useState } from 'react';
import { Download, RefreshCw, Search, Wallet, TrendingDown, TrendingUp, ShoppingCart, ReceiptText } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { format, subDays } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';
import { supabase } from '@/integrations/supabase/client';
import { MerchantCardError, MerchantCardLoading } from '@/components/merchant/MerchantDataState';
import { formatPrice } from '@/lib/utils';
import { downloadCsv } from '@/lib/csv';
import { toast } from 'sonner';

const DONE_STATUSES = ['DONE', 'DELIVERED', 'COMPLETED'];
const REFUNDED_STATUSES = ['REFUNDED', 'CANCELLED', 'CANCELED', 'REJECTED'];
const localDate = (date: Date) => format(date, 'yyyy-MM-dd');

type OrderRow = {
  id: string; total: number | null; subtotal: number | null; shipping_cost: number | null;
  voucher_discount: number | null; status: string; payment_status: string | null;
  payment_method: string | null; delivery_name: string | null; created_at: string;
};
type FeeSetting = { fee_percent: number; is_enabled: boolean };
type Wallet = { id: string; balance_rupiah: number; debt_rupiah: number; is_active: boolean };
type LedgerRow = { source_id: string | null; entry_type: string; amount_delta_rupiah: number; debt_delta_rupiah: number; base_amount_rupiah: number | null; fee_percent: number | null; created_at: string };
type FinanceData = { orders: OrderRow[]; fee: FeeSetting | null; wallet: Wallet | null; ledger: LedgerRow[] };

const statusLabel = (status: string) => ({ DONE: 'Selesai', DELIVERED: 'Terkirim', COMPLETED: 'Selesai', REFUNDED: 'Refund', CANCELLED: 'Dibatalkan', CANCELED: 'Dibatalkan', REJECTED: 'Ditolak' }[status] ?? status);
const paymentLabel = (value: string | null) => ({ COD: 'COD', TRANSFER: 'Transfer', QRIS: 'QRIS', CASH: 'Tunai', UNPAID: 'Belum dibayar', PAID: 'Lunas' }[value ?? ''] ?? value ?? '-');
const amount = (value: number | null | undefined) => Number(value ?? 0);

export default function MerchantFinancePage() {
  const { merchantId, merchantName, loading: guardLoading } = useMerchantGuard();
  const [from, setFrom] = useState(() => localDate(subDays(new Date(), 30)));
  const [to, setTo] = useState(() => localDate(new Date()));
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [paymentFilter, setPaymentFilter] = useState('ALL');
  const [search, setSearch] = useState('');

  const { data, isLoading, isError, isFetching, refetch } = useQuery<FinanceData>({
    queryKey: ['merchant-finance-detail', merchantId, from, to],
    enabled: !!merchantId && !guardLoading && from <= to,
    retry: false,
    queryFn: async () => {
      const end = new Date(`${to}T00:00:00`);
      end.setDate(end.getDate() + 1);
      const ordersPromise = supabase.from('orders').select('id,total,subtotal,shipping_cost,voucher_discount,status,payment_status,payment_method,delivery_name,created_at').eq('merchant_id', merchantId!).gte('created_at', new Date(`${from}T00:00:00`).toISOString()).lt('created_at', end.toISOString()).order('created_at', { ascending: false });
      const feePromise = supabase.from('commission_fee_settings' as never).select('fee_percent,is_enabled').eq('owner_type' as never, 'MERCHANT' as never).maybeSingle();
      const walletPromise = supabase.from('commission_wallets' as never).select('id,balance_rupiah,debt_rupiah,is_active').eq('owner_type' as never, 'MERCHANT' as never).eq('merchant_id' as never, merchantId! as never).maybeSingle();
      const [ordersRes, feeRes, walletRes] = await Promise.all([ordersPromise, feePromise, walletPromise]);
      if (ordersRes.error) throw ordersRes.error;
      if (feeRes.error) throw feeRes.error;
      if (walletRes.error) throw walletRes.error;
      const wallet = walletRes.data as unknown as Wallet | null;
      let ledger: LedgerRow[] = [];
      if (wallet?.id) {
        const { data: ledgerData, error: ledgerError } = await supabase.from('commission_wallet_ledger' as never).select('source_id,entry_type,amount_delta_rupiah,debt_delta_rupiah,base_amount_rupiah,fee_percent,created_at').eq('wallet_id' as never, wallet.id as never).gte('created_at' as never, new Date(`${from}T00:00:00`).toISOString() as never).lt('created_at' as never, end.toISOString() as never).order('created_at' as never, { ascending: false } as never);
        if (ledgerError) throw ledgerError;
        ledger = (ledgerData ?? []) as unknown as LedgerRow[];
      }
      return { orders: (ordersRes.data ?? []) as OrderRow[], fee: feeRes.data as unknown as FeeSetting | null, wallet, ledger };
    },
  });

  const orders = useMemo(() => data?.orders ?? [], [data?.orders]);
  const visibleOrders = useMemo(() => orders.filter((order) => {
    const matchesStatus = statusFilter === 'ALL' || order.status === statusFilter;
    const matchesPayment = paymentFilter === 'ALL' || (order.payment_method ?? order.payment_status) === paymentFilter;
    const query = search.trim().toLowerCase();
    return matchesStatus && matchesPayment && (!query || order.id.toLowerCase().includes(query) || (order.delivery_name ?? '').toLowerCase().includes(query));
  }), [orders, paymentFilter, search, statusFilter]);

  const completedOrders = orders.filter((order) => DONE_STATUSES.includes(order.status) && order.payment_status !== 'REFUNDED');
  const grossRevenue = completedOrders.reduce((sum, order) => sum + amount(order.subtotal || order.total), 0);
  const shippingRevenue = completedOrders.reduce((sum, order) => sum + amount(order.shipping_cost), 0);
  const discounts = completedOrders.reduce((sum, order) => sum + amount(order.voucher_discount), 0);
  const refunded = orders.filter((order) => order.payment_status === 'REFUNDED' || REFUNDED_STATUSES.includes(order.status)).reduce((sum, order) => sum + amount(order.total), 0);
  const commission = data?.ledger.filter((entry) => entry.entry_type === 'COMMISSION').reduce((sum, entry) => sum + Math.max(0, -amount(entry.amount_delta_rupiah) + amount(entry.debt_delta_rupiah)), 0) ?? (data?.fee?.is_enabled ? Math.round(grossRevenue * Number(data.fee.fee_percent) / 100) : 0);
  const netRevenue = grossRevenue - refunded - commission;

  const getOrderCommission = (order: OrderRow) => {
    const entry = data?.ledger.find((item) => item.source_id === order.id && item.entry_type === 'COMMISSION');
    return entry ? Math.max(0, -amount(entry.amount_delta_rupiah) + amount(entry.debt_delta_rupiah)) : (data?.fee?.is_enabled && DONE_STATUSES.includes(order.status) ? Math.round(amount(order.subtotal || order.total) * Number(data.fee.fee_percent) / 100) : 0);
  };
  const exportCsv = () => {
    downloadCsv(`laporan-keuangan-${merchantName || 'toko'}-${from}-${to}.csv`, [['ID transaksi', 'Tanggal', 'Pelanggan', 'Status', 'Pembayaran', 'Subtotal', 'Ongkir', 'Diskon', 'Total', 'Komisi', 'Bersih'], ...visibleOrders.map((order) => { const fee = getOrderCommission(order); return [order.id, order.created_at, order.delivery_name ?? '', statusLabel(order.status), paymentLabel(order.payment_method ?? order.payment_status), amount(order.subtotal || order.total), amount(order.shipping_cost), amount(order.voucher_discount), amount(order.total), fee, amount(order.total) - fee]; })]);
    toast.success('Laporan transaksi berhasil diekspor');
  };

  if (guardLoading || isLoading) return <MerchantLayout title="Laporan Keuangan" subtitle="Riwayat transaksi dan rekonsiliasi merchant"><MerchantCardLoading label="Memuat laporan keuangan..." /></MerchantLayout>;
  if (isError) return <MerchantLayout title="Laporan Keuangan"><MerchantCardError message="Laporan keuangan gagal dimuat. Periksa koneksi lalu coba lagi." onRetry={() => void refetch()} /></MerchantLayout>;

  return <MerchantLayout title="Laporan Keuangan" subtitle="Riwayat transaksi dan rekonsiliasi merchant" actions={<><Button variant="outline" size="sm" onClick={() => void refetch()} disabled={isFetching}><RefreshCw className={`mr-2 h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />Refresh</Button><Button size="sm" onClick={exportCsv} disabled={!visibleOrders.length}><Download className="mr-2 h-4 w-4" />Export CSV</Button></>}>
    <div className="space-y-6">
      <Card><CardContent className="flex flex-wrap items-end gap-3 p-4"><div><label className="mb-1 block text-xs font-medium">Dari</label><Input type="date" value={from} max={to} onChange={(event) => setFrom(event.target.value)} /></div><div><label className="mb-1 block text-xs font-medium">Sampai</label><Input type="date" value={to} min={from} max={localDate(new Date())} onChange={(event) => setTo(event.target.value)} /></div><div className="rounded-md border bg-muted/30 px-3 py-2 text-sm"><span className="text-muted-foreground">Periode </span><strong>{format(new Date(`${from}T00:00:00`), 'd MMM yyyy', { locale: idLocale })} – {format(new Date(`${to}T00:00:00`), 'd MMM yyyy', { locale: idLocale })}</strong></div><div className="ml-auto text-xs text-muted-foreground">{orders.length} transaksi ditemukan</div></CardContent></Card>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">{[['Omzet produk', grossRevenue, TrendingUp, 'text-emerald-600'], ['Refund', refunded, TrendingDown, 'text-red-600'], ['Komisi dipotong', commission, ReceiptText, 'text-orange-600'], ['Pendapatan bersih', netRevenue, Wallet, 'text-primary'], ['Pesanan selesai', completedOrders.length, ShoppingCart, 'text-blue-600']].map(([label, value, Icon, tone]) => <Card key={String(label)}><CardContent className="p-4"><div className="flex items-center justify-between"><p className="text-xs text-muted-foreground">{label}</p><Icon className={`h-4 w-4 ${tone}`} /></div><p className="mt-2 text-xl font-bold">{label === 'Pesanan selesai' ? value : formatPrice(Number(value))}</p><p className="mt-1 text-[11px] text-muted-foreground">{label === 'Komisi dipotong' ? (data?.fee?.is_enabled ? `Tarif dinamis ${data.fee.fee_percent}%` : 'Komisi nonaktif') : label === 'Pendapatan bersih' ? 'Omzet − refund − komisi' : 'Periode terpilih'}</p></CardContent></Card>)}</div>
      <div className="grid gap-4 lg:grid-cols-3"><Card><CardHeader><CardTitle className="text-base">Saldo merchant</CardTitle><CardDescription>Saldo dipakai otomatis untuk potongan komisi.</CardDescription></CardHeader><CardContent><p className="text-2xl font-bold">{formatPrice(data?.wallet?.balance_rupiah ?? 0)}</p><p className="mt-2 text-sm text-muted-foreground">Tagihan tertunggak: <strong className={(data?.wallet?.debt_rupiah ?? 0) > 0 ? 'text-destructive' : 'text-foreground'}>{formatPrice(data?.wallet?.debt_rupiah ?? 0)}</strong></p><p className="mt-1 text-xs text-muted-foreground">{data?.wallet?.is_active === false ? 'Wallet nonaktif' : 'Wallet aktif'} · <a className="text-primary underline" href="/merchant/wallet">Kelola saldo</a></p></CardContent></Card><Card className="lg:col-span-2"><CardHeader><CardTitle className="text-base">Rincian arus transaksi</CardTitle><CardDescription>Angka dihitung dari transaksi yang tersimpan pada periode aktif.</CardDescription></CardHeader><CardContent className="grid grid-cols-2 gap-4 sm:grid-cols-4"><div><p className="text-xs text-muted-foreground">Subtotal</p><p className="font-semibold">{formatPrice(grossRevenue)}</p></div><div><p className="text-xs text-muted-foreground">Ongkir</p><p className="font-semibold">{formatPrice(shippingRevenue)}</p></div><div><p className="text-xs text-muted-foreground">Diskon</p><p className="font-semibold">{formatPrice(discounts)}</p></div><div><p className="text-xs text-muted-foreground">Tarif aktif</p><p className="font-semibold">{data?.fee?.is_enabled ? `${data.fee.fee_percent}%` : 'Nonaktif'}</p></div></CardContent></Card></div>
      <Card><CardHeader><CardTitle>Riwayat transaksi</CardTitle><CardDescription>Cari berdasarkan ID/pelanggan dan filter status atau metode pembayaran.</CardDescription></CardHeader><CardContent><div className="mb-4 flex flex-wrap gap-2"><div className="relative min-w-56 flex-1"><Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" /><Input className="pl-9" placeholder="Cari ID atau nama pelanggan" value={search} onChange={(event) => setSearch(event.target.value)} /></div><Select value={statusFilter} onValueChange={setStatusFilter}><SelectTrigger className="w-40"><SelectValue placeholder="Status" /></SelectTrigger><SelectContent><SelectItem value="ALL">Semua status</SelectItem>{['DONE', 'DELIVERED', 'COMPLETED', 'REFUNDED', 'CANCELLED'].map((status) => <SelectItem key={status} value={status}>{statusLabel(status)}</SelectItem>)}</SelectContent></Select><Select value={paymentFilter} onValueChange={setPaymentFilter}><SelectTrigger className="w-40"><SelectValue placeholder="Pembayaran" /></SelectTrigger><SelectContent><SelectItem value="ALL">Semua pembayaran</SelectItem>{['COD', 'TRANSFER', 'QRIS', 'CASH'].map((method) => <SelectItem key={method} value={method}>{paymentLabel(method)}</SelectItem>)}</SelectContent></Select></div>{!visibleOrders.length ? <p className="py-10 text-center text-sm text-muted-foreground">Tidak ada transaksi yang cocok dengan filter.</p> : <div className="overflow-x-auto"><table className="w-full min-w-[760px] text-sm"><thead><tr className="border-b text-left text-xs text-muted-foreground"><th className="px-2 py-3">Transaksi</th><th className="px-2 py-3">Tanggal</th><th className="px-2 py-3">Status</th><th className="px-2 py-3">Pembayaran</th><th className="px-2 py-3 text-right">Total</th><th className="px-2 py-3 text-right">Komisi</th><th className="px-2 py-3 text-right">Bersih</th></tr></thead><tbody>{visibleOrders.map((order) => { const fee = getOrderCommission(order); return <tr key={order.id} className="border-b last:border-0"><td className="px-2 py-3"><p className="font-medium">#{order.id.slice(0, 8).toUpperCase()}</p><p className="text-xs text-muted-foreground">{order.delivery_name || 'Pelanggan'}</p></td><td className="px-2 py-3 text-xs text-muted-foreground">{format(new Date(order.created_at), 'd MMM yyyy, HH:mm', { locale: idLocale })}</td><td className="px-2 py-3"><Badge variant={REFUNDED_STATUSES.includes(order.status) ? 'destructive' : DONE_STATUSES.includes(order.status) ? 'default' : 'secondary'}>{statusLabel(order.status)}</Badge></td><td className="px-2 py-3">{paymentLabel(order.payment_method ?? order.payment_status)}</td><td className="px-2 py-3 text-right font-medium">{formatPrice(amount(order.total))}</td><td className="px-2 py-3 text-right text-orange-600">{fee ? `-${formatPrice(fee)}` : '-'}</td><td className="px-2 py-3 text-right font-semibold text-emerald-600">{formatPrice(amount(order.total) - fee)}</td></tr>; })}</tbody></table></div>}</CardContent></Card>
      <p className="text-xs text-muted-foreground">Komisi final mengikuti snapshot ledger server-side. Untuk transaksi lama yang belum memiliki ledger, tampilan menggunakan tarif merchant aktif sebagai estimasi dan akan ditandai ulang saat settlement tersedia.</p>
    </div>
  </MerchantLayout>;
}
