import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { ArrowLeft, Copy, CheckCircle, QrCode as QrIcon, CreditCard, Clock, AlertTriangle, RefreshCw, Loader2 } from 'lucide-react';
import { motion } from 'framer-motion';
import { QRCodeSVG } from 'qrcode.react';
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
import { createOrGetGdcQrisMpm, queryGdcQrisMpmStatus, type GdcQrisMpmPayment } from '@/lib/gdcQrisMpmApi';
import { getStaticQrisPublicUrl } from '@/lib/staticQris';

interface PaymentInfo {
  qrisImageUrl: string | null;
  bankName: string | null;
  bankAccountNumber: string | null;
  bankAccountName: string | null;
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
  const { user, loading: authLoading } = useAuth();
  const guestToken = searchParams.get('guest_token') || getGuestOrderAccess(orderId || '', null)?.token;
  
  const [order, setOrder] = useState<OrderInfo | null>(null);
  const [paymentInfo, setPaymentInfo] = useState<PaymentInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // State khusus GDC QRIS MPM Dinamis
  const isGdcMpmProvider = searchParams.get('provider') === 'gdc-mpm';
  const [gdcPayment, setGdcPayment] = useState<GdcQrisMpmPayment | null>(null);
  const [gdcLoading, setGdcLoading] = useState(false);
  const [gdcError, setGdcError] = useState<string | null>(null);
  const autoCreateAttemptedForRef = useRef<string | null>(null);

  const isGdcMpmPayment = isGdcMpmProvider || Boolean(gdcPayment) || order?.payment_channel === 'QRIS_MPM_GDC';

