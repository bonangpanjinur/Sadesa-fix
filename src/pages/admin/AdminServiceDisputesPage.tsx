import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, Check, CheckCircle2, Eye, FileWarning, RefreshCw, ShieldCheck, Wallet, X } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { AdminStatePanel } from '@/components/admin/AdminPagePrimitives';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import { supabase } from '@/integrations/supabase/client';
import { logAdminAction } from '@/lib/auditLog';
import { formatPrice } from '@/lib/utils';
import { toast } from 'sonner';

const db = supabase as unknown as { from: typeof supabase.from; rpc: typeof supabase.rpc };
type ServiceRefund = { id: string; request_id: string; amount: number; status: 'PENDING' | 'COMPLETED'; external_reference: string | null; recorded_at: string | null };
type Dispute = { id: string; request_id: string; requester_id: string; provider_id: string; reason: string; amount: number | null; evidence_urls: string[]; status: string; admin_note: string | null; resolution: string | null; created_at: string; request?: { title: string; description: string; location: string; status: string; agreed_price: number | null; provider_payout: number | null }; refund?: ServiceRefund | null };
const statusMeta: Record<string, { label: string; tone: 'default' | 'secondary' | 'destructive' | 'outline' }> = { OPEN: { label: 'Terbuka', tone: 'destructive' }, IN_REVIEW: { label: 'Sedang ditinjau', tone: 'secondary' }, WAITING_PARTIES: { label: 'Menunggu pihak', tone: 'outline' }, REFUND_APPROVED: { label: 'Refund disetujui · menunggu transfer', tone: 'default' }, REFUNDED: { label: 'Refund ditransfer', tone: 'default' }, RELEASE_APPROVED: { label: 'Pencairan disetujui', tone: 'default' }, RESOLVED: { label: 'Selesai', tone: 'default' }, CLOSED: { label: 'Ditutup', tone: 'secondary' }, REJECTED: { label: 'Ditolak', tone: 'destructive' } };
const money = (value: number | null | undefined) => formatPrice(Number(value || 0));

