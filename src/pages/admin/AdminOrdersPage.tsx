import { useCallback, useEffect, useState, useMemo } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { 
  Receipt, 
  Eye, 
  MoreHorizontal, 
  Package, 
  Truck, 
  AlertCircle, 
  TrendingUp, 
  Clock, 
  CheckCircle2,
  Check,
  BarChart3
} from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { DataTable } from '@/components/admin/DataTable';
import { CourierAssignDialog } from '@/components/admin/CourierAssignDialog';
import { OrderDetailsDialog } from '@/components/order/OrderDetailsDialog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { StatsCard } from '@/components/admin/StatsCard';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { formatPrice, cn } from '@/lib/utils';

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
  payment_proof_url: string | null;
  delivery_type: string;
  delivery_name: string | null;
  delivery_phone: string | null;
  delivery_address: string | null;
  delivery_lat: number | null;
  delivery_lng: number | null;
  subtotal: number;
  shipping_cost: number;
  total: number;
  cod_service_fee: number | null;
  notes: string | null;
  cancellation_reason: string | null;
  created_at: string;
  courier_id: string | null;
  merchant_id: string | null;
  merchants: { name: string; location_lat: number | null; location_lng: number | null } | null;
}

const ADMIN_CANCELLABLE_ORDER_STATUSES = [
  'NEW',
  'PENDING_PAYMENT',
  'PENDING_CONFIRMATION',
  'CONFIRMED',
  'PROCESSED',
  'READY',
  'ASSIGNED',
  'COURIER_ACCEPTED',
  'PICKED_UP',
  'DELIVERING',
  'SENT',
] as const;

const ADMIN_CANCEL_REASONS = [
  'Permintaan pelanggan',
  'Stok produk habis',
  'Pembayaran tidak terverifikasi',
  'Merchant tidak dapat memproses',
  'Duplikasi pesanan',
  'Lainnya',
] as const;

