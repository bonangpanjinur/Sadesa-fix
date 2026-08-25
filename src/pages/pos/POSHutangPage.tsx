import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertCircle, CalendarClock, CreditCard, History, RefreshCw, Search, Wallet } from 'lucide-react';
import { POSLayout } from '@/components/pos/POSLayout';
import { usePOS } from '@/contexts/POSContext';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { toast } from 'sonner';

interface PurchaseOrder {
  id: string;
  po_number: string;
  supplier_id: string | null;
  supplier_name: string;
  total: number;
  amount_paid: number;
  amount_due: number;
  payment_status: 'unpaid' | 'partial' | 'paid' | 'overdue';
  payment_terms_days: number;
  due_date: string | null;
  order_date: string;
  status: string;
}

interface SupplierPayment {
  id: string;
  purchase_order_id: string;
  amount: number;
  payment_method: string;
  reference: string | null;
  notes: string | null;
  paid_at: string;
}

interface GenericResult {
  data: unknown;
  error: { message: string } | null;
}

interface QueryBuilder<T> extends PromiseLike<{ data: T[] | null; error: { message: string } | null }> {
  select(columns: string): QueryBuilder<T>;
  eq(column: string, value: string): QueryBuilder<T>;
  order(column: string, options?: { ascending?: boolean }): QueryBuilder<T>;
}

interface UntypedClient {
  from<T extends Record<string, unknown>>(table: string): QueryBuilder<T>;
  rpc(name: string, params: Record<string, unknown>): Promise<GenericResult>;
}

const db = supabase as unknown as UntypedClient;

function numeric(value: unknown) {
  return typeof value === 'number' ? value : Number(value ?? 0);
}

function mapOrder(row: Record<string, unknown>): PurchaseOrder {
  const supplier = row.pos_suppliers as { name?: string | null } | null;
  const dueDate = typeof row.due_date === 'string' ? row.due_date : null;
  const paymentStatus = (typeof row.payment_status === 'string' ? row.payment_status : 'unpaid') as PurchaseOrder['payment_status'];
  const isOverdue = paymentStatus !== 'paid' && dueDate !== null && new Date(dueDate) < new Date();
  return {
    id: String(row.id), po_number: String(row.po_number ?? row.order_number ?? row.id).slice(0, 24),
    supplier_id: typeof row.supplier_id === 'string' ? row.supplier_id : null,
    supplier_name: supplier?.name ?? String(row.supplier_name ?? 'Tanpa supplier'), total: numeric(row.total),
    amount_paid: numeric(row.amount_paid), amount_due: numeric(row.amount_due),
    payment_status: isOverdue ? 'overdue' : paymentStatus,
    payment_terms_days: numeric(row.payment_terms_days), due_date: dueDate,
    order_date: String(row.order_date ?? row.created_at ?? new Date().toISOString()), status: String(row.status ?? 'draft'),
  };
}

const statusLabel: Record<PurchaseOrder['payment_status'], string> = { unpaid: 'Belum dibayar', partial: 'Sebagian', paid: 'Lunas', overdue: 'Jatuh tempo' };

