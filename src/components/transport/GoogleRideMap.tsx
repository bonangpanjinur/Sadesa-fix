import { useEffect, useRef, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { isGoogleMapsRideEnabled, loadGoogleMaps } from '@/lib/googleMaps';
import { CircleMarker, MapContainer, Marker, Polyline, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

type Point = { lat: number; lng: number };

interface DriverPoint extends Point {
  id: string;
}

interface GoogleRideMapProps {
  center: Point;
  pickupLocation: Point | null;
  destinationLocation: Point | null;
  drivers?: DriverPoint[];
  nearestDriverId?: string;
  route?: [number, number][];
  mode: 'pickup' | 'destination';
  onMapClick: (point: Point) => void;
  onReady?: () => void;
}

const DEFAULT_CENTER = { lat: -7.3274, lng: 108.2207 };
const hasGoogleMapsKey = isGoogleMapsRideEnabled();
const motorIcon = (isNearest = false) => L.divIcon({
  className: 'courier-motor-marker',
  html: `<span style="display:flex;align-items:center;justify-content:center;width:${isNearest ? 38 : 32}px;height:${isNearest ? 38 : 32}px;border-radius:9999px;background:${isNearest ? '#f59e0b' : '#2563eb'};border:3px solid white;box-shadow:0 2px 8px rgba(0,0,0,.3);font-size:${isNearest ? 21 : 18}px">🏍️</span>`,
  iconSize: [isNearest ? 38 : 32, isNearest ? 38 : 32],
  iconAnchor: [isNearest ? 19 : 16, isNearest ? 19 : 16],
});

function OpenStreetMapClickHandler({ onMapClick }: { onMapClick: (point: Point) => void }) {
  useMapEvents({
    click: (event) => onMapClick({ lat: event.latlng.lat, lng: event.latlng.lng }),
  });
  return null;
}

function OpenStreetMapViewport({ pickupLocation, destinationLocation }: Pick<GoogleRideMapProps, 'pickupLocation' | 'destinationLocation'>) {
  const map = useMap();
  useEffect(() => {
    const points = [pickupLocation, destinationLocation].filter((point): point is Point => point !== null);
    if (points.length > 1) {
      map.fitBounds(L.latLngBounds(points.map((point) => [point.lat, point.lng])), { padding: [40, 40], maxZoom: 16 });
    } else if (points.length === 1) {
      map.setView([points[0].lat, points[0].lng], 15, { animate: true });
    }
  }, [destinationLocation, map, pickupLocation]);
  return null;
}

function OpenStreetMapRideFallback({
  center,
  pickupLocation,
  destinationLocation,
  drivers,
  route,
  onMapClick,
  nearestDriverId,
}: GoogleRideMapProps) {
  return (
    <div className="relative h-full min-h-[320px] w-full">
      <MapContainer center={[center.lat, center.lng]} zoom={14} className="h-full min-h-[320px] w-full" scrollWheelZoom zoomControl>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <OpenStreetMapClickHandler onMapClick={onMapClick} />
        <OpenStreetMapViewport pickupLocation={pickupLocation} destinationLocation={destinationLocation} />
        {pickupLocation && <CircleMarker center={[pickupLocation.lat, pickupLocation.lng]} radius={11} pathOptions={{ color: '#ffffff', weight: 3, fillColor: '#10b981', fillOpacity: 1 }} />}
        {destinationLocation && <CircleMarker center={[destinationLocation.lat, destinationLocation.lng]} radius={11} pathOptions={{ color: '#ffffff', weight: 3, fillColor: '#ef4444', fillOpacity: 1 }} />}
        {drivers.map((driver) => {
          const isNearest = driver.id === nearestDriverId;
          return (
            <Marker key={driver.id} position={[driver.lat, driver.lng]} icon={motorIcon(isNearest)} />
          );
        })}
        {route.length > 1 && <Polyline positions={route} pathOptions={{ color: '#059669', weight: 4, opacity: 0.85 }} />}
      </MapContainer>
    </div>
  );
}

export function GoogleRideMap({
  center,
  pickupLocation,
  destinationLocation,
  drivers = [],
  nearestDriverId,
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
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>(hasGoogleMapsKey ? 'loading' : 'error');

  onMapClickRef.current = onMapClick;

  useEffect(() => {
    let disposed = false;
    if (!hasGoogleMapsKey) return;

    loadGoogleMaps().then(() => {
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
      console.warn('Google Maps tidak tersedia, menggunakan OpenStreetMap:', error);
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

    const addMarker = (point: Point, color: string, title: string, isNearest = false) => {
      const marker = new google.maps.Marker({
        map,
        position: point,
        ...(title === 'Driver' ? {} : {
          title,
          label: { text: title === 'Pickup' ? 'P' : 'T', color: '#ffffff', fontWeight: '700' },
        }),
        icon: title === 'Driver'
          ? { url: '/motor-icon.png', scaledSize: new google.maps.Size(isNearest ? 42 : 36, isNearest ? 42 : 36), anchor: new google.maps.Point(isNearest ? 21 : 18, isNearest ? 21 : 18) }
          : { path: google.maps.SymbolPath.CIRCLE, scale: 11, fillColor: color, fillOpacity: 1, strokeColor: '#ffffff', strokeWeight: 2 },
      });
      markersRef.current.push(marker);
    };

    if (pickupLocation) addMarker(pickupLocation, '#10b981', 'Pickup');
    if (destinationLocation) addMarker(destinationLocation, '#ef4444', 'Tujuan');
    drivers.forEach((driver) => addMarker(driver, driver.id === nearestDriverId ? '#f59e0b' : '#2563eb', 'Driver', driver.id === nearestDriverId));

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
  }, [destinationLocation, drivers, nearestDriverId, pickupLocation, route, status]);

  return (
    <div className="relative h-full min-h-[320px] w-full">
      {status === 'error' ? (
        <OpenStreetMapRideFallback {...{ center, pickupLocation, destinationLocation, drivers, nearestDriverId, route, mode, onMapClick }} />
      ) : (
        <>
          <div ref={mapElement} className="h-full min-h-[320px] w-full" />
          {status === 'loading' && (
            <div className="absolute inset-0 flex items-center justify-center bg-muted/80">
              <div className="flex items-center gap-2 rounded-full bg-background px-4 py-2 text-xs shadow">
                <Loader2 className="h-4 w-4 animate-spin text-primary" /> Memuat Google Maps...
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
