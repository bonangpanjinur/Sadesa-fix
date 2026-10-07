import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { MapContainer, Marker, Popup, TileLayer, useMap } from 'react-leaflet';
import L from 'leaflet';
import { ExternalLink, MapPin, Navigation, Search, Star, Store } from 'lucide-react';
import type { Product } from '@/types';
import { Button } from '@/components/ui/button';
import { calculateDistance } from '@/hooks/useUserLocation';

interface ProductMerchantMapProps {
  products: Product[];
  center: { lat: number; lng: number };
  userLocation?: { lat: number; lng: number } | null;
}

interface MerchantPoint {
  id: string;
  name: string;
  address?: string | null;
  imageUrl?: string | null;
  slug?: string | null;
  ratingAvg: number;
  ratingCount: number;
  reviews: NonNullable<Product['merchantReviews']>;
  lat: number;
  lng: number;
  productCount: number;
  isOpen?: boolean;
  distanceKm: number;
}

interface MerchantCluster {
  id: string;
  members: MerchantPoint[];
  lat: number;
  lng: number;
}

function escapeHtml(value: string) {
  return value.replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    "'": '&#39;',
    '"': '&quot;',
  })[character] || character);
}

function createMerchantIcon(merchant: MerchantPoint) {
  const safeName = escapeHtml(merchant.name);
  const safeImageUrl = merchant.imageUrl ? escapeHtml(merchant.imageUrl) : '';
  const image = safeImageUrl
    ? `<img src="${safeImageUrl}" alt="" class="merchant-map-marker__image" />`
    : `<span class="merchant-map-marker__fallback">${escapeHtml(merchant.name.charAt(0).toUpperCase())}</span>`;

  return L.divIcon({
    className: 'merchant-map-marker-wrapper',
    html: `<div class="merchant-map-marker" title="${safeName}">${image}<span class="merchant-map-marker__label">${safeName}</span></div>`,
    iconSize: [150, 48],
    iconAnchor: [24, 24],
    popupAnchor: [0, -24],
  });
}

function createClusterIcon(count: number) {
  return L.divIcon({
    className: 'merchant-map-cluster-wrapper',
    html: `<div class="merchant-map-cluster">${count}</div>`,
    iconSize: [44, 44],
    iconAnchor: [22, 22],
  });
}

function formatDistance(distanceKm: number) {
  if (!Number.isFinite(distanceKm)) return 'Jarak tidak tersedia';
  if (distanceKm < 1) return `${Math.round(distanceKm * 1000)} m dari kamu`;
  return `${distanceKm.toFixed(1)} km dari kamu`;
}

function openMerchantNavigation(merchant: MerchantPoint, userLocation?: { lat: number; lng: number } | null) {
  const params = new URLSearchParams({
    api: '1',
    destination: `${merchant.lat},${merchant.lng}`,
    travelmode: 'driving',
  });
  if (userLocation) params.set('origin', `${userLocation.lat},${userLocation.lng}`);
  window.open(`https://www.google.com/maps/dir/?${params.toString()}`, '_blank', 'noopener,noreferrer');
}

function MerchantPopup({ merchant, userLocation }: { merchant: MerchantPoint; userLocation?: { lat: number; lng: number } | null }) {
  return (
    <div className="min-w-[190px] space-y-2">
      <div className="flex items-center gap-2">
        {merchant.imageUrl ? (
          <img src={merchant.imageUrl} alt="" className="h-9 w-9 rounded-lg object-cover" />
        ) : (
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 text-primary"><Store className="h-4 w-4" /></div>
        )}
        <div className="min-w-0">
          <p className="truncate font-semibold text-foreground">{merchant.name}</p>
          <p className="text-xs text-muted-foreground">{formatDistance(merchant.distanceKm)}</p>
        </div>
      </div>
      <div className="flex items-center gap-1 text-xs">
        <Star className="h-3.5 w-3.5 fill-amber-400 text-amber-400" />
        <span className="font-semibold text-foreground">{merchant.ratingCount > 0 ? merchant.ratingAvg.toFixed(1) : 'Baru'}</span>
        <span className="text-muted-foreground">({merchant.ratingCount} ulasan)</span>
      </div>
      {merchant.reviews.filter((review) => review.comment?.trim()).slice(0, 2).map((review) => (
        <p key={review.id} className="line-clamp-2 border-l-2 border-primary/20 pl-2 text-[11px] italic text-muted-foreground">“{review.comment}”</p>
      ))}
      <p className="text-xs text-muted-foreground">{merchant.productCount} produk tersedia</p>
      <div className="grid grid-cols-3 gap-1.5">
        <Button asChild size="sm" className="h-8 rounded-lg px-2 text-xs">
          <Link to={`/merchant/${merchant.slug || merchant.id}`}>
            Lihat toko <ExternalLink className="ml-1 h-3 w-3" />
          </Link>
        </Button>
        <Button asChild type="button" size="sm" variant="outline" className="h-8 rounded-lg px-2 text-xs">
          <Link to={`/merchant/${merchant.id}/review`}>
            <Star className="mr-1 h-3 w-3" /> Ulas
          </Link>
        </Button>
        <Button type="button" size="sm" variant="outline" className="h-8 rounded-lg px-2 text-xs" onClick={() => openMerchantNavigation(merchant, userLocation)}>
          <Navigation className="mr-1 h-3 w-3" /> Rute
        </Button>
      </div>
    </div>
  );
}

