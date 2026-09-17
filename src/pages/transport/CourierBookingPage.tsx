import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowLeft, Box, CalendarDays, Check, ContactRound, Info, LocateFixed, Loader2, MapPin, Navigation, PackageCheck, UserRound } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { MapContainer, Marker, Polyline, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { toast } from '@/hooks/use-toast';
import { formatAddressSummary, reverseGeocode } from '@/hooks/useGeocoding';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { getRoadRoute, type RoadRoute } from '@/lib/routeCalculation';

type CourierMode = 'send' | 'pickup';
type DistanceBand = 'near' | 'medium' | 'far';
type RoutePoint = { lat: number; lng: number };
type DeviceContact = { name?: string[]; tel?: string[] };
type ContactPickerNavigator = Navigator & {
  contacts?: {
    select: (properties: Array<'name' | 'tel'>, options?: { multiple?: boolean }) => Promise<DeviceContact[]>;
  };
};
type AvailableDriver = { id: string; name: string; lat: number; lng: number };

const distanceOptions: Array<{ value: DistanceBand; label: string; price: number }> = [
  { value: 'near', label: '0–3 km', price: 8000 },
  { value: 'medium', label: '3–7 km', price: 12000 },
  { value: 'far', label: 'Lebih dari 7 km', price: 18000 },
];

const mapCenter: [number, number] = [-7.3274, 108.2207];

const pickupIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
  shadowUrl: markerShadow,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41],
});

const destinationIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
  shadowUrl: markerShadow,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41],
});

const driverIcon = new L.Icon({
  iconUrl: '/motor-icon.png',
  iconSize: [34, 34],
  iconAnchor: [17, 34],
  popupAnchor: [0, -34],
});

