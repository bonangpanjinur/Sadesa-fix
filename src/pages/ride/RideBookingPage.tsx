import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { safeGoBack } from '@/lib/utils';
import { Bike, Loader2, ArrowLeft, LocateFixed, MapPin, Navigation, Clock } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { Button } from '@/components/ui/button';
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
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { formatPrice } from '@/lib/utils';
import { geocodeFreeformAddress, reverseGeocode, formatAddressSummary } from '@/hooks/useGeocoding';
import { calculateETA, formatETA } from '@/lib/etaCalculation';
import { getRoadRoute, type RoadRoute } from '@/lib/routeCalculation';
import { GoogleRideMap } from '@/components/transport/GoogleRideMap';
import { NominatimAddressInput } from '@/components/transport/NominatimAddressInput';

interface FareSettings { base_fare: number; per_km_fare: number; min_fare: number; max_fare: number; }
const DEFAULT_FARE: FareSettings = { base_fare: 5000, per_km_fare: 3000, min_fare: 5000, max_fare: 100000 };

function haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

interface DriverMarker { id: string; lat: number; lng: number; }

export default function RideBookingPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [mode, setMode] = useState<'pickup' | 'destination'>('pickup');
  const [pickupLocation, setPickupLocation] = useState<{ lat: number; lng: number } | null>(null);
  const [pickupAddress, setPickupAddress] = useState('');
  const [destLocation, setDestLocation] = useState<{ lat: number; lng: number } | null>(null);
  const [destAddress, setDestAddress] = useState('');
  const [fareSettings, setFareSettings] = useState<FareSettings>(DEFAULT_FARE);
  const [submitting, setSubmitting] = useState(false);
  const [gettingGps, setGettingGps] = useState(false);
  const [drivers, setDrivers] = useState<DriverMarker[]>([]);
  const [mapCenter] = useState<[number, number]>([-7.3274, 108.2207]);
  const [activeRide, setActiveRide] = useState<{ id: string; status: string } | null>(null);
  const [geocoding, setGeocoding] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [roadRoute, setRoadRoute] = useState<RoadRoute | null>(null);
  const [routeLoading, setRouteLoading] = useState(false);
  const geocodeAbort = useRef<AbortController | null>(null);
  const manualAddressRef = useRef({ pickup: false, destination: false });

  const nearbyDrivers = useMemo(() => {
    if (!pickupLocation) return drivers;
    return [...drivers].sort((a, b) => (
      haversineDistance(pickupLocation.lat, pickupLocation.lng, a.lat, a.lng)
      - haversineDistance(pickupLocation.lat, pickupLocation.lng, b.lat, b.lng)
    ));
  }, [drivers, pickupLocation]);

  const nearestDriver = nearbyDrivers[0] ?? null;
  const nearestDriverDistance = nearestDriver && pickupLocation
    ? haversineDistance(pickupLocation.lat, pickupLocation.lng, nearestDriver.lat, nearestDriver.lng)
    : null;

  const fetchDrivers = useCallback(async () => {
    const { data } = await supabase.from('public_couriers').select('id, current_lat_approx, current_lng_approx, is_available, status')
      .eq('is_available', true).eq('status', 'ACTIVE')
      .not('current_lat_approx', 'is', null).not('current_lng_approx', 'is', null);
    if (data) setDrivers(data.flatMap(d => (
      d.id && d.current_lat_approx != null && d.current_lng_approx != null
        ? [{ id: d.id, lat: d.current_lat_approx, lng: d.current_lng_approx }]
        : []
    )));
  }, []);

  const handleGps = useCallback(() => {
    setGettingGps(true);
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const loc = { lat: pos.coords.latitude, lng: pos.coords.longitude };
        setPickupLocation(loc);
        manualAddressRef.current.pickup = false;
        setGettingGps(false);
        setMode('destination');
        // Reverse geocode GPS position
        setGeocoding(true);
        try {
          const result = await reverseGeocode(loc.lat, loc.lng);
          setPickupAddress(result ? formatAddressSummary(result) : 'Lokasi saya saat ini');
        } catch {
          setPickupAddress('Lokasi saya saat ini');
        } finally {
          setGeocoding(false);
        }
      },
      () => { setGettingGps(false); },
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }, []);

  useEffect(() => {
    if (!user) { navigate('/auth'); return; }
    supabase.from('app_settings').select('value').eq('key', 'ride_fare_settings').maybeSingle()
      .then(({ data }) => {
        if (data?.value) {
          const v = data.value as Record<string, unknown>;
          setFareSettings({
            base_fare: Number(v.base_fare) || DEFAULT_FARE.base_fare,
            per_km_fare: Number(v.per_km_fare) || DEFAULT_FARE.per_km_fare,
            min_fare: Number(v.min_fare) || DEFAULT_FARE.min_fare,
            max_fare: Number(v.max_fare) || DEFAULT_FARE.max_fare,
          });
        }
      });
    // Fetch nearby drivers
    fetchDrivers();
    // Check active ride
    supabase.from('ride_requests').select('id, status')
      .eq('passenger_id', user.id)
      .in('status', ['SEARCHING', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'])
      .order('created_at', { ascending: false }).limit(1)
      .then(({ data }) => {
        if (data && data.length > 0) setActiveRide(data[0] as unknown as { id: string; status: string });
      });
    handleGps();
  }, [user, navigate, fetchDrivers, handleGps]);

  // Real-time driver position updates
  useEffect(() => {
    // Refresh the privacy-filtered public view every 15 seconds.
    const interval = setInterval(fetchDrivers, 15000);

    return () => {
      clearInterval(interval);
    };
  }, [fetchDrivers]);


  const handleMapClick = useCallback(async (lat: number, lng: number) => {
    // Cancel previous geocode request
    if (geocodeAbort.current) geocodeAbort.current.abort();
    geocodeAbort.current = new AbortController();

    if (mode === 'pickup') {
      setPickupLocation({ lat, lng });
      setPickupAddress('Memuat alamat...');
      manualAddressRef.current.pickup = false;
    } else {
      setDestLocation({ lat, lng });
      setDestAddress('Memuat alamat...');
      manualAddressRef.current.destination = false;
    }

    // Reverse geocode the clicked point
    setGeocoding(true);
    try {
      const result = await reverseGeocode(lat, lng);
      const address = result ? formatAddressSummary(result) : `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
      if (mode === 'pickup') {
        setPickupAddress(address);
      } else {
        setDestAddress(address);
      }
    } catch {
      const fallback = `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
      if (mode === 'pickup') setPickupAddress(fallback);
      else setDestAddress(fallback);
    } finally {
      setGeocoding(false);
    }
  }, [mode]);

  useEffect(() => {
    const query = pickupAddress.trim();
    if (!manualAddressRef.current.pickup || query.length < 4) return;
    const timer = window.setTimeout(async () => {
      setGeocoding(true);
      const result = await geocodeFreeformAddress(query);
      if (result && manualAddressRef.current.pickup) setPickupLocation({ lat: result.lat, lng: result.lng });
      setGeocoding(false);
    }, 700);
    return () => window.clearTimeout(timer);
  }, [pickupAddress]);

  useEffect(() => {
    const query = destAddress.trim();
    if (!manualAddressRef.current.destination || query.length < 4) return;
    const timer = window.setTimeout(async () => {
      setGeocoding(true);
      const result = await geocodeFreeformAddress(query);
      if (result && manualAddressRef.current.destination) setDestLocation({ lat: result.lat, lng: result.lng });
      setGeocoding(false);
    }, 700);
    return () => window.clearTimeout(timer);
  }, [destAddress]);

  const straightLineDistanceKm = pickupLocation && destLocation
    ? haversineDistance(pickupLocation.lat, pickupLocation.lng, destLocation.lat, destLocation.lng) : 0;
  const distanceKm = roadRoute?.distanceKm ?? straightLineDistanceKm;

  const estimatedFare = Math.min(
    fareSettings.max_fare,
    Math.max(fareSettings.min_fare, Math.round(fareSettings.base_fare + distanceKm * fareSettings.per_km_fare))
  );

  const etaMinutes = roadRoute?.durationMinutes ?? (pickupLocation && destLocation
    ? calculateETA({ lat: pickupLocation.lat, lng: pickupLocation.lng }, { lat: destLocation.lat, lng: destLocation.lng }, 'motor')
    : 0);

  const fitPoints = useMemo(() => {
    if (roadRoute?.geometry.length) return roadRoute.geometry;
    const pts: [number, number][] = [];
    if (pickupLocation) pts.push([pickupLocation.lat, pickupLocation.lng]);
    if (destLocation) pts.push([destLocation.lat, destLocation.lng]);
    return pts;
  }, [pickupLocation, destLocation, roadRoute]);

  useEffect(() => {
    if (!pickupLocation || !destLocation) {
      setRoadRoute(null);
      setRouteLoading(false);
      return;
    }

    const controller = new AbortController();
    setRouteLoading(true);
    getRoadRoute(pickupLocation, destLocation, controller.signal)
      .then((route) => setRoadRoute(route))
      .catch((error: unknown) => {
        if ((error as { name?: string })?.name !== 'AbortError') {
          console.warn('Gagal mengambil rute jalan, menggunakan jarak langsung:', error);
          setRoadRoute(null);
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setRouteLoading(false);
      });

    return () => controller.abort();
  }, [pickupLocation, destLocation]);

  const handleSubmit = async () => {
    if (!user || !pickupLocation || !destLocation) return;
    setSubmitting(true);
    try {
      const { data, error } = await supabase.rpc('create_ride_request', {
        p_pickup_lat: pickupLocation.lat,
        p_pickup_lng: pickupLocation.lng,
        p_pickup_address: pickupAddress || 'Titik jemput',
        p_destination_lat: destLocation.lat,
        p_destination_lng: destLocation.lng,
        p_destination_address: destAddress || 'Titik tujuan',
      });
      if (error) throw error;
      toast({ title: 'Mencari driver...', description: 'Permintaan ojek Anda sedang dicari driver terdekat' });
      navigate(`/ride/${data}`);
    } catch (err) {
      console.error(err);
      toast({ title: 'Gagal memesan ojek', variant: 'destructive' });
    } finally {
      setSubmitting(false);
      setShowConfirm(false);
    }
  };

  const canOrder = !!pickupLocation && !!destLocation && distanceKm > 0.05;

  return (
    <div className="fixed inset-0 flex flex-col bg-background">
      {/* Compact header */}
      <div className="relative z-20 flex items-center gap-3 px-4 py-3 bg-background/95 backdrop-blur border-b border-border">
        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => safeGoBack(navigate)}>
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <div className="flex items-center gap-2">
          <Bike className="h-5 w-5 text-primary" />
          <h1 className="text-base font-bold">Ojek Desa</h1>
        </div>
        <div className="ml-auto flex items-center gap-1.5">
          <Button variant="ghost" size="sm" className="h-8 text-xs" onClick={() => navigate('/ride/history')}>
            <Clock className="h-3.5 w-3.5 mr-1" /> Riwayat
          </Button>
          <Button
            variant="outline" size="sm"
            className="h-8 text-xs"
            onClick={handleGps} disabled={gettingGps}
          >
            {gettingGps ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <LocateFixed className="h-3.5 w-3.5" />}
          </Button>
        </div>
      </div>

      {/* Active ride banner */}
      {activeRide && (
        <div
          className="relative z-20 flex items-center gap-3 px-4 py-2.5 bg-primary text-primary-foreground cursor-pointer"
          onClick={() => navigate(`/ride/${activeRide.id}`)}
        >
          <Loader2 className="h-4 w-4 animate-spin" />
          <span className="text-sm font-medium flex-1">
            Perjalanan sedang berlangsung — tap untuk lihat
          </span>
          <Navigation className="h-4 w-4" />
        </div>
      )}

      {/* Fullscreen Google map */}
      <div className="flex-1 relative z-0">
        <GoogleRideMap
          center={{ lat: mapCenter[0], lng: mapCenter[1] }}
          pickupLocation={pickupLocation}
          destinationLocation={destLocation}
          drivers={nearbyDrivers}
          nearestDriverId={nearestDriver?.id}
          route={fitPoints.length > 1 ? fitPoints : []}
          mode={mode}
          onMapClick={({ lat, lng }) => void handleMapClick(lat, lng)}
        />

        {/* Mode indicator floating on map */}
        <div className="absolute top-3 left-3 z-[1000]">
          <div className="bg-background/90 backdrop-blur-sm px-3 py-1.5 rounded-full text-xs font-semibold shadow border border-border flex items-center gap-2">
            <span className={`h-2 w-2 rounded-full ${mode === 'pickup' ? 'bg-emerald-500' : 'bg-red-500'}`} />
            {mode === 'pickup' ? 'Tap peta: pilih jemput' : 'Tap peta: pilih tujuan'}
          </div>
        </div>

        {/* Geocoding indicator */}
        {geocoding && (
          <div className="absolute top-12 left-3 z-[1000] bg-background/90 backdrop-blur-sm px-3 py-1.5 rounded-full text-xs shadow border border-border flex items-center gap-1.5">
            <Loader2 className="h-3 w-3 animate-spin text-primary" />
            Mengambil alamat...
          </div>
        )}

        {/* Driver count */}
        {nearbyDrivers.length > 0 && (
          <div className="absolute top-3 right-3 z-[1000] bg-background/90 backdrop-blur-sm px-3 py-1.5 rounded-full text-xs font-medium shadow border border-border flex items-center gap-1.5">
            <Navigation className="h-3 w-3 text-primary" />
            {nearbyDrivers.length} ojek aktif
          </div>
        )}
        {nearestDriver && nearestDriverDistance != null && pickupLocation && (
          <div className="absolute bottom-3 left-3 right-3 z-[1000] rounded-xl border border-primary/20 bg-background/95 px-3 py-2 shadow-lg backdrop-blur">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-primary">Ojek terdekat tersedia</p>
            <div className="mt-0.5 flex items-center justify-between gap-3">
              <span className="truncate text-sm font-semibold">🏍️ Driver tersedia</span>
              <span className="shrink-0 text-xs text-muted-foreground">{nearestDriverDistance.toFixed(2)} km dari Anda</span>
            </div>
          </div>
        )}
      </div>

      {/* Bottom sheet */}
      <AnimatePresence>
        <motion.div
          initial={{ y: 100, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          className="relative z-10 bg-card border-t border-border rounded-t-2xl shadow-lg px-4 pt-4 pb-6 space-y-3"
        >
          {/* Address inputs are intentionally independent from the map-mode controls. */}
          <div className="space-y-2">
            <label className={`flex w-full items-center gap-3 rounded-xl border px-3 py-2.5 text-left text-sm transition ${
              mode === 'pickup' ? 'border-emerald-500 bg-emerald-50/50 ring-1 ring-emerald-500/30' : 'border-border bg-muted/30'
            }`}>
              <span className="h-3 w-3 shrink-0 rounded-full bg-emerald-500" />
              <NominatimAddressInput
                id="ride-pickup-address"
                placeholder="Ketik alamat titik jemput"
                value={pickupAddress}
                onFocus={() => setMode('pickup')}
                onChange={(value) => {
                  manualAddressRef.current.pickup = true;
                  setPickupLocation(null);
                  setPickupAddress(value);
                }}
                className="relative z-10 h-auto min-w-0 border-0 bg-transparent p-0 text-sm focus-visible:ring-0 focus-visible:ring-offset-0"
                onPlaceSelected={({ address, location }) => {
                  manualAddressRef.current.pickup = false;
                  setPickupAddress(address);
                  setPickupLocation(location);
                  setMode('destination');
                }}
              />
            </label>
            <label className={`flex w-full items-center gap-3 rounded-xl border px-3 py-2.5 text-left text-sm transition ${
              mode === 'destination' ? 'border-red-500 bg-red-50/50 ring-1 ring-red-500/30' : 'border-border bg-muted/30'
            }`}>
              <span className="h-3 w-3 shrink-0 rounded-full bg-red-500" />
              <NominatimAddressInput
                id="ride-destination-address"
                placeholder="Ketik alamat tujuan"
                value={destAddress}
                onFocus={() => setMode('destination')}
                onChange={(value) => {
                  manualAddressRef.current.destination = true;
                  setDestLocation(null);
                  setDestAddress(value);
                }}
                className="relative z-10 h-auto min-w-0 border-0 bg-transparent p-0 text-sm focus-visible:ring-0 focus-visible:ring-offset-0"
                onPlaceSelected={({ address, location }) => {
                  manualAddressRef.current.destination = false;
                  setDestAddress(address);
                  setDestLocation(location);
                }}
              />
            </label>
          </div>
          <p className="flex items-center gap-1.5 px-1 text-[10px] text-muted-foreground">
            <MapPin className="h-3 w-3 text-primary" />
            Pilih titik langsung di peta atau ketik alamat untuk mencari otomatis.
          </p>

          {/* Fare estimation + Order */}
          {canOrder && (
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="space-y-3">
              <div className="flex items-center justify-between text-sm bg-muted/50 rounded-xl px-4 py-3">
                <div className="space-y-0.5">
                  <p className="text-muted-foreground text-xs">Jarak</p>
                  <p className="font-semibold">{routeLoading ? 'Menghitung…' : `${distanceKm.toFixed(1)} km via jalan`}</p>
                </div>
                <div className="h-8 w-px bg-border" />
                <div className="space-y-0.5 text-center">
                  <p className="text-muted-foreground text-xs">Waktu</p>
                  <p className="font-semibold">~{formatETA(etaMinutes)}</p>
                </div>
                <div className="h-8 w-px bg-border" />
                <div className="space-y-0.5 text-right">
                  <p className="text-muted-foreground text-xs">Estimasi</p>
                  <p className="font-bold text-primary text-base">{formatPrice(estimatedFare)}</p>
                </div>
              </div>
            </motion.div>
          )}

          {!canOrder && (
            <p className="text-center text-xs text-muted-foreground py-1">
              {!pickupLocation ? 'Pilih titik jemput di peta atau gunakan GPS' :
               !destLocation ? 'Tap peta untuk pilih tujuan' : 'Jarak terlalu dekat'}
            </p>
          )}
        </motion.div>
      </AnimatePresence>

      {canOrder && (
        <div className="pointer-events-none fixed inset-x-0 bottom-0 z-30 border-t border-border/70 bg-background/95 px-4 pb-[calc(0.75rem+env(safe-area-inset-bottom))] pt-3 shadow-[0_-6px_20px_rgba(0,0,0,0.08)] backdrop-blur">
          <Button
            className="pointer-events-auto mx-auto flex h-12 w-full max-w-2xl rounded-xl text-sm font-bold shadow-lg"
            onClick={() => setShowConfirm(true)}
            disabled={submitting}
          >
            <Bike className="mr-2 h-4 w-4" />
            Pesan Ojek · {formatPrice(estimatedFare)}
          </Button>
        </div>
      )}

      {/* Booking Confirmation Dialog */}
      <AlertDialog open={showConfirm} onOpenChange={setShowConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Konfirmasi Pesanan Ojek</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-3 pt-2">
                <div className="space-y-2 text-sm">
                  <div className="flex items-start gap-2">
                    <div className="w-2.5 h-2.5 rounded-full bg-emerald-500 mt-1.5 flex-shrink-0" />
                    <div>
                      <p className="text-xs text-muted-foreground">Jemput</p>
                      <p className="font-medium text-foreground">{pickupAddress}</p>
                    </div>
                  </div>
                  <div className="flex items-start gap-2">
                    <div className="w-2.5 h-2.5 rounded-full bg-red-500 mt-1.5 flex-shrink-0" />
                    <div>
                      <p className="text-xs text-muted-foreground">Tujuan</p>
                      <p className="font-medium text-foreground">{destAddress}</p>
                    </div>
                  </div>
                </div>
                <div className="flex justify-between text-sm bg-muted rounded-lg px-3 py-2">
                  <span>Jarak: <strong>{distanceKm.toFixed(1)} km via jalan</strong></span>
                  <span>~<strong>{formatETA(etaMinutes)}</strong></span>
                </div>
                <div className="text-center">
                  <p className="text-xs text-muted-foreground">Estimasi Tarif</p>
                  <p className="text-xl font-bold text-primary">{formatPrice(estimatedFare)}</p>
                </div>
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Batal</AlertDialogCancel>
            <AlertDialogAction onClick={handleSubmit} disabled={submitting}>
              {submitting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Bike className="h-4 w-4 mr-2" />}
              Konfirmasi Pesan
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
