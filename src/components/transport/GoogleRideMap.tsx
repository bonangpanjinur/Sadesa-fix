import { useEffect } from 'react';
import { CircleMarker, MapContainer, Marker, Polyline, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

type Point = { lat: number; lng: number };
interface DriverPoint extends Point { id: string; }
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

const motorIcon = (isNearest = false) => L.divIcon({
  className: 'courier-motor-marker',
  html: `<span style="display:flex;align-items:center;justify-content:center;width:${isNearest ? 38 : 32}px;height:${isNearest ? 38 : 32}px;border-radius:9999px;background:${isNearest ? '#f59e0b' : '#2563eb'};border:3px solid white;box-shadow:0 2px 8px rgba(0,0,0,.3);font-size:${isNearest ? 21 : 18}px">🏍️</span>`,
  iconSize: [isNearest ? 38 : 32, isNearest ? 38 : 32],
  iconAnchor: [isNearest ? 19 : 16, isNearest ? 19 : 16],
});

function MapClickHandler({ onMapClick }: { onMapClick: (point: Point) => void }) {
  useMapEvents({ click: (event) => onMapClick({ lat: event.latlng.lat, lng: event.latlng.lng }) });
  return null;
}

function MapViewport({ pickupLocation, destinationLocation }: Pick<GoogleRideMapProps, 'pickupLocation' | 'destinationLocation'>) {
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

function MapReady({ onReady }: { onReady?: () => void }) {
  const map = useMap();
  useEffect(() => { onReady?.(); }, [map, onReady]);
  return null;
}

export function GoogleRideMap({
  center,
  pickupLocation,
  destinationLocation,
  drivers = [],
  nearestDriverId,
  route = [],
  onMapClick,
  onReady,
}: GoogleRideMapProps) {
  return (
    <div className="relative h-full min-h-[320px] w-full">
      <MapContainer
        center={[center.lat, center.lng]}
        zoom={14}
        className="h-full min-h-[320px] w-full"
        scrollWheelZoom
        zoomControl
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <MapClickHandler onMapClick={onMapClick} />
        <MapViewport pickupLocation={pickupLocation} destinationLocation={destinationLocation} />
        <MapReady onReady={onReady} />
        {pickupLocation && <CircleMarker center={[pickupLocation.lat, pickupLocation.lng]} radius={11} pathOptions={{ color: '#ffffff', weight: 3, fillColor: '#10b981', fillOpacity: 1 }} />}
        {destinationLocation && <CircleMarker center={[destinationLocation.lat, destinationLocation.lng]} radius={11} pathOptions={{ color: '#ffffff', weight: 3, fillColor: '#ef4444', fillOpacity: 1 }} />}
        {drivers.map((driver) => (
          <Marker key={driver.id} position={[driver.lat, driver.lng]} icon={motorIcon(driver.id === nearestDriverId)} />
        ))}
        {route.length > 1 && <Polyline positions={route} pathOptions={{ color: '#059669', weight: 4, opacity: 0.85 }} />}
      </MapContainer>
    </div>
  );
}
