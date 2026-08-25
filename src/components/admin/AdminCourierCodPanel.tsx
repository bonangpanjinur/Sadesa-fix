import { useEffect, useState } from 'react';
import { Banknote, CheckCircle2, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';

interface CodRecord { id: string; courier_id: string; order_id: string; expected_cash: number; collected_cash: number; variance: number; status: string; notes: string | null; submitted_at: string; }

export function AdminCourierCodPanel() {
  const [records, setRecords] = useState<CodRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [reviewing, setReviewing] = useState<string | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});

  const fetchRecords = async () => {
    setLoading(true);
    const { data, error } = await supabase.from('courier_cod_reconciliations').select('*').in('status', ['pending', 'shortage', 'overage', 'matched']).order('submitted_at', { ascending: false }).limit(100);
    if (error) toast.error('Gagal memuat rekonsiliasi COD');
    setRecords((data ?? []) as CodRecord[]);
    setLoading(false);
  };

  useEffect(() => { void fetchRecords(); }, []);

  const review = async (record: CodRecord, status: 'approved' | 'disputed') => {
    setReviewing(record.id);
    try {
      const { error } = await supabase.rpc('review_courier_cod_reconciliation' as never, { p_id: record.id, p_status: status, p_notes: notes[record.id] || null } as never);
      if (error) throw error;
      toast.success(status === 'approved' ? 'COD disetujui' : 'COD ditandai dispute');
      await fetchRecords();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Gagal memproses COD'); } finally { setReviewing(null); }
  };

  return <Card><CardHeader><CardTitle className="flex items-center gap-2"><Banknote className="h-4 w-4 text-primary" />Review COD Courier</CardTitle></CardHeader><CardContent>{loading ? <div className="py-6 text-center text-muted-foreground">Memuat data...</div> : records.length === 0 ? <div className="py-6 text-center text-muted-foreground">Tidak ada rekonsiliasi COD yang menunggu review.</div> : <div className="space-y-3">{records.map((record) => <div key={record.id} className="rounded-lg border p-4 space-y-3"><div className="flex items-start justify-between gap-3"><div><p className="font-mono text-sm">Order #{record.order_id.slice(0, 8).toUpperCase()}</p><p className="text-xs text-muted-foreground">Courier #{record.courier_id.slice(0, 8).toUpperCase()} · {new Date(record.submitted_at).toLocaleString('id-ID')}</p></div><Badge variant={record.status === 'matched' ? 'default' : record.status === 'shortage' ? 'destructive' : 'secondary'}>{record.status}</Badge></div><div className="grid grid-cols-3 gap-2 text-sm"><div><p className="text-muted-foreground">Expected</p><p className="font-semibold">{formatPrice(record.expected_cash)}</p></div><div><p className="text-muted-foreground">Disetor</p><p className="font-semibold">{formatPrice(record.collected_cash)}</p></div><div><p className="text-muted-foreground">Selisih</p><p className={`font-semibold ${record.variance === 0 ? 'text-green-600' : 'text-amber-600'}`}>{formatPrice(Math.abs(record.variance))}</p></div></div>{record.variance !== 0 && <p className="text-xs text-amber-600 flex items-center gap-1"><AlertTriangle className="h-3 w-3" />Periksa bukti dan catatan setoran sebelum menyetujui.</p>}<Textarea placeholder="Catatan reviewer (opsional)" value={notes[record.id] ?? ''} onChange={(event) => setNotes((current) => ({ ...current, [record.id]: event.target.value }))} maxLength={500} /><div className="flex justify-end gap-2"><Button size="sm" variant="outline" onClick={() => void review(record, 'disputed')} disabled={reviewing === record.id}>Tandai Dispute</Button><Button size="sm" onClick={() => void review(record, 'approved')} disabled={reviewing === record.id}><CheckCircle2 className="h-4 w-4 mr-1" />Setujui</Button></div></div>)}</div>}</CardContent></Card>;
}
