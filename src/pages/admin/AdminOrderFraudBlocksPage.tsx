import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle2, RefreshCw, ShieldOff } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';
import { reportObservability } from '@/lib/observability';
import { toast } from 'sonner';

type BlockType = 'user' | 'device' | 'ip';
interface FraudBlock {
  id: string;
  block_type: BlockType;
  block_value: string;
  user_id: string | null;
  reason: string;
  failed_order_count: number;
  distinct_user_count: number;
  blocked_until: string;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

type Filter = 'all' | 'active' | 'expired';

function formatDate(value: string) {
  return new Date(value).toLocaleString('id-ID');
}

function isActive(block: FraudBlock) {
  return new Date(block.blocked_until).getTime() > Date.now();
}

export default function AdminOrderFraudBlocksPage() {
  const [blocks, setBlocks] = useState<FraudBlock[]>([]);
  const [filter, setFilter] = useState<Filter>('active');
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<FraudBlock | null>(null);
  const [reason, setReason] = useState('');
  const [unblocking, setUnblocking] = useState(false);

  const loadBlocks = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('order_fraud_blocks' as never)
      .select('*')
      .order('blocked_until', { ascending: false });
    if (error) {
      reportObservability('security', 'admin_fraud_blocks_load_failed', 'error', {}, error);
      toast.error('Gagal memuat daftar blokir');
    } else {
      setBlocks((data ?? []) as unknown as FraudBlock[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => { void loadBlocks(); }, [loadBlocks]);

  const visibleBlocks = useMemo(() => blocks.filter((block) => {
    const active = isActive(block);
    return filter === 'all' || (filter === 'active' ? active : !active);
  }), [blocks, filter]);

  const activeCount = blocks.filter(isActive).length;

  const openUnblock = (block: FraudBlock) => {
    setSelected(block);
    setReason('');
  };

  const submitUnblock = async () => {
    if (!selected || reason.trim().length < 10 || unblocking) return;
    setUnblocking(true);
    const { error } = await supabase.rpc('unblock_order_fraud_block' as never, {
      p_block_id: selected.id,
      p_reason: reason.trim(),
    } as never);
    if (error) {
      reportObservability('security', 'admin_fraud_block_unblock_failed', 'error', { blockType: selected.block_type }, error);
      toast.error(error.message || 'Gagal membuka blokir');
    } else {
      reportObservability('security', 'admin_fraud_block_unblocked', 'info', { blockType: selected.block_type });
      toast.success('Blokir berhasil dibuka');
      setSelected(null);
      setReason('');
      await loadBlocks();
    }
    setUnblocking(false);
  };

  return (
    <AdminLayout
      title="Fraud Blocks"
      subtitle="Tinjau blokir otomatis order dan buka secara manual dengan alasan audit"
    >
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <AlertTriangle className="h-4 w-4 text-amber-500" />
          {activeCount} blokir aktif
        </div>
        <div className="flex flex-wrap gap-2">
          {(['active', 'expired', 'all'] as Filter[]).map((value) => (
            <Button key={value} size="sm" variant={filter === value ? 'default' : 'outline'} onClick={() => setFilter(value)}>
              {value === 'active' ? 'Aktif' : value === 'expired' ? 'Kedaluwarsa' : 'Semua'}
            </Button>
          ))}
          <Button size="sm" variant="outline" onClick={() => void loadBlocks()} disabled={loading}>
            <RefreshCw className={`mr-2 h-4 w-4 ${loading ? 'animate-spin' : ''}`} /> Refresh
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><ShieldOff className="h-5 w-5 text-primary" />Daftar blokir otomatis</CardTitle>
          <CardDescription>Unblock hanya mengakhiri block saat ini. Jika pola order berulang, sistem dapat membuat block baru.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {loading ? <div className="py-12 text-center text-muted-foreground">Memuat daftar blokir...</div> : visibleBlocks.length === 0 ? <div className="py-12 text-center text-muted-foreground">Tidak ada data untuk filter ini.</div> : visibleBlocks.map((block) => {
            const active = isActive(block);
            return (
              <div key={block.id} className="flex flex-col gap-3 rounded-lg border p-4 md:flex-row md:items-center">
                <div className="flex min-w-0 flex-1 items-start gap-3">
                  <div className={`mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg ${active ? 'bg-destructive/10' : 'bg-muted'}`}>
                    {active ? <AlertTriangle className="h-5 w-5 text-destructive" /> : <CheckCircle2 className="h-5 w-5 text-muted-foreground" />}
                  </div>
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge variant="outline">{block.block_type.toUpperCase()}</Badge>
                      <Badge variant={active ? 'destructive' : 'secondary'}>{active ? 'Aktif' : 'Kedaluwarsa'}</Badge>
                      <span className="break-all font-mono text-sm">{block.block_value}</span>
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">{block.reason}</p>
                    <p className="text-xs text-muted-foreground">{block.failed_order_count} order gagal · {block.distinct_user_count} user · dibuat {formatDate(block.created_at)} · berakhir {formatDate(block.blocked_until)}</p>
                  </div>
                </div>
                {active && <Button variant="outline" size="sm" onClick={() => openUnblock(block)}><ShieldOff className="mr-2 h-4 w-4" />Unblock</Button>}
              </div>
            );
          })}
        </CardContent>
      </Card>

      <Dialog open={Boolean(selected)} onOpenChange={(open) => { if (!open && !unblocking) setSelected(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Unblock {selected?.block_type.toUpperCase()}</DialogTitle>
            <DialogDescription>
              Block <span className="font-mono">{selected?.block_value}</span> akan dihentikan sekarang. Tulis alasan audit minimal 10 karakter.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2 py-2">
            <Label htmlFor="unblock-reason">Alasan unblock *</Label>
            <Textarea id="unblock-reason" value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Contoh: pembayaran pengguna telah diverifikasi manual" rows={4} />
            <p className="text-xs text-muted-foreground">{reason.trim().length}/500 karakter</p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSelected(null)} disabled={unblocking}>Batal</Button>
            <Button onClick={() => void submitUnblock()} disabled={unblocking || reason.trim().length < 10 || reason.trim().length > 500}>
              {unblocking ? 'Membuka blokir...' : 'Konfirmasi Unblock'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}