function haversineDistance(first: RoutePoint, second: RoutePoint) {
  const earthRadiusKm = 6371;
  const latitudeDelta = ((second.lat - first.lat) * Math.PI) / 180;
  const longitudeDelta = ((second.lng - first.lng) * Math.PI) / 180;
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos((first.lat * Math.PI) / 180)
    * Math.cos((second.lat * Math.PI) / 180)
    * Math.sin(longitudeDelta / 2) ** 2;
  return earthRadiusKm * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function getDistanceBand(distanceKm: number): DistanceBand {
  if (distanceKm <= 3) return 'near';
  if (distanceKm <= 7) return 'medium';
  return 'far';
}

function MapClickHandler({ onSelect }: { onSelect: (point: RoutePoint) => void }) {
  useMapEvents({
    click(event) {
      onSelect({ lat: event.latlng.lat, lng: event.latlng.lng });
    },
  });
  return null;
}

function FitRouteBounds({ points }: { points: RoutePoint[] }) {
  const map = useMap();

  useEffect(() => {
    if (points.length < 2) return;
    map.fitBounds(
      L.latLngBounds(points.map((point) => L.latLng(point.lat, point.lng))),
      { padding: [40, 40], maxZoom: 16 },
    );
  }, [map, points]);

  return null;
}

function FocusMapPoint({ point }: { point: RoutePoint | null }) {
  const map = useMap();

  useEffect(() => {
    if (!point) return;
    map.setView([point.lat, point.lng], Math.max(map.getZoom(), 15), { animate: true });
  }, [map, point]);

  return null;
}

export default function CourierBookingPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [mode, setMode] = useState<CourierMode>('send');
  const [pickupAddress, setPickupAddress] = useState('');
  const [destinationAddress, setDestinationAddress] = useState('');
  const [pickupLocation, setPickupLocation] = useState<RoutePoint | null>(null);
  const [destinationLocation, setDestinationLocation] = useState<RoutePoint | null>(null);
  const [mapMode, setMapMode] = useState<'pickup' | 'destination'>('pickup');
  const [geocoding, setGeocoding] = useState<'pickup' | 'destination' | null>(null);
  const [recipientName, setRecipientName] = useState('');
  const [recipientPhone, setRecipientPhone] = useState('');
  const [packageType, setPackageType] = useState('');
  const [weight, setWeight] = useState('1');
  const [distanceBand, setDistanceBand] = useState<DistanceBand>('near');
  const [scheduled, setScheduled] = useState(false);
  const [notes, setNotes] = useState('');
  const [cod, setCod] = useState(false);
  const [contactLoading, setContactLoading] = useState(false);
  const [gettingGps, setGettingGps] = useState(false);
  const [gpsAccuracy, setGpsAccuracy] = useState<number | null>(null);
  const [drivers, setDrivers] = useState<AvailableDriver[]>([]);
  const [driversLoading, setDriversLoading] = useState(true);
  const [driversError, setDriversError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [roadRoute, setRoadRoute] = useState<RoadRoute | null>(null);
  const [routeLoading, setRouteLoading] = useState(false);

  const straightLineDistanceKm = pickupLocation && destinationLocation
    ? haversineDistance(pickupLocation, destinationLocation)
    : 0;
  const distanceKm = roadRoute?.distanceKm ?? straightLineDistanceKm;

  const routePoints = useMemo(
    () => roadRoute?.geometry.length
      ? roadRoute.geometry.map(([lat, lng]) => ({ lat, lng }))
      : [pickupLocation, destinationLocation].filter((point): point is RoutePoint => point !== null),
    [destinationLocation, pickupLocation, roadRoute],
  );

  const fetchDrivers = useCallback(async ({ showLoading = false }: { showLoading?: boolean } = {}) => {
    if (showLoading) setDriversLoading(true);
    const { data, error } = await supabase
      .from('couriers')
      .select('id, name, current_lat, current_lng')
      .eq('is_available', true)
      .eq('status', 'ACTIVE')
      .not('current_lat', 'is', null)
      .not('current_lng', 'is', null);

    if (error) {
      console.error('Gagal mengambil lokasi driver:', error);
      setDriversError('Lokasi kurir belum dapat dimuat. Coba lagi.');
      setDriversLoading(false);
      return;
    }

    setDriversError(null);
    const availableDrivers = (data ?? []).flatMap((driver) => {
      if (driver.current_lat == null || driver.current_lng == null) return [];
      return [{
        id: driver.id,
        name: driver.name,
        lat: Number(driver.current_lat),
        lng: Number(driver.current_lng),
      }];
    });
    setDrivers(availableDrivers);
    setDriversLoading(false);
  }, []);

  useEffect(() => {
    void fetchDrivers({ showLoading: true });

    const channel = supabase
      .channel('courier-availability-map')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'couriers' }, (payload) => {
        if (payload.eventType === 'DELETE') {
          setDrivers((current) => current.filter((driver) => driver.id !== payload.old.id));
          return;
        }

        const updated = payload.new as {
          id: string;
          name: string;
          current_lat: number | null;
          current_lng: number | null;
          is_available: boolean;
          status: string;
        };
        const isAvailable = updated.is_available
          && updated.status === 'ACTIVE'
          && updated.current_lat != null
          && updated.current_lng != null;

        setDrivers((current) => {
          const withoutUpdated = current.filter((driver) => driver.id !== updated.id);
          if (!isAvailable) return withoutUpdated;
          return [
            ...withoutUpdated,
            {
              id: updated.id,
              name: updated.name || 'Driver',
              lat: Number(updated.current_lat),
              lng: Number(updated.current_lng),
            },
          ];
        });
      })
      .subscribe();

    const refreshInterval = window.setInterval(() => { void fetchDrivers(); }, 15000);
    return () => {
      window.clearInterval(refreshInterval);
      supabase.removeChannel(channel);
    };
  }, [fetchDrivers]);

  useEffect(() => {
    if (!pickupLocation || !destinationLocation) {
      setRoadRoute(null);
      setRouteLoading(false);
      return;
    }

    const controller = new AbortController();
    setRouteLoading(true);
    getRoadRoute(pickupLocation, destinationLocation, controller.signal)
      .then((route) => setRoadRoute(route))
      .catch((error: unknown) => {
        if ((error as { name?: string })?.name !== 'AbortError') {
          console.warn('Gagal mengambil rute jalan:', error);
          setRoadRoute(null);
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setRouteLoading(false);
      });

    return () => controller.abort();
  }, [destinationLocation, pickupLocation]);

  const nearbyDrivers = useMemo(() => {
    if (!pickupLocation) return drivers;
    return drivers.filter((driver) => haversineDistance(pickupLocation, driver) <= 10);
  }, [drivers, pickupLocation]);

  const handleGps = useCallback(() => {
    if (!navigator.geolocation) {
      toast({
        title: 'GPS tidak tersedia',
        description: 'Perangkat atau browser ini tidak menyediakan akses lokasi.',
        variant: 'destructive',
      });
      return;
    }

    setGettingGps(true);
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        const location = {
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        };
        setPickupLocation(location);
        setPickupAddress('Memuat alamat...');
        setMapMode('destination');
        setGpsAccuracy(Math.round(position.coords.accuracy));
        setGettingGps(false);
        setGeocoding('pickup');

        try {
          const result = await reverseGeocode(location.lat, location.lng);
          setPickupAddress(result ? formatAddressSummary(result) : 'Lokasi saya saat ini');
        } catch {
          setPickupAddress('Lokasi saya saat ini');
        } finally {
          setGeocoding(null);
        }
      },
      (error) => {
        setGettingGps(false);
        const description = error.code === error.PERMISSION_DENIED
          ? 'Izinkan akses lokasi pada browser untuk menggunakan GPS.'
          : 'Lokasi belum berhasil ditemukan. Coba lagi di area dengan sinyal GPS lebih baik.';
        toast({ title: 'Lokasi GPS belum tersedia', description, variant: 'destructive' });
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  }, []);

  const handleMapSelect = async (point: RoutePoint) => {
    const selectedMode = mapMode;
    if (selectedMode === 'pickup') {
      setPickupLocation(point);
      setPickupAddress(`${point.lat.toFixed(5)}, ${point.lng.toFixed(5)}`);
      setMapMode('destination');
    } else {
      setDestinationLocation(point);
      setDestinationAddress(`${point.lat.toFixed(5)}, ${point.lng.toFixed(5)}`);
    }

    setGeocoding(selectedMode);
    try {
      const result = await reverseGeocode(point.lat, point.lng);
      const address = result ? formatAddressSummary(result) : `${point.lat.toFixed(5)}, ${point.lng.toFixed(5)}`;
      if (selectedMode === 'pickup') setPickupAddress(address);
      else setDestinationAddress(address);
    } finally {
      setGeocoding(null);
    }
  };

  useEffect(() => {
    if (distanceKm > 0) setDistanceBand(getDistanceBand(distanceKm));
  }, [distanceKm]);

  const estimate = useMemo(() => {
    const base = distanceOptions.find((option) => option.value === distanceBand)?.price ?? 8000;
    const weightFee = Math.max(0, Number(weight || 0) - 2) * 2500;
    const codFee = cod ? 2000 : 0;
    return { base, weightFee, codFee, total: base + weightFee + codFee };
  }, [cod, distanceBand, weight]);

  const canContinue = Boolean(
    pickupLocation
    && destinationLocation
    && pickupAddress.trim()
    && destinationAddress.trim()
    && recipientName.trim()
    && recipientPhone.trim()
    && packageType.trim(),
  );

  const handleContinue = async () => {
    if (!canContinue) {
      toast({ title: 'Lengkapi detail pengiriman', description: 'Pilih titik pickup dan tujuan di peta, lalu lengkapi alamat, penerima, dan barang.', variant: 'destructive' });
      return;
    }
    if (!user) {
      navigate('/auth');
      return;
    }
    setSubmitting(true);
    try {
      const { data, error } = await supabase.rpc('create_courier_order' as never, {
        p_request: {
          mode,
          pickup_lat: pickupLocation!.lat,
          pickup_lng: pickupLocation!.lng,
          pickup_address: pickupAddress,
          destination_lat: destinationLocation!.lat,
          destination_lng: destinationLocation!.lng,
          destination_address: destinationAddress,
          recipient_name: recipientName,
          recipient_phone: recipientPhone,
          package_type: packageType,
          weight_kg: Number(weight || 1),
          cod,
          notes,
          scheduled,
        },
      } as never);
      if (error) throw error;
      const result = data as { order_id?: string; dispatch_status?: string } | null;
      if (!result?.order_id) throw new Error('Order kurir tidak terbentuk');
      toast({
        title: 'Pesanan kurir dibuat',
        description: result.dispatch_status === 'OFFERED' ? 'Mencari kurir terdekat.' : 'Pesanan menunggu kurir yang tersedia.',
      });
      navigate(`/orders/${result.order_id}/tracking`);
    } catch (error) {
      const errorMessage = error instanceof Error
        ? error.message
        : (error as { message?: string; details?: string } | null)?.message
          || (error as { details?: string } | null)?.details
          || 'Layanan antar belum siap. Pastikan database layanan kurir sudah diperbarui.';
      toast({
        title: 'Gagal membuat pesanan kurir',
        description: errorMessage,
        variant: 'destructive',
      });
    } finally {
      setSubmitting(false);
    }
  };

  const handlePickContact = async () => {
    const contactPicker = (typeof navigator !== 'undefined' ? navigator : null) as ContactPickerNavigator | null;
    if (!contactPicker?.contacts) {
      toast({
        title: 'Pilih kontak belum tersedia',
        description: 'Gunakan Chrome Android terbaru atau isi nama dan nomor telepon secara manual.',
        variant: 'destructive',
      });
      return;
    }

    setContactLoading(true);
    try {
      const [contact] = await contactPicker.contacts.select(['name', 'tel'], { multiple: false });
      const name = contact?.name?.[0]?.trim();
      const phone = contact?.tel?.[0]?.trim();
      if (name) setRecipientName(name);
      if (phone) setRecipientPhone(phone);
      if (name || phone) {
        toast({ title: 'Kontak dipilih', description: 'Nama dan nomor telepon penerima sudah diisi otomatis.' });
      }
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return;
      toast({ title: 'Kontak tidak dapat dibuka', description: 'Silakan isi data penerima secara manual.', variant: 'destructive' });
    } finally {
      setContactLoading(false);
    }
  };

  return (
    <div className="mobile-shell min-h-screen bg-background">
      <Header />
      <main className="px-5 pb-28 pt-5">
        <div className="mb-5 flex items-center gap-3">
          <Button variant="ghost" size="icon" className="h-9 w-9" onClick={() => navigate('/ride')}>
            <ArrowLeft className="h-4 w-4" />
            <span className="sr-only">Kembali</span>
          </Button>
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wide text-amber-600">Kirim barang langsung</p>
            <h1 className="font-heading text-xl font-bold">Kurir Barang</h1>
          </div>
        </div>

        <Card className="mb-4 border-amber-200 bg-amber-50/70 p-4 dark:border-amber-900 dark:bg-amber-950/25">
          <div className="flex gap-3">
            <Info className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
            <p className="text-xs leading-relaxed text-muted-foreground">
              Ini bukan pengiriman pesanan toko. Kurir mengambil barang dari titik pickup Anda lalu mengantarkannya langsung ke penerima. Tarif di bawah adalah estimasi awal berdasarkan jarak dan berat barang.
            </p>
          </div>
        </Card>

        <div className="space-y-4">
          <Card className="p-4">
            <div className="mb-3 flex items-center gap-2">
              <PackageCheck className="h-4 w-4 text-amber-600" />
              <h2 className="text-sm font-bold">Jenis layanan</h2>
            </div>
            <RadioGroup value={mode} onValueChange={(value) => setMode(value as CourierMode)} className="grid grid-cols-2 gap-3">
              <Label htmlFor="send" className={`flex cursor-pointer items-center gap-2 rounded-xl border p-3 text-xs ${mode === 'send' ? 'border-amber-500 bg-amber-50 dark:bg-amber-950/30' : 'border-border'}`}>
                <RadioGroupItem value="send" id="send" />
                <span><strong>Kirim barang</strong><br /><span className="text-muted-foreground">Saya mengirim</span></span>
              </Label>
              <Label htmlFor="pickup" className={`flex cursor-pointer items-center gap-2 rounded-xl border p-3 text-xs ${mode === 'pickup' ? 'border-amber-500 bg-amber-50 dark:bg-amber-950/30' : 'border-border'}`}>
                <RadioGroupItem value="pickup" id="pickup" />
                <span><strong>Ambil barang</strong><br /><span className="text-muted-foreground">Kurir mengambil</span></span>
              </Label>
            </RadioGroup>
          </Card>

          <Card className="space-y-4 p-4">
            <div className="flex items-center gap-2">
              <MapPin className="h-4 w-4 text-primary" />
              <h2 className="text-sm font-bold">Rute pengiriman</h2>
            </div>
            <div className="overflow-hidden rounded-xl border border-border/70">
              <div className="relative h-64 bg-muted">
                <MapContainer
                  center={mapCenter}
                  zoom={14}
                  scrollWheelZoom
                  style={{ height: '100%', width: '100%' }}
                  zoomControl={false}
                >
                  <TileLayer
                    attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                  />
                  <MapClickHandler onSelect={handleMapSelect} />
                  <FitRouteBounds points={routePoints} />
                  <FocusMapPoint point={pickupLocation} />
                  {pickupLocation && <Marker position={[pickupLocation.lat, pickupLocation.lng]} icon={pickupIcon} />}
                  {destinationLocation && <Marker position={[destinationLocation.lat, destinationLocation.lng]} icon={destinationIcon} />}
                  {nearbyDrivers.map((driver) => (
                    <Marker key={driver.id} position={[driver.lat, driver.lng]} icon={driverIcon} title={driver.name} />
                  ))}
                  {pickupLocation && destinationLocation && (
                    roadRoute?.geometry.length ? (
                      <Polyline
                        positions={roadRoute.geometry}
                        pathOptions={{ color: '#d97706', weight: 4, opacity: 0.9 }}
                      />
                    ) : (
                      <Polyline
                        positions={[
                          [pickupLocation.lat, pickupLocation.lng],
                          [destinationLocation.lat, destinationLocation.lng],
                        ]}
                        pathOptions={{ color: '#d97706', weight: 4, dashArray: '10, 8', opacity: 0.6 }}
                      />
                    )
                  )}
                </MapContainer>
                <div className="pointer-events-none absolute left-3 top-3 z-[400] rounded-full border border-border/60 bg-background/90 px-3 py-1.5 text-[10px] font-semibold shadow-sm backdrop-blur">
                  Tap peta untuk {mapMode === 'pickup' ? 'pilih pickup' : 'pilih tujuan'}
                </div>
                <div className="absolute right-3 top-3 z-[400] flex flex-col items-end gap-2">
                  <div className="rounded-full border border-border/60 bg-background/90 px-3 py-1.5 text-[10px] font-semibold shadow-sm backdrop-blur">
                    {driversLoading ? 'Mencari driver...' : `${nearbyDrivers.length} driver tersedia`}
                  </div>
                  <Button
                    type="button"
                    size="sm"
                    variant="secondary"
                    className="h-8 rounded-full border border-border/60 bg-background/95 px-3 text-[10px] font-semibold shadow-sm hover:bg-background"
                    onClick={handleGps}
                    disabled={gettingGps}
                  >
                    {gettingGps ? <Loader2 className="mr-1.5 h-3 w-3 animate-spin" /> : <LocateFixed className="mr-1.5 h-3 w-3 text-primary" />}
                    {gettingGps ? 'Mencari lokasi...' : 'Gunakan GPS'}
                  </Button>
                </div>
                {geocoding && (
                  <div className="absolute bottom-3 left-3 z-[400] flex items-center gap-1.5 rounded-full bg-background/90 px-3 py-1.5 text-[10px] shadow-sm">
                    <Loader2 className="h-3 w-3 animate-spin text-primary" />
                    Mengambil alamat...
                  </div>
                )}
                {driversError && (
                  <div className="absolute bottom-3 right-3 z-[400] max-w-[220px] rounded-lg border border-destructive/30 bg-background/95 p-2.5 text-[10px] shadow-sm backdrop-blur">
                    <p className="text-destructive">{driversError}</p>
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      className="mt-2 h-7 w-full text-[10px]"
                      onClick={() => void fetchDrivers({ showLoading: true })}
                    >
                      Coba lagi
                    </Button>
                  </div>
                )}
              </div>
              <div className="flex items-center justify-between gap-3 rounded-xl bg-primary/5 px-3 py-2 text-[10px] text-muted-foreground">
                <span className="flex items-center gap-1.5">
                  <Navigation className="h-3.5 w-3.5 text-primary" />
                  {pickupLocation ? `${nearbyDrivers.length} driver dalam radius 10 km dari pickup` : 'Pilih pickup untuk melihat driver terdekat'}
                </span>
                {gpsAccuracy != null && <strong className="shrink-0 text-primary">Akurasi GPS ±{gpsAccuracy} m</strong>}
              </div>
              <div className="flex items-center justify-between gap-2 border-t border-border/70 bg-card p-2">
                <button
                  type="button"
                  onClick={() => setMapMode('pickup')}
                  className={`flex flex-1 items-center gap-2 rounded-lg px-2.5 py-2 text-left text-[10px] transition ${mapMode === 'pickup' ? 'bg-emerald-50 text-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-200' : 'text-muted-foreground'}`}
                >
                  <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-emerald-500" />
                  <span><strong className="block">Pickup</strong>{pickupLocation ? 'Titik dipilih' : 'Belum dipilih'}</span>
                </button>
                <button
                  type="button"
                  onClick={() => setMapMode('destination')}
                  className={`flex flex-1 items-center gap-2 rounded-lg px-2.5 py-2 text-left text-[10px] transition ${mapMode === 'destination' ? 'bg-red-50 text-red-800 dark:bg-red-950/40 dark:text-red-200' : 'text-muted-foreground'}`}
                >
                  <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-red-500" />
                  <span><strong className="block">Tujuan</strong>{destinationLocation ? 'Titik dipilih' : 'Belum dipilih'}</span>
                </button>
              </div>
            </div>
            {distanceKm > 0 && (
              <div className="flex items-center justify-between rounded-xl bg-amber-50 px-3 py-2.5 text-xs text-amber-900 dark:bg-amber-950/30 dark:text-amber-100">
                <span className="flex items-center gap-2">
                  <Navigation className="h-3.5 w-3.5" />
                  {routeLoading ? 'Menghitung rute jalan...' : roadRoute ? 'Jarak via jalan' : 'Jarak garis lurus'}
                </span>
                <strong>{distanceKm.toFixed(1)} km</strong>
              </div>
            )}
            <div className="space-y-3">
              <div>
                <Label htmlFor="courier-pickup" className="mb-1.5 block text-xs text-muted-foreground">Lokasi pengambilan</Label>
                <Input id="courier-pickup" value={pickupAddress} onChange={(event) => setPickupAddress(event.target.value)} placeholder="Contoh: Pasar Desa Sukamaju" />
              </div>
              <div>
                <Label htmlFor="courier-destination" className="mb-1.5 block text-xs text-muted-foreground">Lokasi tujuan</Label>
                <Input id="courier-destination" value={destinationAddress} onChange={(event) => setDestinationAddress(event.target.value)} placeholder="Contoh: Jl. Merdeka No. 10" />
              </div>
            </div>
          </Card>

          <Card className="space-y-4 p-4">
            <div className="flex items-center gap-2">
              <UserRound className="h-4 w-4 text-primary" />
              <h2 className="text-sm font-bold">Detail penerima</h2>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <Label htmlFor="recipient-name" className="mb-1.5 block text-xs text-muted-foreground">Nama penerima</Label>
                <Input id="recipient-name" value={recipientName} onChange={(event) => setRecipientName(event.target.value)} placeholder="Nama lengkap" autoComplete="name" />
              </div>
              <div>
                <Label htmlFor="recipient-phone" className="mb-1.5 block text-xs text-muted-foreground">Nomor telepon</Label>
                <Input id="recipient-phone" value={recipientPhone} onChange={(event) => setRecipientPhone(event.target.value)} placeholder="08xxxxxxxxxx" inputMode="tel" autoComplete="tel" />
              </div>
            </div>
            <Button
              type="button"
              variant="outline"
              className="h-10 w-full rounded-xl border-primary/30 text-xs font-semibold text-primary hover:bg-primary/5"
              onClick={handlePickContact}
              disabled={contactLoading}
            >
              {contactLoading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <ContactRound className="mr-2 h-4 w-4" />}
              {contactLoading ? 'Membuka kontak...' : 'Pilih dari kontak'}
            </Button>
            <p className="text-[10px] leading-relaxed text-muted-foreground">
              Data kontak hanya dipakai untuk mengisi pesanan ini dan tidak disimpan tanpa konfirmasi Anda.
            </p>
          </Card>

          <Card className="space-y-4 p-4">
            <div className="flex items-center gap-2">
              <Box className="h-4 w-4 text-primary" />
              <h2 className="text-sm font-bold">Detail barang</h2>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <Label htmlFor="package-type" className="mb-1.5 block text-xs text-muted-foreground">Jenis barang</Label>
                <Input id="package-type" value={packageType} onChange={(event) => setPackageType(event.target.value)} placeholder="Contoh: makanan" />
              </div>
              <div>
                <Label htmlFor="weight" className="mb-1.5 block text-xs text-muted-foreground">Perkiraan berat (kg)</Label>
                <Input id="weight" value={weight} onChange={(event) => setWeight(event.target.value.replace(/[^\d.]/g, ''))} inputMode="decimal" />
              </div>
            </div>
            <div>
              <Label htmlFor="distance" className="mb-1.5 block text-xs text-muted-foreground">Jarak dari peta</Label>
              <div id="distance" className="flex h-10 items-center rounded-md border border-input bg-muted/40 px-3 text-sm text-muted-foreground">
                {distanceKm > 0 ? `${distanceKm.toFixed(1)} km · ${distanceOptions.find((option) => option.value === distanceBand)?.label}` : 'Pilih pickup dan tujuan di peta'}
              </div>
            </div>
            <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-border p-3 text-xs">
              <input type="checkbox" checked={cod} onChange={(event) => setCod(event.target.checked)} className="h-4 w-4 accent-primary" />
              <span><strong>Aktifkan COD</strong><br /><span className="text-muted-foreground">Biaya layanan COD ditambahkan ke estimasi.</span></span>
            </label>
            <Textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Catatan untuk kurir (opsional)" className="min-h-[70px]" />
          </Card>

          <Card className="p-4">
            <button type="button" onClick={() => setScheduled((value) => !value)} className="flex w-full items-center gap-3 text-left">
              <CalendarDays className="h-4 w-4 text-primary" />
              <span className="flex-1 text-xs font-semibold">Jadwalkan pengambilan</span>
              <span className={`flex h-5 w-5 items-center justify-center rounded-full border ${scheduled ? 'border-primary bg-primary text-primary-foreground' : 'border-muted-foreground/40'}`}>
                {scheduled && <Check className="h-3 w-3" />}
              </span>
            </button>
            {scheduled && <p className="mt-2 pl-7 text-[10px] text-muted-foreground">Jadwal spesifik dapat dipilih saat dispatch kurir diaktifkan.</p>}
          </Card>
        </div>

        <div className="mobile-action-safe mt-5 mb-4 rounded-2xl border border-border/70 bg-card p-4 shadow-lg">
          <div className="mb-3 flex items-center justify-between">
            <div>
              <p className="text-[10px] text-muted-foreground">Estimasi biaya layanan</p>
              <p className="font-heading text-xl font-bold text-primary">Rp{estimate.total.toLocaleString('id-ID')}</p>
            </div>
            <div className="text-right text-[10px] text-muted-foreground">
              <p>Jarak {distanceOptions.find((option) => option.value === distanceBand)?.label}</p>
              {estimate.weightFee > 0 && <p>Tambahan berat Rp{estimate.weightFee.toLocaleString('id-ID')}</p>}
              {estimate.codFee > 0 && <p>COD Rp{estimate.codFee.toLocaleString('id-ID')}</p>}
            </div>
          </div>
          <Separator className="mb-3" />
          <Button className="h-11 w-full rounded-xl font-bold" onClick={handleContinue} disabled={submitting}>
            {submitting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
            {submitting ? 'Membuat pesanan...' : 'Buat pesanan kurir'}
          </Button>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}