export default function POSHutangPage() {
  const { tenant, activeOutlet, formatCurrency } = usePOS();
  const [orders, setOrders] = useState<PurchaseOrder[]>([]);
  const [payments, setPayments] = useState<SupplierPayment[]>([]);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState<PurchaseOrder | null>(null);
  const [payAmount, setPayAmount] = useState('');
  const [paymentMethod, setPaymentMethod] = useState('transfer');
  const [reference, setReference] = useState('');
  const [notes, setNotes] = useState('');
  const [historyOpen, setHistoryOpen] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);

  const load = useCallback(async () => {
    if (!tenant || !activeOutlet) return;
    setLoading(true);
    try {
      const [orderResult, paymentResult] = await Promise.all([
        db.from<Record<string, unknown>>('pos_purchase_orders').select('*, pos_suppliers(name)').eq('tenant_id', tenant.id).eq('outlet_id', activeOutlet.id).order('due_date', { ascending: true }),
        db.from<Record<string, unknown>>('pos_supplier_payments').select('*').eq('tenant_id', tenant.id).eq('outlet_id', activeOutlet.id).order('paid_at', { ascending: false }),
      ]);
      if (orderResult.error) throw new Error(orderResult.error.message);
      if (paymentResult.error) throw new Error(paymentResult.error.message);
      setOrders((orderResult.data ?? []).map(mapOrder));
      setPayments((paymentResult.data ?? []).map((row) => ({ id: String(row.id), purchase_order_id: String(row.purchase_order_id), amount: numeric(row.amount), payment_method: String(row.payment_method ?? 'other'), reference: typeof row.reference === 'string' ? row.reference : null, notes: typeof row.notes === 'string' ? row.notes : null, paid_at: String(row.paid_at ?? row.created_at) })));
    } catch (error) {
      console.error('Failed to load supplier payables:', error);
      toast.error('Gagal memuat hutang supplier');
    } finally { setLoading(false); }
  }, [activeOutlet, tenant]);

  useEffect(() => { void load(); }, [load]);

  const filtered = useMemo(() => orders.filter((order) => `${order.po_number} ${order.supplier_name}`.toLowerCase().includes(query.toLowerCase())), [orders, query]);
  const outstanding = orders.reduce((sum, order) => sum + (order.payment_status === 'paid' ? 0 : order.amount_due), 0);
  const overdue = orders.filter((order) => order.payment_status === 'overdue');
  const openPayment = (order: PurchaseOrder) => { setSelected(order); setPayAmount(String(Math.max(0, order.amount_due))); setPaymentMethod('transfer'); setReference(''); setNotes(''); };
  const selectedPayments = selected ? payments.filter((payment) => payment.purchase_order_id === selected.id) : [];

  const recordPayment = async () => {
    if (!tenant || !activeOutlet || !selected) return;
    const amount = Number(payAmount);
    if (!Number.isFinite(amount) || amount <= 0 || amount > selected.amount_due) { toast.error('Jumlah pembayaran melebihi saldo hutang'); return; }
    setActionLoading(true);
    try {
      const { error } = await db.rpc('record_supplier_payment', { p_tenant_id: tenant.id, p_outlet_id: activeOutlet.id, p_purchase_order_id: selected.id, p_amount: amount, p_payment_method: paymentMethod, p_reference: reference || null, p_notes: notes || null });
      if (error) throw new Error(error.message);
      toast.success('Pembayaran hutang berhasil dicatat'); setSelected(null); await load();
    } catch (error) { console.error('Failed to record supplier payment:', error); toast.error(error instanceof Error ? error.message : 'Gagal mencatat pembayaran'); } finally { setActionLoading(false); }
  };

  return <POSLayout title="Hutang Supplier" subtitle="Termin, jatuh tempo, pembayaran sebagian, dan histori transaksi">
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
      <Card><CardContent className="p-4"><Wallet className="h-4 w-4 text-primary mb-2" /><p className="text-xs text-muted-foreground">Total hutang</p><p className="text-xl font-bold">{formatCurrency(outstanding)}</p></CardContent></Card>
      <Card><CardContent className="p-4"><AlertCircle className="h-4 w-4 text-destructive mb-2" /><p className="text-xs text-muted-foreground">Jatuh tempo</p><p className="text-xl font-bold text-destructive">{overdue.length}</p></CardContent></Card>
      <Card><CardContent className="p-4"><CalendarClock className="h-4 w-4 text-warning mb-2" /><p className="text-xs text-muted-foreground">PO terbuka</p><p className="text-xl font-bold">{orders.filter((order) => order.payment_status !== 'paid').length}</p></CardContent></Card>
      <Card><CardContent className="p-4"><History className="h-4 w-4 text-muted-foreground mb-2" /><p className="text-xs text-muted-foreground">Riwayat pembayaran</p><p className="text-xl font-bold">{payments.length}</p></CardContent></Card>
    </div>
    <Card>
      <CardHeader className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3"><CardTitle>Daftar Hutang Pembelian</CardTitle><div className="flex gap-2"><div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" /><Input className="pl-9 w-64" placeholder="Cari PO atau supplier" value={query} onChange={(event) => setQuery(event.target.value)} /></div><Button variant="outline" size="icon" onClick={() => void load()} aria-label="Refresh"><RefreshCw className="h-4 w-4" /></Button></div></CardHeader>
      <CardContent>{loading ? <div className="flex justify-center py-12"><RefreshCw className="h-7 w-7 animate-spin text-primary" /></div> : filtered.length === 0 ? <p className="text-center py-12 text-muted-foreground">Belum ada hutang pembelian.</p> : <div className="space-y-3">{filtered.map((order) => <div key={order.id} className="border rounded-lg p-4 flex flex-col lg:flex-row lg:items-center gap-3"><div className="flex-1"><div className="flex items-center gap-2"><p className="font-semibold">{order.po_number}</p><Badge variant={order.payment_status === 'overdue' ? 'destructive' : order.payment_status === 'paid' ? 'success' : 'warning'}>{statusLabel[order.payment_status]}</Badge></div><p className="text-sm text-muted-foreground">{order.supplier_name} · Total {formatCurrency(order.total)}</p><p className="text-xs text-muted-foreground mt-1">Jatuh tempo: {order.due_date ? new Date(order.due_date).toLocaleDateString('id-ID') : 'Tanpa termin'} · Dibayar {formatCurrency(order.amount_paid)}</p></div><div className="text-right"><p className="font-bold">{formatCurrency(order.amount_due)}</p><p className="text-xs text-muted-foreground">Saldo terutang</p></div><div className="flex gap-2"><Button variant="outline" size="sm" onClick={() => { setSelected(order); setHistoryOpen(true); }}><History className="h-4 w-4 mr-1" />Riwayat</Button>{order.payment_status !== 'paid' && <Button size="sm" onClick={() => openPayment(order)}><CreditCard className="h-4 w-4 mr-1" />Bayar</Button>}</div></div>)}</div>}</CardContent>
    </Card>
    <Dialog open={!!selected && !historyOpen} onOpenChange={(open) => !open && setSelected(null)}><DialogContent><DialogHeader><DialogTitle>Bayar Hutang Supplier</DialogTitle></DialogHeader>{selected && <div className="space-y-4"><div className="rounded-lg bg-muted p-3 text-sm"><p className="font-semibold">{selected.po_number} · {selected.supplier_name}</p><p className="text-muted-foreground">Saldo: {formatCurrency(selected.amount_due)}</p></div><div><Label>Jumlah pembayaran</Label><Input className="mt-1" type="number" min="1" max={selected.amount_due} value={payAmount} onChange={(event) => setPayAmount(event.target.value)} /></div><div><Label>Metode pembayaran</Label><select className="mt-1 h-10 w-full rounded-md border bg-background px-3 text-sm" value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)}><option value="transfer">Transfer</option><option value="cash">Cash</option><option value="debit">Debit</option><option value="credit">Credit</option><option value="other">Lainnya</option></select></div><div><Label>Referensi</Label><Input className="mt-1" value={reference} onChange={(event) => setReference(event.target.value)} placeholder="Nomor bukti transfer" /></div><div><Label>Catatan</Label><Textarea className="mt-1" value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={500} /></div></div>}<DialogFooter><Button variant="outline" onClick={() => setSelected(null)}>Batal</Button><Button onClick={() => void recordPayment()} disabled={actionLoading}>{actionLoading ? 'Menyimpan...' : 'Simpan Pembayaran'}</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={historyOpen} onOpenChange={(open) => { setHistoryOpen(open); if (!open) setSelected(null); }}><DialogContent><DialogHeader><DialogTitle>Histori Pembayaran</DialogTitle></DialogHeader>{selected && <div className="space-y-3"><p className="text-sm text-muted-foreground">{selected.po_number} · {selected.supplier_name}</p>{selectedPayments.length === 0 ? <p className="py-6 text-center text-muted-foreground">Belum ada pembayaran.</p> : selectedPayments.map((payment) => <div key={payment.id} className="border rounded-md p-3 flex justify-between"><div><p className="font-medium">{formatCurrency(payment.amount)}</p><p className="text-xs text-muted-foreground">{payment.payment_method} · {new Date(payment.paid_at).toLocaleString('id-ID')}</p>{payment.reference && <p className="text-xs">Ref: {payment.reference}</p>}</div></div>)}</div>}<DialogFooter><Button onClick={() => { setHistoryOpen(false); setSelected(null); }}>Tutup</Button></DialogFooter></DialogContent></Dialog>
  </POSLayout>;
}
