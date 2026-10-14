import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, Check, FileCheck2, RefreshCw, X } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { AdminFilterBar, AdminStatePanel } from '@/components/admin/AdminPagePrimitives';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';
import { logAdminAction } from '@/lib/auditLog';

type ApprovalKind = 'refund' | 'return' | 'void' | 'price_override' | 'approval';
type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'processed';

interface ApprovalItem {
  id: string;
  kind: ApprovalKind;
  status: ApprovalStatus;
  title: string;
  description: string;
  amount: number | null;
  createdAt: string;
  subjectId: string | null;
  metadata: Record<string, unknown>;
}

interface QueryResult<T> {
  data: T[] | null;
  error: { message: string } | null;
}

interface QueryBuilder<T> extends PromiseLike<QueryResult<T>> {
  select(columns: string): QueryBuilder<T>;
  eq(column: string, value: string): QueryBuilder<T>;
  order(column: string, options?: { ascending?: boolean }): QueryBuilder<T>;
  update(values: Record<string, unknown>): QueryBuilder<T>;
}

interface UntypedSupabaseClient {
  from<T extends Record<string, unknown>>(table: string): QueryBuilder<T>;
  rpc(name: string, params: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

const db = supabase as unknown as UntypedSupabaseClient;

const kindLabels: Record<ApprovalKind, string> = {
  refund: 'Refund',
  return: 'Return POS',
  void: 'Void POS',
  price_override: 'Price Override',
  approval: 'Approval Lainnya',
};

function toText(value: unknown, fallback = '-') {
  return typeof value === 'string' && value.trim() ? value : fallback;
}

function toAmount(value: unknown): number | null {
  return typeof value === 'number' ? value : typeof value === 'string' && value ? Number(value) : null;
}

function mapApprovalRows(rows: Record<string, unknown>[]): ApprovalItem[] {
  return rows.map((row) => {
    const rawType = toText(row.request_type, 'approval');
    const kind: ApprovalKind = rawType === 'refund' || rawType === 'return' || rawType === 'void' || rawType === 'price_override' ? rawType : 'approval';
    return {
      id: toText(row.id),
      kind,
      status: toText(row.status, 'pending') as ApprovalStatus,
      title: `${kindLabels[kind]}${kind === 'approval' ? ` (${rawType})` : ''} #${toText(row.id).slice(0, 8)}`,
      description: toText(row.reason, 'Tidak ada alasan yang diberikan'),
      amount: toAmount(row.requested_amount),
      createdAt: toText(row.created_at, new Date().toISOString()),
      subjectId: typeof row.subject_id === 'string' ? row.subject_id : null,
      metadata: row,
    };
  });
}

export default function AdminApprovalCenterPage() {
  const [items, setItems] = useState<ApprovalItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<'all' | ApprovalKind>('all');
  const [selected, setSelected] = useState<ApprovalItem | null>(null);
  const [decisionNotes, setDecisionNotes] = useState('');
  const [actionLoading, setActionLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const loadApprovals = useCallback(async (showRefresh = false) => {
    if (showRefresh) setRefreshing(true); else setLoading(true);
    setErrorMessage(null);
    try {
      const [refunds, returns, voids, overrides, approvals] = await Promise.all([
        db.from<Record<string, unknown>>('refund_requests').select('*').eq('status', 'PENDING').order('created_at', { ascending: false }),
        db.from<Record<string, unknown>>('pos_sale_returns').select('*').eq('status', 'pending').order('created_at', { ascending: false }),
        db.from<Record<string, unknown>>('pos_void_requests').select('*').eq('status', 'pending').order('created_at', { ascending: false }),
        db.from<Record<string, unknown>>('pos_price_override_requests').select('*').eq('status', 'pending').order('created_at', { ascending: false }),
        db.from<Record<string, unknown>>('approval_requests').select('*').eq('status', 'pending').order('created_at', { ascending: false }),
      ]);
      const firstError = [refunds, returns, voids, overrides, approvals].find((result) => result.error);
      if (firstError?.error) throw new Error(firstError.error.message);

      const mappedRefunds = (refunds.data ?? []).map((row): ApprovalItem => ({
        id: toText(row.id), kind: 'refund', status: 'pending',
        title: `Refund #${toText(row.id).slice(0, 8)}`,
        description: toText(row.reason, 'Permintaan refund marketplace'),
        amount: toAmount(row.amount), createdAt: toText(row.created_at, new Date().toISOString()),
        subjectId: typeof row.order_id === 'string' ? row.order_id : null, metadata: row,
      }));
      const mappedReturns = (returns.data ?? []).map((row): ApprovalItem => ({
        id: toText(row.id), kind: 'return', status: 'pending',
        title: `Retur ${toText(row.return_number, `#${toText(row.id).slice(0, 8)}`)}`,
        description: toText(row.reason, 'Retur penjualan POS'),
        amount: toAmount(row.total_refund), createdAt: toText(row.created_at, new Date().toISOString()),
        subjectId: typeof row.sale_id === 'string' ? row.sale_id : null, metadata: row,
      }));
      const mappedVoids = (voids.data ?? []).map((row): ApprovalItem => ({
        id: toText(row.id), kind: 'void', status: 'pending',
        title: `Void Sale #${toText(row.sale_id).slice(0, 8)}`,
        description: toText(row.reason, 'Pembatalan transaksi POS'), amount: null,
        createdAt: toText(row.created_at, new Date().toISOString()), subjectId: toText(row.sale_id), metadata: row,
      }));
      const mappedOverrides = (overrides.data ?? []).map((row): ApprovalItem => ({
        id: toText(row.id), kind: 'price_override', status: 'pending',
        title: `Price Override #${toText(row.id).slice(0, 8)}`,
        description: toText(row.reason, 'Perubahan harga transaksi POS'),
        amount: toAmount(row.requested_price), createdAt: toText(row.created_at, new Date().toISOString()),
        subjectId: typeof row.sale_item_id === 'string' ? row.sale_item_id : null, metadata: row,
      }));
      setItems([...mappedRefunds, ...mappedReturns, ...mappedVoids, ...mappedOverrides, ...mapApprovalRows(approvals.data ?? [])]);
    } catch (error) {
      console.error('Failed to load approval center:', error);
      setErrorMessage('Gagal memuat approval tertunda. Periksa koneksi dan permission database, lalu coba lagi.');
      toast.error('Gagal memuat approval yang tertunda');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => { void loadApprovals(); }, [loadApprovals]);

  const filteredItems = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    return items.filter((item) => {
      const matchesKind = filter === 'all' || item.kind === filter;
      const searchable = `${item.title} ${item.description} ${item.id} ${item.subjectId ?? ''}`.toLowerCase();
      return matchesKind && (!normalized || searchable.includes(normalized));
    });
  }, [filter, items, query]);

  const decide = async (approve: boolean) => {
    if (!selected) return;
    setActionLoading(true);
    try {
      let error: { message: string } | null = null;
      if (selected.kind === 'return') {
        ({ error } = await db.rpc('approve_pos_sale_return', { p_return_id: selected.id, p_approve: approve, p_rejection_reason: decisionNotes || null }));
      } else if (selected.kind === 'void') {
        ({ error } = await db.rpc('decide_pos_void', { p_request_id: selected.id, p_approve: approve, p_reason: decisionNotes || null }));
      } else if (selected.kind === 'price_override') {
        ({ error } = await db.rpc('decide_pos_price_override', { p_request_id: selected.id, p_approve: approve, p_reason: decisionNotes || null }));
      } else if (selected.kind === 'approval' && selected.metadata.request_type === 'stock_adjustment') {
        ({ error } = await db.rpc('decide_pos_stock_adjustment', { p_request_id: selected.id, p_approve: approve, p_notes: decisionNotes || null }));
      } else if (selected.kind === 'approval') {
        ({ error } = await db.rpc('decide_approval_request', { p_request_id: selected.id, p_approve: approve, p_notes: decisionNotes || null }));
      } else {
        ({ error } = await db.rpc('decide_refund_request', { p_request_id: selected.id, p_approve: approve, p_notes: decisionNotes || null }));
      }
      if (error) throw new Error(error.message);
      await logAdminAction(approve ? 'APPROVE_TRANSACTION_REQUEST' : 'REJECT_TRANSACTION_REQUEST', selected.kind, selected.id, { status: 'pending' }, { status: approve ? 'approved' : 'rejected', notes: decisionNotes || null });
      toast.success(selected.kind === 'refund' && approve
        ? 'Refund disetujui dan masuk antrean pencairan manual. Dana belum dikirim.'
        : `${kindLabels[selected.kind]} berhasil ${approve ? 'disetujui' : 'ditolak'}`);
      setSelected(null);
      setDecisionNotes('');
      await loadApprovals(true);
    } catch (error) {
      console.error('Failed to decide approval:', error);
      toast.error(error instanceof Error ? error.message : 'Gagal memproses approval');
    } finally {
      setActionLoading(false);
    }
  };

  const pendingCount = items.length;
  const amountTotal = items.reduce((sum, item) => sum + (item.amount ?? 0), 0);

  return (
    <AdminLayout title="Approval Center" subtitle="Kelola refund, retur, void, price override, dan permintaan approval transaksi">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Menunggu</p><p className="text-2xl font-bold text-warning">{pendingCount}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Refund</p><p className="text-2xl font-bold">{items.filter((item) => item.kind === 'refund' || item.kind === 'return').length}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Kontrol POS</p><p className="text-2xl font-bold">{items.filter((item) => item.kind === 'void' || item.kind === 'price_override').length}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Nilai terindikasi</p><p className="text-2xl font-bold">{formatPrice(amountTotal)}</p></CardContent></Card>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2"><FileCheck2 className="h-5 w-5 text-primary" /> Permintaan Tertunda</CardTitle>
        </CardHeader>
        <AdminFilterBar
          search={query}
          onSearchChange={setQuery}
          searchPlaceholder="Cari ID, alasan, atau subject..."
          actions={<Button variant="outline" size="sm" onClick={() => void loadApprovals(true)} disabled={refreshing} className="gap-2"><RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} /> Segarkan</Button>}
        >
          <select value={filter} onChange={(event) => setFilter(event.target.value as 'all' | ApprovalKind)} aria-label="Filter tipe approval" className="h-9 rounded-md border border-input bg-background px-3 text-sm">
            <option value="all">Semua tipe</option><option value="refund">Refund</option><option value="return">Retur POS</option><option value="void">Void POS</option><option value="price_override">Price override</option><option value="approval">Approval lainnya</option>
          </select>
        </AdminFilterBar>
        <CardContent>
          {loading ? <AdminStatePanel type="loading" title="Memuat tugas approval" description="Mengumpulkan refund, retur, void, dan price override yang menunggu keputusan." /> : errorMessage ? <AdminStatePanel type="error" description={errorMessage} actionLabel="Coba lagi" onAction={() => void loadApprovals(true)} /> : filteredItems.length === 0 ? <AdminStatePanel type="empty" title={query || filter !== 'all' ? 'Tidak ada hasil yang cocok' : 'Tidak ada approval tertunda'} description={query || filter !== 'all' ? 'Ubah kata kunci atau filter untuk melihat data lain.' : 'Semua tugas sensitif sudah ditangani.'} /> : <div className="space-y-3">
            {filteredItems.map((item) => <div key={`${item.kind}-${item.id}`} className="rounded-lg border p-4 flex flex-col lg:flex-row lg:items-center gap-4">
              <div className="flex-1 min-w-0"><div className="flex flex-wrap items-center gap-2 mb-1"><Badge variant="outline">{kindLabels[item.kind]}</Badge><span className="font-semibold truncate">{item.title}</span></div><p className="text-sm text-muted-foreground line-clamp-2">{item.description}</p><p className="text-xs text-muted-foreground mt-1">{new Date(item.createdAt).toLocaleString('id-ID')} · ID {item.id.slice(0, 12)}</p></div>
              <div className="flex items-center gap-4"><div className="text-right">{item.amount !== null && <p className="font-semibold">{formatPrice(item.amount)}</p>}<Badge variant="warning">Pending</Badge></div><Button onClick={() => { setSelected(item); setDecisionNotes(''); }}><FileCheck2 className="h-4 w-4 mr-2" />Review</Button></div>
            </div>)}
          </div>}
        </CardContent>
      </Card>

      {selected && <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-labelledby="approval-dialog-title">
        <Card className="w-full max-w-lg"><CardHeader><CardTitle id="approval-dialog-title" className="flex items-center gap-2"><AlertTriangle className="h-5 w-5 text-warning" />Review {kindLabels[selected.kind]}</CardTitle></CardHeader><CardContent className="space-y-4"><div className="rounded-md bg-muted/50 p-3"><p className="font-medium">{selected.title}</p><p className="text-sm text-muted-foreground mt-1">{selected.description}</p>{selected.amount !== null && <p className="font-semibold mt-2">Nilai: {formatPrice(selected.amount)}</p>}<p className="text-xs text-muted-foreground mt-2 break-all">Subject: {selected.subjectId ?? '-'}</p></div><Textarea value={decisionNotes} onChange={(event) => setDecisionNotes(event.target.value)} placeholder="Catatan keputusan (wajib diisi saat menolak)" maxLength={1000} /><div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setSelected(null)} disabled={actionLoading}>Batal</Button><Button variant="destructive" onClick={() => void decide(false)} disabled={actionLoading || !decisionNotes.trim()}><X className="h-4 w-4 mr-2" />Tolak</Button><Button onClick={() => void decide(true)} disabled={actionLoading}><Check className="h-4 w-4 mr-2" />Setujui</Button></div></CardContent></Card>
      </div>}
    </AdminLayout>
  );
}
