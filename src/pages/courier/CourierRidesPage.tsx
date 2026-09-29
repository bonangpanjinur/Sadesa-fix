import { useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Bike, MapPin, Navigation, CheckCircle, Loader2, RefreshCw, User, MessageCircle, X, Package } from 'lucide-react';
import { CourierLayout } from '@/components/courier/CourierLayout';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { formatPrice } from '@/lib/utils';
import { MapContainer, TileLayer, Marker, Polyline } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { OrderChat } from '@/components/chat/OrderChat';
import { DeliveryOfferCard, type DeliveryOfferCardData } from '@/components/courier/DeliveryOfferCard';
import { getRoadRoute } from '@/lib/routeCalculation';
import { getRpcErrorMessage } from '@/lib/courierOrderStatus';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';

const pickupIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
  shadowUrl: markerShadow,
  iconSize: [20, 33], iconAnchor: [10, 33], popupAnchor: [1, -28], shadowSize: [33, 33],
});

const destIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
  shadowUrl: markerShadow,
  iconSize: [20, 33], iconAnchor: [10, 33], popupAnchor: [1, -28], shadowSize: [33, 33],
});

interface RideRequest {
  id: string;
  passenger_id: string;
  status: string;
  pickup_address: string;
  destination_address: string;
  pickup_lat: number;
  pickup_lng: number;
  destination_lat: number;
  destination_lng: number;
  distance_km: number;
  estimated_fare: number;
  created_at: string;
}

interface ActiveRide extends RideRequest {
  driver_id: string | null;
}

interface CourierInfo {
  id: string;
  current_lat: number | null;
  current_lng: number | null;
}

interface DeliveryOffer {
  id: string;
  order_id: string;
  expires_at: string;
  orders?: DeliveryOfferCardData['order'];
}

interface RidesData {
  availableRides: RideRequest[];
  activeRide: ActiveRide | null;
  passengerNames: Record<string, string>;
}

interface RideReasonDialogState {
  kind: 'advance' | 'cancel';
  nextStatus?: string;
  title: string;
  description: string;
  initialValue: string;
}