export default function AdminServiceDisputesPage() {
  const [disputes, setDisputes] = useState<Dispute[]>([]);
  const [selected, setSelected] = useState<Dispute | null>(null);
  const [filter, setFilter] = useState('ALL');
  const [decision, setDecision] = useState('');
  const [note, setNote] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [refundReference, setRefundReference] = useState('');
  const [refundNote, setRefundNote] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await db.from('service_disputes').select('*,request:service_requests(title,description,location,status,agreed_price,provider_payout),refund:service_refunds!service_refunds_dispute_id_fkey(id,request_id,amount,status,external_reference,recorded_at)').order('created_at', { ascending: false });
    if (error) toast.error('Gagal memuat sengketa jasa. Pastikan migrasi sengketa sudah diterapkan.');
    else setDisputes(data || []);
    setLoading(false);
  }, []);
  useEffect(() => { void load(); }, [load]);

  const filtered = useMemo(() => disputes.filter((item) => filter === 'ALL' || item.status === filter), [disputes, filter]);
  const openCount = disputes.filter((item) => ['OPEN', 'IN_REVIEW', 'WAITING_PARTIES'].includes(item.status)).length;
  const refundCount = disputes.filter((item) => item.status === 'REFUND_APPROVED').length;
  const disputedValue = disputes.filter((item) => !['RESOLVED', 'CLOSED', 'REJECTED'].includes(item.status)).reduce((sum, item) => sum + Number(item.amount || item.request?.agreed_price || 0), 0);

  function openReview(item: Dispute) { setSelected(item); setDecision(item.status === 'OPEN' ? 'IN_REVIEW' : ['IN_REVIEW','WAITING_PARTIES'].includes(item.status) ? item.status : 'IN_REVIEW'); setNote(item.admin_note || ''); setRefundReference(''); setRefundNote(''); }
  async function saveDecision() {
    if (!selected || !decision || !note.trim()) return toast.error('Catatan keputusan wajib diisi agar riwayat mediasi jelas.');
    setSaving(true);
    const { error } = await db.rpc('service_admin_decide_dispute', { p_dispute_id: selected.id, p_decision: decision, p_note: note.trim() });
    if (error) toast.error(error.message || 'Gagal menyimpan keputusan');
    else { await logAdminAction('RESOLVE_SERVICE_DISPUTE', 'service_dispute', selected.id, { status: selected.status }, { status: decision, note: note.trim() }); toast.success('Keputusan sengketa berhasil disimpan.'); setSelected(null); setDecision(''); setNote(''); await load(); }
    setSaving(false);
  }

  async function recordRefund() {
    if (!selected || selected.status !== 'REFUND_APPROVED') return;
    if (refundReference.trim().length < 3) return toast.error('Masukkan referensi transfer refund aktual.');
    setSaving(true);
    const { error } = await db.rpc('service_admin_record_refund', { p_dispute_id: selected.id, p_external_reference: refundReference.trim(), p_note: refundNote.trim() || null });
    if (error) toast.error(error.message || 'Gagal merekonsiliasi transfer refund.');
    else { await logAdminAction('RECORD_SERVICE_REFUND', 'service_dispute', selected.id, { status: 'REFUND_APPROVED' }, { status: 'REFUNDED', external_reference: refundReference.trim() }); toast.success('Transfer refund dicatat dan transaksi direkonsiliasi.'); setRefundReference(''); setRefundNote(''); await load(); const updated = (await db.from('service_disputes').select('*,request:service_requests(title,description,location,status,agreed_price,provider_payout),refund:service_refunds!service_refunds_dispute_id_fkey(id,request_id,amount,status,external_reference,recorded_at)').eq('id', selected.id).single()); if (!updated.error && updated.data) setSelected(updated.data as Dispute); }
    setSaving(false);
  }

  return <AdminLayout title="Sengketa Jasa" subtitle="Mediasi komplain transaksi jasa dan lindungi dana kedua pihak">
    <div className="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4"><Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Kasus aktif</p><p className="mt-1 text-2xl font-bold text-warning">{openCount}</p><p className="text-xs text-muted-foreground">Perlu ditangani</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Nilai dipersengketakan</p><p className="mt-1 text-2xl font-bold">{money(disputedValue)}</p><p className="text-xs text-muted-foreground">Dana dalam risiko</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Refund disetujui</p><p className="mt-1 text-2xl font-bold">{refundCount}</p><p className="text-xs text-muted-foreground">Menunggu proses lanjutan</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Total kasus</p><p className="mt-1 text-2xl font-bold">{disputes.length}</p><p className="text-xs text-muted-foreground">Semua status</p></CardContent></Card></div>
    <Card><CardHeader className="flex-row items-center justify-between space-y-0"><CardTitle className="flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-emerald-700" />Antrean resolusi sengketa</CardTitle><Button variant="outline" size="sm" onClick={() => void load()} className="gap-2"><RefreshCw className="h-4 w-4" />Segarkan</Button></CardHeader><CardContent>{loading ? <AdminStatePanel type="loading" title="Memuat sengketa" description="Mengumpulkan komplain dan bukti transaksi jasa." /> : <><div className="mb-4 flex flex-wrap gap-2"><select value={filter} onChange={(event) => setFilter(event.target.value)} className="h-9 rounded-md border border-input bg-background px-3 text-sm"><option value="ALL">Semua status</option>{Object.entries(statusMeta).map(([value, meta]) => <option key={value} value={value}>{meta.label}</option>)}</select></div>{filtered.length === 0 ? <AdminStatePanel type="empty" title="Tidak ada sengketa" description="Belum ada komplain sesuai filter yang dipilih." /> : <div className="space-y-3">{filtered.map((item) => { const meta = statusMeta[item.status] || statusMeta.OPEN; return <div key={item.id} className="rounded-xl border p-4"><div className="flex flex-col gap-4 lg:flex-row lg:items-center"><div className="flex-1"><div className="flex flex-wrap items-center gap-2"><Badge variant={meta.tone}>{meta.label}</Badge><span className="font-semibold">{item.request?.title || `Request #${item.request_id.slice(0, 8)}`}</span></div><p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{item.reason}</p><p className="mt-1 text-xs text-muted-foreground">#{item.id.slice(0, 8).toUpperCase()} · {new Date(item.created_at).toLocaleString('id-ID')} · Nilai {money(item.amount || item.request?.agreed_price)}</p></div><Button variant="outline" onClick={() => openReview(item)} className="gap-2"><Eye className="h-4 w-4" />Tinjau kasus</Button></div></div>; })}</div>}</>}</CardContent></Card>
    <Dialog open={!!selected} onOpenChange={(open) => !open && setSelected(null)}><DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl"><DialogHeader><DialogTitle className="flex items-center gap-2"><FileWarning className="h-5 w-5 text-warning" />Tinjau sengketa jasa</DialogTitle></DialogHeader>{selected && <div className="space-y-4"><div className="rounded-xl bg-muted/50 p-4"><div className="flex flex-wrap items-center gap-2"><Badge variant={(statusMeta[selected.status] || statusMeta.OPEN).tone}>{(statusMeta[selected.status] || statusMeta.OPEN).label}</Badge><span className="font-semibold">{selected.request?.title || `Request #${selected.request_id.slice(0, 8)}`}</span></div><p className="mt-3 text-sm">{selected.reason}</p><p className="mt-2 text-xs text-muted-foreground">Lokasi: {selected.request?.location || '-'} · Nilai: {money(selected.amount || selected.request?.agreed_price)}</p></div>{selected.request && <div className="grid gap-3 rounded-xl border p-4 text-sm sm:grid-cols-2"><div><p className="text-xs text-muted-foreground">Status pekerjaan</p><p className="font-semibold">{selected.request.status}</p></div><div><p className="text-xs text-muted-foreground">Harga kesepakatan</p><p className="font-semibold">{money(selected.request.agreed_price)}</p></div><div><p className="text-xs text-muted-foreground">Dana penyedia</p><p className="font-semibold">{money(selected.request.provider_payout)}</p></div><div><p className="text-xs text-muted-foreground">Request ID</p><p className="font-semibold">#{selected.request_id.slice(0, 8).toUpperCase()}</p></div></div>}{selected.evidence_urls?.length > 0 && <div><p className="mb-2 text-sm font-semibold">Bukti komplain</p><div className="flex gap-2 overflow-x-auto">{selected.evidence_urls.map((url) => <a key={url} href={url} target="_blank" rel="noreferrer"><img src={url} alt="Bukti sengketa" className="h-24 w-24 rounded-lg border object-cover" /></a>)}</div></div>}{selected.status === 'REFUND_APPROVED' && selected.refund?.status === 'PENDING' && <div className="space-y-3 rounded-xl border border-amber-300 bg-amber-50 p-4"><p className="font-semibold text-amber-950">Refund disetujui: {money(selected.refund.amount)}</p><p className="text-sm text-amber-900">Lakukan refund melalui kanal transfer di luar aplikasi. Setelah berhasil, catat referensinya di bawah. Status transaksi tidak akan menjadi REFUNDED sebelum pencatatan ini.</p><Input value={refundReference} onChange={(event) => setRefundReference(event.target.value)} placeholder="Referensi transfer refund aktual (wajib)" maxLength={200} /><Textarea value={refundNote} onChange={(event) => setRefundNote(event.target.value)} placeholder="Catatan refund (opsional)" maxLength={1000} /><Button onClick={() => void recordRefund()} disabled={saving || refundReference.trim().length < 3}>{saving ? 'Mencatat...' : 'Catat transfer refund selesai'}</Button></div>}{selected.refund?.status === 'COMPLETED' && <div className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-900">Refund {money(selected.refund.amount)} tercatat pada {selected.refund.recorded_at ? new Date(selected.refund.recorded_at).toLocaleString('id-ID') : '-'} · Referensi {selected.refund.external_reference}</div>}{['OPEN','IN_REVIEW','WAITING_PARTIES'].includes(selected.status) && <><div><label className="text-sm font-medium">Keputusan admin</label><select value={decision} onChange={(event) => setDecision(event.target.value)} className="mt-1 w-full rounded-md border bg-background p-2 text-sm">{['IN_REVIEW','WAITING_PARTIES','REFUND_APPROVED','RELEASE_APPROVED','REJECTED'].map((value) => <option key={value} value={value}>{statusMeta[value].label}</option>)}</select></div><Textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="Catatan mediasi dan alasan keputusan wajib diisi" maxLength={2000} /><p className="flex items-center gap-1 text-xs text-muted-foreground"><CheckCircle2 className="h-3 w-3" />Refund baru ditandai selesai setelah referensi transfer aktual dicatat. Pencairan tetap menunggu aksi payout terpisah.</p></>}</div>}<DialogFooter><Button variant="outline" onClick={() => setSelected(null)} disabled={saving}>Tutup</Button>{selected && ['OPEN','IN_REVIEW','WAITING_PARTIES'].includes(selected.status) && <Button onClick={() => void saveDecision()} disabled={saving || !decision || !note.trim()}>{saving ? 'Menyimpan...' : 'Simpan keputusan'}</Button>}</DialogFooter></DialogContent></Dialog>
  </AdminLayout>;
}
