import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogDescription,
  DialogTitle,
} from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { useQuery } from '@tanstack/react-query';
import { formatPrice } from '@/lib/utils';
import { User, Phone, MapPin, CreditCard, Check, X, Truck, Printer, Store, CheckCircle, Package, ImageIcon, RefreshCw, Download, Share2, Loader2 } from 'lucide-react';
import { useEffect, useState } from 'react';
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { getPaymentProofSignedUrl } from '@/lib/paymentProof';

interface OrderItem {
  id: string;
  product_name: string;
  quantity: number;
  product_price: number;
  subtotal: number;
}

interface OrderRow {
  id: string;
  status: string;
  payment_status: string | null;
  payment_proof_url?: string | null;
  payment_method?: string | null;
  delivery_type: string;
  delivery_name: string | null;
  delivery_phone: string | null;
  delivery_address: string | null;
  subtotal: number;
  shipping_cost: number;
  total: number;
  cod_service_fee?: number | null;
  notes: string | null;
  created_at: string;
  courier_id: string | null;
  merchants?: { name: string } | null;
  is_self_delivery?: boolean;
  self_delivery_fee_amount?: number | null;
  self_delivery_fee_status?: string | null;
  expedition_name?: string | null;
  tracking_number?: string | null;
  expedition_provider_id?: string | null;
}

interface ExpeditionProvider {
  id: string;
  name: string;
  logo_url: string | null;
  tracking_website: string;
}

interface OrderDetailsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  order: OrderRow | null;
  orderItems: OrderItem[];
  onUpdateStatus: (orderId: string, newStatus: string) => void;
  onOpenAssignCourier: (order: OrderRow) => void;
  getStatusBadge: (status: string) => React.ReactNode;
  getPaymentBadge: (paymentStatus: string | null) => React.ReactNode;
  onVerifyPayment: (orderId: string) => Promise<boolean>;
  onRejectPayment: (orderId: string, reason: string) => Promise<boolean>;
}

