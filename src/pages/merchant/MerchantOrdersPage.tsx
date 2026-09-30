import { useState, useEffect, useRef, useCallback, useMemo, type ReactNode } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Receipt, Check, X, Package, MoreHorizontal, User, MapPin, Phone, Truck, CreditCard, MessageSquare, Printer, RefreshCw, Wifi, Search, Download, Clock, CheckCircle2, ImageIcon, Navigation, Eye, CalendarDays } from 'lucide-react';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { DataTable } from '@/components/admin/DataTable';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';
import { OrderInvoice } from '@/components/merchant/OrderInvoice';
import { printInvoice } from '@/lib/invoicePrint';
import { useRealtimeOrders } from '@/hooks/useRealtimeOrders';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';
import { MerchantDeliveryTracker } from '@/components/merchant/MerchantDeliveryTracker';
import { getPaymentProofSignedUrl } from '@/lib/paymentProof';
import { OrderChat } from '@/components/chat/OrderChat';
import { CourierAssignDialog } from '@/components/admin/CourierAssignDialog';
import { MERCHANT_ORDER_STATUS_FILTER_OPTIONS, orderStatusLabel } from '@/lib/orderStatus';
import { MerchantCardError, MerchantCardLoading } from '@/components/merchant/MerchantDataState';

interface OrderItem {
  id: string;
  product_name: string;
  quantity: number;
  product_price: number;
  subtotal: number;
}

// Use OrderRow from the hook, extending with payment_proof_url
import type { OrderRow as HookOrderRow } from '@/hooks/useRealtimeOrders';
type OrderRow = HookOrderRow;

interface MerchantOrdersWorkspaceProps {
  embedded?: boolean;
  merchantIdOverride?: string;
}

function MerchantOrdersShell({ embedded, children }: { embedded: boolean; children: ReactNode }) {
  return embedded ? <>{children}</> : <MerchantLayout title="Pesanan" subtitle="Kelola pesanan masuk">{children}</MerchantLayout>;
}

