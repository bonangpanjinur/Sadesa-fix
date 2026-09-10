import { useEffect, useState } from 'react';
import { AlertTriangle, CheckCircle2, MessageSquare } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Dispute { id: string; order_id: string; title: string | null; category: string | null; reason: string; amount: number; status: string; dispute_status: string | null; merchant_response: string | null; admin_notes: string | null; evidence_urls: string[] | null; created_at: string; }
const statuses = ['OPEN', 'IN_MEDIATION', 'RESOLVED_REFUND', 'RESOLVED_REJECTED', 'CLOSED'];

export default function AdminDisputeCenterPage() {
  const [disputes, setDisputes] = useState<Dispute[]>([]);
  const [selected, setSelected] = useState<Dispute | null>(null);
  const [decision, setDecision] = useState('');
  const [notes, setNotes] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase.from('refund_requests').select('id, order_id, title, category, reason, amount, status, dispute_status, merchant_response, admin_notes, evidence_urls, created_at').order('created_at', { ascending: false }).limit(100);
    if (error) toast.error('Gagal memuat dispute');
    setDisputes((data ?? []) as Dispute[]); setLoading(false);
  };
  useEffect(() => { void load(); }, []);

  const saveDecision = async () => {
    if (!selected || !decision) return;
    setSaving(true);
    try {
      let error;
      if (decision === 'RESOLVED_REFUND' || decision === 'RESOLVED_REJECTED') {
        const result = await supabase.rpc('process_refund_decision' as never, {
          p_refund_id: selected.id,
          p_approve: decision === 'RESOLVED_REFUND',
          p_notes: notes.trim() || null,
        } as never);
        error = result.error;
      } else {
        const result = await supabase.from('refund_requests').update({ dispute_status: decision, admin_notes: notes.trim() || null }).eq('id', selected.id);
        error = result.error;
      }
      if (error) throw error;
      toast.success('Keputusan dispute disimpan'); setSelected(null); setDecision(''); setNotes(''); await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Gagal menyimpan keputusan'); } finally { setSaving(false); }
  };

  return <AdminLayout title="Dispute Center" subtitle="Mediasi komplain buyer, merchant, delivery, dan pembayaran"><div className="space-y-4"><Card><CardHeader><CardTitle className="flex items-center gap-2"><MessageSquare className="h-5 w-5" />Daftar Dispute</CardTitle></CardHeader><CardContent>{loading ? <p className="py-8 text-center text-muted-foreground">Memuat dispute...</p> : disputes.length === 0 ? <p className="py-8 text-center text-muted-foreground">Tidak ada dispute.</p> : <div className="space-y-3">{disputes.map((dispute) => <div key={dispute.id} className="border rounded-lg p-4"><div className="flex items-start justify-between gap-3"><div><p className="font-medium">{dispute.title || 'Komplain Pesanan'}</p><p className="text-xs text-muted-foreground">Order #{dispute.order_id.slice(0, 8).toUpperCase()} · {dispute.category || 'Lainnya'} · {new Date(dispute.created_at).toLocaleDateString('id-ID')}</p></div><Badge variant={dispute.dispute_status === 'RESOLVED_REFUND' ? 'default' : dispute.dispute_status === 'RESOLVED_REJECTED' ? 'destructive' : 'secondary'}>{dispute.dispute_status || dispute.status}</Badge></div><p className="text-sm text-muted-foreground mt-2 line-clamp-2">{dispute.reason}</p><div className="flex justify-between items-center mt-3"><span className="text-sm font-semibold">Nominal: Rp {Number(dispute.amount || 0).toLocaleString('id-ID')}</span><Button size="sm" variant="outline" onClick={() => { setSelected(dispute); setDecision(dispute.dispute_status || 'IN_MEDIATION'); setNotes(dispute.admin_notes || ''); }}>Tinjau</Button></div></div>)}</div>}</CardContent></Card></div><Dialog open={!!selected} onOpenChange={(open) => !open && setSelected(null)}><DialogContent className="max-w-lg"><DialogHeader><DialogTitle><AlertTriangle className="inline h-4 w-4 mr-2" />Tinjau Dispute</DialogTitle></DialogHeader>{selected && <div className="space-y-4"><div className="rounded-lg bg-muted p-3 text-sm"><p className="font-medium">{selected.title || 'Komplain Pesanan'}</p><p className="mt-1">{selected.reason}</p>{selected.merchant_response && <p className="mt-2 border-t pt-2"><strong>Respons merchant:</strong> {selected.merchant_response}</p>}</div>{selected.evidence_urls?.length > 0 && <div className="flex gap-2 overflow-x-auto">{selected.evidence_urls.map((url) => <img key={url} src={url} alt="Bukti dispute" className="h-20 w-20 rounded object-cover border" />)}</div>}<div><label className="text-sm font-medium">Keputusan</label><select className="mt-1 w-full rounded-md border bg-background p-2 text-sm" value={decision} onChange={(event) => setDecision(event.target.value)}>{statuses.map((status) => <option key={status} value={status}>{status}</option>)}</select></div><Textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Catatan keputusan admin" maxLength={1000} /><p className="text-xs text-muted-foreground flex items-center gap-1"><CheckCircle2 className="h-3 w-3" />Keputusan akan tercatat pada histori dispute.</p></div>}<DialogFooter><Button variant="outline" onClick={() => setSelected(null)}>Batal</Button><Button onClick={() => void saveDecision()} disabled={saving || !decision}>{saving ? 'Menyimpan...' : 'Simpan Keputusan'}</Button></DialogFooter></DialogContent></Dialog></AdminLayout>;
}