export function OrderDetailsDialog({
  open,
  onOpenChange,
  order,
  orderItems,
  onUpdateStatus,
  onOpenAssignCourier,
  getStatusBadge,
  getPaymentBadge,
  onVerifyPayment,
  onRejectPayment,
}: OrderDetailsDialogProps) {
  const [isProcessing, setIsProcessing] = useState(false);
  const [isReviewingPayment, setIsReviewingPayment] = useState(false);
  const [isRejectingPayment, setIsRejectingPayment] = useState(false);
  const [paymentRejectionReason, setPaymentRejectionReason] = useState('');
  const [isDownloadingProof, setIsDownloadingProof] = useState(false);
  const [isSharingOrder, setIsSharingOrder] = useState(false);
  const [deliveryType, setDeliveryType] = useState<"courier" | "self">("courier");
  const [trackingNumber, setTrackingNumber] = useState('');
  const [expeditionProviderId, setExpeditionProviderId] = useState('');
  const [expeditionProviders, setExpeditionProviders] = useState<ExpeditionProvider[]>([]);
  const paymentProofQuery = useQuery<string>({
    queryKey: ['admin-order-payment-proof', order?.id, order?.payment_proof_url],
    queryFn: async () => {
      const signedUrl = await getPaymentProofSignedUrl(order?.payment_proof_url);
      if (!signedUrl) throw new Error('Bukti pembayaran tidak dapat dimuat.');
      return signedUrl;
    },
    enabled: open && !!order?.payment_proof_url,
    retry: false,
  });

  useEffect(() => {
    if (!open || order?.delivery_type !== 'EXPEDITION') return;
    supabase.from('expedition_providers').select('id, name, logo_url, tracking_website').eq('is_active', true).order('sort_order').order('name')
      .then(({ data, error }) => {
        if (error) toast.error(`Gagal memuat master ekspedisi: ${error.message}`);
        else setExpeditionProviders((data || []) as unknown as ExpeditionProvider[]);
      });
  }, [open, order?.delivery_type]);

  if (!order) return null;

  const handleExpeditionHandoff = async () => {
    const provider = expeditionProviders.find((item) => item.id === expeditionProviderId);
    if (!provider || !trackingNumber.trim()) {
      toast.error('Pilih ekspedisi dan isi nomor resi');
      return;
    }
    setIsProcessing(true);
    try {
      const { error } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: order.id,
        p_to_status: 'SENT',
        p_reason: JSON.stringify({
          type: 'EXPEDITION_HANDOFF',
          expedition_provider_id: provider.id,
          expedition_name: provider.name,
          expedition_logo_url: provider.logo_url,
          expedition_tracking_url: provider.tracking_website,
          tracking_number: trackingNumber.trim(),
        }),
      } as never);
      if (error) throw error;
      toast.success('Pesanan diserahkan ke ekspedisi');
      onUpdateStatus(order.id, 'SENT');
      onOpenChange(false);
    } catch (error) {
      console.error('Expedition handoff error:', error);
      toast.error(error instanceof Error ? error.message : 'Gagal menyerahkan ke ekspedisi');
    } finally {
      setIsProcessing(false);
    }
  };

  const handlePrint = () => {
    const printContent = document.getElementById('order-print-content');
    if (!printContent) return;

    const printWindow = window.open('', '_blank');
    if (!printWindow) return;

    printWindow.document.write(`
      <html>
        <head>
          <title>Invoice #${order.id.slice(0, 8).toUpperCase()}</title>
          <style>
            body { font-family: sans-serif; padding: 20px; color: #333; }
            .header { text-align: center; border-bottom: 2px solid #eee; padding-bottom: 20px; margin-bottom: 20px; }
            .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
            .section-title { font-weight: bold; margin-bottom: 10px; border-bottom: 1px solid #eee; padding-bottom: 5px; }
            table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
            th { text-align: left; border-bottom: 1px solid #eee; padding: 10px 0; }
            td { padding: 10px 0; border-bottom: 1px solid #f9f9f9; }
            .totals { text-align: right; }
            .total-row { font-weight: bold; font-size: 1.2em; }
            .footer { margin-top: 40px; text-align: center; font-size: 0.8em; color: #888; }
          </style>
        </head>
        <body>
          <div class="header">
            <h1>INVOICE</h1>
            <p>#${order.id.toUpperCase()}</p>
            <p>Tanggal: ${new Date(order.created_at).toLocaleString('id-ID')}</p>
          </div>
          
          <div class="info-grid">
            <div>
              <div class="section-title">Merchant</div>
              <p><strong>${order.merchants?.name || '-'}</strong></p>
            </div>
            <div>
              <div class="section-title">Pelanggan</div>
              <p>${order.delivery_name || 'Pelanggan'}</p>
              <p>${order.delivery_phone || '-'}</p>
              <p>${order.delivery_address || '-'}</p>
            </div>
          </div>

          <div class="section-title">Item Pesanan</div>
          <table>
            <thead>
              <tr>
                <th>Produk</th>
                <th>Harga</th>
                <th>Qty</th>
                <th style="text-align: right">Subtotal</th>
              </tr>
            </thead>
            <tbody>
              ${orderItems.map(item => `
                <tr>
                  <td>${item.product_name}</td>
                  <td>${formatPrice(item.product_price)}</td>
                  <td>${item.quantity}</td>
                  <td style="text-align: right">${formatPrice(item.subtotal)}</td>
                </tr>
              `).join('')}
            </tbody>
          </table>

          <div class="totals">
            <p>Subtotal: ${formatPrice(order.subtotal)}</p>
            <p>Ongkos Kirim: ${formatPrice(order.shipping_cost)}</p>
            <p class="total-row">Total: ${formatPrice(order.total)}</p>
          </div>

          ${order.notes ? `
            <div style="margin-top: 20px; padding: 10px; background: #f9f9f9; border-radius: 5px;">
              <div class="section-title">Catatan</div>
              <p>${order.notes}</p>
            </div>
          ` : ''}

          <div class="footer">
            <p>Terima kasih telah berbelanja di UMKM Mitra</p>
          </div>
          <script>
            window.onload = () => {
              window.print();
              window.onafterprint = () => window.close();
            };
          </script>
        </body>
      </html>
    `);
    printWindow.document.close();
  };

  const handleDownloadPaymentProof = async () => {
    if (!paymentProofQuery.data) return;
    setIsDownloadingProof(true);
    let objectUrl: string | null = null;
    try {
      const response = await fetch(paymentProofQuery.data);
      if (!response.ok) throw new Error('Unduhan bukti pembayaran gagal.');
      const blob = await response.blob();
      const extension = blob.type === 'image/png' ? 'png' : blob.type === 'image/webp' ? 'webp' : 'jpg';
      objectUrl = URL.createObjectURL(blob);
      const downloadLink = document.createElement('a');
      downloadLink.href = objectUrl;
      downloadLink.download = `bukti-pembayaran-${order.id.slice(0, 8).toUpperCase()}.${extension}`;
      document.body.appendChild(downloadLink);
      downloadLink.click();
      downloadLink.remove();
      window.setTimeout(() => {
        if (objectUrl) URL.revokeObjectURL(objectUrl);
      }, 1000);
      toast.success('Bukti pembayaran berhasil diunduh');
    } catch {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      toast.error('Gagal mengunduh bukti pembayaran. Coba lagi.');
    } finally {
      setIsDownloadingProof(false);
    }
  };

  const handleShareOrder = async () => {
    const orderNumber = order.id.slice(0, 8).toUpperCase();
    const shareText = [
      `Detail Pesanan #${orderNumber}`,
      order.merchants?.name ? `Merchant: ${order.merchants.name}` : null,
      `Status pesanan: ${order.status}`,
      `Pembayaran: ${order.payment_method || '-'} (${order.payment_status || '-'})`,
      '',
      'Item pesanan:',
      ...(orderItems.length > 0
        ? orderItems.map((item) => `- ${item.product_name} × ${item.quantity}: ${formatPrice(item.subtotal)}`)
        : ['- Rincian item tidak tersedia']),
      `Subtotal produk: ${formatPrice(order.subtotal)}`,
      `Ongkos kirim: ${formatPrice(order.shipping_cost)}`,
      `Total: ${formatPrice(order.total)}`,
      `Pengiriman: ${order.delivery_type === 'PICKUP' ? 'Ambil sendiri' : order.delivery_type === 'EXPEDITION' ? 'Ekspedisi' : 'Diantar'}`,
    ].filter((line): line is string => line !== null).join('\n');

    setIsSharingOrder(true);
    try {
      if (typeof navigator.share === 'function') {
        await navigator.share({ title: `Detail Pesanan #${orderNumber}`, text: shareText });
        toast.success('Detail pesanan siap dibagikan');
      } else if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(shareText);
        toast.success('Detail pesanan disalin. Silakan tempel untuk membagikannya.');
      } else {
        throw new Error('Fitur berbagi tidak tersedia di perangkat ini.');
      }
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') return;
      toast.error(error instanceof Error ? error.message : 'Gagal membagikan detail pesanan.');
    } finally {
      setIsSharingOrder(false);
    }
  };

  const handleVerifyPayment = async () => {
    setIsReviewingPayment(true);
    try {
      await onVerifyPayment(order.id);
    } finally {
      setIsReviewingPayment(false);
    }
  };

  const handleRejectPayment = async () => {
    const reason = paymentRejectionReason.trim();
    if (reason.length < 3) return;
    setIsReviewingPayment(true);
    try {
      const rejected = await onRejectPayment(order.id, reason);
      if (rejected) {
        setIsRejectingPayment(false);
        setPaymentRejectionReason('');
      }
    } finally {
      setIsReviewingPayment(false);
    }
  };

  // Accept the order first, then optionally start self-delivery through the
  // valid server state transition PROCESSED -> DELIVERING.
  const handleProcessOrder = async () => {
    try {
      setIsProcessing(true);
      
      const isPickup = order.delivery_type === 'PICKUP';
      const isExpedition = order.delivery_type === 'EXPEDITION';
      const isSelfDelivery = !isPickup && !isExpedition && deliveryType === "self";

      const { error: processError } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: order.id,
        p_to_status: 'PROCESSED',
        p_reason: 'Merchant menerima pesanan',
      } as never);

      if (processError) throw processError;

      let newStatus = 'PROCESSED';
      if (isSelfDelivery) {
        const { error: selfDeliveryError } = await supabase.rpc('merchant_transition_order' as never, {
          p_order_id: order.id,
          p_to_status: 'DELIVERING',
          p_reason: 'Merchant memilih antar sendiri',
        } as never);
        if (selfDeliveryError) throw selfDeliveryError;
        newStatus = 'DELIVERING';
      }
      
      if (isPickup) {
        toast.success('Pesanan diproses (Pembeli akan ambil sendiri).');
      } else if (isExpedition) {
        toast.success('Pesanan diproses untuk diserahkan ke ekspedisi.');
      } else {
        toast.success(isSelfDelivery ? 'Pesanan diproses, silakan antar pesanan!' : 'Pesanan diproses. Silakan pilih Kurir Desa.');
      }
      
      // Update parent component status optimistically
      onUpdateStatus(order.id, newStatus);
      onOpenChange(false);

      // Jika menggunakan kurir desa, otomatis buka modal tugaskan kurir untuk pengalaman seperti di dashboard admin
      if (!isPickup && !isExpedition && !isSelfDelivery && onOpenAssignCourier) {
        setTimeout(() => {
          onOpenAssignCourier({ ...order, status: newStatus, is_self_delivery: false });
        }, 300);
      }

    } catch (err) {
      console.error(err);
      toast.error('Gagal memproses pesanan');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleCompleteSelfDelivery = async () => {
    try {
      setIsProcessing(true);
      const { error } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: order.id,
        p_to_status: 'DONE',
        p_reason: 'Pengiriman mandiri selesai',
      } as never);

      if (error) throw error;
      
      toast.success('Pesanan selesai!');
      onUpdateStatus(order.id, 'DONE');
      onOpenChange(false);
    } catch (e) {
      toast.error('Gagal menyelesaikan pesanan');
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader className="flex flex-row items-center justify-between space-y-0">
          <DialogDescription className="sr-only">
            Informasi pesanan, pembayaran, item, serta tindakan pengelolaan pesanan.
          </DialogDescription>
          <DialogTitle>
            Detail Pesanan #{order.id.slice(0, 8).toUpperCase()}
          </DialogTitle>
          <div className="flex shrink-0 gap-2">
            <Button type="button" variant="outline" size="sm" onClick={() => void handleShareOrder()} disabled={isSharingOrder}>
              {isSharingOrder ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Share2 className="h-4 w-4 mr-2" />}
              Bagikan
            </Button>
            <Button variant="outline" size="sm" onClick={handlePrint}>
              <Printer className="h-4 w-4 mr-2" />
              Cetak
            </Button>
          </div>
        </DialogHeader>
        <div className="space-y-4 py-4 max-h-[70vh] overflow-y-auto" id="order-print-content">
          {/* Status Row */}
          <div className="flex items-center justify-between gap-4">
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">Status:</span>
              {getStatusBadge(order.status)}
            </div>
            <div className="flex items-center gap-2">
              <CreditCard className="h-4 w-4 text-muted-foreground" />
              {getPaymentBadge(order.payment_status)}
            </div>
          </div>

          {/* Self Delivery Indicator */}
          {order.is_self_delivery && (
            <div className="flex items-center gap-2 p-3 bg-blue-50 text-blue-700 rounded-lg text-sm border border-blue-100">
              <Store className="w-4 h-4" />
              <span className="font-medium">Pengiriman Mandiri (Diantar Kurir Toko)</span>
            </div>
          )}

          {/* Merchant */}
          <div className="bg-secondary/50 rounded-lg p-3">
            <p className="text-sm text-muted-foreground">Merchant</p>
            <p className="font-medium">{order.merchants?.name || '-'}</p>
          </div>

          {/* Customer Info */}
          <div className="bg-secondary/50 rounded-lg p-4 space-y-2">
            <p className="text-sm font-medium mb-2">Informasi Pengiriman</p>
            <div className="flex items-center gap-2 text-sm">
              <User className="h-4 w-4 text-muted-foreground" />
              <span>{order.delivery_name || 'Pelanggan'}</span>
            </div>
            {order.delivery_phone && (
              <div className="flex items-center gap-2 text-sm">
                <Phone className="h-4 w-4 text-muted-foreground" />
                <span>{order.delivery_phone}</span>
              </div>
            )}
            {order.delivery_address && (
              <div className="flex items-start gap-2 text-sm">
                <MapPin className="h-4 w-4 text-muted-foreground mt-0.5" />
                <span>{order.delivery_address}</span>
              </div>
            )}
            <Badge variant="outline" className="mt-2">
              {order.delivery_type === 'PICKUP'
                ? 'Ambil Sendiri'
                : order.delivery_type === 'EXPEDITION' ? 'Ekspedisi' : 'Diantar Kurir'}
            </Badge>
          </div>

          {/* Items */}
          <div className="space-y-2">
            <p className="text-sm font-medium">Item Pesanan</p>
            <div className="border border-border rounded-lg divide-y divide-border">
              {orderItems.map((item) => (
                <div key={item.id} className="p-3 flex justify-between">
                  <div>
                    <p className="font-medium text-sm">{item.product_name}</p>
                    <p className="text-xs text-muted-foreground">
                      {item.quantity} x {formatPrice(item.product_price)}
                    </p>
                  </div>
                  <p className="font-medium text-sm">
                    {formatPrice(item.subtotal)}
                  </p>
                </div>
              ))}
            </div>
          </div>

          {/* Notes */}
          {order.notes && (
            <div className="text-sm bg-muted/50 rounded-lg p-3">
              <p className="text-muted-foreground mb-1">Catatan:</p>
              <p>{order.notes}</p>
            </div>
          )}

          {order.payment_proof_url && (
            <section className="space-y-2" aria-label="Bukti Pembayaran">
              <div className="flex items-center gap-2">
                <ImageIcon className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
                <p className="text-sm font-medium">Bukti Pembayaran</p>
              </div>
              {paymentProofQuery.isLoading || (paymentProofQuery.isError && paymentProofQuery.isFetching) ? (
                <div role="status" className="flex min-h-32 items-center justify-center rounded-lg border border-dashed text-sm text-muted-foreground">
                  Memuat bukti pembayaran...
                </div>
              ) : paymentProofQuery.isError ? (
                <div role="alert" className="rounded-lg border border-destructive/25 bg-destructive/5 p-3 text-sm">
                  <p className="text-muted-foreground">Bukti pembayaran tidak dapat dimuat. Coba lagi.</p>
                  <Button type="button" variant="outline" size="sm" className="mt-2" onClick={() => void paymentProofQuery.refetch()}>
                    <RefreshCw className="mr-2 h-3.5 w-3.5" aria-hidden="true" />
                    Coba lagi
                  </Button>
                </div>
              ) : paymentProofQuery.data ? (
                <div className="space-y-1">
                  <a href={paymentProofQuery.data} target="_blank" rel="noopener noreferrer" aria-label="Buka bukti pembayaran ukuran penuh">
                    <img
                      src={paymentProofQuery.data}
                      alt="Bukti pembayaran yang diunggah pembeli"
                      className="max-h-64 w-full cursor-zoom-in rounded-lg border border-border bg-secondary/30 object-contain"
                    />
                  </a>
                  <p className="text-center text-xs text-muted-foreground">Klik gambar untuk memperbesar</p>
                  <Button type="button" variant="outline" size="sm" className="w-full" onClick={() => void handleDownloadPaymentProof()} disabled={isDownloadingProof}>
                    {isDownloadingProof ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Download className="mr-2 h-4 w-4" />}
                    {isDownloadingProof ? 'Mengunduh bukti...' : 'Unduh bukti pembayaran'}
                  </Button>
                </div>
              ) : null}
            </section>
          )}

          {order.status === 'PENDING_PAYMENT' && order.payment_status === 'FAILED' && (
            <div role="status" className="rounded-lg border border-destructive/20 bg-destructive/5 p-3 text-sm text-muted-foreground">
              Bukti sebelumnya ditolak. Menunggu pembeli mengunggah bukti pembayaran baru.
            </div>
          )}

          {order.status === 'PENDING_PAYMENT'
            && order.payment_method === 'TRANSFER'
            && !!order.payment_proof_url
            && !['PAID', 'FAILED'].includes(order.payment_status || '') && (
              <section className="space-y-3 rounded-lg border border-border p-4" aria-label="Tinjau pembayaran">
                <div>
                  <p className="text-sm font-semibold">Tinjau Pembayaran</p>
                  <p className="text-xs text-muted-foreground">Periksa bukti transfer sebelum mengonfirmasi atau menolaknya.</p>
                </div>
                {isRejectingPayment ? (
                  <div className="space-y-2">
                    <p className="rounded-md bg-destructive/5 p-2 text-xs text-muted-foreground" role="note">
                      Penolakan hanya menolak bukti ini. Pesanan tetap menunggu pembayaran sehingga pembeli dapat mengunggah bukti baru.
                    </p>
                    <Label htmlFor="payment-rejection-reason">Alasan penolakan (wajib)</Label>
                    <Textarea
                      id="payment-rejection-reason"
                      value={paymentRejectionReason}
                      onChange={(event) => setPaymentRejectionReason(event.target.value)}
                      placeholder="Contoh: nominal transfer tidak sesuai"
                      maxLength={1000}
                      disabled={isReviewingPayment}
                    />
                    <div className="flex gap-2">
                      <Button type="button" variant="outline" className="flex-1" onClick={() => { setIsRejectingPayment(false); setPaymentRejectionReason(''); }} disabled={isReviewingPayment}>
                        Batal
                      </Button>
                      <Button type="button" variant="destructive" className="flex-1" onClick={() => void handleRejectPayment()} disabled={isReviewingPayment || paymentRejectionReason.trim().length < 3}>
                        {isReviewingPayment ? 'Memproses...' : 'Konfirmasi Penolakan'}
                      </Button>
                    </div>
                  </div>
                ) : (
                  <div className="flex flex-col gap-2 sm:flex-row">
                    <Button type="button" className="flex-1" onClick={() => void handleVerifyPayment()} disabled={isReviewingPayment}>
                      {isReviewingPayment ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Check className="mr-2 h-4 w-4" />}
                      Konfirmasi Pembayaran
                    </Button>
                    <Button type="button" variant="destructive" className="flex-1" onClick={() => setIsRejectingPayment(true)} disabled={isReviewingPayment}>
                      <X className="mr-2 h-4 w-4" />
                      Tolak Bukti Pembayaran
                    </Button>
                  </div>
                )}
              </section>
            )}

          {/* Cost Breakdown */}
          <div className="border-t border-border pt-4 space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Subtotal Produk</span>
              <span>{formatPrice(order.subtotal)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Ongkos Kirim</span>
              <span>{formatPrice(order.shipping_cost)}</span>
            </div>
            {order.is_self_delivery && <div className="flex justify-between text-sm"><span className="text-muted-foreground">Fee admin antar sendiri</span><span>{order.self_delivery_fee_status === 'WAIVED' ? 'Gratis' : formatPrice(order.self_delivery_fee_amount || 0)}</span></div>}
            {(order.cod_service_fee ?? 0) > 0 && (
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Biaya COD</span>
                <span>{formatPrice(order.cod_service_fee || 0)}</span>
              </div>
            )}
            {/* Platform fee = total - subtotal - shipping - cod_fee */}
            {(() => {
              const platformFee = order.total - order.subtotal - order.shipping_cost - (order.cod_service_fee || 0);
              return platformFee > 0 ? (
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Biaya Platform</span>
                  <span>{formatPrice(platformFee)}</span>
                </div>
              ) : null;
            })()}
            <div className="flex justify-between font-bold text-lg pt-1 border-t border-dashed border-border">
              <span>Total</span>
              <span className="text-primary">{formatPrice(order.total)}</span>
            </div>
            <div className="flex justify-between text-xs text-muted-foreground">
              <span>Pendapatan Merchant</span>
              <span className="font-medium text-foreground">{formatPrice(order.subtotal)}</span>
            </div>
          </div>

          {/* Action Buttons */}
          <div className="flex flex-col gap-2 pt-2">
            {order.status === 'NEW' && (
              <div className="space-y-3">
                {order.delivery_type === 'INTERNAL' && (
                  <div className="bg-slate-50 p-3 rounded-lg border border-slate-200">
                    <Label className="text-sm font-semibold mb-3 block">Metode Pengiriman:</Label>
                    <RadioGroup 
                      value={deliveryType} 
                      onValueChange={(v) => setDeliveryType(v as "courier" | "self")}
                      className="flex flex-col space-y-2"
                    >
                      <div className="flex items-center space-x-2">
                        <RadioGroupItem value="courier" id="r-courier" />
                        <Label htmlFor="r-courier" className="flex items-center gap-2 cursor-pointer font-normal text-sm">
                          <Truck className="w-4 h-4 text-muted-foreground" />
                          Kirim dengan Kurir Desa
                        </Label>
                      </div>
                      <div className="flex items-center space-x-2">
                        <RadioGroupItem value="self" id="r-self" />
                        <Label htmlFor="r-self" className="flex items-center gap-2 cursor-pointer font-normal text-sm">
                          <Store className="w-4 h-4 text-muted-foreground" />
                          Kirim Sendiri (Kurir Toko Pribadi)
                        </Label>
                      </div>
                    </RadioGroup>
                  </div>
                )}

                <div className="flex gap-2">
                  <Button 
                    className="flex-1"
                    onClick={handleProcessOrder}
                    disabled={isProcessing}
                  >
                    <Check className="h-4 w-4 mr-2" />
                    {isProcessing ? "Memproses..." :
                      (order.delivery_type === 'PICKUP'
                        ? "Terima Pesanan"
                        : order.delivery_type === 'EXPEDITION'
                          ? "Proses untuk Ekspedisi"
                          : (deliveryType === "self" ? "Proses & Kirim Sendiri" : "Proses & Pilih Kurir Desa"))}
                  </Button>
                  <Button 
                    variant="destructive"
                    onClick={() => onUpdateStatus(order.id, 'CANCELLED')}
                    disabled={isProcessing}
                  >
                    <X className="h-4 w-4 mr-2" />
                    Tolak
                  </Button>
                </div>
              </div>
            )}
            
            {/* Opsi selesaikan khusus pengiriman mandiri */}
            {order.status === 'DELIVERING' && order.is_self_delivery && (
              <Button 
                className="w-full bg-green-600 hover:bg-green-700" 
                onClick={handleCompleteSelfDelivery}
                disabled={isProcessing}
              >
                <CheckCircle className="h-4 w-4 mr-2" />
                {isProcessing ? "Memproses..." : "Pesanan Sudah Sampai (Selesai)"}
              </Button>
            )}

            {order.status === 'READY' && order.delivery_type === 'PICKUP' && (
              <Button className="w-full bg-green-600 hover:bg-green-700" onClick={() => onUpdateStatus(order.id, 'DONE')} disabled={isProcessing}>
                <CheckCircle className="h-4 w-4 mr-2" />
                Tandai Sudah Diambil / Selesai
              </Button>
            )}
            {/* Opsi standar jika bukan kirim mandiri */}
            {order.status === 'PROCESSED' && order.delivery_type === 'EXPEDITION' && (
              <div className="space-y-3 rounded-lg border border-border bg-muted/20 p-3">
                <p className="text-sm font-semibold">Data Ekspedisi</p>
                <div className="space-y-1.5">
                  <Label htmlFor="expedition-name">Pilih ekspedisi</Label>
                  <Select value={expeditionProviderId} onValueChange={setExpeditionProviderId}>
                    <SelectTrigger id="expedition-name"><SelectValue placeholder="Pilih ekspedisi" /></SelectTrigger>
                    <SelectContent>{expeditionProviders.map((provider) => <SelectItem key={provider.id} value={provider.id}><span className="flex items-center gap-2">{provider.logo_url && <img src={provider.logo_url} alt="" className="h-5 w-5 object-contain" />} {provider.name}</span></SelectItem>)}</SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="tracking-number">Nomor resi</Label>
                  <input
                    id="tracking-number"
                    value={trackingNumber}
                    onChange={(event) => setTrackingNumber(event.target.value)}
                    placeholder="Masukkan nomor resi"
                    className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                    maxLength={120}
                  />
                </div>
                <Button className="w-full" onClick={handleExpeditionHandoff} disabled={isProcessing}>
                  <Package className="h-4 w-4 mr-2" />
                  {isProcessing ? 'Menyimpan...' : 'Tandai Diserahkan ke Ekspedisi'}
                </Button>
              </div>
            )}
            
            {order.status === 'SENT' && !order.is_self_delivery && order.delivery_type !== 'EXPEDITION' && (
              <Button 
                className="w-full"
                onClick={() => onUpdateStatus(order.id, 'DONE')}
              >
                <Check className="h-4 w-4 mr-2" />
                Selesai
              </Button>
            )}

            {order.delivery_type === 'INTERNAL' && !order.courier_id && !order.is_self_delivery && order.status === 'PROCESSED' && (
              <Button 
                variant="outline"
                className="w-full mt-2"
                onClick={() => {
                  onOpenChange(false);
                  onOpenAssignCourier(order);
                }}
              >
                <Truck className="h-4 w-4 mr-2" />
                Tugaskan Kurir Desa
              </Button>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