  // Load data pesanan utama
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
        const context = data as OrderInfo & { qris_image_url?: string | null; bank_name?: string | null; bank_account_number?: string | null; bank_account_name?: string | null };
        orderData = context;
        paymentDestination = {
          merchant_name: context.merchant_name,
          qris_image_url: context.qris_image_url,
          bank_name: context.bank_name,
          bank_account_number: context.bank_account_number,
          bank_account_name: context.bank_account_name,
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
        qrisImageUrl: getStaticQrisPublicUrl(typeof paymentDestination.qris_image_url === 'string' ? paymentDestination.qris_image_url : null),
        bankName: typeof paymentDestination.bank_name === 'string' ? paymentDestination.bank_name : null,
        bankAccountNumber: typeof paymentDestination.bank_account_number === 'string' ? paymentDestination.bank_account_number : null,
        bankAccountName: typeof paymentDestination.bank_account_name === 'string' ? paymentDestination.bank_account_name : null,
      });
    } catch (error) {
      console.error('Error loading payment info:', error);
      if (showLoading) setLoadError(error instanceof Error ? error.message : 'Data pembayaran tidak dapat dimuat');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [orderId, user, guestToken]);

  // Load data payload QRIS dari GDC Edge Function
  const loadGdcPayment = useCallback(async () => {
    if (!orderId) return;
    setGdcLoading(true);
    setGdcError(null);
    try {
      const payment = await createOrGetGdcQrisMpm(orderId);
      setGdcPayment(payment);
    } catch (err) {
      console.error('Error loading GDC QRIS MPM:', err);
      setGdcError(err instanceof Error ? err.message : 'Gagal memuat QRIS Dinamis');
    } finally {
      setGdcLoading(false);
    }
  }, [orderId]);

  // Manual Check Status GDC MPM
  const handleCheckGdcStatus = async () => {
    if (!orderId) return;
    setGdcLoading(true);
    try {
      const payment = await queryGdcQrisMpmStatus(orderId);
      setGdcPayment(payment);
      await loadOrderAndPaymentInfo(false);
      toast({ title: 'Status pembayaran diperbarui' });
    } catch (err) {
      toast({
        title: 'Gagal mengecek status',
        description: err instanceof Error ? err.message : 'Terjadi kesalahan',
        variant: 'destructive',
      });
    } finally {
      setGdcLoading(false);
    }
  };

  useEffect(() => {
    if (!orderId || authLoading) return;
    if (!user && !guestToken) {
      setLoadError('Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.');
      setLoading(false);
      return;
    }
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
  }, [orderId, user, guestToken, authLoading, loadOrderAndPaymentInfo]);

  // Trigger pembuatan QRIS dinamis jika opsi provider=gdc-mpm aktif
  useEffect(() => {
    const attemptKey = orderId ? `${orderId}:gdc-mpm` : null;
    if (isGdcMpmProvider && attemptKey && !authLoading && !gdcPayment && autoCreateAttemptedForRef.current !== attemptKey) {
      autoCreateAttemptedForRef.current = attemptKey;
      if (!user) {
        setGdcError('Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.');
        return;
      }
      void loadGdcPayment();
    }
  }, [isGdcMpmProvider, orderId, user, authLoading, gdcPayment, loadGdcPayment]);

  useEffect(() => {
    if (!isGdcMpmProvider || !orderId || !gdcPayment || !['PENDING'].includes(gdcPayment.status)) return;
    let cancelled = false;
    let timeout: number | undefined;
    let delay = 5000;
    const deadline = order?.confirmation_deadline ? Date.parse(order.confirmation_deadline) : Number.POSITIVE_INFINITY;
    const poll = async () => {
      if (cancelled || Date.now() >= deadline) {
        if (!cancelled && order) setGdcPayment({ ...gdcPayment, status: 'EXPIRED' });
        return;
      }
      try {
        const payment = await queryGdcQrisMpmStatus(orderId);
        if (cancelled) return;
        setGdcPayment(payment);
        await loadOrderAndPaymentInfo(false);
        if (payment.status === 'PAID' || payment.status === 'FAILED' || payment.status === 'EXPIRED') return;
        delay = Math.min(delay * 2, 30000);
      } catch (error) {
        console.warn('Polling status QRIS GDC gagal:', error instanceof Error ? error.message : 'unknown');
      }
      if (!cancelled) timeout = window.setTimeout(() => void poll(), delay);
    };
    timeout = window.setTimeout(() => void poll(), delay);
    return () => {
      cancelled = true;
      if (timeout) window.clearTimeout(timeout);
    };
  }, [gdcPayment, isGdcMpmProvider, loadOrderAndPaymentInfo, order, orderId]);

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
  const isPaymentExpired = paymentStatus === 'EXPIRED' || gdcPayment?.status === 'EXPIRED'
    || Boolean(order.confirmation_deadline && Date.parse(order.confirmation_deadline) <= Date.now() && !isPaymentComplete);
  const hasPaymentInstructions = Boolean(paymentInfo.qrisImageUrl || (paymentInfo.bankName && paymentInfo.bankAccountNumber && paymentInfo.bankAccountName));
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
              <div>
                <p className="font-bold">Pembayaran sudah diterima</p>
                <p className="mt-1">Pesanan akan diproses sesuai status terbaru dari penjual.</p>
              </div>
            </CardContent>
          </Card>
        )}

        {isPaymentExpired && (
          <Card className="border-destructive/30 bg-destructive/5">
            <CardContent className="flex items-start gap-3 p-4 text-sm" role="status">
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-destructive" />
              <div>
                <p className="font-bold">Batas pembayaran telah berakhir</p>
                <p className="mt-1">Pesanan ini tidak lagi menerima pembayaran. Silakan buat pesanan baru atau hubungi penjual.</p>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Notifikasi Menunggu Instruksi Pembayaran Manual */}
        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && !hasPaymentInstructions && (
          <Card className="border-amber-200 bg-amber-50/70">
            <CardContent className="flex items-start gap-3 p-4 text-sm text-amber-950" role="status">
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-amber-600" />
              <div>
                <p className="font-bold">Menunggu instruksi pembayaran</p>
                <p className="mt-1">QRIS atau rekening bank merchant belum tersedia untuk pesanan ini. Jangan melakukan pembayaran sebelum instruksi resmi ditampilkan.</p>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Section 1: GDC QRIS MPM Dinamis (Render lewat qrcode.react) */}
        {isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && (
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.15 }}>
            <Card>
              <CardContent className="p-4 flex flex-col items-center text-center">
                <div className="flex items-center gap-2 mb-3">
                  <QrIcon className="h-5 w-5 text-primary" />
                  <h3 className="font-bold">QRIS Otomatis (GDC SNAP)</h3>
                  <Badge variant="secondary" className="text-[10px] bg-emerald-100 text-emerald-800">Instant</Badge>
                </div>

                {gdcLoading ? (
                  <div className="py-8 flex flex-col items-center gap-2">
                    <Loader2 className="h-8 w-8 animate-spin text-primary" />
                    <p className="text-xs text-muted-foreground">Membuat QRIS Dinamis...</p>
                  </div>
                ) : gdcError ? (
                  <div className="py-4 text-sm text-destructive flex flex-col items-center gap-2">
                    <AlertTriangle className="h-6 w-6" />
                    <p>{gdcError}</p>
                    <Button size="sm" variant="outline" onClick={() => void loadGdcPayment()}>
                      Coba Lagi
                    </Button>
                  </div>
                ) : gdcPayment?.qr_content ? (
                  <div className="flex flex-col items-center w-full">
                    <div className="p-4 bg-white rounded-xl border border-border shadow-sm my-2 flex justify-center">
                      <QRCodeSVG
                        value={gdcPayment.qr_content}
                        size={220}
                        style={{ height: 'auto', maxWidth: '100%', width: '100%' }}
                        level="M"
                      />
                    </div>
                    <p className="text-xs text-muted-foreground max-w-xs mt-2">
                      Scan kode QRIS di atas menggunakan <strong>GoPay, OVO, ShopeePay, DANA, BCA, atau m-Banking</strong>. Pembayaran akan terverifikasi secara otomatis.
                    </p>

                    {/* Tombol Cek Status Manual */}
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={handleCheckGdcStatus}
                      disabled={gdcLoading}
                      className="mt-4 gap-2 text-xs"
                    >
                      <RefreshCw className={`h-3.5 w-3.5 ${gdcLoading ? 'animate-spin' : ''}`} />
                      Cek Status Pembayaran
                    </Button>
                  </div>
                ) : null}
              </CardContent>
            </Card>
          </motion.div>
        )}

        {/* Section 2: QRIS Manual Toko (Gambar Statis Merchant) */}
        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && paymentInfo.qrisImageUrl && (
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}>
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center gap-2 mb-4">
                  <QrIcon className="h-5 w-5 text-primary" />
                  <h3 className="font-bold">QRIS Toko</h3>
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

        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && paymentInfo.bankName && paymentInfo.bankAccountNumber && paymentInfo.bankAccountName && (
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.25 }}>
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center gap-2 mb-4">
                  <CreditCard className="h-5 w-5 text-primary" />
                  <h3 className="font-bold">Transfer Bank</h3>
                </div>
                <div className="space-y-1 rounded-lg border bg-secondary/50 p-3 text-sm">
                  <p><span className="text-muted-foreground">Bank:</span> {paymentInfo.bankName}</p>
                  <p><span className="text-muted-foreground">Nomor rekening:</span> {paymentInfo.bankAccountNumber}</p>
                  <p><span className="text-muted-foreground">Atas nama:</span> {paymentInfo.bankAccountName}</p>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">Transfer sesuai total pembayaran, kemudian unggah bukti transfer di bawah.</p>
              </CardContent>
            </Card>
          </motion.div>
        )}

        {/* Upload Bukti Pembayaran (Hanya untuk QRIS Manual Toko) */}
        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && hasPaymentInstructions && (
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 }}>
            <Card>
              <CardContent className="p-4">
                <h3 className="font-bold text-sm mb-3">Upload Bukti Pembayaran</h3>
                {order.payment_status === 'FAILED' && (
                  <p role="alert" className="mb-3 rounded-lg border border-destructive/20 bg-destructive/5 p-3 text-sm text-muted-foreground">
                    Bukti sebelumnya ditolak. Unggah ulang bukti pembayaran QRIS atau transfer bank yang benar; status akan kembali menunggu verifikasi setelah berhasil diunggah.
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
          </motion.div>
        )}

        {/* Petunjuk Pembayaran (Hanya untuk QRIS Manual Toko) */}
        {!isGdcMpmPayment && !isPaymentComplete && !isPaymentExpired && hasPaymentInstructions && <motion.div
          initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.4 }}
        >
          <Card>
            <CardContent className="p-4">
              <h3 className="font-bold text-sm mb-3">Petunjuk Pembayaran</h3>
              <ol className="space-y-2 text-sm text-muted-foreground list-decimal list-inside">
                <li>Bayar melalui QRIS atau transfer bank sesuai <strong className="text-foreground">total yang tertera</strong></li>
                <li>Pastikan tujuan pembayaran sesuai dengan nama merchant atau rekening pada instruksi</li>
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