function ClusteredMerchantMarkers({ merchants, userLocation }: { merchants: MerchantPoint[]; userLocation?: { lat: number; lng: number } | null }) {
  const map = useMap();
  const [zoom, setZoom] = useState(() => map.getZoom());

  useEffect(() => {
    const updateZoom = () => setZoom(map.getZoom());
    map.on('zoomend', updateZoom);
    return () => {
      map.off('zoomend', updateZoom);
    };
  }, [map]);

  const clusters = useMemo<MerchantCluster[]>(() => {
    // Cluster radius is measured in screen pixels, so it adapts naturally to zoom.
    const clusterRadius = 68;
    const result: MerchantCluster[] = [];

    merchants.forEach((merchant) => {
      const point = map.project([merchant.lat, merchant.lng], zoom);
      const matchingCluster = result.find((cluster) => {
        const clusterPoint = map.project([cluster.lat, cluster.lng], zoom);
        return point.distanceTo(clusterPoint) < clusterRadius;
      });

      if (matchingCluster) {
        matchingCluster.members.push(merchant);
        matchingCluster.lat = matchingCluster.members.reduce((sum, item) => sum + item.lat, 0) / matchingCluster.members.length;
        matchingCluster.lng = matchingCluster.members.reduce((sum, item) => sum + item.lng, 0) / matchingCluster.members.length;
      } else {
        result.push({ id: merchant.id, members: [merchant], lat: merchant.lat, lng: merchant.lng });
      }
    });

    return result;
  }, [map, merchants, zoom]);

  return (
    <>
      {clusters.map((cluster) => {
        if (cluster.members.length > 1) {
          return (
            <Marker
              key={`cluster-${cluster.id}`}
              position={[cluster.lat, cluster.lng]}
              icon={createClusterIcon(cluster.members.length)}
              eventHandlers={{
                click: () => map.fitBounds(
                  L.latLngBounds(cluster.members.map((merchant) => [merchant.lat, merchant.lng] as [number, number])),
                  { padding: [48, 48], maxZoom: 17 },
                ),
              }}
            />
          );
        }

        const merchant = cluster.members[0];
        return (
          <Marker key={merchant.id} position={[merchant.lat, merchant.lng]} icon={createMerchantIcon(merchant)}>
            <Popup><MerchantPopup merchant={merchant} userLocation={userLocation} /></Popup>
          </Marker>
        );
      })}
    </>
  );
}

function MapViewport({ center, points }: { center: [number, number]; points: MerchantPoint[] }) {
  const map = useMap();

  useEffect(() => {
    if (points.length > 1) {
      const bounds = L.latLngBounds(points.map((point) => [point.lat, point.lng] as [number, number]));
      map.fitBounds(bounds, { padding: [36, 36], maxZoom: 15 });
    } else {
      map.setView(center, map.getZoom() < 10 ? 13 : map.getZoom());
    }
  }, [center, map, points]);

  return null;
}

