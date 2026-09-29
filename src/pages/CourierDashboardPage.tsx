import { useEffect, useState, useRef } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate, Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import { 
  Package, 
  MapPin, 
  Clock, 
  Phone, 
  Navigation,
  CheckCircle,
  Truck,
  RefreshCw,
  User,
  LogOut,
  AlertCircle,
  Wallet,
  Camera,
  History,
  Banknote,
  PiggyBank,
  Bike,
  Star
} from 'lucide-react';
import { CourierLayout } from '@/components/courier/CourierLayout';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import { CourierLocationUpdater } from '@/components/CourierLocationUpdater';
import { NavigationButton } from '@/components/courier/NavigationButton';
import { DeliveryOfferCard, type DeliveryOfferCardData } from '@/components/courier/DeliveryOfferCard';
import { ProofOfDelivery } from '@/components/courier/ProofOfDelivery';
import { OrderBatchingPanel } from '@/components/courier/OrderBatchingPanel';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { formatDistance, calculateDistance } from '@/lib/etaCalculation';
import { formatPrice } from '@/lib/utils';
import { getRpcErrorMessage } from '@/lib/courierOrderStatus';
import { usePushNotification } from '@/hooks/usePushNotification';

interface CourierData {
  id: string;
  name: string;
  phone: string;
  is_available: boolean;
  vehicle_type: string;
  current_lat: number | null;
  current_lng: number | null;
  available_balance: number | null;
  registration_status: string;
  rejection_reason: string | null;
  rating_avg: number | null;
  rating_count: number | null;
}

interface AssignedOrder {
  id: string;
  status: string;
  delivery_name: string | null;
  delivery_phone: string | null;
  delivery_address: string | null;
  delivery_lat: number | null;
  delivery_lng: number | null;
  total: number;
  created_at: string;
  notes: string | null;
  pickup_address: string | null;
  pickup_lat: number | null;
  pickup_lng: number | null;
  shipping_cost: number;
  courier_earning_estimate: number;
  courier_platform_fee: number;
  merchants: { name: string; address: string | null } | null;
}

interface DeliveryOffer {
  id: string;
  order_id: string;
  expires_at: string;
  orders?: DeliveryOfferCardData['order'];
}

