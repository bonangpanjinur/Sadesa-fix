import { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, RefreshCw, RotateCcw, WifiOff } from 'lucide-react';
import { POSLayout } from '@/components/pos/POSLayout';
import { POSEmptyState, POSErrorState, POSLoadingState } from '@/components/pos/POSPageStates';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { usePOS } from '@/contexts/POSContext';
import { getPendingSales, retryPendingSale, type PendingSale } from '@/lib/posOfflineDB';
import { formatPrice } from '@/lib/utils';
import { toast } from 'sonner';

export default function POSOfflineConflictPage() {
  const { tenant, activeOutlet } = usePOS();
  const [sales, setSales] = useState<PendingSale[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [retrying, setRetrying] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenant || !activeOutlet) return;
    setLoading(true);
    setError(null);
    try {
      setSales(await getPendingSales(tenant.id, activeOutlet.id));
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Offline queue tidak dapat dibaca');
    } finally {
      setLoading(false);
    }
  }, [tenant, activeOutlet]);

  useEffect(() => { void load(); }, [load]);

  const retry = async (sale: PendingSale) => {
    setRetrying(sale.id);
    try {
      await retryPendingSale(sale.id);
      toast.success(`Transaksi ${sale.id.slice(0, 8)} dimasukkan kembali ke antrean`);
      await load();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Gagal mengantre ulang transaksi');
    } finally {
      setRetrying(null);
    }
  };

  if (!tenant || !activeOutlet) {
    return <POSLayout title="Offline Conflict Center"><POSEmptyState title="Outlet belum dipilih" description="Pilih outlet aktif untuk melihat antrean offline." /></POSLayout>;
  }
  if (loading) return <POSLayout title="Offline Conflict Center"><POSLoadingState label="Membaca antrean offline..." /></POSLayout>;
  if (error) return <POSLayout title="Offline Conflict Center"><POSErrorState title="Antrean offline gagal dibaca" description={error} onRetry={() => void load()} /></POSLayout>;

  const conflicts = sales.filter((sale) => sale.status === 'conflict' || sale.status === 'failed');
  return (
    <POSLayout title="Offline Conflict Center" subtitle="Tinjau transaksi yang belum tersinkronisasi">
      <div className="space-y-5">
        <Card className="border-amber-200 bg-amber-50/60">
          <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-start gap-3"><WifiOff className="mt-0.5 h-5 w-5 text-amber-700" aria-hidden="true" /><div><p className="font-semibold text-amber-900">Antrean offline: {sales.length}</p><p className="text-sm text-amber-800">Conflict perlu ditinjau sebelum dicoba ulang agar harga dan stok tidak salah.</p></div></div>
            <Button variant="outline" size="sm" onClick={() => void load()}><RefreshCw className="mr-2 h-4 w-4" />Refresh</Button>
          </CardContent>
        </Card>
        {conflicts.length === 0 ? <POSEmptyState title="Tidak ada conflict" description="Semua transaksi offline sudah tersinkronisasi atau masih menunggu koneksi." /> : (
          <div className="grid gap-4">
            {conflicts.map((sale) => (
              <Card key={sale.id} className="border-destructive/25">
                <CardHeader className="pb-3"><div className="flex items-start justify-between gap-3"><div><CardTitle className="text-base">Transaksi {sale.id.slice(0, 8)}</CardTitle><p className="text-xs text-muted-foreground">{new Date(sale.created_at).toLocaleString('id-ID')}</p></div><Badge variant="destructive"><AlertTriangle className="mr-1 h-3 w-3" />{sale.status === 'conflict' ? 'Conflict' : 'Gagal'}</Badge></div></CardHeader>
                <CardContent className="space-y-3"><div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4"><div><p className="text-muted-foreground">Total</p><p className="font-semibold">{formatPrice(sale.total)}</p></div><div><p className="text-muted-foreground">Pembayaran</p><p className="font-semibold">{sale.payment_method}</p></div><div><p className="text-muted-foreground">Percobaan</p><p className="font-semibold">{sale.attempts || 0}</p></div><div><p className="text-muted-foreground">Kode</p><p className="font-semibold">{sale.conflict_code || 'RETRYABLE_ERROR'}</p></div></div><p className="rounded-lg bg-muted p-3 text-sm" role="alert">{sale.conflict_message || sale.sync_error || 'Transaksi belum dapat disinkronisasi.'}</p><Button size="sm" onClick={() => void retry(sale)} disabled={retrying === sale.id}><RotateCcw className="mr-2 h-4 w-4" />{retrying === sale.id ? 'Mengantrekan...' : 'Coba lagi'}</Button></CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>
    </POSLayout>
  );
}
