import { useEffect, useMemo, useState } from 'react';
import { ArrowLeft, Box, CalendarDays, Check, ContactRound, Info, Loader2, MapPin, Navigation, PackageCheck, UserRound } from 'lucide-react';
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

type CourierMode = 'send' | 'pickup';
type DistanceBand = 'near' | 'medium' | 'far';
type RoutePoint = { lat: number; lng: number };
type DeviceContact = { name?: string[]; tel?: string[] };
type ContactPickerNavigator = Navigator & {
  contacts?: {
    select: (properties: Array<'name' | 'tel'>, options?: { multiple?: boolean }) => Promise<DeviceContact[]>;
  };
};

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

export default function CourierBookingPage() {
  const navigate = useNavigate();
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

  const distanceKm = pickupLocation && destinationLocation
    ? haversineDistance(pickupLocation, destinationLocation)
    : 0;

  const routePoints = useMemo(
    () => [pickupLocation, destinationLocation].filter((point): point is RoutePoint => point !== null),
    [destinationLocation, pickupLocation],
  );

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

  const handleContinue = () => {
    if (!canContinue) {
      toast({ title: 'Lengkapi detail pengiriman', description: 'Pilih titik pickup dan tujuan di peta, lalu lengkapi alamat, penerima, dan barang.', variant: 'destructive' });
      return;
    }
    toast({ title: 'Detail kurir tersimpan', description: 'Pencarian mitra kurir akan tersedia setelah dispatch kurir diaktifkan.' });
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
            <p className="text-[10px] font-bold uppercase tracking-wide text-amber-600">Layanan antar</p>
            <h1 className="font-heading text-xl font-bold">Kurir Barang</h1>
          </div>
        </div>

        <Card className="mb-4 border-amber-200 bg-amber-50/70 p-4 dark:border-amber-900 dark:bg-amber-950/25">
          <div className="flex gap-3">
            <Info className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
            <p className="text-xs leading-relaxed text-muted-foreground">
              Isi detail barang dengan lengkap. Tarif di bawah adalah estimasi awal berdasarkan jarak dan berat barang.
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
                  {pickupLocation && <Marker position={[pickupLocation.lat, pickupLocation.lng]} icon={pickupIcon} />}
                  {destinationLocation && <Marker position={[destinationLocation.lat, destinationLocation.lng]} icon={destinationIcon} />}
                  {pickupLocation && destinationLocation && (
                    <Polyline
                      positions={[
                        [pickupLocation.lat, pickupLocation.lng],
                        [destinationLocation.lat, destinationLocation.lng],
                      ]}
                      pathOptions={{ color: '#d97706', weight: 4, dashArray: '10, 8', opacity: 0.85 }}
                    />
                  )}
                </MapContainer>
                <div className="pointer-events-none absolute left-3 top-3 z-[400] rounded-full border border-border/60 bg-background/90 px-3 py-1.5 text-[10px] font-semibold shadow-sm backdrop-blur">
                  Tap peta untuk {mapMode === 'pickup' ? 'pilih pickup' : 'pilih tujuan'}
                </div>
                {geocoding && (
                  <div className="absolute bottom-3 left-3 z-[400] flex items-center gap-1.5 rounded-full bg-background/90 px-3 py-1.5 text-[10px] shadow-sm">
                    <Loader2 className="h-3 w-3 animate-spin text-primary" />
                    Mengambil alamat...
                  </div>
                )}
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
                <span className="flex items-center gap-2"><Navigation className="h-3.5 w-3.5" /> Jarak garis lurus</span>
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

        <div className="sticky bottom-20 mt-5 rounded-2xl border border-border/70 bg-card/95 p-4 shadow-lg backdrop-blur-xl">
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
          <Button className="h-11 w-full rounded-xl font-bold" onClick={handleContinue}>
            Tinjau pesanan kurir
          </Button>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}