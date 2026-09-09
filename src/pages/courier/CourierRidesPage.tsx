import { useState, useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Bike, MapPin, Navigation, CheckCircle, Loader2, RefreshCw, User, Volume2, MessageCircle, X, Package } from 'lucide-react';
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
  orders: {
    id: string;
    total: number;
    delivery_name: string | null;
    delivery_address: string | null;
    merchants: { name: string } | null;
  } | null;
}

interface RidesData {
  availableRides: RideRequest[];
  activeRide: ActiveRide | null;
  passengerNames: Record<string, string>;
}

export default function CourierRidesPage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [accepting, setAccepting] = useState<string | null>(null);
  const [updatingStatus, setUpdatingStatus] = useState(false);
  const [courierLat, setCourierLat] = useState<number | null>(null);
  const [courierLng, setCourierLng] = useState<number | null>(null);
  const [soundEnabled, setSoundEnabled] = useState(true);
  const [expandedMap, setExpandedMap] = useState<string | null>(null);
  const [chatOpen, setChatOpen] = useState(false);
  const prevRideCount = useRef(0);
  const audioCtxRef = useRef<AudioContext | null>(null);

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

  const { data: deliveryOffers = [], refetch: refetchOffers } = useQuery<DeliveryOffer[]>({
    queryKey: ['courier-order-offers', courierId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('delivery_assignments')
        .select('id, order_id, expires_at, orders(id, total, delivery_name, delivery_address, merchants(name))')
        .eq('courier_id', courierId!)
        .eq('status', 'OFFERED')
        .gt('expires_at', new Date().toISOString())
        .order('offered_at', { ascending: false });
      if (error) throw error;
      return (data || []) as unknown as DeliveryOffer[];
    },
    enabled: !!courierId,
    staleTime: 10_000,
    refetchInterval: 15_000,
  });

  const respondToOffer = async (offerId: string, accept: boolean) => {
    setAccepting(offerId);
    const { error } = await supabase.rpc('courier_respond_to_order_offer' as never, {
      p_assignment_id: offerId,
      p_accept: accept,
      p_reason: accept ? null : 'Kurir menolak tawaran',
    } as never);
    setAccepting(null);
    if (error) {
      toast({ title: 'Tawaran tidak dapat diproses', description: error.message, variant: 'destructive' });
      return;
    }
    toast({ title: accept ? 'Pesanan diambil' : 'Pesanan ditolak' });
    await refetchOffers();
  };

  // Fetch rides data
  const { data: ridesData, isLoading: ridesLoading, refetch: refetchRides } = useQuery<RidesData>({
    queryKey: ['courier-rides', courierId],
    queryFn: async () => {
      const [{ data: available }, { data: active }] = await Promise.all([
        supabase.from('ride_requests').select('*').eq('status', 'SEARCHING').order('created_at', { ascending: false }).limit(20),
        supabase.from('ride_requests').select('*').eq('driver_id', courierId!).in('status', ['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT']).order('created_at', { ascending: false }).limit(1),
      ]);

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
  });

  const availableRides = ridesData?.availableRides ?? [];
  const activeRide = ridesData?.activeRide ?? null;
  const passengerNames = ridesData?.passengerNames ?? {};
  const loading = courierLoading || ridesLoading;

  useEffect(() => {
    if (!activeRide) setChatOpen(false);
  }, [activeRide]);

  // Realtime subscriptions — only invalidate for searchable or owned rides.
  useEffect(() => {
    if (!courierId) return;
    const channel = supabase
      .channel('ride-requests-courier')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ride_requests', filter: 'status=eq.SEARCHING' }, () => {
        queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ride_requests', filter: `driver_id=eq.${courierId}` }, () => {
        queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [courierId, queryClient]);

  // Sound notification when new rides come in
  const playNotificationSound = useCallback(() => {
    try {
      if (!audioCtxRef.current) audioCtxRef.current = new AudioContext();
      const ctx = audioCtxRef.current;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.frequency.setValueAtTime(880, ctx.currentTime);
      osc.frequency.setValueAtTime(1100, ctx.currentTime + 0.1);
      osc.frequency.setValueAtTime(880, ctx.currentTime + 0.2);
      gain.gain.setValueAtTime(0.3, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.4);
      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.4);
    } catch { /* Audio not available */ }
  }, []);

  useEffect(() => {
    if (availableRides.length > prevRideCount.current && prevRideCount.current > 0 && soundEnabled) {
      playNotificationSound();
    }
    prevRideCount.current = availableRides.length;
  }, [availableRides.length, soundEnabled, playNotificationSound]);

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
        toast({ title: 'Ride sudah diambil driver lain', variant: 'destructive' });
      } else {
        toast({ title: '✅ Ride diterima!' });
      }
      queryClient.invalidateQueries({ queryKey: ['courier-rides', courierId] });
    },
    onError: () => toast({ title: 'Gagal menerima ride', variant: 'destructive' }),
    onSettled: () => setAccepting(null),
  });

  const updateRideStatusMutation = useMutation({
    mutationFn: async (newStatus: string) => {
      if (!activeRide || !courierId) return;
      setUpdatingStatus(true);
      const { error: rpcError } = await supabase.rpc('transition_ride_status', {
        p_ride_id: activeRide.id,
        p_to_status: newStatus,
      });

      if (!rpcError) return newStatus;

      // Older Supabase projects imported before the transition RPC was added
      // return PGRST202/42883 here. Keep the UI usable while the idempotent
      // migration is being applied, but still scope the fallback to this
      // driver's current ride and current status.
      const functionMissing = ['PGRST202', '42883'].includes(rpcError.code ?? '')
        || /transition_ride_status|function .*does not exist/i.test(rpcError.message ?? '');

      if (!functionMissing) throw rpcError;

      const timestamps: Record<string, string> = {};
      if (newStatus === 'PICKED_UP') timestamps.picked_up_at = new Date().toISOString();
      if (newStatus === 'COMPLETED') timestamps.completed_at = new Date().toISOString();

      const { data: updatedRide, error: updateError } = await supabase
        .from('ride_requests')
        .update({ status: newStatus, ...timestamps })
        .eq('id', activeRide.id)
        .eq('driver_id', courierId)
        .eq('status', activeRide.status)
        .select('id')
        .maybeSingle();

      if (updateError) throw updateError;
      if (!updatedRide) {
        throw new Error('Ride sudah berubah atau tidak lagi ditugaskan kepada Anda');
      }
      return newStatus;
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

  const openNavigation = (lat: number, lng: number) => {
    window.open(`https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`, '_blank');
  };

  return (
    <CourierLayout title="Ojek Desa" subtitle="Terima dan kelola perjalanan ojek">
      <div className="space-y-6">
        <div className="flex justify-end">
          <Button variant={soundEnabled ? 'default' : 'outline'} size="sm" onClick={() => setSoundEnabled(!soundEnabled)} className="text-xs">
            <Volume2 className="h-3.5 w-3.5 mr-1" />
            {soundEnabled ? 'Notifikasi On' : 'Notifikasi Off'}
          </Button>
        </div>

        {deliveryOffers.length > 0 && (
          <Card className="p-5 border-amber-300 border-2">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-bold flex items-center gap-2"><Package className="h-5 w-5 text-amber-600" /> Tawaran Pesanan</h3>
              <Badge variant="outline">{deliveryOffers.length} baru</Badge>
            </div>
            <div className="space-y-3">
              {deliveryOffers.map((offer) => (
                <div key={offer.id} className="rounded-lg border p-3 space-y-2">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="font-semibold">#{offer.order_id.slice(0, 8).toUpperCase()}</p>
                      <p className="text-xs text-muted-foreground">{offer.orders?.merchants?.name || 'Merchant'} · {offer.orders?.delivery_name || 'Pembeli'}</p>
                      <p className="text-xs text-muted-foreground">{offer.orders?.delivery_address || 'Alamat tujuan tersedia setelah diambil'}</p>
                    </div>
                    <p className="font-bold">{formatPrice(offer.orders?.total || 0)}</p>
                  </div>
                  <div className="flex gap-2">
                    <Button className="flex-1" size="sm" onClick={() => void respondToOffer(offer.id, true)} disabled={accepting === offer.id}>
                      {accepting === offer.id ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <CheckCircle className="h-4 w-4 mr-1" />} Ambil Pesanan
                    </Button>
                    <Button className="flex-1" size="sm" variant="outline" onClick={() => void respondToOffer(offer.id, false)} disabled={accepting === offer.id}>
                      <X className="h-4 w-4 mr-1" /> Tolak
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

        {activeRide && (
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }}>
            <Card className="p-5 border-primary border-2">
              <div className="flex items-center gap-2 mb-3">
                <Bike className="h-5 w-5 text-primary" />
                <h3 className="font-bold">Perjalanan Aktif</h3>
                <Badge>{activeRide.status}</Badge>
              </div>
              <div className="space-y-2 mb-4">
                <div className="flex items-start gap-2 text-sm">
                  <div className="w-2.5 h-2.5 rounded-full bg-primary mt-1.5 flex-shrink-0" />
                  <div>
                    <p className="text-xs text-muted-foreground">Jemput</p>
                    <p className="font-medium">{activeRide.pickup_address}</p>
                  </div>
                </div>
                <div className="flex items-start gap-2 text-sm">
                  <div className="w-2.5 h-2.5 rounded-full bg-destructive mt-1.5 flex-shrink-0" />
                  <div>
                    <p className="text-xs text-muted-foreground">Tujuan</p>
                    <p className="font-medium">{activeRide.destination_address}</p>
                  </div>
                </div>
              </div>
              <div className="flex items-center justify-between text-sm mb-4">
                <span className="text-muted-foreground">{activeRide.distance_km} km</span>
                <span className="font-bold text-primary text-lg">{formatPrice(activeRide.estimated_fare)}</span>
              </div>
              <div className="flex gap-2">
                {['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'].includes(activeRide.status) && (
                  <Button variant="outline" size="sm" className="flex-1" onClick={() => setChatOpen(true)}>
                    <MessageCircle className="h-4 w-4 mr-1" /> Chat Penumpang
                  </Button>
                )}
                {activeRide.status === 'ACCEPTED' && (
                  <Button variant="outline" size="sm" className="flex-1" onClick={() => openNavigation(activeRide.pickup_lat, activeRide.pickup_lng)}>
                    <Navigation className="h-4 w-4 mr-1" /> Navigasi Jemput
                  </Button>
                )}
                {['PICKED_UP', 'IN_TRANSIT'].includes(activeRide.status) && (
                  <Button variant="outline" size="sm" className="flex-1" onClick={() => openNavigation(activeRide.destination_lat, activeRide.destination_lng)}>
                    <Navigation className="h-4 w-4 mr-1" /> Navigasi Tujuan
                  </Button>
                )}
                {getNextAction() && (
                  <Button size="sm" className="flex-1" onClick={() => updateRideStatusMutation.mutate(getNextAction()!.nextStatus)} disabled={updatingStatus}>
                    {updatingStatus ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <CheckCircle className="h-4 w-4 mr-1" />}
                    {getNextAction()!.label}
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
            <Button variant="ghost" size="sm" onClick={() => refetchRides()}>
              <RefreshCw className="h-4 w-4" />
            </Button>
          </div>

          {loading ? (
            <div className="text-center py-8"><Loader2 className="h-6 w-6 animate-spin mx-auto" /></div>
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
                      <div className="flex items-center justify-between">
                        <span className="font-bold text-primary">{formatPrice(ride.estimated_fare)}</span>
                        <div className="flex gap-1.5">
                          <Button size="sm" variant="outline" onClick={() => setExpandedMap(expandedMap === ride.id ? null : ride.id)}>
                            <MapPin className="h-3.5 w-3.5 mr-1" />
                            {expandedMap === ride.id ? 'Tutup Peta' : 'Lihat Rute'}
                          </Button>
                          <Button size="sm" onClick={() => acceptRideMutation.mutate(ride.id)} disabled={accepting === ride.id || !!activeRide}>
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
                          <Polyline
                            positions={[[ride.pickup_lat, ride.pickup_lng], [ride.destination_lat, ride.destination_lng]]}
                            pathOptions={{ color: 'hsl(160,84%,39%)', weight: 2, dashArray: '8, 6', opacity: 0.7 }}
                          />
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
    </CourierLayout>
  );
}