export default function CourierRidesPage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const queryClient = useQueryClient();
  const [accepting, setAccepting] = useState<string | null>(null);
  const [updatingStatus, setUpdatingStatus] = useState(false);
  const [courierLat, setCourierLat] = useState<number | null>(null);
  const [courierLng, setCourierLng] = useState<number | null>(null);
  const [expandedMap, setExpandedMap] = useState<string | null>(null);
  const [roadRoute, setRoadRoute] = useState<[number, number][]>([]);
  const [routeFallback, setRouteFallback] = useState(false);
  const [chatOpen, setChatOpen] = useState(false);
  const [chatConversationId, setChatConversationId] = useState<string | null>(null);
  const [respondingOffer, setRespondingOffer] = useState<string | null>(null);
  const [reasonDialog, setReasonDialog] = useState<RideReasonDialogState | null>(null);
  const [reasonText, setReasonText] = useState('');
  const [cancelling, setCancelling] = useState(false);

  // Fetch courier info
  const { data: courierInfo, isLoading: courierLoading } = useQuery<CourierInfo | null>({
    queryKey: ['courier-info', user?.id],
    queryFn: async () => {
      const { data } = await supabase
        .from('couriers')
        .select('id, current_lat, current_lng')
        .eq('user_id', user!.id)
        .eq('registration_status', 'APPROVED')
        .maybeSingle();
      if (!data) return null;
      if (data.current_lat) setCourierLat(data.current_lat);
      if (data.current_lng) setCourierLng(data.current_lng);
      navigator.geolocation?.getCurrentPosition(
        pos => { setCourierLat(pos.coords.latitude); setCourierLng(pos.coords.longitude); },
        () => {}, { enableHighAccuracy: true, timeout: 5000 }
      );
      return data;
    },
    enabled: !!user,
    staleTime: 300_000,
  });

  const courierId = courierInfo?.id ?? null;

  const { data: deliveryOffers = [], isLoading: deliveryOffersLoading } = useQuery<DeliveryOffer[]>({
    queryKey: ['courier-rides-delivery-offers', courierId],
    queryFn: async () => {
      if (!courierId) return [];
      const { data, error } = await supabase.rpc('get_courier_delivery_offers' as never);
      if (error) throw error;
      return (data || []) as unknown as DeliveryOffer[];
    },
    enabled: !!courierId,
    refetchInterval: 15_000,
  });

  // Fetch rides data
  const { data: ridesData, isLoading: ridesLoading, isFetching: ridesFetching, isError: ridesError, refetch: refetchRides } = useQuery<RidesData>({
    queryKey: ['courier-rides', courierId],
    queryFn: async () => {
      // An active courier session acts as a lightweight dispatch heartbeat.
      // The RPC is server-authoritative and safely no-ops when another session
      // already owns the dispatch lock; failure must not hide the local inbox.
      try {
        await supabase.rpc('process_expired_ride_offers' as never);
      } catch {
        // Older deployments may not have the optional expiry RPC yet.
      }
      const [{ data: pendingOffers, error: offersError }, { data: active }] = await Promise.all([
        supabase.from('ride_request_offers' as never)
          .select('ride_id')
          .eq('courier_id', courierId!)
          .eq('status', 'PENDING')
          .gt('expires_at', new Date().toISOString())
          .order('offered_at', { ascending: false })
          .limit(20),
        supabase.from('ride_requests').select('*').eq('driver_id', courierId!).in('status', ['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT']).order('created_at', { ascending: false }).limit(1),
      ]);
      if (offersError) throw offersError;
      const rideIds = [...new Set(((pendingOffers || []) as unknown as Array<{ ride_id: string }>)
        .map((offer) => offer.ride_id)
        .filter(Boolean))];
      const { data: available } = rideIds.length > 0
        ? await supabase.from('ride_requests').select('*').in('id', rideIds).eq('status', 'SEARCHING').order('created_at', { ascending: false })
        : { data: [] };

      const rides = (available || []) as unknown as RideRequest[];
      const passengerIds = [...new Set([
        ...rides.map(r => r.passenger_id),
        ...((active?.[0] as { passenger_id?: string } | undefined)?.passenger_id
          ? [(active[0] as { passenger_id: string }).passenger_id]
          : []),
      ])];
      const passengerNames: Record<string, string> = {};

      if (passengerIds.length > 0) {
        const { data: profiles } = await supabase.from('profiles').select('user_id, full_name').in('user_id', passengerIds);
        if (profiles) {
          profiles.forEach((p: { user_id: string; full_name: string | null }) => {
            if (p.full_name) passengerNames[p.user_id] = p.full_name;
          });
        }
      }

      return {
        availableRides: rides,
        activeRide: active && active.length > 0 ? (active[0] as unknown as ActiveRide) : null,
        passengerNames,
      };
    },
    enabled: !!courierId,
    staleTime: 30_000,
    refetchInterval: 15_000,
  });

  const availableRides = useMemo(() => ridesData?.availableRides ?? [], [ridesData?.availableRides]);
  const activeRide = ridesData?.activeRide ?? null;
  const passengerNames = ridesData?.passengerNames ?? {};
  const loading = courierLoading || ridesLoading;

  useEffect(() => {
    if (!activeRide) setChatOpen(false);
  }, [activeRide]);

  useEffect(() => {
    const conversationId = searchParams.get('conversationId');
    if (conversationId && activeRide) {
      setChatConversationId(conversationId);
      setChatOpen(true);
    }
  }, [activeRide, searchParams]);

  // Realtime subscriptions — only invalidate offers targeted to this courier
  // or rides already accepted by this courier. Listening to every SEARCHING
  // ride makes the UI look like every courier can accept every ride, while the
  // server-authoritative RPC correctly rejects non-targeted couriers.
  useEffect(() => {
    if (!courierId) return;
    const channel = supabase
      .channel('ride-requests-courier')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ride_request_offers', filter: `courier_id=eq.${courierId}` }, () => {
        queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ride_requests', filter: `driver_id=eq.${courierId}` }, () => {
        queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'delivery_assignments', filter: `courier_id=eq.${courierId}` }, () => {
        queryClient.invalidateQueries({ queryKey: ['courier-rides-delivery-offers', courierId] });
      })
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
      });
    return () => { supabase.removeChannel(channel); };
  }, [courierId, queryClient]);

  const respondToDeliveryOffer = async (assignmentId: string, accept: boolean) => {
    setRespondingOffer(assignmentId);
    try {
      const { error } = await supabase.rpc('respond_delivery_offer' as never, {
        p_assignment_id: assignmentId,
        p_accept: accept,
        p_reason: accept ? null : 'Kurir menolak tawaran',
      } as never);
      if (error) throw error;
      queryClient.invalidateQueries({ queryKey: ['courier-rides-delivery-offers', courierId] });
      queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
      toast({ title: accept ? 'Pesanan pengantaran diterima' : 'Tawaran pengantaran ditolak' });
    } catch (error) {
      toast({ title: 'Tawaran pengantaran tidak dapat diproses', description: getRpcErrorMessage(error), variant: 'destructive' });
    } finally {
      setRespondingOffer(null);
    }
  };

  const haversine = (lat1: number, lng1: number, lat2: number, lng2: number) => {
    const R = 6371;
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLng = ((lng2 - lng1) * Math.PI) / 180;
    const a = Math.sin(dLat / 2) ** 2 + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  };

  const acceptRideMutation = useMutation({
    mutationFn: async (rideId: string) => {
      setAccepting(rideId);
      const { data, error } = await supabase.rpc('accept_ride', { p_ride_id: rideId, p_courier_id: courierId! });
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      if (data === false) {
        toast({ title: 'Penawaran sudah berakhir atau tidak tersedia lagi', variant: 'destructive' });
      } else {
        toast({ title: '✅ Ride diterima!' });
      }
      queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
    },
    onError: () => toast({ title: 'Gagal menerima ride', variant: 'destructive' }),
    onSettled: () => setAccepting(null),
  });

  const declineRideMutation = useMutation({
    mutationFn: async (rideId: string) => {
      const { data, error } = await supabase.rpc('decline_ride_request' as never, { p_ride_id: rideId } as never);
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
      toast({
        title: data === false ? 'Penawaran sudah berakhir' : 'Penawaran ditolak',
        description: data === false ? undefined : 'Permintaan akan ditawarkan ke ojek berikutnya.',
      });
    },
    onError: () => toast({ title: 'Gagal menolak penawaran ojek', variant: 'destructive' }),
  });

  const updateRideStatusMutation = useMutation({
    mutationFn: async ({ newStatus, verificationNote }: { newStatus: string; verificationNote?: string }) => {
      if (!activeRide || !courierId) return;
      setUpdatingStatus(true);
      const { error: rpcError } = await supabase.rpc('transition_ride_status', {
        p_ride_id: activeRide.id,
        p_to_status: newStatus,
        p_verification_note: verificationNote || null,
      });

      if (!rpcError) return newStatus;
      throw rpcError;
    },
    onSuccess: (newStatus) => {
      toast({ title: newStatus === 'COMPLETED' ? '✅ Perjalanan selesai!' : 'Status diperbarui' });
      queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
    },
    onError: (error) => toast({
      title: 'Gagal memperbarui status',
      description: error instanceof Error ? error.message : 'Silakan coba lagi.',
      variant: 'destructive',
    }),
    onSettled: () => setUpdatingStatus(false),
  });

  const getNextAction = () => {
    if (!activeRide) return null;
    switch (activeRide.status) {
      case 'ACCEPTED': return { label: 'Sudah Dijemput', nextStatus: 'PICKED_UP' };
      case 'PICKED_UP': return { label: 'Mulai Perjalanan', nextStatus: 'IN_TRANSIT' };
      case 'IN_TRANSIT': return { label: 'Selesai', nextStatus: 'COMPLETED' };
      default: return null;
    }
  };

  const advanceActiveRide = () => {
    const action = getNextAction();
    if (!action) return;
    if (action.nextStatus === 'PICKED_UP' || action.nextStatus === 'COMPLETED') {
      const initialValue = action.nextStatus === 'PICKED_UP' ? 'Penumpang sudah dijemput' : 'Penumpang sudah sampai';
      setReasonDialog({
        kind: 'advance',
        nextStatus: action.nextStatus,
        title: action.nextStatus === 'PICKED_UP' ? 'Konfirmasi penjemputan' : 'Konfirmasi perjalanan selesai',
        description: action.nextStatus === 'PICKED_UP'
          ? 'Tulis catatan singkat setelah penumpang sudah naik.'
          : 'Tulis catatan singkat setelah penumpang sudah sampai.',
        initialValue,
      });
      setReasonText(initialValue);
      return;
    }
    updateRideStatusMutation.mutate({ newStatus: action.nextStatus });
  };

  const openNavigation = (lat: number, lng: number) => {
    window.open(`https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`, '_blank');
  };

  const cancelActiveRide = async (reason: string) => {
    if (!activeRide) return;
    setCancelling(true);
    try {
      const { error } = await supabase.rpc('driver_cancel_ride' as never, { p_ride_id: activeRide.id, p_reason: reason } as never);
      if (error) throw error;
      queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
      toast({ title: 'Perjalanan dibatalkan', description: 'Penumpang telah diberi tahu.' });
    } catch (error) {
      toast({ title: 'Gagal membatalkan perjalanan', description: getRpcErrorMessage(error), variant: 'destructive' });
    } finally {
      setCancelling(false);
    }
  };

  const submitReason = () => {
    const trimmedReason = reasonText.trim();
    if (!trimmedReason || !reasonDialog) return;
    if (reasonDialog.kind === 'advance' && reasonDialog.nextStatus) {
      updateRideStatusMutation.mutate({ newStatus: reasonDialog.nextStatus, verificationNote: trimmedReason });
    } else {
      void cancelActiveRide(trimmedReason);
    }
    setReasonDialog(null);
    setReasonText('');
  };

  useEffect(() => {
    const ride = availableRides.find((item) => item.id === expandedMap);
    if (!ride) { setRoadRoute([]); setRouteFallback(false); return; }
    const controller = new AbortController();
    void getRoadRoute(
      { lat: ride.pickup_lat, lng: ride.pickup_lng },
      { lat: ride.destination_lat, lng: ride.destination_lng },
      controller.signal,
    ).then((route) => {
      if (route?.geometry?.length) { setRoadRoute(route.geometry); setRouteFallback(false); }
      else { setRoadRoute([[ride.pickup_lat, ride.pickup_lng], [ride.destination_lat, ride.destination_lng]]); setRouteFallback(true); }
    }).catch(() => { setRoadRoute([[ride.pickup_lat, ride.pickup_lng], [ride.destination_lat, ride.destination_lng]]); setRouteFallback(true); });
    return () => controller.abort();
  }, [expandedMap, availableRides]);

  return (
    <CourierLayout title="Ojek Desa" subtitle="Terima dan kelola perjalanan ojek">
      <div className="space-y-4 sm:space-y-6">
        {deliveryOffersLoading ? (
          <Card className="border-primary/20 p-4">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" /> Memuat tawaran pengiriman...
            </div>
          </Card>
        ) : deliveryOffers.length > 0 && (
          <Card className="border-primary/40 shadow-sm">
            <div className="space-y-3 p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-semibold">Tawaran Pengiriman Barang</p>
                  <p className="text-xs text-muted-foreground">Pilih Terima atau Tolak sebelum waktu habis</p>
                </div>
                <Badge>{deliveryOffers.length}</Badge>
              </div>
              {deliveryOffers.map((offer) => (
                <DeliveryOfferCard
                  key={offer.id}
                  offer={{ id: offer.id, order_id: offer.order_id, expires_at: offer.expires_at, order: offer.orders || null }}
                  busy={respondingOffer === offer.id}
                  onRespond={respondToDeliveryOffer}
                />
              ))}
            </div>
          </Card>
        )}

        {activeRide && (
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }}>
            <Card className="border-2 border-primary p-4 sm:p-5">
              <div className="flex items-center gap-2 mb-3">
                <Bike className="h-5 w-5 text-primary" />
                <h3 className="font-bold">Perjalanan Aktif</h3>
                <Badge>{activeRide.status === 'ACCEPTED' ? 'Menuju jemput' : activeRide.status === 'PICKED_UP' ? 'Penumpang dijemput' : 'Dalam perjalanan'}</Badge>
              </div>
              <div className="space-y-2 mb-4">
                <div className="flex items-start gap-2 text-sm">
                  <div className="w-2.5 h-2.5 rounded-full bg-primary mt-1.5 flex-shrink-0" />
                  <div>
                    <p className="text-xs text-muted-foreground">Jemput</p>
                    <p className="break-words font-medium">{activeRide.pickup_address}</p>
                  </div>
                </div>
                <div className="flex items-start gap-2 text-sm">
                  <div className="w-2.5 h-2.5 rounded-full bg-destructive mt-1.5 flex-shrink-0" />
                  <div>
                    <p className="text-xs text-muted-foreground">Tujuan</p>
                    <p className="break-words font-medium">{activeRide.destination_address}</p>
                  </div>
                </div>
              </div>
              <div className="flex items-center justify-between text-sm mb-4">
                <span className="text-muted-foreground">{activeRide.distance_km} km</span>
                <span className="font-bold text-primary text-lg">{formatPrice(activeRide.estimated_fare)}</span>
              </div>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'].includes(activeRide.status) && (
                  <Button variant="outline" size="sm" className="min-h-11 w-full sm:min-h-9" onClick={() => setChatOpen(true)}>
                    <MessageCircle className="h-4 w-4 mr-1" /> Chat Penumpang
                  </Button>
                )}
                {activeRide.status === 'ACCEPTED' && (
                  <Button variant="outline" size="sm" className="min-h-11 w-full sm:min-h-9" onClick={() => openNavigation(activeRide.pickup_lat, activeRide.pickup_lng)}>
                    <Navigation className="h-4 w-4 mr-1" /> Navigasi Jemput
                  </Button>
                )}
                {['PICKED_UP', 'IN_TRANSIT'].includes(activeRide.status) && (
                  <Button variant="outline" size="sm" className="min-h-11 w-full sm:min-h-9" onClick={() => openNavigation(activeRide.destination_lat, activeRide.destination_lng)}>
                    <Navigation className="h-4 w-4 mr-1" /> Navigasi Tujuan
                  </Button>
                )}
                {getNextAction() && (
                  <Button size="sm" className="min-h-11 w-full sm:min-h-9" onClick={advanceActiveRide} disabled={updatingStatus}>
                    {updatingStatus ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <CheckCircle className="h-4 w-4 mr-1" />}
                    {getNextAction()!.label}
                  </Button>
                )}
                {['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'].includes(activeRide.status) && (
                  <Button
                    variant="destructive"
                    size="sm"
                    className="min-h-11 w-full sm:min-h-9"
                    onClick={() => {
                      setReasonDialog({
                        kind: 'cancel',
                        title: 'Batalkan perjalanan',
                        description: 'Alasan pembatalan wajib diisi agar penumpang dan admin menerima konteks yang jelas.',
                        initialValue: 'Kendaraan bermasalah',
                      });
                      setReasonText('Kendaraan bermasalah');
                    }}
                    disabled={cancelling || updatingStatus}
                  >
                    <X className="h-4 w-4 mr-1" /> Batalkan perjalanan
                  </Button>
                )}
              </div>
            </Card>
          </motion.div>
        )}

        <div>
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-bold flex items-center gap-2">
              <MapPin className="h-4 w-4" />
              Permintaan Ojek ({availableRides.length})
            </h3>
            <Button variant="ghost" size="sm" onClick={() => void refetchRides()} disabled={ridesFetching} aria-label="Muat ulang permintaan ojek" title="Muat ulang permintaan ojek">
              <RefreshCw className={`h-4 w-4 ${ridesFetching ? 'animate-spin' : ''}`} />
            </Button>
          </div>

          {loading ? (
            <div className="text-center py-8"><Loader2 className="h-6 w-6 animate-spin mx-auto" /></div>
          ) : ridesError ? (
            <Card className="p-8 text-center">
              <p className="font-semibold">Permintaan ojek belum dapat dimuat</p>
              <p className="mt-1 text-sm text-muted-foreground">Periksa koneksi lalu tekan muat ulang.</p>
              <Button className="mt-4" variant="outline" onClick={() => void refetchRides()}>Coba lagi</Button>
            </Card>
          ) : availableRides.length === 0 ? (
            <Card className="p-8 text-center">
              <Bike className="h-10 w-10 text-muted-foreground mx-auto mb-2" />
              <p className="text-sm text-muted-foreground">Belum ada permintaan ojek saat ini</p>
            </Card>
          ) : (
            <div className="space-y-3">
              {availableRides.map((ride, idx) => (
                <motion.div key={ride.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: idx * 0.05 }}>
                  <Card className="overflow-hidden">
                    <div className="p-4">
                      <div className="flex items-start justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center">
                            <User className="h-3.5 w-3.5 text-primary" />
                          </div>
                          <div>
                            <p className="text-sm font-medium">{passengerNames[ride.passenger_id] || 'Penumpang'}</p>
                            <p className="text-[10px] text-muted-foreground">
                              {new Date(ride.created_at).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' })}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-1.5">
                          {courierLat && courierLng && (
                            <Badge variant="outline" className="text-[10px]">
                              <MapPin className="h-3 w-3 mr-0.5" />
                              {haversine(courierLat, courierLng, ride.pickup_lat, ride.pickup_lng).toFixed(1)} km
                            </Badge>
                          )}
                          <Badge variant="secondary">{ride.distance_km} km</Badge>
                        </div>
                      </div>
                      <div className="space-y-1.5 mb-3 text-sm">
                        <div className="flex items-center gap-2">
                          <div className="w-2 h-2 rounded-full bg-primary flex-shrink-0" />
                          <span className="truncate">{ride.pickup_address}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <div className="w-2 h-2 rounded-full bg-destructive flex-shrink-0" />
                          <span className="truncate">{ride.destination_address}</span>
                        </div>
                      </div>
                          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                            <span className="font-bold text-primary">{formatPrice(ride.estimated_fare)}</span>
                            <div className="grid w-full grid-cols-2 gap-2 sm:w-auto sm:grid-cols-3">
                              <Button size="sm" variant="outline" className="min-h-11 sm:min-h-9" onClick={() => setExpandedMap(expandedMap === ride.id ? null : ride.id)}>
                                <MapPin className="h-3.5 w-3.5 mr-1" />
                                {expandedMap === ride.id ? 'Tutup Peta' : 'Lihat Rute'}
                              </Button>
                              <Button
                                size="sm"
                                variant="outline"
                                className="min-h-11 sm:min-h-9"
                                onClick={() => declineRideMutation.mutate(ride.id)}
                                disabled={declineRideMutation.isPending || accepting === ride.id || !!activeRide}
                              >
                                <X className="h-3.5 w-3.5 mr-1" /> Tolak
                              </Button>
                              <Button
                                size="sm"
                                className="min-h-11 sm:min-h-9 col-span-2 sm:col-span-1"
                                onClick={() => acceptRideMutation.mutate(ride.id)}
                                disabled={accepting === ride.id || declineRideMutation.isPending || !!activeRide}
                              >
                                {accepting === ride.id ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <CheckCircle className="h-4 w-4 mr-1" />}
                                Terima
                              </Button>
                            </div>
                      </div>
                    </div>

                    {expandedMap === ride.id && (
                      <div className="h-[150px] border-t border-border">
                        <MapContainer
                          center={[(ride.pickup_lat + ride.destination_lat) / 2, (ride.pickup_lng + ride.destination_lng) / 2]}
                          zoom={13}
                          style={{ height: '100%', width: '100%' }}
                          zoomControl={false}
                          dragging={false}
                          scrollWheelZoom={false}
                          doubleClickZoom={false}
                          attributionControl={false}
                        >
                          <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
                          <Marker position={[ride.pickup_lat, ride.pickup_lng]} icon={pickupIcon} />
                          <Marker position={[ride.destination_lat, ride.destination_lng]} icon={destIcon} />
                          <Polyline positions={roadRoute} pathOptions={{ color: routeFallback ? 'hsl(45,90%,45%)' : 'hsl(160,84%,39%)', weight: 3, dashArray: routeFallback ? '8, 6' : undefined, opacity: 0.8 }} />
                        </MapContainer>
                      </div>
                    )}
                  </Card>
                </motion.div>
              ))}
            </div>
          )}
        </div>
      </div>
      {chatOpen && activeRide && (
        <OrderChat
          conversationId={chatConversationId}
          orderId={activeRide.id}
          contextType="ride"
          rideRequestId={activeRide.id}
          otherUserId={activeRide.passenger_id}
          otherUserName={passengerNames[activeRide.passenger_id] || 'Penumpang'}
          chatType="buyer_courier"
          senderRole="driver"
          isOpen={chatOpen}
          onClose={() => setChatOpen(false)}
        />
      )}
      <Dialog
        open={!!reasonDialog}
        onOpenChange={(open) => {
          if (!open && !cancelling && !updateRideStatusMutation.isPending) setReasonDialog(null);
        }}
      >
        <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{reasonDialog?.title}</DialogTitle>
            <DialogDescription>{reasonDialog?.description}</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="ride-reason">Catatan atau alasan</Label>
            <Textarea
              id="ride-reason"
              value={reasonText}
              onChange={(event) => setReasonText(event.target.value)}
              placeholder={reasonDialog?.initialValue || 'Tulis catatan'}
              maxLength={500}
              autoFocus
            />
            <p className="text-right text-xs text-muted-foreground">{reasonText.length}/500</p>
          </div>
          <DialogFooter className="gap-2 sm:gap-0">
            <Button variant="outline" onClick={() => setReasonDialog(null)} disabled={cancelling || updateRideStatusMutation.isPending}>Batal</Button>
            <Button onClick={submitReason} disabled={!reasonText.trim() || cancelling || updateRideStatusMutation.isPending}>
              {(cancelling || updateRideStatusMutation.isPending) && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />}
              Konfirmasi
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </CourierLayout>
  );
}
