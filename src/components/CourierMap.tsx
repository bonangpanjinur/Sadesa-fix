import { useCallback, useEffect, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap, Polyline } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { Loader2, Navigation, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { getRoadRoute } from '@/lib/routeCalculation';

// Fix for default marker icons in Leaflet with Vite
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';

// @ts-expect-error properti internal Leaflet tidak ada di tipe publik
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconUrl: '/motor-icon.png',
  iconRetinaUrl: '/motor-icon.png',
  shadowUrl: markerShadow,
  iconSize: [40, 40],
  iconAnchor: [20, 40],
  popupAnchor: [0, -40],
});

// Custom courier icon (motorcycle)
const courierIcon = new L.Icon({
  // Arahkan ke file gambar di folder public
  iconUrl: '/motor-icon.png', 
  
  // Sesuaikan ukuran gambar (px) agar tidak terlalu besar/kecil di layar
  iconSize: [40, 40], 
  
  // Titik Anchor (Sumbu X, Y). 
  // Bagian mana dari gambar yang menjadi "titik akurat" koordinat?
  // Jika ukurannya 40x40, titik tengah bawah (ban motor menapak jalan) adalah [20, 40]
  iconAnchor: [20, 40], 
  
  // Posisi munculnya kotak keterangan (popup) saat motor di-klik.
  // Muncul pas di atas motor (X: 0, Y: -40 ditarik ke atas)
  popupAnchor: [0, -40], 
});

// Destination icon (red)
const destinationIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
  shadowUrl: markerShadow,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41],
});

interface CourierLocation {
  id: string;
  lat: number;
  lng: number;
  lastUpdate: string;
  isAvailable: boolean;
}

interface CourierMapProps {
  courierId?: string;
  showAllCouriers?: boolean;
  height?: string;
  destinationLat?: number | null;
  destinationLng?: number | null;
  destinationLabel?: string;
  /** For merchant self-delivery: listen to order-specific broadcast */
  selfDeliveryOrderId?: string;
  /** Merchant name for self-delivery popup label */
  selfDeliveryLabel?: string;
}

const GPS_FRESHNESS_MS = 90_000;

function MapUpdater({ center }: { center: [number, number] }) {
  const map = useMap();
  useEffect(() => {
    map.setView(center, map.getZoom());
  }, [center, map]);
  return null;
}

function FitBounds({ points, onFitted }: { points: [number, number][]; onFitted: () => void }) {
  const map = useMap();
  useEffect(() => {
    if (points.length >= 2) {
      const bounds = L.latLngBounds(points.map(p => L.latLng(p[0], p[1])));
      map.fitBounds(bounds, { padding: [40, 40], maxZoom: 16 });
      onFitted();
    }
  }, [points, map, onFitted]);
  return null;
}

