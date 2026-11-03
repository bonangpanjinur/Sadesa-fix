import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { AlertTriangle, ArrowLeft, CheckCircle, Clock, Copy, ExternalLink, Loader2, QrCode } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { formatPrice } from '@/lib/utils';
import { toast } from '@/hooks/use-toast';
import { queryGdcQrisPayment, type GdcQrisAttempt } from '@/lib/gdcQrisApi';

function statusText(status: GdcQrisAttempt['status']) {
  if (status === 'SUCCEEDED') return 'Pembayaran diterima';
  if (status === 'FAILED') return 'Pembayaran gagal';
  if (status === 'EXPIRED') return 'QRIS kedaluwarsa';
  if (status === 'UNKNOWN') return 'Status sedang diverifikasi';
  return 'Menunggu pembayaran';
}

export default function GdcQrisPaymentPage() {
  const navigate = useNavigate();
  const { orderId, attemptId } = useParams();
  const [attempt, setAttempt] = useState<GdcQrisAttempt | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async (initial = false) => {
    if (!attemptId) return;
    if (initial) setLoading(true); else setRefreshing(true);
    try {
      const result = await queryGdcQrisPayment(attemptId);
      setAttempt(result.attempt);
      setError(null);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Status QRIS belum dapat dimuat');
    } finally {
      if (initial) setLoading(false); else setRefreshing(false);
    }
  }, [attemptId]);

  useEffect(() => { void refresh(true); }, [refresh]);
  useEffect(() => {
    if (!attempt || ['SUCCEEDED', 'FAILED', 'EXPIRED'].includes(attempt.status)) return;
    const timer = window.setInterval(() => void refresh(false), 5000);
    return () => window.clearInterval(timer);
  }, [attempt, refresh]);

  const qrValue = attempt?.qr_content || null;
  const expired = Boolean(attempt?.expires_at && Date.parse(attempt.expires_at) <= Date.now());
  const isComplete = attempt?.status === 'SUCCEEDED';
  const isFailed = attempt?.status === 'FAILED' || attempt?.status === 'EXPIRED' || expired;
  const statusVariant = isComplete ? 'default' : isFailed ? 'destructive' : 'secondary';
  const expiryLabel = useMemo(() => {
    if (!attempt?.expires_at) return null;
    return new Date(attempt.expires_at).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' });
  }, [attempt?.expires_at]);

  const copyReference = async () => {
    if (!attempt?.partner_reference_no) return;
    await navigator.clipboard.writeText(attempt.partner_reference_no);
    toast({ title: 'Referensi pembayaran disalin' });
  };

  if (loading) return <div className="mobile-shell flex min-h-screen items-center justify-center bg-secondary"><Loader2 className="h-8 w-8 animate-spin text-primary" /></div>;

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-secondary">
      <header className="flex items-center gap-3 border-b bg-card p-4">
        <button onClick={() => navigate('/orders')} className="flex h-8 w-8 items-center justify-center rounded-full hover:bg-secondary" aria-label="Kembali"><ArrowLeft className="h-5 w-5" /></button>
        <div><p className="text-xs text-muted-foreground">Pembayaran QRIS</p><h1 className="font-bold">QRIS Dinamis GDC</h1></div>
      </header>
      <main className="flex-1 space-y-4 overflow-y-auto p-4">
        {error && <Card className="border-amber-200 bg-amber-50"><CardContent className="flex items-start gap-3 p-4 text-sm text-amber-950"><AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" /><div><p className="font-semibold">Status belum dapat diperbarui</p><p className="mt-1">{error}</p><Button variant="outline" size="sm" className="mt-3" onClick={() => void refresh(false)}>Coba lagi</Button></div></CardContent></Card>}
        <Card>
          <CardHeader className="flex-row items-center justify-between space-y-0"><CardTitle className="text-base">Status pembayaran</CardTitle><Badge variant={statusVariant}>{isComplete ? <CheckCircle className="mr-1 h-3 w-3" /> : isFailed ? <AlertTriangle className="mr-1 h-3 w-3" /> : <Clock className="mr-1 h-3 w-3" />}{statusText(attempt?.status || 'PENDING')}</Badge></CardHeader>
          <CardContent className="space-y-3"><div className="flex items-center justify-between rounded-lg border bg-primary/5 p-3"><span className="text-sm font-medium">Total</span><span className="text-xl font-bold text-primary">{formatPrice(attempt?.amount || 0)}</span></div><div className="flex items-center justify-between text-xs text-muted-foreground"><span>Order</span><span className="font-mono">{orderId?.slice(0, 8).toUpperCase()}</span></div>{expiryLabel && <div className="flex items-center justify-between text-xs text-muted-foreground"><span>Berlaku sampai</span><span>{expiryLabel}</span></div>}</CardContent>
        </Card>
        {isComplete ? <Card className="border-emerald-200 bg-emerald-50"><CardContent className="flex items-start gap-3 p-4 text-sm text-emerald-900"><CheckCircle className="mt-0.5 h-5 w-5 text-emerald-600" /><div><p className="font-bold">Pembayaran sudah diterima</p><p className="mt-1">Status order akan diperbarui otomatis.</p></div></CardContent></Card> : isFailed ? <Card className="border-destructive/30 bg-destructive/5"><CardContent className="p-4 text-sm"><p className="font-bold">QRIS tidak dapat digunakan</p><p className="mt-1 text-muted-foreground">Silakan kembali ke pesanan atau hubungi merchant jika dana sudah terpotong.</p></CardContent></Card> : <Card><CardContent className="flex flex-col items-center p-5 text-center"><p className="mb-4 text-sm text-muted-foreground">Buka aplikasi bank atau e-wallet yang mendukung QRIS, lalu scan kode berikut.</p>{attempt?.qr_image ? <img src={attempt.qr_image} alt="QRIS pembayaran dinamis" className="max-h-72 w-72 rounded-lg border bg-white p-2 object-contain" /> : qrValue ? <div className="rounded-lg border bg-white p-4"><QRCodeSVG value={qrValue} size={240} includeMargin /></div> : <div className="flex h-64 w-64 items-center justify-center rounded-lg border bg-muted"><QrCode className="h-16 w-16 text-muted-foreground" /></div>}{attempt?.qr_url && <Button variant="outline" className="mt-4" onClick={() => window.open(attempt.qr_url || '', '_blank', 'noopener,noreferrer')}><ExternalLink className="mr-2 h-4 w-4" />Buka QR di halaman GDC</Button>}<p className="mt-4 text-xs text-muted-foreground">Halaman ini memeriksa status secara otomatis setiap 5 detik.</p></CardContent></Card>}
        {attempt?.partner_reference_no && <Card><CardContent className="flex items-center justify-between gap-3 p-4"><div><p className="text-xs text-muted-foreground">Referensi pembayaran</p><p className="font-mono text-xs">{attempt.partner_reference_no}</p></div><Button variant="ghost" size="sm" onClick={() => void copyReference()}><Copy className="h-4 w-4" /></Button></CardContent></Card>}
        <div className="flex gap-2"><Button className="flex-1" variant={isComplete ? 'default' : 'outline'} onClick={() => navigate('/orders')}>Lihat Pesanan</Button>{!isComplete && !isFailed && <Button variant="outline" onClick={() => void refresh(false)} disabled={refreshing}>{refreshing ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Perbarui'}</Button>}</div>
      </main>
    </div>
  );
}
