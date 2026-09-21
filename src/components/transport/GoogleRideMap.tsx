import { useEffect, useRef, useState } from 'react';
import { AlertCircle, Loader2, MapPin } from 'lucide-react';
import { Loader } from '@googlemaps/js-api-loader';
import { Card } from '@/components/ui/card';

type Point = { lat: number; lng: number };

interface DriverPoint extends Point {
  id: string;
  name: string;
}

interface GoogleRideMapProps {
  center: Point;
  pickupLocation: Point | null;
  destinationLocation: Point | null;
  drivers?: DriverPoint[];
  route?: [number, number][];
  mode: 'pickup' | 'destination';
  onMapClick: (point: Point) => void;
  onReady?: () => void;
}

const DEFAULT_CENTER = { lat: -7.3274, lng: 108.2207 };

export function GoogleRideMap({
  center,
  pickupLocation,
  destinationLocation,
  drivers = [],
  route = [],
  mode,
  onMapClick,
  onReady,
}: GoogleRideMapProps) {
  const mapElement = useRef<HTMLDivElement>(null);
  const mapRef = useRef<google.maps.Map | null>(null);
  const markersRef = useRef<google.maps.Marker[]>([]);
  const routeRef = useRef<google.maps.Polyline | null>(null);
  const onMapClickRef = useRef(onMapClick);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');

  onMapClickRef.current = onMapClick;

  useEffect(() => {
    let disposed = false;
    const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string | undefined;

    if (!apiKey) {
      setStatus('error');
      return;
    }

    const loader = new Loader({ apiKey, version: 'weekly', libraries: ['places'] });
    loader.load().then(() => {
      if (disposed || !mapElement.current) return;
      const map = new google.maps.Map(mapElement.current, {
        center: DEFAULT_CENTER,
        zoom: 14,
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: false,
        clickableIcons: false,
        gestureHandling: 'greedy',
      });
      mapRef.current = map;
      map.addListener('click', (event: google.maps.MapMouseEvent) => {
        if (event.latLng) onMapClickRef.current({ lat: event.latLng.lat(), lng: event.latLng.lng() });
      });
      setStatus('ready');
      onReady?.();
    }).catch((error: unknown) => {
      console.error('Google Maps failed to load:', error);
      if (!disposed) setStatus('error');
    });

    return () => {
      disposed = true;
      markersRef.current.forEach((marker) => marker.setMap(null));
      routeRef.current?.setMap(null);
      mapRef.current = null;
    };
  }, [onReady]);

  useEffect(() => {
    if (!mapRef.current) return;
    mapRef.current.setCenter(center);
  }, [center]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || status !== 'ready') return;

    markersRef.current.forEach((marker) => marker.setMap(null));
    markersRef.current = [];

    const addMarker = (point: Point, color: string, title: string) => {
      const marker = new google.maps.Marker({
        map,
        position: point,
        title,
        label: { text: title === 'Pickup' ? 'P' : title === 'Tujuan' ? 'T' : 'D', color: '#ffffff', fontWeight: '700' },
        icon: { path: google.maps.SymbolPath.CIRCLE, scale: title === 'Driver' ? 8 : 11, fillColor: color, fillOpacity: 1, strokeColor: '#ffffff', strokeWeight: 2 },
      });
      markersRef.current.push(marker);
    };

    if (pickupLocation) addMarker(pickupLocation, '#10b981', 'Pickup');
    if (destinationLocation) addMarker(destinationLocation, '#ef4444', 'Tujuan');
    drivers.forEach((driver) => addMarker(driver, '#2563eb', 'Driver'));

    routeRef.current?.setMap(null);
    routeRef.current = route.length > 1
      ? new google.maps.Polyline({ map, path: route.map(([lat, lng]) => ({ lat, lng })), strokeColor: '#059669', strokeOpacity: 0.85, strokeWeight: 4 })
      : null;

    const points = [pickupLocation, destinationLocation].filter((point): point is Point => point !== null);
    if (points.length > 1) {
      const bounds = new google.maps.LatLngBounds();
      points.forEach((point) => bounds.extend(point));
      map.fitBounds(bounds, 50);
    } else if (points.length === 1) {
      map.setCenter(points[0]);
      map.setZoom(15);
    }
  }, [destinationLocation, drivers, pickupLocation, route, status]);

  return (
    <div className="relative h-full min-h-[320px] w-full">
      <div ref={mapElement} className="h-full min-h-[320px] w-full" />
      {status === 'loading' && (
        <div className="absolute inset-0 flex items-center justify-center bg-muted/80">
          <div className="flex items-center gap-2 rounded-full bg-background px-4 py-2 text-xs shadow">
            <Loader2 className="h-4 w-4 animate-spin text-primary" /> Memuat Google Maps...
          </div>
        </div>
      )}
      {status === 'error' && (
        <Card className="absolute inset-4 flex items-center justify-center border-amber-200 bg-amber-50 p-4 text-amber-900">
          <div className="max-w-sm text-center">
            <AlertCircle className="mx-auto mb-2 h-6 w-6 text-amber-600" />
            <p className="text-sm font-semibold">Google Maps belum dikonfigurasi</p>
            <p className="mt-1 text-xs leading-relaxed">Tambahkan VITE_GOOGLE_MAPS_API_KEY pada environment aplikasi untuk mengaktifkan peta.</p>
            <p className="mt-2 flex items-center justify-center gap-1 text-[10px] text-amber-700"><MapPin className="h-3 w-3" /> Mode aktif: pilih {mode === 'pickup' ? 'pickup' : 'tujuan'}</p>
          </div>
        </Card>
      )}
    </div>
  );
}