export function CourierMap({ courierId, showAllCouriers = false, height = '400px', destinationLat, destinationLng, destinationLabel = 'Tujuan Pengiriman', selfDeliveryOrderId, selfDeliveryLabel = 'Kurir Toko' }: CourierMapProps) {
  const [couriers, setCouriers] = useState<CourierLocation[]>([]);
  const [loading, setLoading] = useState(true);
  const [center, setCenter] = useState<[number, number]>([-6.2088, 106.8456]);
  const [hasFittedBounds, setHasFittedBounds] = useState(false);
  const [roadRoute, setRoadRoute] = useState<[number, number][]>([]);

  const hasDestination = destinationLat != null && destinationLng != null;

  // Use the road network for the buyer-facing tracking line. The old straight
  // segment could cut through buildings and fields, which made the live route
  // look inaccurate even when the courier GPS position was correct.
  useEffect(() => {
    const courier = couriers[0];
    if (!courier || !hasDestination) {
      setRoadRoute([]);
      return;
    }

    const controller = new AbortController();
    setRoadRoute([]);
    void getRoadRoute(
      { lat: courier.lat, lng: courier.lng },
      { lat: destinationLat!, lng: destinationLng! },
      controller.signal,
    ).then((route) => {
      if (!controller.signal.aborted) setRoadRoute(route?.geometry ?? []);
    }).catch((error) => {
      if (!controller.signal.aborted) {
        console.warn('Rute jalan tracking tidak tersedia:', error);
      }
    });

    return () => controller.abort();
  }, [couriers, destinationLat, destinationLng, hasDestination]);

  const fetchCouriers = useCallback(async () => {
    try {
      let query = supabase
        .from('couriers')
        .select('id, current_lat, current_lng, last_location_update, is_available')
        .not('current_lat', 'is', null)
        .not('current_lng', 'is', null);

      if (courierId) {
        query = query.eq('id', courierId);
      } else if (showAllCouriers) {
        query = query.eq('is_available', true)
          .eq('status', 'ACTIVE')
          .eq('registration_status', 'APPROVED')
          .gte('last_location_update', new Date(Date.now() - GPS_FRESHNESS_MS).toISOString());
      }

      const { data, error } = await query;
      if (error) throw error;

      const locations: CourierLocation[] = (data || []).map((c) => ({
        id: c.id,
        lat: c.current_lat!,
        lng: c.current_lng!,
        lastUpdate: c.last_location_update || '',
        isAvailable: c.is_available,
      }));

      setCouriers(locations);

      if (locations.length > 0) {
        setCenter([locations[0].lat, locations[0].lng]);
      }
    } catch (error) {
      console.error('Error fetching courier locations:', error);
    } finally {
      setLoading(false);
    }
  }, [courierId, showAllCouriers]);

  useEffect(() => {
    // For self-delivery mode, we don't fetch couriers from DB - we listen to broadcast only
    if (selfDeliveryOrderId) {
      // Try fetching merchant location as initial position
      const fetchMerchantLocation = async () => {
        if (!courierId) { setLoading(false); return; }
        const { data } = await supabase
          .from('merchants')
          .select('id, location_lat, location_lng')
          .eq('id', courierId)
          .maybeSingle();
        
        if (data?.location_lat && data?.location_lng) {
          setCouriers([{
            id: data.id,
                lat: data.location_lat,
            lng: data.location_lng,
            lastUpdate: new Date().toISOString(),
            isAvailable: true,
          }]);
          setCenter([data.location_lat, data.location_lng]);
        }
        setLoading(false);
      };
      fetchMerchantLocation();

      const channel = supabase.channel(`merchant-delivery-${selfDeliveryOrderId}`);
      channel
        .on('broadcast', { event: 'location-update' }, (payload) => {
          const data = payload.payload as { id: string; lat: number; lng: number; timestamp: string };
          setCouriers((prev) => {
            if (prev.length === 0) {
              return [{
                id: data.id,
                lat: data.lat,
                lng: data.lng,
                lastUpdate: data.timestamp,
                isAvailable: true,
              }];
            }
            return prev.map((c) => ({ ...c, lat: data.lat, lng: data.lng, lastUpdate: data.timestamp }));
          });
          setCenter([data.lat, data.lng]);
        })
        .subscribe();

      return () => { supabase.removeChannel(channel); };
    }

    // Regular courier tracking mode
    fetchCouriers();

    const channelName = courierId ? `courier-tracking-${courierId}` : 'courier-locations';
    const channel = supabase.channel(channelName);

    channel
      .on('broadcast', { event: 'location-update' }, (payload) => {
        const data = payload.payload as { id: string; lat: number; lng: number; timestamp: string };
        setCouriers((prev) => {
          const exists = prev.some((c) => c.id === data.id);
          if (exists) {
            return prev.map((c) =>
              c.id === data.id
                ? { ...c, lat: data.lat, lng: data.lng, lastUpdate: data.timestamp }
                : c
            );
          }
          return prev;
        });
        if (courierId && !hasDestination) {
          setCenter([data.lat, data.lng]);
        }
      })
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'couriers', filter: courierId ? `id=eq.${courierId}` : undefined },
        (payload) => {
          const updated = payload.new as {
            id: string;
            current_lat: number | null;
            current_lng: number | null;
            last_location_update: string | null;
            is_available: boolean;
            status: string;
            registration_status: string;
          };
          const locationIsFresh = updated.last_location_update
            ? Date.now() - new Date(updated.last_location_update).getTime() <= GPS_FRESHNESS_MS
            : false;
          if (updated.current_lat != null && updated.current_lng != null && (!showAllCouriers || (updated.is_available && updated.status === 'ACTIVE' && locationIsFresh))) {
            setCouriers((prev) =>
              prev.map((c) =>
                c.id === updated.id
                  ? { ...c, lat: updated.current_lat, lng: updated.current_lng, lastUpdate: updated.last_location_update || '', isAvailable: updated.is_available }
                  : c
              )
            );
          } else if (showAllCouriers) {
            setCouriers((prev) => prev.filter((courier) => courier.id !== updated.id));
          }
        }
      )
      .subscribe();

    // Broadcasts are ephemeral. Poll as a fallback so a passenger who opens
    // the tracking page after the last broadcast still sees movement.
    const refreshInterval = setInterval(fetchCouriers, 10000);

    return () => {
      supabase.removeChannel(channel);
      clearInterval(refreshInterval);
    };
  }, [courierId, showAllCouriers, selfDeliveryOrderId, hasDestination, selfDeliveryLabel, fetchCouriers]);

  // Compute fit-bounds points
  const fitPoints: [number, number][] = [];
  if (couriers.length > 0) fitPoints.push([couriers[0].lat, couriers[0].lng]);
  if (hasDestination) fitPoints.push([destinationLat!, destinationLng!]);

  if (loading) {
    return (
      <div className="flex items-center justify-center bg-muted rounded-xl" style={{ height }}>
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="relative rounded-xl overflow-hidden border border-border" style={{ height }}>
      <MapContainer
        center={center}
        zoom={14}
        style={{ height: '100%', width: '100%' }}
        zoomControl={false}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        {/* Auto-fit when we have courier + destination */}
        {fitPoints.length >= 2 && !hasFittedBounds ? (
          <FitBounds points={fitPoints} onFitted={() => setHasFittedBounds(true)} />
        ) : (
          <MapUpdater center={center} />
        )}

        {/* Courier markers */}
        {couriers.map((courier) => (
          // Public map markers reveal location only; identity appears in the assigned-ride panel.
          <Marker key={courier.id} position={[courier.lat, courier.lng]} icon={courierIcon} />
        ))}

        {/* Destination marker */}
        {hasDestination && (
          <Marker position={[destinationLat!, destinationLng!]} icon={destinationIcon}>
            <Popup>
              <div className="text-sm">
                <p className="font-bold">📍 {destinationLabel}</p>
              </div>
            </Popup>
          </Marker>
        )}

        {/* Road-following route between courier and destination */}
        {roadRoute.length > 1 ? (
          <Polyline
            positions={roadRoute}
            pathOptions={{ color: 'hsl(var(--primary))', weight: 4, opacity: 0.85 }}
          />
        ) : null}
      </MapContainer>

      {/* Refresh button */}
      <Button
        size="icon"
        variant="secondary"
        className="absolute top-3 right-3 z-[1000] shadow-md"
        onClick={() => { if (!selfDeliveryOrderId) { setLoading(true); fetchCouriers(); } }}
      >
        <RefreshCw className="h-4 w-4" />
      </Button>

      {/* Live indicator */}
      {couriers.length > 0 && (courierId || selfDeliveryOrderId) && (
        <div className="absolute top-3 left-3 z-[1000] bg-background/90 backdrop-blur-sm px-3 py-1.5 rounded-full text-xs font-medium shadow-md border border-border flex items-center gap-2">
          <span className="relative flex h-2.5 w-2.5">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
            <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-emerald-500" />
          </span>
          Live
        </div>
      )}

      {/* Courier count badge */}
      {showAllCouriers && couriers.length > 0 && (
        <div className="absolute bottom-3 left-3 z-[1000] bg-background/90 backdrop-blur-sm px-3 py-1.5 rounded-full text-sm font-medium shadow-md border border-border">
          <Navigation className="h-3.5 w-3.5 inline mr-1.5 text-primary" />
          {couriers.length} kurir aktif
        </div>
      )}
    </div>
  );
}
