import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { ArrowLeft, CheckCircle, Clock, Copy, CreditCard, Loader2, RefreshCw, ShoppingBag } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice, safeGoBack } from '@/lib/utils';
import { toast } from '@/hooks/use-toast';
import { getGuestOrderAccess, guestOrderUrl } from '@/lib/guestCheckout';

interface GuestOrderItem {
  name: string;
  quantity: number;
  price: number;
  subtotal: number;
}

interface GuestOrderStatus {
  order_id: string;
  created_at: string;
  merchant_name?: string | null;
  items: GuestOrderItem[];
  subtotal: number;
  shipping_cost: number;
  total: number;
  status: string;
  payment_method: string;
  payment_status: string;
  guest_token_expires_at: string;
}

function statusLabel(status: string): string {
  const labels: Record<string, string> = {
    NEW: 'Pesanan baru',
    PENDING_PAYMENT: 'Menunggu pembayaran',
    PENDING_CONFIRMATION: 'Menunggu konfirmasi',
    PROCESSING: 'Sedang diproses',
    READY: 'Siap dikirim',
    ON_DELIVERY: 'Sedang dikirim',
    COMPLETED: 'Selesai',
    CANCELLED: 'Dibatalkan',
  };
  return labels[status] || status.replaceAll('_', ' ');
}

export default function GuestOrderStatusPage() {
  const navigate = useNavigate();
  const { orderId } = useParams();
  const [searchParams] = useSearchParams();
  const [order, setOrder] = useState<GuestOrderStatus | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const loadStatus = useCallback(async () => {
    if (!orderId) return;
    const access = getGuestOrderAccess(orderId, searchParams.get('guest_token'));
    const accessToken = searchParams.get('guest_token') || access?.token;
    setToken(accessToken);
    if (!accessToken) {
      setLoading(false);
      return;
    }

    setLoading(true);
    const { data, error } = await supabase.rpc('get_guest_order_status' as never, {
      p_order_id: orderId,
      p_guest_access_token: accessToken,
    } as never);
    if (error || !data) {
      toast({ title: 'Link status tidak valid atau sudah kedaluwarsa', description: 'Minta link status terbaru dari perangkat yang digunakan saat checkout.', variant: 'destructive' });
      setOrder(null);
    } else {
      setOrder(data as GuestOrderStatus);
    }
    setLoading(false);
  }, [orderId, searchParams]);

  useEffect(() => { void loadStatus(); }, [loadStatus]);

  const copyStatusLink = async () => {
    if (!orderId || !token) return;
    await navigator.clipboard.writeText(`${window.location.origin}${guestOrderUrl(orderId, token)}`);
    toast({ title: 'Link status disalin', description: 'Simpan link ini untuk melihat pesanan tanpa login.' });
  };

  if (loading) {
    return <div className="mobile-shell min-h-screen flex items-center justify-center bg-background"><Loader2 className="h-8 w-8 animate-spin text-primary" /></div>;
  }

  if (!order || !token) {
    return (
      <div className="mobile-shell min-h-screen flex flex-col items-center justify-center bg-background p-6 text-center">
        <ShoppingBag className="h-12 w-12 text-muted-foreground mb-4" />
        <h1 className="text-xl font-bold">Status pesanan tidak tersedia</h1>
        <p className="mt-2 text-sm text-muted-foreground">Link token mungkin sudah kedaluwarsa atau dibuka di perangkat lain.</p>
        <Button className="mt-5" onClick={() => navigate('/')}><ShoppingBag className="mr-2 h-4 w-4" /> Kembali belanja</Button>
      </div>
    );
  }

  const paymentPending = order.payment_method === 'TRANSFER' && !['PAID', 'VERIFIED'].includes(order.payment_status);

  return (
    <div className="mobile-shell min-h-screen flex flex-col bg-secondary">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b bg-card p-4">
        <button type="button" onClick={() => safeGoBack(navigate)} className="flex h-8 w-8 items-center justify-center rounded-full hover:bg-secondary" aria-label="Kembali"><ArrowLeft className="h-5 w-5" /></button>
        <div className="min-w-0 flex-1"><p className="text-xs text-muted-foreground">Status pesanan guest</p><h1 className="truncate font-bold">#{order.order_id.slice(0, 8).toUpperCase()}</h1></div>
        <Button type="button" variant="ghost" size="icon" onClick={() => void loadStatus()} aria-label="Muat ulang"><RefreshCw className="h-4 w-4" /></Button>
      </header>
      <main className="flex-1 space-y-4 overflow-y-auto p-4 pb-8">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-start justify-between gap-3">
              <div><p className="text-sm text-muted-foreground">Pesanan untuk</p><p className="font-bold">{order.merchant_name || 'Merchant'}</p></div>
              <Badge variant="secondary" className="flex items-center gap-1"><Clock className="h-3 w-3" />{statusLabel(order.status)}</Badge>
            </div>
            <div className="mt-4 flex items-center justify-between rounded-lg bg-primary/5 p-3"><span className="font-medium">Total</span><span className="text-xl font-bold text-primary">{formatPrice(order.total)}</span></div>
            <p className="mt-3 text-xs text-muted-foreground">Link berlaku sampai {new Date(order.guest_token_expires_at).toLocaleDateString('id-ID')}.</p>
          </CardContent>
        </Card>

        <Card><CardHeader className="pb-2"><CardTitle className="text-base">Produk</CardTitle></CardHeader><CardContent className="space-y-3">
          {order.items.map((item, index) => <div key={`${item.name}-${index}`} className="flex items-start justify-between gap-3 text-sm"><div><p className="font-medium">{item.name}</p><p className="text-muted-foreground">{item.quantity} × {formatPrice(item.price)}</p></div><span className="font-semibold">{formatPrice(item.subtotal)}</span></div>)}
          <div className="border-t pt-3 text-sm"><div className="flex justify-between"><span className="text-muted-foreground">Subtotal</span><span>{formatPrice(order.subtotal)}</span></div><div className="mt-1 flex justify-between"><span className="text-muted-foreground">Pengiriman</span><span>{formatPrice(order.shipping_cost)}</span></div></div>
        </CardContent></Card>

        {paymentPending && <Card className="border-primary/30"><CardContent className="space-y-3 p-4"><div className="flex items-center gap-2"><CreditCard className="h-5 w-5 text-primary" /><p className="font-bold">Pembayaran belum selesai</p></div><p className="text-sm text-muted-foreground">Buka halaman pembayaran untuk melihat rekening/QRIS dan mengunggah bukti transfer.</p><Button className="w-full" onClick={() => navigate(guestOrderUrl(order.order_id, token, 'payment'))}>Bayar dan upload bukti</Button></CardContent></Card>}
        {!paymentPending && <Card className="border-emerald-200 bg-emerald-50/50"><CardContent className="flex gap-3 p-4 text-sm"><CheckCircle className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" /><p>Pembayaran sudah diterima atau pesanan tidak memerlukan pembayaran transfer. Status akan diperbarui oleh merchant.</p></CardContent></Card>}

        <div className="space-y-2"><Button variant="outline" className="w-full" onClick={copyStatusLink}><Copy className="mr-2 h-4 w-4" /> Salin link status</Button><Button variant="outline" className="w-full" onClick={() => navigate('/')}><ShoppingBag className="mr-2 h-4 w-4" /> Lanjut belanja</Button></div>
      </main>
    </div>
  );
}