export function ProductMerchantMap({ products, center, userLocation }: ProductMerchantMapProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [liveUserLocation, setLiveUserLocation] = useState(userLocation);

  useEffect(() => {
    setLiveUserLocation(userLocation);
  }, [userLocation]);

  useEffect(() => {
    if (!navigator.geolocation) return;
    const watchId = navigator.geolocation.watchPosition(
      ({ coords }) => setLiveUserLocation({ lat: coords.latitude, lng: coords.longitude }),
      () => undefined,
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 10000 },
    );
    return () => navigator.geolocation.clearWatch(watchId);
  }, []);

  const merchants = useMemo<MerchantPoint[]>(() => {
    const grouped = new Map<string, MerchantPoint>();

    products.forEach((product) => {
      if (product.locationLat == null || product.locationLng == null) return;
      const existing = grouped.get(product.merchantId);
      if (existing) {
        existing.productCount += 1;
        return;
      }

      grouped.set(product.merchantId, {
        id: product.merchantId,
        name: product.merchantName || 'Toko lokal',
        address: product.merchantAddress,
        imageUrl: product.merchantImageUrl,
        slug: product.merchantSlug,
        ratingAvg: product.merchantRatingAvg || 0,
        ratingCount: product.merchantRatingCount || 0,
        reviews: product.merchantReviews || [],
        lat: product.locationLat,
        lng: product.locationLng,
        productCount: 1,
        isOpen: product.isMerchantOpen,
        distanceKm: liveUserLocation
          ? calculateDistance(liveUserLocation.lat, liveUserLocation.lng, product.locationLat, product.locationLng)
          : Infinity,
      });
    });

    return [...grouped.values()].sort((a, b) => a.distanceKm - b.distanceKm);
  }, [liveUserLocation, products]);

  const visibleMerchants = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    if (!query) return merchants;
    return merchants.filter((merchant) => `${merchant.name} ${merchant.address || ''}`.toLowerCase().includes(query));
  }, [merchants, searchQuery]);

  const mapCenter: [number, number] = [center.lat, center.lng];

  return (
    <div className="space-y-3">
      <div className="space-y-2">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            value={searchQuery}
            onChange={(event) => setSearchQuery(event.target.value)}
            placeholder="Cari toko berdasarkan nama atau alamat"
            aria-label="Cari toko berdasarkan nama atau alamat"
            className="h-11 w-full rounded-2xl border border-border bg-background pl-10 pr-3 text-sm outline-none transition focus:border-primary/40 focus:ring-4 focus:ring-primary/10"
          />
        </div>
        <div className="flex items-center gap-1.5 px-1 text-xs text-muted-foreground">
          <Navigation className="h-3.5 w-3.5 text-primary" />
          Jarak diperbarui otomatis dari lokasi GPS terbaru kamu
        </div>
      </div>
      <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
        <MapContainer center={mapCenter} zoom={13} scrollWheelZoom className="h-[390px] w-full">
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <MapViewport center={mapCenter} points={visibleMerchants} />
          {liveUserLocation && (
            <Marker
              position={[liveUserLocation.lat, liveUserLocation.lng]}
              icon={L.divIcon({
                className: 'user-location-marker-wrapper',
                html: '<div class="user-location-marker" title="Lokasi kamu"></div>',
                iconSize: [18, 18],
                iconAnchor: [9, 9],
              })}
            >
              <Popup>Lokasi kamu</Popup>
            </Marker>
          )}
          <ClusteredMerchantMarkers merchants={visibleMerchants} userLocation={liveUserLocation} />
        </MapContainer>
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between px-1">
          <div className="flex items-center gap-1.5 text-sm font-semibold text-foreground"><MapPin className="h-4 w-4 text-primary" />Toko di sekitar</div>
          <span className="text-xs text-muted-foreground">{visibleMerchants.length} dari {merchants.length} toko</span>
        </div>
        {visibleMerchants.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground">
            {merchants.length === 0 ? 'Belum ada toko dengan titik lokasi pada hasil ini.' : 'Toko dengan nama atau alamat tersebut tidak ditemukan.'}
          </div>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {visibleMerchants.map((merchant) => (
              <Link
                key={merchant.id}
                to={`/merchant/${merchant.slug || merchant.id}`}
                className="flex items-center gap-3 rounded-xl border border-border bg-card p-3 transition hover:border-primary/40 hover:bg-primary/5"
              >
                {merchant.imageUrl ? (
                  <img src={merchant.imageUrl} alt="" className="h-11 w-11 shrink-0 rounded-xl object-cover" loading="lazy" decoding="async" />
                ) : (
                  <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary"><Store className="h-5 w-5" /></div>
                )}
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <p className="truncate text-sm font-semibold text-foreground">{merchant.name}</p>
                    <span className={merchant.isOpen ? 'h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-500' : 'h-1.5 w-1.5 shrink-0 rounded-full bg-muted-foreground'} />
                  </div>
                  <p className="text-xs text-muted-foreground">{formatDistance(merchant.distanceKm)} · {merchant.productCount} produk</p>
                </div>
                <ExternalLink className="h-4 w-4 shrink-0 text-muted-foreground" />
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
