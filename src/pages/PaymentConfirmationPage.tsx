import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { ArrowLeft, Copy, CheckCircle, CreditCard, QrCode, Clock, ExternalLink, AlertTriangle } from 'lucide-react';
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

interface PaymentInfo {
  bankName: string;
  bankAccountNumber: string;
  bankAccountName: string;
  qrisImageUrl: string | null;
}

interface OrderInfo {
  id: string;
  total: number;
  payment_method: string;
  payment_status: string;
  merchant_id: string;
  created_at: string;
  merchant_name?: string;
  payment_proof_url?: string | null;
  confirmation_deadline?: string | null;
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
  const [copied, setCopied] = useState(false);

  const loadOrderAndPaymentInfo = useCallback(async () => {
    setLoading(true);
    setLoadError(null);
    try {
      if (!orderId) return;
      let orderData: OrderInfo | null = null;
      let merchantData: { name?: string; bank_name?: string; bank_account_number?: string; bank_account_name?: string; qris_image_url?: string | null } | null = null;
      let adminSettings: { value?: unknown } | null = null;

      if (!user && guestToken) {
        const { data, error } = await supabase.rpc('get_guest_order_payment_context' as never, {
          p_order_id: orderId,
          p_guest_access_token: guestToken,
        } as never);
        if (error || !data) throw new Error('Pesanan guest tidak ditemukan atau link sudah kedaluwarsa');
        const context = data as OrderInfo & { bank_name?: string; bank_account_number?: string; bank_account_name?: string; qris_image_url?: string | null };
        orderData = context;
        merchantData = context;
      } else if (user) {
        const result = await supabase
          .from('orders')
          .select('id, total, payment_method, payment_status, merchant_id, created_at, payment_proof_url, confirmation_deadline')
          .eq('id', orderId)
          .eq('buyer_id', user.id)
          .maybeSingle();
        if (result.error || !result.data) throw new Error('Pesanan tidak ditemukan');
        orderData = result.data as OrderInfo;
        const [{ data: merchant }, { data: settings }] = await Promise.all([
          supabase.from('merchants').select('name, bank_name, bank_account_number, bank_account_name, qris_image_url').eq('id', orderData.merchant_id).maybeSingle(),
          supabase.from('app_settings').select('value').eq('key', 'admin_payment_info').maybeSingle(),
        ]);
        merchantData = merchant;
        adminSettings = settings;
      } else {
        throw new Error('Link pembayaran tidak memiliki token guest');
      }

      if (!orderData) throw new Error('Pesanan tidak ditemukan');
      setOrder({ ...orderData, merchant_name: merchantData?.name || orderData.merchant_name || 'Merchant' });

      let bankName = merchantData?.bank_name || '';
      let bankAccountNumber = merchantData?.bank_account_number || '';
      let bankAccountName = merchantData?.bank_account_name || '';
      let qrisImageUrl = merchantData?.qris_image_url || null;
      if (!bankName || !bankAccountNumber) {
        const adminPayment = (adminSettings?.value || {}) as Record<string, string>;
        if (!bankName) bankName = adminPayment.bank_name || '';
        if (!bankAccountNumber) bankAccountNumber = adminPayment.bank_account_number || '';
        if (!bankAccountName) bankAccountName = adminPayment.bank_account_name || '';
        if (!qrisImageUrl) qrisImageUrl = adminPayment.qris_image_url || null;
      }
      setPaymentInfo({ bankName, bankAccountNumber, bankAccountName, qrisImageUrl });
    } catch (error) {
      console.error('Error loading payment info:', error);
      setLoadError(error instanceof Error ? error.message : 'Data pembayaran tidak dapat dimuat');
    } finally {
      setLoading(false);
    }
  }, [orderId, user, guestToken]);

  useEffect(() => {
    if (!orderId || (!user && !guestToken)) return;
    void loadOrderAndPaymentInfo();
  }, [orderId, user, guestToken, loadOrderAndPaymentInfo]);

