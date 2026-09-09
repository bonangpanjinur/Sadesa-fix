import { useCallback, useEffect, useState } from 'react';
import { Package, Clock, Truck, CheckCircle, XCircle, MessageCircle, Phone, CreditCard, ImageIcon, Users } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';
import { format } from 'date-fns';
import { id } from 'date-fns/locale';
import { useNavigate } from 'react-router-dom';

interface Order {
  id: string;
  status: string;
  total: number;
  subtotal: number;
  shipping_cost: number;
  delivery_type: string;
  delivery_name: string | null;
  delivery_phone: string | null;
  delivery_address: string | null;
  payment_method: string | null;
  payment_status: string | null;
  notes: string | null;
  created_at: string;
  confirmation_deadline: string | null;
  payment_proof_url: string | null;
}

interface CourierOption {
  id: string;
  name: string;
  phone: string;
  vehicle_type: string;
  is_available: boolean;
  distance_km?: number;
}

function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number) {
  const r = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

interface OrderStatusManagerProps {
  merchantId: string;
}

const STATUS_CONFIG: Record<string, { label: string; color: string; icon: React.ComponentType<{ className?: string }> }> = {
  'PENDING_CONFIRMATION': { label: 'Konfirmasi', color: 'bg-warning', icon: Clock },
  'PENDING_PAYMENT': { label: 'Menunggu Bayar', color: 'bg-warning', icon: CreditCard },
  'NEW': { label: 'Baru', color: 'bg-info', icon: Package },
  'PROCESSED': { label: 'Diproses', color: 'bg-primary', icon: Package },
  'SENT': { label: 'Dikirim', color: 'bg-warning', icon: Truck },
  'DELIVERED': { label: 'Sampai', color: 'bg-info', icon: CheckCircle },
  'DONE': { label: 'Selesai', color: 'bg-success', icon: CheckCircle },
  'CANCELED': { label: 'Batal', color: 'bg-destructive', icon: XCircle },
  'REJECTED_BY_BUYER': { label: 'Ditolak Pembeli', color: 'bg-destructive', icon: XCircle },
};

export function OrderStatusManager({ merchantId }: OrderStatusManagerProps) {
  const navigate = useNavigate();
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedOrder, setSelectedOrder] = useState<Order | null>(null);
  const [showRejectDialog, setShowRejectDialog] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [updating, setUpdating] = useState(false);
  const [activeTab, setActiveTab] = useState('pending');
  
  // Courier assignment state
  const [showCourierDialog, setShowCourierDialog] = useState(false);
  const [courierOrderId, setCourierOrderId] = useState<string | null>(null);
  const [deliveryMethod, setDeliveryMethod] = useState<'self' | 'village' | null>(null);
  const [availableCouriers, setAvailableCouriers] = useState<CourierOption[]>([]);
  const [selectedCourierId, setSelectedCourierId] = useState<string>('');
  const [loadingCouriers, setLoadingCouriers] = useState(false);

  const fetchOrders = useCallback(async () => {
    try {
      const { data, error } = await supabase
        .from('orders')
        .select('*')
        .eq('merchant_id', merchantId)
        .order('created_at', { ascending: false })
        .limit(50);

      if (error) throw error;
      setOrders(data || []);
    } catch (error) {
      console.error('Error fetching orders:', error);
    } finally {
      setLoading(false);
    }
  }, [merchantId]);

  useEffect(() => {
    fetchOrders();
  }, [fetchOrders]);

  const updateOrderStatus = async (orderId: string, newStatus: string, courierId?: string | null) => {
    setUpdating(true);
    try {
      const { error } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: orderId,
        p_to_status: newStatus,
        p_reason: courierId ? `Kurir ditugaskan: ${courierId}` : null,
      } as never);

      if (error) throw error;

      setOrders(prev => prev.map(o => 
        o.id === orderId ? { ...o, status: newStatus } : o
      ));
      toast.success('Status pesanan diperbarui');
    } catch (error) {
      toast.error('Gagal memperbarui status');
    } finally {
      setUpdating(false);
    }
  };

  const handleSendOrder = (orderId: string) => {
    setCourierOrderId(orderId);
    setDeliveryMethod(null);
    setSelectedCourierId('');
    setShowCourierDialog(true);
  };

  const fetchAvailableCouriers = async () => {
    setLoadingCouriers(true);
    try {
      // Get merchant's village_id
      const { data: merchantData } = await supabase
        .from('merchants')
        .select('village_id')
        .eq('id', merchantId)
        .maybeSingle();

      if (merchantData?.village_id) {
        const { data: couriers } = await supabase
          .from('couriers')
          .select('id, name, phone, vehicle_type, is_available, current_lat, current_lng, last_location_update')
          .eq('village_id', merchantData.village_id)
          .eq('status', 'ACTIVE')
          .eq('registration_status', 'APPROVED')
          .eq('is_available', true);

        const { data: merchantLocation } = await supabase.from('merchants').select('location_lat, location_lng').eq('id', merchantId).maybeSingle();
        const lat = Number(merchantLocation?.location_lat);
        const lng = Number(merchantLocation?.location_lng);
        setAvailableCouriers((couriers || []).map(courier => ({
          ...courier,
          distance_km: Number.isFinite(lat) && Number.isFinite(lng) && courier.current_lat && courier.current_lng
            ? distanceKm(lat, lng, Number(courier.current_lat), Number(courier.current_lng))
            : undefined,
        })).sort((a, b) => (a.distance_km ?? Number.MAX_SAFE_INTEGER) - (b.distance_km ?? Number.MAX_SAFE_INTEGER)));
      } else {
        // No village, fetch all active couriers
        const { data: couriers } = await supabase
          .from('couriers')
          .select('id, name, phone, vehicle_type, is_available, current_lat, current_lng, last_location_update')
          .eq('status', 'ACTIVE')
          .eq('registration_status', 'APPROVED')
          .eq('is_available', true);

        setAvailableCouriers(couriers || []);
      }
    } catch (error) {
      console.error('Error fetching couriers:', error);
    } finally {
      setLoadingCouriers(false);
    }
  };

  const handleConfirmSend = async () => {
    if (!courierOrderId) return;
    
    if (deliveryMethod === 'self') {
      setUpdating(true);
      try {
        const { error } = await supabase.rpc('merchant_transition_order' as never, {
          p_order_id: courierOrderId,
          p_to_status: 'DELIVERING',
          p_reason: 'Merchant memilih antar sendiri',
        } as never);

        if (error) throw error;
        setOrders(prev => prev.map(o => 
          o.id === courierOrderId ? { ...o, status: 'DELIVERING' } : o
        ));
        toast.success('Pesanan siap diantar sendiri');
      } catch (error) {
        toast.error(error instanceof Error ? error.message : 'Gagal mengubah status pengiriman');
      } finally {
        setUpdating(false);
      }
    } else if (deliveryMethod === 'village' && selectedCourierId) {
      setUpdating(true);
      try {
        const { error } = await supabase.rpc('create_delivery_offer' as never, {
          p_order_id: courierOrderId,
          p_courier_id: selectedCourierId,
        } as never);
        if (error) throw error;
        setOrders(prev => prev.map(o => o.id === courierOrderId ? { ...o, status: 'ASSIGNED' } : o));
        toast.success('Tawaran pesanan dikirim ke kurir');
      } catch (error) {
        toast.error(error instanceof Error ? error.message : 'Gagal menawarkan pesanan ke kurir');
      } finally {
        setUpdating(false);
      }
    }
    
    setShowCourierDialog(false);
    setCourierOrderId(null);
    setDeliveryMethod(null);
    setSelectedCourierId('');
  };

  const verifyPayment = async (orderId: string) => {
    setUpdating(true);
    try {
      const { error } = await supabase.rpc('merchant_verify_order_payment', {
        p_order_id: orderId,
      });

      if (error) throw error;

      setOrders(prev => prev.map(o => 
        o.id === orderId ? { ...o, status: 'PROCESSED', payment_status: 'PAID' } : o
      ));
      toast.success('Pembayaran berhasil diverifikasi');
    } catch (error) {
      toast.error('Gagal memverifikasi pembayaran');
    } finally {
      setUpdating(false);
    }
  };

  const rejectOrder = async () => {
    if (!selectedOrder) return;
    setUpdating(true);

    try {
      const { error } = await supabase.rpc('merchant_transition_order' as never, {
        p_order_id: selectedOrder.id,
        p_to_status: 'CANCELED',
        p_reason: rejectReason ? `Dibatalkan pedagang: ${rejectReason}` : 'Dibatalkan oleh pedagang',
      } as never);

      if (error) throw error;

      setOrders(prev => prev.map(o => 
        o.id === selectedOrder.id ? { ...o, status: 'CANCELED' } : o
      ));
      toast.success('Pesanan dibatalkan');
      setShowRejectDialog(false);
      setRejectReason('');
      setSelectedOrder(null);
    } catch (error) {
      toast.error('Gagal membatalkan pesanan');
    } finally {
      setUpdating(false);
    }
  };

  const openWhatsApp = (phone: string, orderId: string) => {
    const message = encodeURIComponent(
      `Halo, ini dari toko kami. Pesanan #${orderId.slice(0, 8).toUpperCase()} Anda sedang kami proses. Ada yang bisa kami bantu?`
    );
    const formattedPhone = phone.startsWith('0') ? '62' + phone.slice(1) : phone;
    window.open(`https://wa.me/${formattedPhone}?text=${message}`, '_blank');
  };

  const filterOrders = (status: string) => {
    switch (status) {
      case 'pending':
        return orders.filter(o => ['PENDING_CONFIRMATION', 'NEW', 'PENDING_PAYMENT'].includes(o.status));
      case 'processing':
        return orders.filter(o => o.status === 'PROCESSED');
      case 'shipping':
        return orders.filter(o => ['SENT', 'DELIVERED'].includes(o.status));
      case 'completed':
        return orders.filter(o => ['DONE', 'CANCELED', 'REJECTED_BY_BUYER'].includes(o.status));
      default:
        return orders;
    }
  };

  const getNextStatus = (currentStatus: string): string | null => {
    const flow: Record<string, string> = {
      'PENDING_CONFIRMATION': 'PROCESSED',
      'NEW': 'PROCESSED',
      'PROCESSED': 'SENT',
    };
    return flow[currentStatus] || null;
  };

  const getNextStatusLabel = (currentStatus: string): string => {
    const labels: Record<string, string> = {
      'PENDING_CONFIRMATION': 'Terima & Proses',
      'NEW': 'Proses Pesanan',
      'PROCESSED': 'Kirim Pesanan',
    };
    return labels[currentStatus] || '';
  };

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Kelola Pesanan</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="animate-pulse space-y-4">
            {[1, 2, 3].map(i => (
              <div key={i} className="h-24 bg-muted rounded" />
            ))}
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Package className="h-5 w-5" />
            Kelola Pesanan
          </CardTitle>
        </CardHeader>
        <CardContent>
          <Tabs value={activeTab} onValueChange={setActiveTab}>
            <TabsList className="grid w-full grid-cols-4 mb-4">
              <TabsTrigger value="pending" className="relative">
                Baru
                {filterOrders('pending').length > 0 && (
                  <Badge className="absolute -top-2 -right-2 h-5 w-5 p-0 flex items-center justify-center text-xs">
                    {filterOrders('pending').length}
                  </Badge>
                )}
              </TabsTrigger>
              <TabsTrigger value="processing">Diproses</TabsTrigger>
              <TabsTrigger value="shipping">Dikirim</TabsTrigger>
              <TabsTrigger value="completed">Selesai</TabsTrigger>
            </TabsList>

            {['pending', 'processing', 'shipping', 'completed'].map((tab) => (
              <TabsContent key={tab} value={tab} className="space-y-3">
                {filterOrders(tab).length === 0 ? (
                  <p className="text-center text-muted-foreground py-8">
                    Tidak ada pesanan
                  </p>
                ) : (
                  filterOrders(tab).map((order) => {
                    const config = STATUS_CONFIG[order.status] || STATUS_CONFIG['NEW'];
                    const StatusIcon = config.icon;
                    const nextStatus = getNextStatus(order.status);

                    return (
                      <div 
                        key={order.id}
                        className="border rounded-lg p-4 space-y-3"
                      >
                        <div className="flex items-start justify-between">
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="font-mono text-sm font-medium">
                                #{order.id.slice(0, 8).toUpperCase()}
                              </span>
                              <Badge className={`${config.color} text-white`}>
                                <StatusIcon className="h-3 w-3 mr-1" />
                                {config.label}
                              </Badge>
                              {order.payment_method === 'COD' && (
                                <Badge variant="outline" className="border-warning text-warning">
                                  COD
                                </Badge>
                              )}
                            </div>
                            <p className="text-xs text-muted-foreground mt-1">
                              {format(new Date(order.created_at), 'dd MMM yyyy, HH:mm', { locale: id })}
                            </p>
                          </div>
                          <p className="font-bold text-lg">{formatPrice(order.total)}</p>
                        </div>

                        {order.delivery_name && (
                          <div className="bg-muted/50 rounded-lg p-3 text-sm">
                            <p className="font-medium">{order.delivery_name}</p>
                            {order.delivery_phone && (
                              <p className="text-muted-foreground">{order.delivery_phone}</p>
                            )}
                            {order.delivery_address && (
                              <p className="text-muted-foreground text-xs mt-1">
                                {order.delivery_address}
                              </p>
                            )}
                            {order.notes && (
                              <p className="text-xs mt-2 italic">
                                Catatan: {order.notes}
                              </p>
                            )}
                            {order.payment_proof_url && (
                              <div className="mt-2">
                                <p className="text-xs font-medium mb-1">Bukti Pembayaran:</p>
                                <img 
                                  src={order.payment_proof_url} 
                                  alt="Bukti pembayaran" 
                                  className="w-full max-h-40 object-contain rounded border border-border cursor-pointer"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    window.open(order.payment_proof_url!, '_blank');
                                  }}
                                />
                              </div>
                            )}
                          </div>
                        )}

                        {order.status === 'PENDING_CONFIRMATION' && order.confirmation_deadline && (
                          <div className="bg-warning/10 border border-warning/30 rounded-lg p-2 text-xs text-warning">
                            <Clock className="h-3 w-3 inline mr-1" />
                            Konfirmasi sebelum: {format(new Date(order.confirmation_deadline), 'HH:mm', { locale: id })}
                          </div>
                        )}

                        <div className="flex items-center gap-2 pt-2">
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => navigate(`/merchant/chat?orderId=${order.id}`)}
                          >
                            <MessageCircle className="h-4 w-4 mr-1" />
                            Pesan
                          </Button>
                          {order.delivery_phone && (
                            <>
                              <Button
                                size="sm"
                                variant="outline"
                                onClick={() => openWhatsApp(order.delivery_phone!, order.id)}
                              >
                                <MessageCircle className="h-4 w-4 mr-1" />
                                WhatsApp
                              </Button>
                              <Button
                                size="sm"
                                variant="outline"
                                onClick={() => window.open(`tel:${order.delivery_phone}`, '_self')}
                              >
                                <Phone className="h-4 w-4" />
                              </Button>
                            </>
                          )}

                          <div className="flex-1" />

                          {!['DONE', 'CANCELED', 'REJECTED_BY_BUYER'].includes(order.status) && (
                            <>
                              <Button
                                size="sm"
                                variant="ghost"
                                className="text-destructive hover:text-destructive"
                                onClick={() => {
                                  setSelectedOrder(order);
                                  setShowRejectDialog(true);
                                }}
                              >
                                Batalkan
                              </Button>
                              
                              {/* Payment verification button */}
                              {order.status === 'PENDING_PAYMENT' && order.payment_proof_url && (
                                <Button
                                  size="sm"
                                  onClick={() => verifyPayment(order.id)}
                                  disabled={updating}
                                  className="bg-primary"
                                >
                                  <CheckCircle className="h-4 w-4 mr-1" />
                                  Verifikasi Bayar
                                </Button>
                              )}

                              {order.status === 'PENDING_PAYMENT' && !order.payment_proof_url && (
                                <Badge variant="outline" className="text-xs">
                                  Menunggu Bukti Bayar
                                </Badge>
                              )}
                              
                              {order.status !== 'PENDING_PAYMENT' && nextStatus && (
                                order.status === 'PROCESSED' ? (
                                  <Button
                                    size="sm"
                                    onClick={() => handleSendOrder(order.id)}
                                    disabled={updating}
                                  >
                                    <Truck className="h-4 w-4 mr-1" />
                                    Kirim Pesanan
                                  </Button>
                                ) : (
                                  <Button
                                    size="sm"
                                    onClick={() => updateOrderStatus(order.id, nextStatus)}
                                    disabled={updating}
                                  >
                                    {getNextStatusLabel(order.status)}
                                  </Button>
                                )
                              )}
                            </>
                          )}
                        </div>
                      </div>
                    );
                  })
                )}
              </TabsContent>
            ))}
          </Tabs>
        </CardContent>
      </Card>

      {/* Reject Dialog */}
      <Dialog open={showRejectDialog} onOpenChange={setShowRejectDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Batalkan Pesanan</DialogTitle>
            <DialogDescription>Pesanan akan dibatalkan dan alasan akan dicatat dalam riwayat order.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Apakah Anda yakin ingin membatalkan pesanan #{selectedOrder?.id.slice(0, 8).toUpperCase()}?
            </p>
            <Textarea
              placeholder="Alasan pembatalan (opsional)"
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value)}
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowRejectDialog(false)}>
              Batal
            </Button>
            <Button 
              variant="destructive" 
              onClick={rejectOrder}
              disabled={updating}
            >
              Ya, Batalkan Pesanan
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Courier Assignment Dialog */}
      <Dialog open={showCourierDialog} onOpenChange={setShowCourierDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Truck className="h-5 w-5" />
              Pilih Metode Pengiriman
            </DialogTitle>
            <DialogDescription>Pilih antar sendiri atau kirimkan tawaran kepada kurir desa yang tersedia.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Pilih cara pengiriman untuk pesanan #{courierOrderId?.slice(0, 8).toUpperCase()}
            </p>
            
            {/* Self delivery option */}
            <button
              type="button"
              onClick={() => setDeliveryMethod('self')}
              className={`w-full p-4 rounded-lg border-2 text-left transition ${
                deliveryMethod === 'self' 
                  ? 'border-primary bg-primary/5' 
                  : 'border-border hover:border-muted-foreground/30'
              }`}
            >
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                  <Truck className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <p className="font-medium text-foreground">Antar Sendiri (Kurir Toko)</p>
                  <p className="text-xs text-muted-foreground">Anda atau kurir toko yang mengantar pesanan</p>
                </div>
              </div>
            </button>
            
            {/* Village courier option */}
            <button
              type="button"
              onClick={() => {
                setDeliveryMethod('village');
                fetchAvailableCouriers();
              }}
              className={`w-full p-4 rounded-lg border-2 text-left transition ${
                deliveryMethod === 'village' 
                  ? 'border-primary bg-primary/5' 
                  : 'border-border hover:border-muted-foreground/30'
              }`}
            >
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-info/10 flex items-center justify-center">
                  <Users className="h-5 w-5 text-info" />
                </div>
                <div>
                  <p className="font-medium text-foreground">Tugaskan ke Kurir Desa</p>
                  <p className="text-xs text-muted-foreground">Pilih kurir desa yang tersedia untuk mengantar</p>
                </div>
              </div>
            </button>

            {/* Courier selection dropdown */}
            {deliveryMethod === 'village' && (
              <div className="space-y-2 pl-2 border-l-2 border-primary/30 ml-5">
                <Label className="text-sm">Pilih Kurir</Label>
                {loadingCouriers ? (
                  <p className="text-xs text-muted-foreground">Memuat kurir...</p>
                ) : availableCouriers.length === 0 ? (
                  <p className="text-xs text-destructive">Tidak ada kurir yang tersedia di desa ini</p>
                ) : (
                  <Select value={selectedCourierId} onValueChange={setSelectedCourierId}>
                    <SelectTrigger>
                      <SelectValue placeholder="Pilih kurir..." />
                    </SelectTrigger>
                    <SelectContent>
                      {availableCouriers.map((courier) => (
                        <SelectItem key={courier.id} value={courier.id}>
                          <div className="flex items-center gap-2">
                            <span>{courier.name}</span>
                            <span className="text-xs text-muted-foreground">({courier.vehicle_type})</span>
                            <span className="text-xs text-success">● Online</span>
                            {courier.distance_km !== undefined && <span className="text-xs text-primary">{courier.distance_km.toFixed(1)} km</span>}
                          </div>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowCourierDialog(false)}>
              Batal
            </Button>
            <Button
              onClick={handleConfirmSend}
              disabled={
                updating || 
                !deliveryMethod || 
                (deliveryMethod === 'village' && !selectedCourierId)
              }
            >
              <Truck className="h-4 w-4 mr-1" />
              Kirim Pesanan
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