export default function CourierDashboardPage() {
  const navigate = useNavigate();
  const { user, signOut, loading: authLoading } = useAuth();
  const queryClient = useQueryClient();
  const [updatingStatus, setUpdatingStatus] = useState(false);
  const [podOrderId, setPodOrderId] = useState<string | null>(null);
  const [respondingOffer, setRespondingOffer] = useState<string | null>(null);
  const [releasingOrder, setReleasingOrder] = useState<string | null>(null);
  const [realtimeOnline, setRealtimeOnline] = useState(false);
  const { isSupported: pushSupported, permission: pushPermission, subscribe: subscribeToPush } = usePushNotification();

  // Query: profil kurir + status registrasi
  const { data: courierQueryData, isLoading: courierLoading, isError: fetchError } = useQuery<CourierData | null>({
    queryKey: ['courier-profile', user?.id],
    queryFn: async () => {
      if (!user) return null;
      const { data, error } = await supabase
        .from('couriers')
        .select('id, name, phone, is_available, vehicle_type, current_lat, current_lng, registration_status, rejection_reason, available_balance, rating_avg, rating_count')
        .eq('user_id', user.id)
        .maybeSingle();
      if (error) throw error;
      return data as CourierData | null;
    },
    enabled: !!user && !authLoading,
    staleTime: 60_000,
  });

  const courier = courierQueryData?.registration_status === 'APPROVED' ? courierQueryData : null;
  const courierStatus = courierQueryData
    ? { registration_status: courierQueryData.registration_status, rejection_reason: courierQueryData.rejection_reason }
    : null;
  const loading = courierLoading;

  const fetchCourierData = () => {
    queryClient.invalidateQueries({ queryKey: ['courier-profile', user?.id] });
    queryClient.invalidateQueries({ queryKey: ['courier-assigned-orders', courier?.id] });
  };

  // Query: only count ride offers targeted to this courier. Counting all
  // SEARCHING rides makes the dashboard promise work that this courier cannot
  // accept because accept_ride requires a matching pending offer.
  const { data: rideRequestCount = 0 } = useQuery({
    queryKey: ['courier-ride-count', courier?.id],
    queryFn: async () => {
      if (!courier) return 0;
      const { count, error } = await supabase
        .from('ride_request_offers' as never)
        .select('ride_id', { count: 'exact', head: true })
        .eq('courier_id', courier.id)
        .eq('status', 'PENDING')
        .gt('expires_at', new Date().toISOString());
      if (error) throw error;
      return count || 0;
    },
    enabled: !!courier,
    staleTime: 30_000,
    refetchInterval: 30_000,
  });

  const { data: orders = [], isLoading: ordersLoading, isError: ordersError, isFetching: ordersFetching } = useQuery<AssignedOrder[]>({
    queryKey: ['courier-assigned-orders', courier?.id],
    queryFn: async () => {
      if (!courier) return [];
      const { data } = await supabase
        .from('orders')
        .select('*, pickup_address, pickup_lat, pickup_lng, shipping_cost, courier_earning_estimate, courier_platform_fee, merchants(name, address)')
        .eq('courier_id', courier.id)
        .in('status', ['COURIER_ACCEPTED', 'PICKED_UP', 'SENT', 'DELIVERING'])
        .order('created_at', { ascending: false });
      return (data || []) as AssignedOrder[];
    },
    enabled: !!courier,
    staleTime: 30_000,
  });

  const { data: deliveryOffers = [], isError: deliveryOffersError } = useQuery<DeliveryOffer[]>({
    queryKey: ['courier-delivery-offers', courier?.id],
    queryFn: async () => {
      if (!courier) return [];
      const { data, error } = await supabase.rpc('get_courier_delivery_offers' as never);
      if (error) throw error;
      return (data || []) as unknown as DeliveryOffer[];
    },
    enabled: !!courier,
    refetchInterval: 15_000,
  });

  // Real-time notification for new assigned orders
  useEffect(() => {
    if (!courier?.id) return;
    const channel = supabase
      .channel('courier-new-orders')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'delivery_assignments',
        filter: `courier_id=eq.${courier.id}`,
      }, () => {
        toast({ title: 'Tawaran pengiriman baru', description: 'Periksa detail pickup dan tujuan sebelum menerima.' });
        queryClient.invalidateQueries({ queryKey: ['courier-delivery-offers', courier.id] });
      })
      .on('postgres_changes', {
        event: 'UPDATE', schema: 'public', table: 'delivery_assignments', filter: `courier_id=eq.${courier.id}`,
      }, () => {
        queryClient.invalidateQueries({ queryKey: ['courier-delivery-offers', courier.id] });
        queryClient.invalidateQueries({ queryKey: ['courier-assigned-orders', courier.id] });
      })
      .on('postgres_changes', {
        event: 'DELETE', schema: 'public', table: 'delivery_assignments', filter: `courier_id=eq.${courier.id}`,
      }, () => queryClient.invalidateQueries({ queryKey: ['courier-delivery-offers', courier.id] }))
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'orders',
        filter: `courier_id=eq.${courier.id}`,
      }, (payload) => {
        if (payload.new && (payload.new as { status: string }).status === 'COURIER_ACCEPTED') {
          toast({ title: '🚀 Pesanan Baru!', description: 'Anda mendapat tugas pengiriman baru' });
          queryClient.invalidateQueries({ queryKey: ['courier-assigned-orders', courier.id] });
        }
      })
      .subscribe((status) => {
        const connected = status === 'SUBSCRIBED';
        setRealtimeOnline(connected);
        if (connected) {
          queryClient.invalidateQueries({ queryKey: ['courier-delivery-offers', courier.id] });
          queryClient.invalidateQueries({ queryKey: ['courier-assigned-orders', courier.id] });
        }
      });
    return () => { supabase.removeChannel(channel); };
  }, [courier?.id, queryClient]);

  const toggleAvailability = async (checked: boolean) => {
    if (!courier) return;
    setUpdatingStatus(true);

    try {
      if (checked) {
        if (!navigator.geolocation) throw new Error('Perangkat ini tidak mendukung GPS');
        await new Promise<GeolocationPosition>((resolve, reject) => {
          navigator.geolocation.getCurrentPosition(resolve, reject, {
            enableHighAccuracy: true,
            timeout: 15_000,
            maximumAge: 0,
          });
        });
      }
      const { error } = await supabase
        .from('couriers')
        .update({ is_available: checked })
        .eq('id', courier.id);

      if (error) throw error;

      queryClient.setQueryData(['courier-profile', user?.id], { ...courierQueryData, is_available: checked });
      queryClient.setQueryData(['courier-global-presence', user?.id], (current: { id: string; is_available: boolean; registration_status: string } | null | undefined) =>
        current ? { ...current, is_available: checked } : current,
      );
      if (checked && pushSupported && pushPermission !== 'denied') {
        const subscribed = await subscribeToPush();
        if (!subscribed) {
          toast({
            title: 'Notifikasi latar belum aktif',
            description: 'Izinkan notifikasi agar bunyi dan getar tetap masuk saat aplikasi tidak dibuka.',
            variant: 'destructive',
          });
        }
      }
      toast({
        title: checked ? 'Anda sekarang online' : 'Anda sekarang offline',
      });
    } catch (error) {
      console.error('Error updating availability:', error);
      toast({
        title: 'Gagal mengubah status',
        variant: 'destructive',
      });
    } finally {
      setUpdatingStatus(false);
    }
  };

  const respondToDeliveryOffer = async (assignmentId: string, accept: boolean) => {
    setRespondingOffer(assignmentId);
    try {
      const { error } = await supabase.rpc('respond_delivery_offer' as never, {
        p_assignment_id: assignmentId,
        p_accept: accept,
        p_reason: accept ? null : 'Kurir menolak tawaran',
      } as never);
      if (error) throw error;
      queryClient.invalidateQueries({ queryKey: ['courier-delivery-offers', courier?.id] });
      queryClient.invalidateQueries({ queryKey: ['courier-assigned-orders', courier?.id] });
      toast({ title: accept ? 'Pesanan diambil' : 'Tawaran ditolak', description: accept ? 'Arahkan ke toko untuk mengambil pesanan.' : undefined });
    } catch (error) {
      toast({ title: 'Tawaran tidak dapat diproses', description: getRpcErrorMessage(error), variant: 'destructive' });
    } finally {
      setRespondingOffer(null);
    }
  };

  const releaseOrder = async (orderId: string) => {
    const reason = window.prompt('Alasan melepas tugas (wajib):', 'Merchant tidak siap');
    if (!reason?.trim()) return;
    setReleasingOrder(orderId);
    try {
      const { error } = await supabase.rpc('courier_release_order' as never, { p_order_id: orderId, p_reason: reason.trim() } as never);
      if (error) throw error;
      queryClient.invalidateQueries({ queryKey: ['courier-assigned-orders', courier?.id] });
      toast({ title: 'Tugas dilepas', description: 'Pesanan dikembalikan untuk penugasan ulang.' });
    } catch (error) {
      toast({ title: 'Gagal melepas tugas', description: getRpcErrorMessage(error), variant: 'destructive' });
    } finally { setReleasingOrder(null); }
  };

  const updateOrderStatus = async (orderId: string, newStatus: string) => {
    try {
      const { error } = await supabase.rpc('courier_transition_order' as never, {
        p_order_id: orderId,
        p_to_status: newStatus,
      } as never);

      if (error) throw error;

      // Refresh orders dari query cache
      queryClient.invalidateQueries({ queryKey: ['courier-assigned-orders', courier?.id] });

      toast({ title: 'Status pesanan diperbarui' });
    } catch (error) {
      console.error('Error updating order:', error);
      toast({
        title: 'Gagal memperbarui status',
        description: getRpcErrorMessage(error),
        variant: 'destructive',
      });
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'ASSIGNED':
        return <Badge variant="secondary">Ditugaskan</Badge>;
      case 'COURIER_ACCEPTED':
        return <Badge variant="info">Menuju Toko</Badge>;
      case 'PICKED_UP':
        return <Badge variant="warning">Diambil</Badge>;
      case 'SENT':
        return <Badge variant="info">Dalam Perjalanan</Badge>;
      case 'DELIVERING':
        return <Badge variant="info">Dalam Perjalanan</Badge>;
      default:
        return <Badge variant="outline">{status}</Badge>;
    }
  };

  const getNextAction = (order: AssignedOrder) => {
    switch (order.status) {
      case 'COURIER_ACCEPTED':
        return { label: 'Ambil Pesanan', nextStatus: 'PICKED_UP', needsPOD: false };
      case 'PICKED_UP':
        return { label: 'Mulai Antar', nextStatus: 'SENT', needsPOD: false };
      case 'SENT':
        return { label: 'Selesai + Foto', nextStatus: 'DELIVERED', needsPOD: true };
      case 'DELIVERING':
        return { label: 'Selesai + Foto', nextStatus: 'DELIVERED', needsPOD: true };
      default:
        return null;
    }
  };

  const handleSignOut = async () => {
    await signOut();
    navigate('/');
  };

  if (authLoading || loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
      </div>
    );
  }

  // Fetch error - show retry instead of "Belum Terdaftar"
  if (fetchError) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center p-4">
        <div className="text-center">
          <AlertCircle className="h-12 w-12 text-destructive mx-auto mb-4" />
          <h2 className="font-bold text-lg mb-2">Gagal Memuat Data</h2>
          <p className="text-muted-foreground mb-4">
            Terjadi kesalahan saat mengambil data kurir
          </p>
          <div className="flex gap-2 justify-center">
            <Button variant="outline" onClick={() => navigate('/')}>
              Beranda
            </Button>
            <Button onClick={() => { fetchCourierData(); }}>
              <RefreshCw className="h-4 w-4 mr-1" /> Coba Lagi
            </Button>
          </div>
        </div>
      </div>
    );
  }

  // Not registered at all
  if (!courierStatus) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center p-4">
        <div className="text-center">
          <AlertCircle className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
          <h2 className="font-bold text-lg mb-2">Belum Terdaftar</h2>
          <p className="text-muted-foreground mb-4">
            Anda belum terdaftar sebagai kurir
          </p>
          <Button onClick={() => navigate('/register/courier')}>
            Daftar Sebagai Kurir
          </Button>
        </div>
      </div>
    );
  }

  // Pending verification
  if (courierStatus.registration_status === 'PENDING') {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center p-4">
        <div className="text-center max-w-sm">
          <div className="w-16 h-16 bg-warning/10 rounded-full flex items-center justify-center mx-auto mb-4">
            <Clock className="h-8 w-8 text-warning animate-pulse" />
          </div>
          <h2 className="font-bold text-lg mb-2">Menunggu Verifikasi</h2>
          <p className="text-muted-foreground mb-4">
            Pendaftaran kurir Anda sedang dalam proses review oleh admin. Kami akan memberitahu Anda setelah disetujui.
          </p>
          <Button variant="outline" onClick={() => navigate('/')}>
            Kembali ke Beranda
          </Button>
        </div>
      </div>
    );
  }

  // Rejected
  if (courierStatus.registration_status === 'REJECTED') {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center p-4">
        <div className="text-center max-w-sm">
          <div className="w-16 h-16 bg-destructive/10 rounded-full flex items-center justify-center mx-auto mb-4">
            <AlertCircle className="h-8 w-8 text-destructive" />
          </div>
          <h2 className="font-bold text-lg mb-2">Pendaftaran Ditolak</h2>
          <p className="text-muted-foreground mb-4">
            {courierStatus.rejection_reason || 'Maaf, pendaftaran kurir Anda tidak disetujui. Silakan coba mendaftar kembali.'}
          </p>
          <div className="flex gap-2 justify-center">
            <Button variant="outline" onClick={() => navigate('/')}>
              Beranda
            </Button>
            <Button onClick={() => navigate('/register/courier')}>
              Daftar Ulang
            </Button>
          </div>
        </div>
      </div>
    );
  }

  if (!courier) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center p-4">
        <div className="text-center">
          <AlertCircle className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
          <h2 className="font-bold text-lg mb-2">Terjadi Kesalahan</h2>
          <p className="text-muted-foreground mb-4">Gagal memuat data kurir</p>
          <Button onClick={() => fetchCourierData()}>Coba Lagi</Button>
        </div>
      </div>
    );
  }

  return (
    <CourierLayout title="Dashboard Kurir" subtitle="Kelola pengiriman dan perjalanan">
      <div className="space-y-6">
        {/* Courier Profile Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl p-5 border border-border"
        >
          <div className="flex items-center gap-4 mb-4">
            <div className="w-14 h-14 bg-primary/10 rounded-full flex items-center justify-center">
              <User className="h-7 w-7 text-primary" />
            </div>
            <div className="flex-1">
              <h2 className="font-bold text-lg">{courier.name}</h2>
              <p className="text-sm text-muted-foreground flex items-center gap-1">
                <Truck className="h-3.5 w-3.5" />
                {courier.vehicle_type === 'motor' ? 'Motor' : courier.vehicle_type}
              </p>
              <div className="mt-1 flex items-center gap-1.5 text-sm" aria-label={`Rating ${courier.rating_avg ?? 0} dari 5 dari ${courier.rating_count ?? 0} ulasan`}>
                <Star className="h-4 w-4 fill-amber-400 text-amber-400" />
                <span className="font-semibold text-amber-700 dark:text-amber-300">
                  {courier.rating_count ? Number(courier.rating_avg ?? 0).toFixed(1) : 'Baru'}
                </span>
                <span className="text-xs text-muted-foreground">
                  {courier.rating_count ? `${courier.rating_count} ulasan` : 'Belum ada ulasan'}
                </span>
              </div>
            </div>
            <Button variant="ghost" size="icon" onClick={handleSignOut}>
              <LogOut className="h-5 w-5 text-muted-foreground" />
            </Button>
          </div>

          {/* Online/Offline Toggle */}
          <div className={`flex items-center justify-between rounded-xl border p-4 ${courier.is_available ? 'border-status-online/20 bg-status-online/5' : 'border-border bg-secondary'}`}>
            <div className="flex items-center gap-3">
              <div className={`h-3 w-3 rounded-full ${courier.is_available ? 'bg-status-online animate-pulse' : 'bg-muted-foreground'}`} />
              <div>
                <Label className="font-medium">
                  {courier.is_available ? 'Online' : 'Offline'}
                </Label>
                <p className="text-xs text-muted-foreground">
                  {courier.is_available ? 'Siap menerima pesanan' : 'Tidak menerima pesanan'}
                </p>
              </div>
            </div>
            <Switch
              checked={courier.is_available}
              onCheckedChange={toggleAvailability}
              disabled={updatingStatus}
              className="data-[state=checked]:bg-status-online"
            />
          </div>
        </motion.div>

        {/* Balance Summary */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.08 }}
        >
          <div className="rounded-2xl bg-gradient-to-r from-primary to-brand-dark p-5 text-primary-foreground shadow-brand">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm opacity-80 flex items-center gap-1.5"><Wallet className="h-4 w-4" />Saldo Tersedia</span>
              <Link to="/courier/deposit" className="text-xs underline opacity-80 hover:opacity-100">Setor Saldo</Link>
            </div>
            <p className="text-2xl font-bold">{formatPrice(courier.available_balance || 0)}</p>
          </div>
        </motion.div>

        {/* Location Tracking */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
        >
          <CourierLocationUpdater
            courierId={courier.id}
            autoStart={courier.is_available}
            mandatory
            onTrackingError={() => {
              queryClient.setQueryData<CourierData | null>(['courier-profile', user?.id], (old) =>
                old ? { ...old, is_available: false } : old
              );
              toast({ title: 'GPS wajib aktif', description: 'Status Anda diubah offline karena lokasi tidak tersedia.', variant: 'destructive' });
            }}
            onLocationUpdate={(lat, lng) => {
              queryClient.setQueryData<CourierData | null>(['courier-profile', user?.id], (old) =>
                old ? { ...old, current_lat: lat, current_lng: lng } : old
              );
            }}
          />
        </motion.div>

        <div className="grid grid-cols-3 gap-2 sm:gap-3" aria-label="Ringkasan aktivitas kurir">
          <Card className="border-border shadow-sm">
            <CardContent className="p-3 sm:p-4">
              <p className="text-[11px] text-muted-foreground sm:text-xs">Pesanan aktif</p>
              <p className="mt-1 text-xl font-bold sm:text-2xl">{orders.length}</p>
            </CardContent>
          </Card>
          <Card className="border-border shadow-sm">
            <CardContent className="p-3 sm:p-4">
              <p className="text-[11px] text-muted-foreground sm:text-xs">Tawaran barang</p>
              <p className="mt-1 text-xl font-bold text-primary sm:text-2xl">{deliveryOffers.length}</p>
            </CardContent>
          </Card>
          <Card className="border-border shadow-sm">
            <CardContent className="p-3 sm:p-4">
              <p className="text-[11px] text-muted-foreground sm:text-xs">Permintaan ojek</p>
              <p className="mt-1 text-xl font-bold text-primary sm:text-2xl">{rideRequestCount}</p>
            </CardContent>
          </Card>
        </div>

        <Card className="border-primary/40 shadow-sm">
          <CardContent className="p-4 space-y-3">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="font-semibold">Kirim Barang Langsung</p>
                <p className="text-xs text-muted-foreground">Tawaran pickup dan pengantaran barang masuk di sini.</p>
              </div>
              <Badge>{deliveryOffers.length}</Badge>
            </div>
            {deliveryOffersError ? (
              <div className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">Tawaran belum dapat dimuat. Buka menu Pengiriman Barang untuk mencoba lagi.</div>
            ) : deliveryOffers.length > 0 ? (
              deliveryOffers.map((offer) => (
                <DeliveryOfferCard
                  key={offer.id}
                  offer={{ id: offer.id, order_id: offer.order_id, expires_at: offer.expires_at, order: offer.orders || null }}
                  busy={respondingOffer === offer.id}
                  onRespond={respondToDeliveryOffer}
                />
              ))
            ) : (
              <div className="rounded-lg bg-secondary/60 p-3 text-sm text-muted-foreground">Belum ada tawaran aktif. Status Anda harus Online agar dapat menerima tawaran baru.</div>
            )}
            <div className="flex items-center justify-between gap-3">
              <p className={`text-[11px] ${realtimeOnline ? 'text-emerald-600' : 'text-amber-600'}`}>
                {realtimeOnline ? 'Realtime tersambung' : 'Memperbarui otomatis setiap 15 detik'}
              </p>
              <Link to="/courier/deliveries"><Button size="sm" variant="outline">Buka Pengiriman Barang</Button></Link>
            </div>
          </CardContent>
        </Card>

        {/* Ojek Desa Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.12 }}
        >
          <Link
            to="/courier/rides"
            className="flex items-center justify-between rounded-xl border border-border bg-card p-4 transition hover:border-primary/40 hover:bg-secondary"
          >
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/10">
                <Bike className="h-5 w-5 text-primary" />
              </div>
              <div>
                <p className="font-medium">Ojek Desa</p>
                <p className="text-sm text-muted-foreground">
                  {rideRequestCount > 0 ? `${rideRequestCount} permintaan baru` : 'Terima perjalanan ojek'}
                </p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {rideRequestCount > 0 && (
                  <span className="flex h-5 w-5 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-foreground">
                  {rideRequestCount > 9 ? '9+' : rideRequestCount}
                </span>
              )}
              <Navigation className="h-4 w-4 text-muted-foreground" />
            </div>
          </Link>
        </motion.div>

        {/* History Link */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.14 }}
        >
          <Link
            to="/courier/history"
            className="flex items-center justify-between p-4 bg-card rounded-xl border border-border hover:bg-secondary transition"
          >
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-secondary rounded-full flex items-center justify-center">
                <History className="h-5 w-5 text-muted-foreground" />
              </div>
              <div>
                <p className="font-medium">Riwayat Pengiriman</p>
                <p className="text-sm text-muted-foreground">Lihat detail & bukti pengiriman</p>
              </div>
            </div>
            <Navigation className="h-4 w-4 text-muted-foreground" />
          </Link>
        </motion.div>

        {/* Earnings Link */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.15 }}
        >
          <Link
            to="/courier/earnings"
            className="flex items-center justify-between p-4 bg-card rounded-xl border border-border hover:bg-secondary transition"
          >
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-primary/10 rounded-full flex items-center justify-center">
                <Wallet className="h-5 w-5 text-primary" />
              </div>
              <div>
                <p className="font-medium">Pendapatan</p>
                <p className="text-sm text-muted-foreground">Lihat riwayat & statistik</p>
              </div>
            </div>
            <Navigation className="h-4 w-4 text-muted-foreground" />
          </Link>
        </motion.div>

        {/* Withdrawal Link */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.18 }}
        >
          <Link
            to="/courier/withdrawal"
            className="flex items-center justify-between p-4 bg-card rounded-xl border border-border hover:bg-secondary transition"
          >
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-secondary rounded-full flex items-center justify-center">
                <Banknote className="h-5 w-5 text-muted-foreground" />
              </div>
              <div>
                <p className="font-medium">Penarikan Saldo</p>
                <p className="text-sm text-muted-foreground">Tarik saldo ke rekening bank</p>
              </div>
            </div>
            <Navigation className="h-4 w-4 text-muted-foreground" />
          </Link>
        </motion.div>

        {/* S4-06: Multi-Order Batching Panel */}
        {courier && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.19 }}
          >
            <OrderBatchingPanel
              activeOrders={orders.map(o => ({
                id: o.id,
                order_number: o.id.slice(0, 8).toUpperCase(),
                buyer_name: o.delivery_name || 'Pembeli',
                buyer_address: o.delivery_address || '-',
                merchant_name: '-',
                total: o.total,
                status: o.status,
                created_at: o.created_at,
              }))}
              onRefresh={fetchCourierData}
            />
          </motion.div>
        )}

        {/* Orders Section */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
        >
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-bold text-lg flex items-center gap-2">
              <Package className="h-5 w-5" />
              Pesanan Aktif
            </h3>
            <Button variant="ghost" size="sm" onClick={fetchCourierData} disabled={ordersFetching} aria-label="Muat ulang pesanan aktif" title="Muat ulang pesanan aktif">
              <RefreshCw className={`h-4 w-4 ${ordersFetching ? 'animate-spin' : ''}`} />
            </Button>
          </div>

          {ordersLoading ? (
            <div className="space-y-3" aria-label="Memuat pesanan aktif">
              {[0, 1].map((item) => <div key={item} className="h-40 animate-pulse rounded-xl border border-border bg-muted/40" />)}
            </div>
          ) : ordersError ? (
            <div className="rounded-2xl border border-destructive/20 bg-destructive/5 p-6 text-center">
              <AlertCircle className="mx-auto mb-3 h-10 w-10 text-destructive" />
              <p className="font-medium">Pesanan aktif belum dapat dimuat</p>
              <p className="mt-1 text-sm text-muted-foreground">Periksa koneksi lalu coba muat ulang.</p>
              <Button className="mt-4" variant="outline" onClick={fetchCourierData}>Coba lagi</Button>
            </div>
          ) : orders.length === 0 ? (
            <div className="bg-card rounded-2xl p-8 border border-border text-center">
              <Package className="h-12 w-12 text-muted-foreground mx-auto mb-3" />
              <p className="font-medium">Belum ada pesanan aktif</p>
              <p className="mt-1 text-sm text-muted-foreground">Pesanan yang Anda terima akan muncul di sini.</p>
            </div>
          ) : (
            <div className="space-y-3">
              {orders.map((order) => {
                const action = getNextAction(order);
                const distance = courier.current_lat && courier.current_lng && order.delivery_lat && order.delivery_lng
                  ? calculateDistance(
                      { lat: courier.current_lat, lng: courier.current_lng },
                      { lat: order.delivery_lat, lng: order.delivery_lng }
                    )
                  : null;

                const handleAction = () => {
                  if (action?.needsPOD) {
                    setPodOrderId(order.id);
                  } else if (action) {
                    updateOrderStatus(order.id, action.nextStatus);
                  }
                };

                return (
                  <div
                    key={order.id}
                    className="rounded-xl border border-border bg-card p-4 shadow-sm"
                  >
                    <div className="mb-3 flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="font-medium text-sm">
                          #{order.id.slice(0, 8).toUpperCase()}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {new Date(order.created_at).toLocaleDateString('id-ID')}
                        </p>
                      </div>
                      {getStatusBadge(order.status)}
                    </div>

                    <div className="space-y-2 mb-4">
                      <div className="flex items-start gap-2 text-sm">
                        <Package className="h-4 w-4 text-primary mt-0.5" />
                        <span className="min-w-0 break-words"><b>{order.merchants?.name || 'Toko'}</b><br /><span className="text-muted-foreground">{order.pickup_address || order.merchants?.address || 'Lokasi toko belum tersedia'}</span></span>
                      </div>
                      <div className="flex items-start gap-2 text-sm">
                        <User className="h-4 w-4 text-muted-foreground mt-0.5" />
                        <span>{order.delivery_name || 'Pelanggan'}</span>
                      </div>
                      
                      {order.delivery_phone && (
                        <div className="flex items-center gap-2 text-sm">
                          <Phone className="h-4 w-4 text-muted-foreground" />
                          <a href={`tel:${order.delivery_phone}`} className="text-primary">
                            {order.delivery_phone}
                          </a>
                        </div>
                      )}

                      <div className="flex items-start gap-2 text-sm">
                        <MapPin className="h-4 w-4 text-muted-foreground mt-0.5" />
                        <span className="min-w-0 break-words text-muted-foreground">
                          {order.delivery_address || 'Alamat tidak tersedia'}
                        </span>
                      </div>

                      {distance !== null && (
                        <div className="flex items-center gap-2 text-sm">
                          <Navigation className="h-4 w-4 text-primary" />
                          <span className="text-primary font-medium">
                            {formatDistance(distance)}
                          </span>
                        </div>
                      )}

                      {order.notes && (
                        <div className="text-xs text-muted-foreground bg-secondary p-2 rounded-lg">
                          Catatan: {order.notes}
                        </div>
                      )}
                    </div>

                    <div className="mb-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
                      {order.pickup_lat != null && order.pickup_lng != null && order.status === 'COURIER_ACCEPTED' && (
                        <NavigationButton lat={order.pickup_lat} lng={order.pickup_lng} address={order.pickup_address || order.merchants?.address || undefined} variant="outline" size="sm" className="w-full">
                          Navigasi ke toko
                        </NavigationButton>
                      )}
                      {order.delivery_lat != null && order.delivery_lng != null && order.status !== 'COURIER_ACCEPTED' && (
                        <NavigationButton
                          lat={order.delivery_lat}
                          lng={order.delivery_lng}
                          address={order.delivery_address || undefined}
                          variant="outline"
                          size="sm"
                          className="w-full"
                        >Navigasi ke pelanggan</NavigationButton>
                      )}
                    </div>

                    <div className="space-y-3 border-t border-border pt-3">
                      <div className="flex items-end justify-between gap-3">
                        <div><p className="text-xs text-muted-foreground">Estimasi pendapatan kurir</p><p className="font-bold text-primary">{formatPrice(order.courier_earning_estimate || order.shipping_cost || 0)}</p><p className="text-[11px] text-muted-foreground">Total pesanan: {formatPrice(order.total)}</p></div>
                      </div>
                      <div className={`grid gap-2 ${action ? 'grid-cols-2' : 'grid-cols-1'}`}>
                      <Button className="min-h-11 w-full" size="sm" variant="outline" onClick={() => void releaseOrder(order.id)} disabled={releasingOrder === order.id}>{releasingOrder === order.id ? 'Memproses…' : 'Lepas tugas'}</Button>
                      {action && (
                        <Button
                          className="min-h-11 w-full"
                          size="sm"
                          onClick={handleAction}
                        >
                          {action.needsPOD ? (
                            <Camera className="h-4 w-4 mr-1" />
                          ) : action.nextStatus === 'PICKED_UP' ? (
                            <Truck className="h-4 w-4 mr-1" />
                          ) : (
                            <CheckCircle className="h-4 w-4 mr-1" />
                          )}
                          {action.label}
                        </Button>
                      )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </motion.div>
      </div>

      {/* POD Dialog */}
      <ProofOfDelivery
        orderId={podOrderId || ''}
        open={!!podOrderId}
        onOpenChange={(open) => !open && setPodOrderId(null)}
        onSuccess={() => {
          setPodOrderId(null);
          fetchCourierData();
        }}
      />
    </CourierLayout>
  );
}