  const handleCopyAccount = () => {
    if (paymentInfo?.bankAccountNumber) {
      navigator.clipboard.writeText(paymentInfo.bankAccountNumber);
      setCopied(true);
      toast({ title: 'Nomor rekening disalin' });
      setTimeout(() => setCopied(false), 2000);
    }
  };

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
  const hasPaymentInstructions = Boolean(
    (paymentInfo.bankName && paymentInfo.bankAccountNumber) || paymentInfo.qrisImageUrl,
  );
  const statusLabel = isPaymentComplete ? 'Pembayaran Diterima' : isPaymentRejected ? 'Bukti Ditolak' : 'Menunggu Pembayaran';

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
                <Badge variant={isPaymentComplete ? 'default' : isPaymentRejected ? 'destructive' : 'secondary'} className="flex items-center gap-1">
                  {isPaymentComplete ? <CheckCircle className="h-3 w-3" /> : isPaymentRejected ? <AlertTriangle className="h-3 w-3" /> : <Clock className="h-3 w-3" />}
                  {statusLabel}
                </Badge>
              </div>
              {order.confirmation_deadline && (
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

        {!isPaymentComplete && !hasPaymentInstructions && (
          <Card className="border-amber-200 bg-amber-50/70">
            <CardContent className="flex items-start gap-3 p-4 text-sm text-amber-950" role="status">
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-amber-600" />
              <div>
                <p className="font-bold">Menunggu instruksi pembayaran</p>
                <p className="mt-1">Penjual belum menyediakan rekening atau QRIS. Jangan melakukan transfer sebelum menerima instruksi resmi. Gunakan total pesanan di atas saat instruksi pembayaran diberikan.</p>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Bank Transfer Info */}
        {!isPaymentComplete && paymentInfo.bankName && paymentInfo.bankAccountNumber && (
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}>
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center gap-2 mb-4">
                  <CreditCard className="h-5 w-5 text-primary" />
                  <h3 className="font-bold">Transfer Bank</h3>
                </div>

                <div className="space-y-3">
                  <div className="p-3 bg-secondary/50 rounded-lg">
                    <p className="text-xs text-muted-foreground mb-1">Bank</p>
                    <p className="font-bold text-lg">{paymentInfo.bankName}</p>
                  </div>

                  <div className="p-3 bg-secondary/50 rounded-lg">
                    <p className="text-xs text-muted-foreground mb-1">Nomor Rekening</p>
                    <div className="flex items-center justify-between">
                      <p className="font-mono font-bold text-lg tracking-wider">{paymentInfo.bankAccountNumber}</p>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={handleCopyAccount}
                        className="h-8"
                      >
                        {copied ? <CheckCircle className="h-4 w-4 text-green-600" /> : <Copy className="h-4 w-4" />}
                        <span className="ml-1 text-xs">{copied ? 'Tersalin' : 'Salin'}</span>
                      </Button>
                    </div>
                  </div>

                  <div className="p-3 bg-secondary/50 rounded-lg">
                    <p className="text-xs text-muted-foreground mb-1">Atas Nama</p>
                    <p className="font-bold">{paymentInfo.bankAccountName}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </motion.div>
        )}

        {/* QRIS */}
        {!isPaymentComplete && paymentInfo.qrisImageUrl && (
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
        {!isPaymentComplete && hasPaymentInstructions && <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 }}>
          <Card>
            <CardContent className="p-4">
              <h3 className="font-bold text-sm mb-3">Upload Bukti Pembayaran</h3>
              {order.payment_status === 'FAILED' && (
                <p role="alert" className="mb-3 rounded-lg border border-destructive/20 bg-destructive/5 p-3 text-sm text-muted-foreground">
                  Bukti sebelumnya ditolak. Ganti dengan bukti transfer yang benar; status akan kembali menunggu verifikasi setelah berhasil diunggah.
                </p>
              )}
              <PaymentProofUpload
                orderId={order.id}
                guestAccessToken={!user ? guestToken : undefined}
                currentProofUrl={order.payment_proof_url}
                isRejected={order.payment_status === 'FAILED'}
                onUploaded={(url) => setOrder(prev => prev ? { ...prev, payment_proof_url: url, payment_status: 'PENDING_TRANSFER' } : prev)}
              />
            </CardContent>
          </Card>
        </motion.div>}

        {/* Instructions */}
        {!isPaymentComplete && hasPaymentInstructions && <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.4 }}>
          <Card>
            <CardContent className="p-4">
              <h3 className="font-bold text-sm mb-3">Petunjuk Pembayaran</h3>
              <ol className="space-y-2 text-sm text-muted-foreground list-decimal list-inside">
                <li>Transfer sesuai <strong className="text-foreground">nominal yang tertera</strong> (harus sama persis)</li>
                <li>Pastikan transfer ke rekening yang benar</li>
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
