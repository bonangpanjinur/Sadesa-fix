import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { ArrowLeft, Copy, CheckCircle, QrCode, Clock, ExternalLink, AlertTriangle } from 'lucide-react';
import { motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { formatPrice } from '@/lib/utils';
import { getGuestOrderAccess, guestOrderUrl } from '@/lib/guestCheckout';
import { toast } from '@/hooks/use-toast';
import { PaymentProofUpload } from '@/components/checkout/PaymentProofUpload';
import { PaymentCountdown } from '@/components/checkout/PaymentCountdown';
import { QRCodeSVG } from 'qrcode.react';
import { createOrGetGdcQrisMpm, queryGdcQrisMpmStatus, type GdcQrisMpmPayment } from '@/lib/gdcQrisMpmApi';

interface PaymentInfo {
  qrisImageUrl: string | null;
}

interface OrderInfo {
  id: string;
  total: number;
  payment_method: string;
  payment_status: string;
  payment_channel?: string | null;
  merchant_id: string;
  created_at: string;
  merchant_name?: string;
  payment_proof_url?: string | null;
  confirmation_deadline?: string | null;
  payment_destination_snapshot?: Record<string, unknown> | null;
}

export default function PaymentConfirmationPage() {
  const navigate = useNavigate();
  const { orderId } = useParams();
  const [searchParams] = useSearchParams();
  const { user } = useAuth();
  const guestToken = searchParams.get('guest_token') || getGuestOrderAccess(orderId || '', null)?.token;
  const [order, setOrder] = useState<OrderInfo | null>(null);
  const [paymentInfo, setPaymentInfo] = useState<PaymentInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  const loadOrderAndPaymentInfo = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    if (showLoading) setLoadError(null);
    try {
      if (!orderId) return;
      let orderData: OrderInfo | null = null;
      let paymentDestination: Record<string, unknown> = {};

      if (!user && guestToken) {
        const { data, error } = await supabase.rpc('get_guest_order_payment_context' as never, {
          p_order_id: orderId,
          p_guest_access_token: guestToken,
        } as never);
        if (error || !data) throw new Error('Pesanan guest tidak ditemukan atau link sudah kedaluwarsa');
        const context = data as OrderInfo & { qris_image_url?: string | null };
        orderData = context;
        paymentDestination = {
          merchant_name: context.merchant_name,
          qris_image_url: context.qris_image_url,
        };
      } else if (user) {
        const result = await supabase
          .from('orders')
          .select('id, total, payment_method, payment_status, payment_channel, merchant_id, created_at, payment_proof_url, confirmation_deadline, payment_destination_snapshot' as never)
          .eq('id', orderId)
          .eq('buyer_id', user.id)
          .maybeSingle();
        if (result.error || !result.data) throw new Error('Pesanan tidak ditemukan');
        orderData = result.data as unknown as OrderInfo;
        paymentDestination = orderData.payment_destination_snapshot || {};
      } else {
        throw new Error('Link pembayaran tidak memiliki token guest');
      }

      if (!orderData) throw new Error('Pesanan tidak ditemukan');
      setOrder({ ...orderData, merchant_name: String(paymentDestination.merchant_name || orderData.merchant_name || 'Merchant') });
      setPaymentInfo({
        qrisImageUrl: typeof paymentDestination.qris_image_url === 'string' ? paymentDestination.qris_image_url : null,
      });
    } catch (error) {
      console.error('Error loading payment info:', error);
      if (showLoading) setLoadError(error instanceof Error ? error.message : 'Data pembayaran tidak dapat dimuat');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [orderId, user, guestToken]);

  useEffect(() => {
    if (!orderId || (!user && !guestToken)) return;
    void loadOrderAndPaymentInfo();
    const refreshInterval = window.setInterval(() => void loadOrderAndPaymentInfo(false), 15000);
    const channel = user
      ? supabase.channel(`payment-order-${orderId}`)
        .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders', filter: `id=eq.${orderId}` }, () => {
          void loadOrderAndPaymentInfo(false);
        })
        .subscribe()
      : null;
    return () => {
      window.clearInterval(refreshInterval);
      if (channel) void supabase.removeChannel(channel);
    };
  }, [orderId, user, guestToken, loadOrderAndPaymentInfo]);

  const handleCopyAmount = () => {
    if (order?.total) {
      navigator.clipboard.writeText(order.total.toString());
      toast({ title: 'Nominal disalin' });
    }
  };

  if (loading) {
    return (
      <div className="mobile-shell bg-background flex flex-col min-h-screen items-center justify-center">
        <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
      </div>
    );
  }

  if (loadError || !order || !paymentInfo) {
    return (
      <div className="mobile-shell bg-background flex flex-col min-h-screen items-center justify-center p-8">
        <AlertTriangle className="h-10 w-10 text-amber-600" />
        <p className="mt-3 text-center font-semibold">Pembayaran belum dapat dimuat</p>
        <p className="mt-1 max-w-sm text-center text-sm text-muted-foreground">{loadError || 'Data pesanan tidak ditemukan atau link sudah kedaluwarsa.'}</p>
        <div className="mt-4 flex w-full max-w-xs flex-col gap-2">
          <Button onClick={() => void loadOrderAndPaymentInfo()}>Coba lagi</Button>
          <Button variant="outline" onClick={() => navigate(user ? '/orders' : (orderId && guestToken ? guestOrderUrl(orderId, guestToken) : '/'))}>{user ? 'Ke Pesanan Saya' : 'Ke Status Pesanan'}</Button>
        </div>
      </div>
    );
  }

  const paymentStatus = order.payment_status.toUpperCase();
  const isPaymentComplete = ['PAID', 'VERIFIED', 'COMPLETED', 'SUCCESS'].includes(paymentStatus);
  const isPaymentRejected = paymentStatus === 'FAILED' || paymentStatus === 'REJECTED';
  const isPaymentExpired = paymentStatus === 'EXPIRED'
    || Boolean(order.confirmation_deadline && Date.parse(order.confirmation_deadline) <= Date.now() && !isPaymentComplete);
  const hasPaymentInstructions = Boolean(paymentInfo.qrisImageUrl);
  const statusLabel = isPaymentComplete ? 'Pembayaran Diterima' : isPaymentExpired ? 'Pembayaran Kedaluwarsa' : isPaymentRejected ? 'Bukti Ditolak' : 'Menunggu Pembayaran';

  return (
    <div className="mobile-shell bg-secondary flex flex-col min-h-screen">
      {/* Header */}
      <div className="p-4 border-b border-border bg-card flex items-center gap-3">
        <button
          onClick={() => navigate(user ? '/orders' : (orderId && guestToken ? guestOrderUrl(orderId, guestToken) : '/'))}
          className="w-8 h-8 rounded-full hover:bg-secondary flex items-center justify-center"
        >
          <ArrowLeft className="h-5 w-5" />
        </button>
        <h2 className="font-bold text-lg text-foreground">Pembayaran</h2>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Order Info */}
        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }}>
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <p className="text-sm text-muted-foreground">Pesanan untuk</p>
                  <p className="font-bold">{order.merchant_name}</p>
                </div>
                <Badge variant={isPaymentComplete ? 'default' : (isPaymentRejected || isPaymentExpired) ? 'destructive' : 'secondary'} className="flex items-center gap-1">
                  {isPaymentComplete ? <CheckCircle className="h-3 w-3" /> : (isPaymentRejected || isPaymentExpired) ? <AlertTriangle className="h-3 w-3" /> : <Clock className="h-3 w-3" />}
                  {statusLabel}
                </Badge>
              </div>
              {order.confirmation_deadline && !isPaymentExpired && (
                <PaymentCountdown deadline={order.confirmation_deadline} />
              )}
              <div className="flex items-center justify-between p-3 bg-primary/5 rounded-lg border border-primary/20">
                <span className="text-sm font-medium">Total Pembayaran</span>
                <div className="flex items-center gap-2">
                  <span className="text-xl font-bold text-primary">{formatPrice(order.total)}</span>
                  <Button variant="ghost" size="sm" onClick={handleCopyAmount} className="h-7 px-2">
                    <Copy className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        </motion.div>

        {isPaymentComplete && (
          <Card className="border-emerald-200 bg-emerald-50/70">
            <CardContent className="flex items-start gap-3 p-4 text-sm text-emerald-900">
              <CheckCircle className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" />
              <div><p className="font-bold">Pembayaran sudah diterima</p><p className="mt-1">Pesanan akan diproses sesuai status terbaru dari penjual.</p></div>
            </CardContent>
          </Card>
        )}

        {isPaymentExpired && (
          <Card className="border-destructive/30 bg-destructive/5">
            <CardContent className="flex items-start gap-3 p-4 text-sm" role="status">
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-destructive" />
              <div><p className="font-bold">Batas pembayaran telah berakhir</p><p className="mt-1">Pesanan ini tidak lagi menerima bukti transfer. Silakan buat pesanan baru atau hubungi penjual.</p></div>
            </CardContent>
          </Card>
        )}

        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && !hasPaymentInstructions && (
          <Card className="border-amber-200 bg-amber-50/70">
            <CardContent className="flex items-start gap-3 p-4 text-sm text-amber-950" role="status">
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-amber-600" />
              <div>
                <p className="font-bold">Menunggu instruksi pembayaran</p>
                <p className="mt-1">QRIS merchant belum tersedia untuk pesanan ini. Jangan melakukan pembayaran sebelum QRIS resmi ditampilkan.</p>
              </div>
            </CardContent>
          </Card>
        )}

        {/* QRIS */}
        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && paymentInfo.qrisImageUrl && (
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}>
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center gap-2 mb-4">
                  <QrCode className="h-5 w-5 text-primary" />
                  <h3 className="font-bold">QRIS</h3>
                </div>

                <div className="flex justify-center p-4 bg-white rounded-lg border">
                  <img
                    src={paymentInfo.qrisImageUrl}
                    alt="QRIS Payment"
                    className="max-w-[280px] w-full h-auto"
                  />
                </div>
                <p className="text-xs text-muted-foreground text-center mt-2">
                  Scan kode QRIS di atas menggunakan aplikasi e-wallet atau mobile banking Anda
                </p>
              </CardContent>
            </Card>
          </motion.div>
        )}

        {/* Upload Bukti Pembayaran */}
        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && hasPaymentInstructions && <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 }}>
          <Card>
            <CardContent className="p-4">
              <h3 className="font-bold text-sm mb-3">Upload Bukti Pembayaran</h3>
              {order.payment_status === 'FAILED' && (
                <p role="alert" className="mb-3 rounded-lg border border-destructive/20 bg-destructive/5 p-3 text-sm text-muted-foreground">
                  Bukti sebelumnya ditolak. Unggah bukti pembayaran QRIS yang benar; status akan kembali menunggu verifikasi setelah berhasil diunggah.
                </p>
              )}
              <PaymentProofUpload
                orderId={order.id}
                guestAccessToken={!user ? guestToken : undefined}
                currentProofUrl={order.payment_proof_url}
                isRejected={order.payment_status === 'FAILED'}
                onUploaded={() => void loadOrderAndPaymentInfo(false)}
              />
            </CardContent>
          </Card>
        </motion.div>}

        {/* Instructions */}
        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && hasPaymentInstructions && <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.4 }}>
          <Card>
            <CardContent className="p-4">
              <h3 className="font-bold text-sm mb-3">Petunjuk Pembayaran</h3>
              <ol className="space-y-2 text-sm text-muted-foreground list-decimal list-inside">
                <li>Pindai QRIS merchant dan bayar sesuai <strong className="text-foreground">nominal yang tertera</strong></li>
                <li>Pastikan nama merchant pada aplikasi pembayaran sesuai dengan toko</li>
                <li><strong className="text-foreground">Upload bukti pembayaran</strong> di atas</li>
                <li>Pesanan akan diproses setelah pembayaran dikonfirmasi oleh penjual</li>
              </ol>
            </CardContent>
          </Card>
        </motion.div>}
      </div>

      {/* Bottom Actions */}
      <div className="p-4 border-t border-border bg-card space-y-2">
        <Button onClick={() => navigate(user ? '/orders' : (orderId && guestToken ? guestOrderUrl(orderId, guestToken) : '/'))} className="w-full" size="lg">
          <CheckCircle className="h-4 w-4 mr-2" />
          {user ? 'Lihat Pesanan Saya' : 'Lihat Status Pesanan'}
        </Button>
        <Button onClick={() => navigate('/')} variant="outline" className="w-full">
          Lanjut Belanja
        </Button>
      </div>
    </div>
  );
}