export default function AdminOrdersPage() {
  const queryClient = useQueryClient();
  const [selectedOrder, setSelectedOrder] = useState<OrderRow | null>(null);
  const [orderItems, setOrderItems] = useState<OrderItem[]>([]);
  const [detailDialogOpen, setDetailDialogOpen] = useState(false);
  const [courierAssignDialogOpen, setCourierAssignDialogOpen] = useState(false);
  const [pendingCancelOrder, setPendingCancelOrder] = useState<OrderRow | null>(null);
  const [cancelSubmitting, setCancelSubmitting] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [customCancelReason, setCustomCancelReason] = useState('');

  const { data: orders = [], isLoading: loading, error: ordersError, refetch: refetchOrders } = useQuery<OrderRow[]>({
    queryKey: ['admin-orders-list'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select('*, merchants(name, location_lat, location_lng)')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data || [];
    },
    staleTime: 30_000,
  });

  const invalidate = useCallback(() => queryClient.invalidateQueries({ queryKey: ['admin-orders-list'] }), [queryClient]);
  const fetchOrders = invalidate;

  // Realtime subscription — invalidate query saat ada perubahan order
  useEffect(() => {
    const channel = supabase
      .channel('admin-orders-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, () => {
        invalidate();
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [invalidate]);

  const viewOrderDetail = async (order: OrderRow) => {
    setSelectedOrder(order);
    
    const { data: items } = await supabase
      .from('order_items')
      .select('*')
      .eq('order_id', order.id);

    setOrderItems(items || []);
    setDetailDialogOpen(true);
  };

  const updateOrderStatus = async (orderId: string, newStatus: string, reason?: string): Promise<boolean> => {
    try {
      const { error } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: orderId,
        p_to_status: newStatus,
        p_reason: newStatus === 'CANCELED' ? reason ?? 'Dibatalkan oleh admin' : 'Pembaruan status oleh admin',
        p_is_self_delivery: null,
      } as never);

      if (error) throw error;
      
      toast.success('Status pesanan diperbarui');
      setDetailDialogOpen(false);
      await fetchOrders();
      return true;
    } catch (error) {
      console.error('Admin order status update failed:', error);
      toast.error(`Gagal mengubah status: ${error instanceof Error ? error.message : 'Silakan coba lagi'}`);
      return false;
    }
  };

  const confirmAdminCancellation = async () => {
    if (!pendingCancelOrder) return;

    const finalReason = cancelReason === 'Lainnya' ? customCancelReason.trim() : cancelReason;
    if (!finalReason) {
      toast.error('Pilih atau isi alasan pembatalan terlebih dahulu');
      return;
    }

    setCancelSubmitting(true);
    const success = await updateOrderStatus(pendingCancelOrder.id, 'CANCELED', finalReason);
    setCancelSubmitting(false);
    if (success) {
      setPendingCancelOrder(null);
      setCancelReason('');
      setCustomCancelReason('');
    }
  };

  const requestAdminCancellation = (order: OrderRow) => {
    setPendingCancelOrder(order);
    setCancelReason('');
    setCustomCancelReason('');
  };

  const verifyPayment = async (orderId: string) => {
    try {
      const { error } = await supabase
        .from('orders')
        .update({ 
          payment_status: 'PAID',
          payment_paid_at: new Date().toISOString(),
          status: 'PROCESSED',
          confirmed_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        })
        .eq('id', orderId);

      if (error) throw error;
      
      toast.success('Pembayaran berhasil diverifikasi');
      setDetailDialogOpen(false);
      fetchOrders();
    } catch (error) {
      toast.error('Gagal memverifikasi pembayaran');
    }
  };

  const openAssignDialog = (order: OrderRow) => {
    setSelectedOrder(order);
    setCourierAssignDialogOpen(true);
  };

  const handleExport = (data: OrderRow[]) => {
    if (data.length === 0) return;
    
    const headers = ['ID', 'Merchant', 'Pelanggan', 'Total', 'Status', 'Pembayaran', 'Tanggal'];
    const csvData = data.map(o => [
      o.id,
      o.merchants?.name || '-',
      o.delivery_name || '-',
      o.total,
      o.status,
      o.payment_status || '-',
      new Date(o.created_at).toLocaleString('id-ID')
    ]);
    
    const csvContent = [
      headers.join(','),
      ...csvData.map(row => row.join(','))
    ].join('\n');
    
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    link.setAttribute('href', url);
    link.setAttribute('download', `pesanan-umkm-${new Date().toISOString().split('T')[0]}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    toast.success('Data pesanan berhasil diekspor');
  };

  const getStatusBadge = (status: string) => {
    const statusMap: Record<string, { label: string; variant: 'default' | 'info' | 'warning' | 'success' | 'destructive' | 'pending' }> = {
      'NEW': { label: 'Baru', variant: 'info' },
      'PENDING_PAYMENT': { label: 'Menunggu Bayar', variant: 'warning' },
      'PENDING_CONFIRMATION': { label: 'Menunggu Konfirmasi', variant: 'warning' },
      'CONFIRMED': { label: 'Dikonfirmasi', variant: 'info' },
      'PROCESSED': { label: 'Diproses', variant: 'warning' },
      'ASSIGNED': { label: 'Kurir Ditugaskan', variant: 'pending' },
      'PICKED_UP': { label: 'Diambil Kurir', variant: 'pending' },
      'DELIVERING': { label: 'Diantar Penjual', variant: 'pending' },
      'SENT': { label: 'Dikirim', variant: 'pending' },
      'DELIVERED': { label: 'Sampai', variant: 'warning' },
      'DONE': { label: 'Selesai', variant: 'success' },
      'CANCELLED': { label: 'Dibatalkan', variant: 'destructive' },
      'CANCELED': { label: 'Dibatalkan', variant: 'destructive' },
    };
    
    const config = statusMap[status] || { label: status, variant: 'default' as const };
    return <Badge variant={config.variant}>{config.label}</Badge>;
  };

  const getPaymentBadge = (paymentStatus: string | null) => {
    const statusMap: Record<string, { label: string; variant: 'warning' | 'info' | 'success' | 'destructive' | 'pending' }> = {
      'UNPAID': { label: 'Belum Bayar', variant: 'warning' },
      'PENDING': { label: 'Menunggu', variant: 'info' },
      'PAID': { label: 'Lunas', variant: 'success' },
      'EXPIRED': { label: 'Expired', variant: 'destructive' },
      'COD': { label: 'COD', variant: 'pending' },
    };
    
    const config = statusMap[paymentStatus || 'UNPAID'] || { label: paymentStatus || '-', variant: 'warning' as const };
    return <Badge variant={config.variant}>{config.label}</Badge>;
  };

  const stats = useMemo(() => {
    const totalRevenue = orders
      .filter(o => o.status === 'DONE' && o.payment_status === 'PAID')
      .reduce((acc, curr) => acc + curr.subtotal, 0);
    
    return {
      total: orders.length,
      new: orders.filter(o => o.status === 'NEW').length,
      processing: orders.filter(o => ['CONFIRMED', 'PROCESSED', 'ASSIGNED', 'PICKED_UP', 'DELIVERING', 'SENT', 'DELIVERED'].includes(o.status)).length,
      done: orders.filter(o => o.status === 'DONE').length,
      revenue: totalRevenue
    };
  }, [orders]);

  const cancellationReport = useMemo(() => {
    const cancelledOrders = orders.filter((order) => ['CANCELED', 'CANCELLED'].includes(order.status));
    const reasonCounts = new Map<string, number>();
    const merchantCounts = new Map<string, number>();

    cancelledOrders.forEach((order) => {
      const reason = order.cancellation_reason?.trim() || 'Alasan tidak dicatat';
      const merchant = order.merchants?.name || 'Merchant tidak diketahui';
      reasonCounts.set(reason, (reasonCounts.get(reason) || 0) + 1);
      merchantCounts.set(merchant, (merchantCounts.get(merchant) || 0) + 1);
    });

    const reasons = [...reasonCounts.entries()]
      .map(([label, count]) => ({ label, count, percentage: cancelledOrders.length ? Math.round((count / cancelledOrders.length) * 100) : 0 }))
      .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
    const merchants = [...merchantCounts.entries()]
      .map(([label, count]) => ({ label, count }))
      .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))
      .slice(0, 5);

    return {
      total: cancelledOrders.length,
      rate: orders.length ? Math.round((cancelledOrders.length / orders.length) * 100) : 0,
      reasons,
      merchants,
    };
  }, [orders]);

  const columns = [
    {
      key: 'id',
      header: 'ID Pesanan',
      render: (item: OrderRow) => (
        <span className="font-mono text-xs">#{item.id.slice(0, 8).toUpperCase()}</span>
      ),
    },
    {
      key: 'merchant',
      header: 'Merchant',
      render: (item: OrderRow) => (
        <span className="font-medium text-sm">{item.merchants?.name || '-'}</span>
      ),
    },
    {
      key: 'customer',
      header: 'Pelanggan',
      render: (item: OrderRow) => (
        <div>
          <p className="font-medium text-sm">{item.delivery_name || 'Pelanggan'}</p>
          <p className="text-[10px] text-muted-foreground">{item.delivery_phone || '-'}</p>
        </div>
      ),
    },
    {
      key: 'total',
      header: 'Total',
      render: (item: OrderRow) => (
        <span className="font-semibold">{formatPrice(item.total)}</span>
      ),
    },
    {
      key: 'payment_status',
      header: 'Pembayaran',
      render: (item: OrderRow) => getPaymentBadge(item.payment_status),
    },
    {
      key: 'status',
      header: 'Status',
      render: (item: OrderRow) => getStatusBadge(item.status),
    },
    {
      key: 'created_at',
      header: 'Tanggal',
      render: (item: OrderRow) => (
        <span className="text-xs text-muted-foreground">
          {new Date(item.created_at).toLocaleDateString('id-ID', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
          })}
        </span>
      ),
    },
    {
      key: 'actions',
      header: '',
      render: (item: OrderRow) => (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="h-8 w-8">
              <MoreHorizontal className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            <DropdownMenuItem onClick={() => viewOrderDetail(item)}>
              <Eye className="h-4 w-4 mr-2" />
              Lihat Detail
            </DropdownMenuItem>
            {item.delivery_type === 'INTERNAL' && !item.courier_id && (
              <DropdownMenuItem onClick={() => openAssignDialog(item)}>
                <Truck className="h-4 w-4 mr-2" />
                Tugaskan Kurir
              </DropdownMenuItem>
            )}
            <DropdownMenuSeparator />
            {/* Payment verification */}
            {item.status === 'PENDING_PAYMENT' && item.payment_proof_url && (
              <DropdownMenuItem onClick={() => verifyPayment(item.id)}>
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
                <DropdownMenuItem onClick={() => updateOrderStatus(item.id, 'PROCESSED')}>
                  <Package className="h-4 w-4 mr-2" />
                  Terima & Proses
                </DropdownMenuItem>
              </>
            )}
            {item.status === 'PROCESSED' && (
              <DropdownMenuItem onClick={() => updateOrderStatus(item.id, 'SENT')}>
                <Truck className="h-4 w-4 mr-2" />
                Kirim
              </DropdownMenuItem>
            )}
            {ADMIN_CANCELLABLE_ORDER_STATUSES.includes(item.status as typeof ADMIN_CANCELLABLE_ORDER_STATUSES[number]) && (
              <DropdownMenuItem 
                onClick={() => requestAdminCancellation(item)}
                className="text-destructive"
              >
                <AlertCircle className="h-4 w-4 mr-2" />
                Batalkan Pesanan
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      ),
    },
  ];

  const filters = [
    {
      key: 'status',
      label: 'Status',
      options: [
        { value: 'NEW', label: 'Baru' },
        { value: 'PENDING_PAYMENT', label: 'Menunggu Bayar' },
        { value: 'PENDING_CONFIRMATION', label: 'Menunggu Konfirmasi' },
        { value: 'CONFIRMED', label: 'Dikonfirmasi' },
        { value: 'PROCESSED', label: 'Diproses' },
        { value: 'ASSIGNED', label: 'Kurir Ditugaskan' },
        { value: 'PICKED_UP', label: 'Diambil Kurir' },
        { value: 'DELIVERING', label: 'Diantar Penjual' },
        { value: 'SENT', label: 'Dikirim' },
        { value: 'DELIVERED', label: 'Sampai' },
        { value: 'DONE', label: 'Selesai' },
        { value: 'CANCELLED', label: 'Dibatalkan' },
      ],
    },
    {
      key: 'payment_status',
      label: 'Pembayaran',
      options: [
        { value: 'UNPAID', label: 'Belum Bayar' },
        { value: 'PENDING', label: 'Menunggu' },
        { value: 'PAID', label: 'Lunas' },
        { value: 'COD', label: 'COD' },
      ],
    },
    {
      key: 'delivery_type',
      label: 'Pengiriman',
      options: [
        { value: 'PICKUP', label: 'Ambil Sendiri' },
        { value: 'INTERNAL', label: 'Diantar' },
      ],
    },
  ];

  return (
    <AdminLayout title="Manajemen Pesanan" subtitle="Pantau dan kelola semua transaksi masuk">
      <div className="space-y-6">
        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatsCard
            title="Total Pesanan"
            value={stats.total}
            icon={<Receipt className="h-5 w-5" />}
            description="Semua pesanan masuk"
          />
          <StatsCard
            title="Pesanan Baru"
            value={stats.new}
            icon={<Clock className="h-5 w-5" />}
            description="Perlu segera diproses"
            className={cn(stats.new > 0 && "border-primary/50 bg-primary/5")}
          />
          <StatsCard
            title="Sedang Diproses"
            value={stats.processing}
            icon={<Package className="h-5 w-5" />}
            description="Dalam pengiriman/proses"
          />
          <StatsCard
            title="Pendapatan Produk"
            value={formatPrice(stats.revenue)}
            icon={<TrendingUp className="h-5 w-5" />}
            description="Subtotal produk (tanpa ongkir)"
          />
        </div>

        <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
          <div className="rounded-xl border border-border bg-card p-5 xl:col-span-2">
            <div className="mb-4 flex items-start justify-between gap-3">
              <div>
                <h2 className="flex items-center gap-2 text-base font-bold">
                  <BarChart3 className="h-5 w-5 text-primary" />
                  Analisis Alasan Pembatalan
                </h2>
                <p className="mt-1 text-sm text-muted-foreground">Gunakan data ini untuk mengevaluasi kendala operasional merchant.</p>
              </div>
              <div className="shrink-0 text-right">
                <p className="text-2xl font-bold text-destructive">{cancellationReport.total}</p>
                <p className="text-xs text-muted-foreground">{cancellationReport.rate}% dari semua pesanan</p>
              </div>
            </div>

            {cancellationReport.reasons.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground">
                Belum ada pesanan dibatalkan pada data ini.
              </p>
            ) : (
              <div className="space-y-3">
                {cancellationReport.reasons.map((reason) => (
                  <div key={reason.label}>
                    <div className="mb-1 flex items-center justify-between gap-3 text-sm">
                      <span className="min-w-0 truncate font-medium">{reason.label}</span>
                      <span className="shrink-0 text-muted-foreground">{reason.count} pesanan · {reason.percentage}%</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-muted" aria-label={`${reason.label}: ${reason.percentage}%`}>
                      <div className="h-full rounded-full bg-destructive transition-all" style={{ width: `${reason.percentage}%` }} />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="rounded-xl border border-border bg-card p-5">
            <h2 className="text-base font-bold">Merchant dengan Pembatalan Terbanyak</h2>
            <p className="mt-1 text-sm text-muted-foreground">Prioritaskan evaluasi pada merchant berikut.</p>
            {cancellationReport.merchants.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">Belum ada data merchant.</p>
            ) : (
              <ol className="mt-4 space-y-3">
                {cancellationReport.merchants.map((merchant, index) => (
                  <li key={merchant.label} className="flex items-center justify-between gap-3 text-sm">
                    <div className="flex min-w-0 items-center gap-3">
                      <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-destructive/10 text-xs font-bold text-destructive">{index + 1}</span>
                      <span className="truncate font-medium">{merchant.label}</span>
                    </div>
                    <span className="shrink-0 font-semibold">{merchant.count}</span>
                  </li>
                ))}
              </ol>
            )}
          </div>
        </div>

        <div className="bg-card border border-border rounded-xl p-6">
          <DataTable
            data={orders}
            columns={columns}
            searchKeys={['id', 'delivery_name', 'delivery_phone']}
            searchPlaceholder="Cari ID, pelanggan, atau telepon..."
            filters={filters}
            loading={loading}
            error={ordersError ? 'Gagal memuat daftar pesanan. Periksa koneksi dan permission database.' : null}
            onRetry={() => void refetchOrders()}
            onExport={handleExport}
            emptyMessage="Belum ada pesanan yang sesuai"
          />
        </div>
      </div>

      <OrderDetailsDialog
        open={detailDialogOpen}
        onOpenChange={setDetailDialogOpen}
        order={selectedOrder}
        orderItems={orderItems}
        onUpdateStatus={updateOrderStatus}
        onOpenAssignCourier={openAssignDialog}
        getStatusBadge={getStatusBadge}
        getPaymentBadge={getPaymentBadge}
      />

      {selectedOrder && (
        <CourierAssignDialog
          open={courierAssignDialogOpen}
          onOpenChange={setCourierAssignDialogOpen}
          orderId={selectedOrder.id}
          merchantLat={selectedOrder.merchants?.location_lat ? Number(selectedOrder.merchants.location_lat) : undefined}
          merchantLng={selectedOrder.merchants?.location_lng ? Number(selectedOrder.merchants.location_lng) : undefined}
          deliveryLat={selectedOrder.delivery_lat ? Number(selectedOrder.delivery_lat) : undefined}
          deliveryLng={selectedOrder.delivery_lng ? Number(selectedOrder.delivery_lng) : undefined}
          onSuccess={() => {
            fetchOrders();
            setDetailDialogOpen(false);
          }}
        />
      )}

      <AlertDialog
        open={!!pendingCancelOrder}
        onOpenChange={(open) => {
          if (!open && !cancelSubmitting) setPendingCancelOrder(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2 text-destructive">
              <AlertCircle className="h-5 w-5" />
              Batalkan pesanan ini?
            </AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-3 text-left">
                <p>
                  Anda akan membatalkan pesanan <strong>#{pendingCancelOrder?.id.slice(0, 8).toUpperCase()}</strong>.
                  Tindakan ini akan mengubah status pesanan menjadi <strong>Dibatalkan</strong> dan tidak dapat dipulihkan dari halaman ini.
                </p>
                <div className="rounded-lg border border-destructive/20 bg-destructive/5 p-3 text-sm text-foreground">
                  <p><span className="text-muted-foreground">Pelanggan:</span> {pendingCancelOrder?.delivery_name || 'Pelanggan'}</p>
                  <p><span className="text-muted-foreground">Total:</span> {pendingCancelOrder ? formatPrice(pendingCancelOrder.total) : '-'}</p>
                  <p><span className="text-muted-foreground">Status saat ini:</span> {pendingCancelOrder?.status || '-'}</p>
                </div>
                <div className="space-y-2">
                  <label htmlFor="admin-cancel-reason" className="text-sm font-medium text-foreground">
                    Alasan pembatalan <span className="text-destructive">*</span>
                  </label>
                  <select
                    id="admin-cancel-reason"
                    value={cancelReason}
                    onChange={(event) => setCancelReason(event.target.value)}
                    disabled={cancelSubmitting}
                    className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                  >
                    <option value="">Pilih alasan pembatalan</option>
                    {ADMIN_CANCEL_REASONS.map((reason) => (
                      <option key={reason} value={reason}>{reason}</option>
                    ))}
                  </select>
                  {cancelReason === 'Lainnya' && (
                    <Textarea
                      value={customCancelReason}
                      onChange={(event) => setCustomCancelReason(event.target.value)}
                      disabled={cancelSubmitting}
                      placeholder="Tuliskan alasan pembatalan..."
                      maxLength={500}
                      rows={3}
                      aria-label="Alasan pembatalan lainnya"
                    />
                  )}
                </div>
                <p className="text-xs text-muted-foreground">
                  Pastikan pembatalan sudah dikonfirmasi secara operasional sebelum melanjutkan.
                </p>
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={cancelSubmitting}>Kembali</AlertDialogCancel>
            <AlertDialogAction
              onClick={(event) => {
                event.preventDefault();
                void confirmAdminCancellation();
              }}
              disabled={cancelSubmitting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {cancelSubmitting ? 'Membatalkan...' : 'Ya, Batalkan Pesanan'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AdminLayout>
  );
}
