import { MapContainer, Marker, Polyline, TileLayer } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';

const pickupIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
  shadowUrl: markerShadow,
  iconSize: [20, 33],
  iconAnchor: [10, 33],
  popupAnchor: [1, -28],
  shadowSize: [33, 33],
});

const destinationIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
  shadowUrl: markerShadow,
  iconSize: [20, 33],
  iconAnchor: [10, 33],
  popupAnchor: [1, -28],
  shadowSize: [33, 33],
});

interface CourierRideRouteMapProps {
  pickupLat: number;
  pickupLng: number;
  destinationLat: number;
  destinationLng: number;
  roadRoute: [number, number][];
  routeFallback: boolean;
}

export function CourierRideRouteMap({
  pickupLat,
  pickupLng,
  destinationLat,
  destinationLng,
  roadRoute,
  routeFallback,
}: CourierRideRouteMapProps) {
  return (
    <MapContainer
      center={[(pickupLat + destinationLat) / 2, (pickupLng + destinationLng) / 2]}
      zoom={13}
      style={{ height: '100%', width: '100%' }}
      zoomControl={false}
      dragging={false}
      scrollWheelZoom={false}
      doubleClickZoom={false}
      attributionControl={false}
    >
      <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
      <Marker position={[pickupLat, pickupLng]} icon={pickupIcon} />
      <Marker position={[destinationLat, destinationLng]} icon={destinationIcon} />
      <Polyline
        positions={roadRoute}
        pathOptions={{
          color: routeFallback ? 'hsl(45,90%,45%)' : 'hsl(160,84%,39%)',
          weight: 3,
          dashArray: routeFallback ? '8, 6' : undefined,
          opacity: 0.8,
        }}
      />
    </MapContainer>
  );
}