export function MerchantOrdersWorkspace({ embedded = false, merchantIdOverride }: MerchantOrdersWorkspaceProps) {
  const { user } = useAuth();
  const { merchantId: guardMerchantId, merchantName: guardMerchantName, loading: guardLoading } = useMerchantGuard();
  const [merchantId, setMerchantId] = useState<string | null>(merchantIdOverride ?? null);
  const [merchantName, setMerchantName] = useState<string>('');
  const [soundEnabled, setSoundEnabled] = useState(true);
  const [selectedOrder, setSelectedOrder] = useState<OrderRow | null>(null);
  const [detailDialogOpen, setDetailDialogOpen] = useState(false);
  const [expeditionName, setExpeditionName] = useState('');
  const [trackingNumber, setTrackingNumber] = useState('');
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [printDialogOpen, setPrintDialogOpen] = useState(false);
  const [isConnected, setIsConnected] = useState(true);
  const [chatOrder, setChatOrder] = useState<OrderRow | null>(null);
  const [courierAssignDialogOpen, setCourierAssignDialogOpen] = useState(false);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [dateFilterOpen, setDateFilterOpen] = useState(false);
  const invoiceRef = useRef<HTMLDivElement>(null);
  const [searchParams, setSearchParams] = useSearchParams();

  // Set merchant from guard
  useEffect(() => {
    if (merchantIdOverride) {
      setMerchantId(merchantIdOverride);
    }
    if (guardMerchantId) {
      setMerchantId(guardMerchantId);
      setMerchantName(guardMerchantName);
    }
  }, [guardMerchantId, guardMerchantName, merchantIdOverride]);

  // Real-time orders hook
  const handleNewOrder = useCallback((order: OrderRow) => {
    setDetailDialogOpen(false);
  }, []);

  const { orders, loading, updateOrderStatus, refetch, loadMore, loadingMore, hasMore } = useRealtimeOrders({
    merchantId,
    onNewOrder: handleNewOrder,
  });

  const orderItemsQuery = useQuery<OrderItem[]>({
    queryKey: ['merchant-order-items', merchantId, selectedOrder?.id],
    queryFn: async () => {
      if (!selectedOrder?.id) return [];
      const { data, error } = await supabase
        .from('order_items')
        .select('*')
        .eq('order_id', selectedOrder.id);
      if (error) throw error;
      return (data || []) as OrderItem[];
    },
    enabled: !!merchantId && !!selectedOrder?.id && (detailDialogOpen || printDialogOpen),
    staleTime: 60_000,
    retry: false,
  });
  const orderItems = orderItemsQuery.data ?? [];
  const orderItemsErrorMessage = 'Item pesanan gagal dimuat. Periksa koneksi lalu coba lagi.';

  const paymentProofQuery = useQuery<string>({
    queryKey: ['merchant-order-payment-proof', merchantId, selectedOrder?.id, selectedOrder?.payment_proof_url],
    queryFn: async () => {
      const signedUrl = await getPaymentProofSignedUrl(selectedOrder?.payment_proof_url);
      if (!signedUrl) throw new Error('Bukti pembayaran gagal dimuat. Periksa koneksi lalu coba lagi.');
      return signedUrl;
    },
    enabled: !!merchantId && !!selectedOrder?.id && detailDialogOpen && !!selectedOrder?.payment_proof_url,
    staleTime: 3_000_000,
    retry: false,
  });

  // Keep an open detail dialog aligned with courier and delivery updates.
  // Otherwise stale status buttons remain visible until the dialog is reopened.
  useEffect(() => {
    setSelectedOrder((current) => {
      if (!current) return current;
      return orders.find((order) => order.id === current.id) ?? current;
    });
  }, [orders]);

  const openAssignDialog = (order: OrderRow) => {
    setSelectedOrder(order);
    setDetailDialogOpen(false);
    setCourierAssignDialogOpen(true);
  };

  // Connection status listener
  useEffect(() => {
    const handleOnline = () => setIsConnected(true);
    const handleOffline = () => setIsConnected(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  const viewOrderDetail = useCallback((order: OrderRow) => {
    setSelectedOrder(order);
    setExpeditionName(order.expedition_name || '');
    setTrackingNumber(order.tracking_number || '');
    setDetailDialogOpen(true);
  }, []);

  const handleExpeditionHandoff = async () => {
    if (!selectedOrder || !expeditionName.trim() || !trackingNumber.trim()) {
      toast.error('Nama ekspedisi dan nomor resi wajib diisi');
      return;
    }
    const { error } = await supabase.rpc('merchant_transition_order' as never, {
      p_order_id: selectedOrder.id,
      p_to_status: 'SENT',
      p_reason: JSON.stringify({ type: 'EXPEDITION_HANDOFF', expedition_name: expeditionName.trim(), tracking_number: trackingNumber.trim() }),
    } as never);
    if (error) { toast.error(error.message || 'Gagal menyerahkan ke ekspedisi'); return; }
    toast.success('Pesanan diserahkan ke ekspedisi');
    setDetailDialogOpen(false);
    await refetch();
  };

  // Handle orderId query parameter from notification click
  useEffect(() => {
    const orderIdFromUrl = searchParams.get('orderId');
    if (orderIdFromUrl && orders.length > 0) {
      const order = orders.find(o => o.id === orderIdFromUrl);
      if (order) {
        viewOrderDetail(order);
        const nextParams = new URLSearchParams(searchParams);
        nextParams.delete('orderId');
        setSearchParams(nextParams, { replace: true });
      }
    }
  }, [searchParams, setSearchParams, orders, viewOrderDetail]);

  const openPrintDialog = useCallback((order: OrderRow) => {
    setSelectedOrder(order);
    setPrintDialogOpen(true);
  }, []);

  const handlePrint = () => {
    if (invoiceRef.current) {
      printInvoice(invoiceRef.current);
    }
  };

  const handleUpdateStatus = async (orderId: string, newStatus: string, reason?: string) => {
    const success = await updateOrderStatus(orderId, newStatus, reason);
    if (success) {
      setDetailDialogOpen(false);
      setRejectDialogOpen(false);
      setRejectReason('');
    }
  };

  const handleSelfDelivery = async (orderId: string) => {
    try {
      const { error } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: orderId,
        p_to_status: 'DELIVERING',
        p_reason: 'Merchant memilih antar sendiri',
      } as never);

      if (error) {
        console.error('Self delivery update error:', error);
        toast.error(`Gagal mengubah status: ${error.message}`);
        return;
      }
      
      toast.success('Pesanan akan diantar sendiri');
      setDetailDialogOpen(false);
      refetch();
    } catch (error: unknown) {
      console.error('Self delivery error:', error);
      toast.error(`Gagal mengubah status: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  };

  const handleSelfDeliveryStatusUpdate = async (orderId: string, newStatus: string) => {
    try {
      const { error } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: orderId,
        p_to_status: newStatus,
        p_reason: 'Pembaruan pengiriman oleh merchant',
      } as never);

      if (error) throw error;
      
      toast.success('Status pengiriman diperbarui');
      setDetailDialogOpen(false);
      refetch();
    } catch (error) {
      console.error('Error:', error);
      toast.error(`Gagal mengubah status: ${error instanceof Error ? error.message : 'Silakan coba lagi'}`);
    }
  };

  const handleVerifyPayment = async (orderId: string) => {
    try {
      const { error } = await supabase.rpc('merchant_verify_order_payment', {
        p_order_id: orderId,
      });

      if (error) throw error;
      
      toast.success('Pembayaran berhasil diverifikasi');
      setDetailDialogOpen(false);
      refetch();
    } catch (error) {
      console.error('Error verifying payment:', error);
      toast.error('Gagal memverifikasi pembayaran');
    }
  };

  const openRejectDialog = (order: OrderRow) => {
    setSelectedOrder(order);
    setRejectDialogOpen(true);
  };

  const handleReject = () => {
    if (selectedOrder && rejectReason.trim()) {
      handleUpdateStatus(selectedOrder.id, 'CANCELED', rejectReason);
    }
  };


  const getStatusBadge = (status: string) => {
    const statusVariants: Record<string, 'info' | 'warning' | 'pending' | 'success' | 'destructive' | 'outline'> = {
      NEW: 'info',
      PENDING_PAYMENT: 'warning',
      PENDING_CONFIRMATION: 'warning',
      PROCESSED: 'pending',
      READY: 'info',
      ASSIGNED: 'warning',
      COURIER_ASSIGNED: 'warning',
      COURIER_ACCEPTED: 'info',
      PICKED_UP: 'info',
      ON_DELIVERY: 'info',
      DELIVERING: 'info',
      SENT: 'info',
      DELIVERED: 'warning',
      DONE: 'success',
      CANCELED: 'destructive',
      CANCELLED: 'destructive',
      REJECTED: 'destructive',
      REJECTED_BY_BUYER: 'destructive',
      REFUNDED: 'outline',
    };
    return <Badge variant={statusVariants[status] || 'outline'}>{orderStatusLabel(status)}</Badge>;
  };

  const getPaymentBadge = (status: string | null, method: string | null) => {
    if (method === 'COD') {
      return <Badge variant="pending">COD</Badge>;
    }
    const statusMap: Record<string, { label: string; variant: 'default' | 'success' | 'warning' | 'destructive' }> = {
      'PAID': { label: 'Lunas', variant: 'success' },
      'PENDING': { label: 'Menunggu', variant: 'warning' },
      'UNPAID': { label: 'Belum Bayar', variant: 'destructive' },
    };
    const config = statusMap[status || 'UNPAID'] || { label: status || '-', variant: 'outline' as const };
    return <Badge variant={config.variant}>{config.label}</Badge>;
  };

  const columns = [
    {
      key: 'id',
      header: 'ID Pesanan',
      render: (item: OrderRow) => (
        <span className="font-mono text-sm">#{item.id.slice(0, 8).toUpperCase()}</span>
      ),
    },
    {
      key: 'customer',
      header: 'Pelanggan',
      render: (item: OrderRow) => (
        <div>
          <p className="font-medium">{item.delivery_name || 'Pelanggan'}</p>
          <p className="text-xs text-muted-foreground">{item.delivery_phone || '-'}</p>
        </div>
      ),
    },
    {
      key: 'total',
      header: 'Total',
      render: (item: OrderRow) => formatPrice(item.total),
    },
    {
      key: 'payment',
      header: 'Pembayaran',
      render: (item: OrderRow) => getPaymentBadge(item.payment_status, item.payment_method),
    },
    {
      key: 'delivery_type',
      header: 'Pengiriman',
      render: (item: OrderRow) => (
        <Badge variant="outline">
          {item.delivery_type === 'PICKUP'
            ? 'Ambil Sendiri'
            : item.delivery_type === 'EXPEDITION'
              ? 'Ekspedisi'
              : item.is_self_delivery ? 'Antar Sendiri' : 'Diantar'}
        </Badge>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (item: OrderRow) => getStatusBadge(item.status),
    },
    {
      key: 'created_at',
      header: 'Tanggal',
      render: (item: OrderRow) => new Date(item.created_at).toLocaleDateString('id-ID'),
    },
    {
      key: 'actions',
      header: '',
      render: (item: OrderRow) => (
        <div className="flex items-center justify-end gap-1">
          <Button
            variant="ghost"
            size="icon"
            aria-label={`Lihat detail pesanan ${item.id.slice(0, 8).toUpperCase()}`}
            title="Lihat detail"
            onClick={() => viewOrderDetail(item)}
          >
            <Eye className="h-4 w-4" />
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" aria-label="Aksi pesanan" title="Aksi pesanan">
                <MoreHorizontal className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => viewOrderDetail(item)}>
              Lihat Detail
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setChatOrder(item)}>
              <MessageSquare className="h-4 w-4 mr-2" />
              Pesan sesuai pesanan
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => openPrintDialog(item)}>
              <Printer className="h-4 w-4 mr-2" />
              Cetak Struk
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            {/* Payment verification for PENDING_PAYMENT orders */}
            {item.status === 'PENDING_PAYMENT' && item.payment_proof_url && (
              <DropdownMenuItem onClick={() => handleVerifyPayment(item.id)}>
                <Check className="h-4 w-4 mr-2" />
                Verifikasi Pembayaran
              </DropdownMenuItem>
            )}
            {item.status === 'PENDING_PAYMENT' && !item.payment_proof_url && (
              <DropdownMenuItem disabled className="text-muted-foreground">
                <Clock className="h-4 w-4 mr-2" />
                Menunggu Bukti Bayar
              </DropdownMenuItem>
            )}
            {(item.status === 'NEW' || item.status === 'PENDING_CONFIRMATION') && (
              <>
                <DropdownMenuItem onClick={() => handleUpdateStatus(item.id, 'PROCESSED')}>
                  <Check className="h-4 w-4 mr-2" />
                  Terima Pesanan
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => openRejectDialog(item)} className="text-destructive">
                  <X className="h-4 w-4 mr-2" />
                  Tolak Pesanan
                </DropdownMenuItem>
              </>
            )}
            {item.status === 'PROCESSED' && (
              item.delivery_type === 'PICKUP' ? (
                <DropdownMenuItem onClick={() => handleUpdateStatus(item.id, 'READY')}>
                  <Package className="h-4 w-4 mr-2" />
                  Siap Diambil
                </DropdownMenuItem>
              ) : (
                <DropdownMenuItem onClick={() => viewOrderDetail(item)}>
                   <Truck className="h-4 w-4 mr-2" />
                   Kirim Pesanan
                 </DropdownMenuItem>
              )
            )}
            {item.status === 'DELIVERING' && (
              <DropdownMenuItem onClick={() => handleSelfDeliveryStatusUpdate(item.id, 'DELIVERED')}>
                <CheckCircle2 className="h-4 w-4 mr-2" />
                Sudah Sampai
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
          </DropdownMenu>
        </div>
      ),
    },
  ];

  const filters = [
    {
      key: 'status',
      label: 'Status',
      options: MERCHANT_ORDER_STATUS_FILTER_OPTIONS,
    },
    {
      key: 'delivery_type',
      label: 'Pengiriman',
      options: [
        { value: 'PICKUP', label: 'Ambil Sendiri' },
        { value: 'INTERNAL', label: 'Diantar' },
        { value: 'EXPEDITION', label: 'Ekspedisi' },
      ],
    },
  ];

  const stats = {
    new: orders.filter(o => o.status === 'NEW').length,
    processed: orders.filter(o => o.status === 'PROCESSED').length,
    sent: orders.filter(o => ['SENT', 'DELIVERING'].includes(o.status)).length,
    done: orders.filter(o => o.status === 'DONE').length,
    total_revenue: orders.filter(o => o.status === 'DONE').reduce((acc, curr) => acc + curr.subtotal, 0)
  };

  const ordersInDateRange = useMemo(() => {
    if (!dateFrom && !dateTo) return orders;
    const start = dateFrom ? new Date(`${dateFrom}T00:00:00`).getTime() : null;
    const end = dateTo ? new Date(`${dateTo}T23:59:59.999`).getTime() : null;
    return orders.filter((order) => {
      const createdAt = new Date(order.created_at).getTime();
      return (!start || createdAt >= start) && (!end || createdAt <= end);
    });
  }, [dateFrom, dateTo, orders]);

  const handleExport = (data: OrderRow[]) => {
    const headers = ['ID Pesanan', 'Pelanggan', 'Telepon', 'Total', 'Status', 'Pembayaran', 'Metode', 'Tipe Pengiriman', 'Tanggal'];
    const csvData = data.map(order => [
      `#${order.id.slice(0, 8).toUpperCase()}`,
      order.delivery_name || '-',
      order.delivery_phone || '-',
      order.total,
      order.status,
      order.payment_status || '-',
      order.payment_method || '-',
      order.delivery_type,
      new Date(order.created_at).toLocaleDateString('id-ID')
    ]);

    const csvContent = [headers, ...csvData].map(e => e.join(",")).join("\n");
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement("a");
    const url = URL.createObjectURL(blob);
    link.setAttribute("href", url);
    link.setAttribute("download", `pesanan-merchant-${new Date().toISOString().slice(0,10)}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  return (
    <MerchantOrdersShell embedded={embedded}>
      {/* Compact operational summary */}
      <p className="mb-2 text-xs text-muted-foreground" role="status">
        Ringkasan berikut dihitung dari {orders.length} pesanan yang dimuat, bukan total sepanjang waktu.
        {hasMore ? ' Masih ada pesanan lama; gunakan “Muat pesanan lama” untuk memperluas cakupan angka.' : ''}
      </p>
      <div className="mb-3 flex flex-wrap items-center gap-x-5 gap-y-1 border-b border-border/70 pb-3 text-xs">
        <div><span className="text-muted-foreground">Baru</span> <strong className="ml-1 text-info">{stats.new}</strong></div>
        <div><span className="text-muted-foreground">Diproses</span> <strong className="ml-1 text-warning-foreground">{stats.processed}</strong></div>
        <div><span className="text-muted-foreground">Selesai</span> <strong className="ml-1 text-success">{stats.done}</strong></div>
        <div className="text-muted-foreground">
          Pendapatan produk dari pesanan dimuat <strong className="ml-1 text-foreground">{formatPrice(stats.total_revenue)}</strong>
        </div>
      </div>

      <div className="flex items-center justify-between gap-2 mb-4">
        <div className="flex items-center gap-2">
          <Receipt className="h-5 w-5 text-primary" />
          <span className="text-muted-foreground text-sm">
            {orders.length} pesanan dimuat
          </span>
          {orders.filter(o => o.status === 'NEW').length > 0 && (
            <Badge variant="info">{orders.filter(o => o.status === 'NEW').length} baru</Badge>
          )}
        </div>
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1.5 text-xs">
            <Wifi className={`h-3.5 w-3.5 ${isConnected ? 'text-primary animate-pulse' : 'text-muted-foreground'}`} />
            <span className={isConnected ? 'text-primary' : 'text-muted-foreground'}>
              {isConnected ? 'Live' : 'Offline'}
            </span>
          </div>
          <Button variant="outline" size="sm" onClick={refetch}>
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>
      </div>

      <div className="mb-3">
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs text-muted-foreground">
            {dateFrom || dateTo ? `Tanggal: ${dateFrom || 'awal'} – ${dateTo || 'sekarang'}` : 'Semua tanggal'}
          </p>
          <Button variant="outline" size="sm" className="h-8" onClick={() => setDateFilterOpen((open) => !open)}>
            <CalendarDays className="mr-2 h-4 w-4" />
            {dateFilterOpen ? 'Tutup tanggal' : 'Tanggal'}
          </Button>
        </div>
        {dateFilterOpen && (
          <div className="mt-2 flex flex-wrap items-end gap-2 rounded-lg border border-border bg-card p-2">
            <label className="space-y-1">
              <span className="text-[11px] font-medium text-muted-foreground">Dari</span>
              <Input type="date" value={dateFrom} max={dateTo || undefined} onChange={(event) => setDateFrom(event.target.value)} className="h-8 w-[150px]" aria-label="Tanggal mulai" />
            </label>
            <label className="space-y-1">
              <span className="text-[11px] font-medium text-muted-foreground">Sampai</span>
              <Input type="date" value={dateTo} min={dateFrom || undefined} onChange={(event) => setDateTo(event.target.value)} className="h-8 w-[150px]" aria-label="Tanggal akhir" />
            </label>
            {(dateFrom || dateTo) && (
              <Button variant="ghost" size="sm" className="h-8" onClick={() => { setDateFrom(''); setDateTo(''); }}>Reset</Button>
            )}
          </div>
        )}
      </div>

      <DataTable
        data={ordersInDateRange}
        columns={columns}
        searchKeys={['id', 'delivery_name', 'delivery_phone']}
        searchPlaceholder="Cari ID, nama, atau telepon..."
        filters={filters}
        loading={loading}
        onExport={handleExport}
        emptyMessage="Belum ada pesanan"
      />
      {hasMore && !dateFrom && !dateTo && (
        <div className="mt-4 flex justify-center">
          <Button variant="outline" size="sm" onClick={() => void loadMore()} disabled={loadingMore}>
            {loadingMore ? 'Memuat pesanan lama...' : 'Muat pesanan lama'}
          </Button>
        </div>
      )}

      {/* Order Detail Dialog */}
      <Dialog open={detailDialogOpen} onOpenChange={setDetailDialogOpen}>
        <DialogContent className="max-w-md max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              Detail Pesanan #{selectedOrder?.id.slice(0, 8).toUpperCase()}
            </DialogTitle>
          </DialogHeader>
          {selectedOrder && (
            <div className="space-y-4 py-4">
              {/* Status Row */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="text-sm text-muted-foreground">Status:</span>
                  {getStatusBadge(selectedOrder.status)}
                </div>
                <div className="flex items-center gap-2">
                  <CreditCard className="h-4 w-4 text-muted-foreground" />
                  {getPaymentBadge(selectedOrder.payment_status, selectedOrder.payment_method)}
                </div>
              </div>

              {/* Customer Info */}
              <div className="bg-secondary/50 rounded-lg p-4 space-y-2">
                <p className="text-sm font-medium mb-2">Informasi Pengiriman</p>
                <div className="flex items-center gap-2 text-sm">
                  <User className="h-4 w-4 text-muted-foreground" />
                  <span>{selectedOrder.delivery_name || 'Pelanggan'}</span>
                </div>
                {selectedOrder.delivery_phone && (
                  <div className="flex items-center gap-2 text-sm">
                    <Phone className="h-4 w-4 text-muted-foreground" />
                    <a href={`https://wa.me/${selectedOrder.delivery_phone.replace(/\D/g, '')}`} 
                       className="text-primary hover:underline"
                       target="_blank" rel="noopener noreferrer">
                      {selectedOrder.delivery_phone}
                    </a>
                  </div>
                )}
                {selectedOrder.delivery_address && (
                  <div className="flex items-start gap-2 text-sm">
                    <MapPin className="h-4 w-4 text-muted-foreground mt-0.5" />
                    <span>{selectedOrder.delivery_address}</span>
                  </div>
                )}
                <Badge variant="outline" className="mt-2">
                  {selectedOrder.delivery_type === 'PICKUP'
                    ? 'Ambil Sendiri'
                    : selectedOrder.delivery_type === 'EXPEDITION'
                      ? 'Ekspedisi'
                      : selectedOrder.is_self_delivery ? 'Antar Sendiri' : 'Diantar Kurir'}
                </Badge>
              </div>

              {/* Items */}
              <div className="space-y-2">
                <p className="text-sm font-medium">Item Pesanan</p>
                {orderItemsQuery.isLoading || (orderItemsQuery.isError && orderItemsQuery.isFetching) ? (
                  <MerchantCardLoading label="Memuat item pesanan..." />
                ) : orderItemsQuery.isError ? (
                  <MerchantCardError message={orderItemsErrorMessage} onRetry={() => void orderItemsQuery.refetch()} />
                ) : orderItems.length === 0 ? (
                  <div role="status" className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
                    Belum ada item pesanan yang dapat ditampilkan.
                  </div>
                ) : (
                  <div className="border border-border rounded-lg divide-y divide-border">
                    {orderItems.map((item) => (
                      <div key={item.id} className="p-3 flex justify-between">
                        <div>
                          <p className="font-medium text-sm">{item.product_name}</p>
                          <p className="text-xs text-muted-foreground">
                            {item.quantity} x {formatPrice(item.product_price)}
                          </p>
                        </div>
                        <p className="font-medium text-sm">{formatPrice(item.subtotal)}</p>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              {/* Notes */}
              {selectedOrder.notes && (
                <div className="text-sm bg-muted/50 rounded-lg p-3">
                  <div className="flex items-center gap-2 mb-1">
                    <MessageSquare className="h-4 w-4 text-muted-foreground" />
                    <span className="text-muted-foreground">Catatan:</span>
                  </div>
                  <p>{selectedOrder.notes}</p>
                </div>
              )}
              <Button
                variant="outline"
                className="w-full justify-start"
                disabled={!selectedOrder.buyer_id}
                onClick={() => selectedOrder.buyer_id && setChatOrder(selectedOrder)}
              >
                <MessageSquare className="h-4 w-4 mr-2" />
                Buka pesan pesanan
                <span className="ml-auto text-xs text-muted-foreground">#{selectedOrder.id.slice(0, 8).toUpperCase()}</span>
              </Button>
              {/* Payment Proof */}
              {selectedOrder.payment_proof_url && (
                <div className="space-y-2">
                  <div className="flex items-center gap-2">
                    <ImageIcon className="h-4 w-4 text-muted-foreground" />
                    <span className="text-sm font-medium">Bukti Pembayaran</span>
                  </div>
                  {paymentProofQuery.isLoading || (paymentProofQuery.isError && paymentProofQuery.isFetching) ? (
                    <MerchantCardLoading label="Memuat bukti pembayaran..." />
                  ) : paymentProofQuery.isError ? (
                    <MerchantCardError
                      message="Bukti pembayaran gagal dimuat. Periksa koneksi lalu coba lagi."
                      onRetry={() => void paymentProofQuery.refetch()}
                    />
                  ) : paymentProofQuery.data ? (
                    <>
                      <div className="relative rounded-lg overflow-hidden border border-border">
                        <img
                          src={paymentProofQuery.data ?? ''}
                          alt="Bukti pembayaran"
                          className="w-full max-h-64 object-contain bg-secondary/30 cursor-pointer"
                          onClick={() => paymentProofQuery.data && window.open(paymentProofQuery.data, '_blank')}
                        />
                      </div>
                      <p className="text-xs text-muted-foreground text-center">Klik gambar untuk memperbesar</p>
                    </>
                  ) : (
                    <div role="status" className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
                      Bukti pembayaran belum tersedia.
                    </div>
                  )}
                </div>
              )}

              {/* Cost Breakdown */}
              <div className="border-t border-border pt-4 space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Subtotal Produk</span>
                  <span>{formatPrice(selectedOrder.subtotal)}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Ongkos Kirim</span>
                  <span>{formatPrice(selectedOrder.shipping_cost)}</span>
                </div>
                {(selectedOrder.cod_service_fee ?? 0) > 0 && (
                  <div className="flex justify-between text-sm">
                    <span className="text-muted-foreground">Biaya COD</span>
                    <span>{formatPrice(selectedOrder.cod_service_fee || 0)}</span>
                  </div>
                )}
                <div className="flex justify-between font-bold text-lg pt-1 border-t border-dashed border-border">
                  <span>Total Pembeli</span>
                  <span className="text-primary">{formatPrice(selectedOrder.total)}</span>
                </div>
                <div className="flex justify-between text-xs text-muted-foreground bg-muted/50 p-2 rounded">
                  <span>Pendapatan Anda (produk saja)</span>
                  <span className="font-medium text-foreground">{formatPrice(selectedOrder.subtotal)}</span>
                </div>
              </div>

              {/* Actions */}
              {/* Payment Verification for PENDING_PAYMENT */}
              {selectedOrder.status === 'PENDING_PAYMENT' && (
                <div className="space-y-3">
                  {selectedOrder.payment_proof_url ? (
                    <Button 
                      className="w-full"
                      onClick={() => handleVerifyPayment(selectedOrder.id)}
                    >
                      <Check className="h-4 w-4 mr-2" />
                      Verifikasi Pembayaran
                    </Button>
                  ) : (
                    <div className="w-full bg-muted/50 rounded-lg p-3 text-center">
                      <p className="text-xs text-muted-foreground">
                        Menunggu pembeli mengunggah bukti pembayaran
                      </p>
                    </div>
                  )}
                  <Button 
                    variant="destructive"
                    className="w-full"
                    onClick={() => {
                      setDetailDialogOpen(false);
                      openRejectDialog(selectedOrder);
                    }}
                  >
                    <X className="h-4 w-4 mr-2" />
                    Tolak Pesanan
                  </Button>
                </div>
              )}
              {/* Actions for NEW / PENDING_CONFIRMATION */}
              {(selectedOrder.status === 'NEW' || selectedOrder.status === 'PENDING_CONFIRMATION') && (
                <div className="flex gap-2">
                  <Button 
                    className="flex-1"
                    onClick={() => handleUpdateStatus(selectedOrder.id, 'PROCESSED')}
                  >
                    <Check className="h-4 w-4 mr-2" />
                    Terima Pesanan
                  </Button>
                  <Button 
                    variant="destructive"
                    onClick={() => {
                      setDetailDialogOpen(false);
                      openRejectDialog(selectedOrder);
                    }}
                  >
                    <X className="h-4 w-4 mr-2" />
                    Tolak
                  </Button>
                </div>
              )}
              {/* PROCESSED: show delivery choice for INTERNAL, or handoff for EXPEDITION/PICKUP */}
              {selectedOrder.status === 'PROCESSED' && (
                selectedOrder.delivery_type === 'PICKUP' ? (
                  <Button 
                    className="w-full"
                    onClick={() => handleUpdateStatus(selectedOrder.id, 'SENT')}
                  >
                    <Package className="h-4 w-4 mr-2" />
                    Siap Diambil
                  </Button>
                ) : selectedOrder.delivery_type === 'EXPEDITION' ? (
                  <div className="w-full space-y-3 rounded-lg border border-border bg-muted/20 p-3">
                    <p className="text-sm font-semibold">Data Ekspedisi</p>
                    <Input value={expeditionName} onChange={(event) => setExpeditionName(event.target.value)} placeholder="Nama ekspedisi, contoh JNE" maxLength={100} />
                    <Input value={trackingNumber} onChange={(event) => setTrackingNumber(event.target.value)} placeholder="Nomor resi" maxLength={120} />
                    <Button className="w-full" onClick={handleExpeditionHandoff} disabled={!expeditionName.trim() || !trackingNumber.trim()}>
                      <Package className="h-4 w-4 mr-2" />
                      Tandai Diserahkan ke Ekspedisi
                    </Button>
                  </div>
                ) : (
                  <div className="space-y-3">
                    <p className="text-sm font-semibold">Pilih Metode Pengiriman:</p>
                    <Button 
                      className="w-full justify-start gap-3 h-auto py-4"
                      variant="outline"
                      onClick={() => handleSelfDelivery(selectedOrder.id)}
                    >
                      <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                        <User className="h-5 w-5 text-primary" />
                      </div>
                      <div className="text-left">
                        <p className="font-bold text-sm">Antar Sendiri</p>
                        <p className="text-xs text-muted-foreground">Anda mengirim langsung ke pembeli</p>
                      </div>
                    </Button>
                    <Button 
                      className="w-full justify-start gap-3 h-auto py-4"
                      variant="outline"
                      onClick={() => openAssignDialog(selectedOrder)}
                    >
                      <div className="h-10 w-10 rounded-full bg-info/10 flex items-center justify-center flex-shrink-0">
                        <Truck className="h-5 w-5 text-info" />
                      </div>
                      <div className="text-left">
                        <p className="font-bold text-sm">Kurir Desa</p>
                        <p className="text-xs text-muted-foreground">Dikirim oleh kurir desa</p>
                      </div>
                    </Button>
                  </div>
                )
              )}
              {/* DELIVERING (self-delivery): location tracker + mark as delivered */}
              {selectedOrder.status === 'DELIVERING' && merchantId && (
                <>
                  <MerchantDeliveryTracker
                    orderId={selectedOrder.id}
                    merchantId={merchantId}
                  />
                  <Button 
                    className="w-full"
                    onClick={() => handleSelfDeliveryStatusUpdate(selectedOrder.id, 'DELIVERED')}
                  >
                    <CheckCircle2 className="h-4 w-4 mr-2" />
                    Sudah Sampai
                  </Button>
                </>
              )}
              {selectedOrder.status === 'DELIVERED' && (
                <div className="w-full bg-muted/50 rounded-lg p-3 text-center">
                  <p className="text-xs text-muted-foreground">
                    Menunggu pembeli menyelesaikan pesanan (otomatis selesai dalam 24 jam)
                  </p>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {chatOrder && chatOrder.buyer_id && (
        <OrderChat
          orderId={chatOrder.id}
          otherUserId={chatOrder.buyer_id}
          otherUserName={chatOrder.delivery_name || 'Pembeli'}
          chatType="buyer_merchant"
          isOpen={!!chatOrder}
          onClose={() => setChatOrder(null)}
        />
      )}
      {selectedOrder && (
        <CourierAssignDialog
          open={courierAssignDialogOpen}
          onOpenChange={setCourierAssignDialogOpen}
          orderId={selectedOrder.id}
          merchantLat={selectedOrder.merchants?.location_lat ?? undefined}
          merchantLng={selectedOrder.merchants?.location_lng ?? undefined}
          deliveryLat={selectedOrder.delivery_lat ?? undefined}
          deliveryLng={selectedOrder.delivery_lng ?? undefined}
          onSuccess={refetch}
        />
      )}

      {/* Reject Dialog */}
      <Dialog open={rejectDialogOpen} onOpenChange={setRejectDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Tolak Pesanan</DialogTitle>
          </DialogHeader>
          <div className="py-4">
            <p className="text-sm text-muted-foreground mb-3">
              Berikan alasan penolakan pesanan #{selectedOrder?.id.slice(0, 8).toUpperCase()}
            </p>
            <Textarea
              placeholder="Alasan penolakan..."
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value)}
              rows={3}
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejectDialogOpen(false)}>
              Batal
            </Button>
            <Button variant="destructive" onClick={handleReject} disabled={!rejectReason.trim()}>
              Tolak Pesanan
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Print Invoice Dialog */}
      <Dialog open={printDialogOpen} onOpenChange={setPrintDialogOpen}>
        <DialogContent className="grid max-h-[calc(100dvh-1rem)] w-[calc(100%-1rem)] grid-rows-[auto_minmax(0,1fr)_auto] gap-0 overflow-hidden p-4 sm:max-h-[calc(100dvh-2rem)] sm:w-full sm:p-6">
          <DialogHeader>
            <DialogTitle>Cetak Struk</DialogTitle>
          </DialogHeader>
          <div className="min-h-0 overflow-y-auto overscroll-contain py-3 sm:py-4">
            {selectedOrder && (
              orderItemsQuery.isLoading || (orderItemsQuery.isError && orderItemsQuery.isFetching) ? (
                <MerchantCardLoading label="Memuat item untuk struk..." />
              ) : orderItemsQuery.isError ? (
                <MerchantCardError message={orderItemsErrorMessage} onRetry={() => void orderItemsQuery.refetch()} />
              ) : orderItems.length === 0 ? (
                <div role="status" className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
                  Struk belum dapat dicetak karena item pesanan tidak tersedia.
                </div>
              ) : (
                <div className="flex justify-center">
                  <OrderInvoice
                    ref={invoiceRef}
                    order={{
                      id: selectedOrder.id,
                      delivery_name: selectedOrder.delivery_name,
                      delivery_phone: selectedOrder.delivery_phone,
                      delivery_address: selectedOrder.delivery_address,
                      delivery_type: selectedOrder.delivery_type,
                      subtotal: selectedOrder.subtotal,
                      shipping_cost: selectedOrder.shipping_cost,
                      total: selectedOrder.total,
                      payment_method: selectedOrder.payment_method,
                      created_at: selectedOrder.created_at,
                      notes: selectedOrder.notes,
                    }}
                    items={orderItems}
                    merchant={{ name: merchantName, address: null, phone: null }}
                  />
                </div>
              )
            )}
          </div>
          <DialogFooter className="flex-col-reverse gap-2 border-t border-border/70 pt-3 sm:flex-row sm:justify-end sm:pt-4">
            <Button className="w-full sm:w-auto" variant="outline" onClick={() => setPrintDialogOpen(false)}>
              Tutup
            </Button>
            <Button className="w-full sm:w-auto" onClick={handlePrint} disabled={orderItemsQuery.isLoading || (orderItemsQuery.isError && orderItemsQuery.isFetching) || orderItemsQuery.isError || orderItems.length === 0}>
              <Printer className="h-4 w-4 mr-2" />
              Cetak
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MerchantOrdersShell>
  );
}

export default function MerchantOrdersPage() {
  return <MerchantOrdersWorkspace />;
}
