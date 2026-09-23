import { useEffect, useMemo } from 'react';
import { Link } from 'react-router-dom';
import { MapContainer, Marker, Popup, TileLayer, useMap } from 'react-leaflet';
import L from 'leaflet';
import { ExternalLink, MapPin, Store } from 'lucide-react';
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
  imageUrl?: string | null;
  slug?: string | null;
  lat: number;
  lng: number;
  productCount: number;
  isOpen?: boolean;
  distanceKm: number;
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

function formatDistance(distanceKm: number) {
  if (!Number.isFinite(distanceKm)) return 'Jarak tidak tersedia';
  if (distanceKm < 1) return `${Math.round(distanceKm * 1000)} m dari kamu`;
  return `${distanceKm.toFixed(1)} km dari kamu`;
}

export function ProductMerchantMap({ products, center, userLocation }: ProductMerchantMapProps) {
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
        imageUrl: product.merchantImageUrl,
        slug: product.merchantSlug,
        lat: product.locationLat,
        lng: product.locationLng,
        productCount: 1,
        isOpen: product.isMerchantOpen,
        distanceKm: userLocation
          ? calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng)
          : Infinity,
      });
    });

    return [...grouped.values()].sort((a, b) => a.distanceKm - b.distanceKm);
  }, [products, userLocation]);

  const mapCenter: [number, number] = [center.lat, center.lng];

  return (
    <div className="space-y-3">
      <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
        <MapContainer center={mapCenter} zoom={13} scrollWheelZoom className="h-[390px] w-full">
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <MapViewport center={mapCenter} points={merchants} />
          {userLocation && (
            <Marker
              position={[userLocation.lat, userLocation.lng]}
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
          {merchants.map((merchant) => (
            <Marker key={merchant.id} position={[merchant.lat, merchant.lng]} icon={createMerchantIcon(merchant)}>
              <Popup>
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
                  <p className="text-xs text-muted-foreground">{merchant.productCount} produk tersedia</p>
                  <Button asChild size="sm" className="h-8 w-full rounded-lg text-xs">
                    <Link to={`/merchant/${merchant.slug || merchant.id}`}>
                      Lihat toko <ExternalLink className="ml-1 h-3 w-3" />
                    </Link>
                  </Button>
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between px-1">
          <div className="flex items-center gap-1.5 text-sm font-semibold text-foreground"><MapPin className="h-4 w-4 text-primary" />Toko di sekitar</div>
          <span className="text-xs text-muted-foreground">{merchants.length} toko</span>
        </div>
        {merchants.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground">
            Belum ada toko dengan titik lokasi pada hasil ini.
          </div>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {merchants.map((merchant) => (
              <Link
                key={merchant.id}
                to={`/merchant/${merchant.slug || merchant.id}`}
                className="flex items-center gap-3 rounded-xl border border-border bg-card p-3 transition hover:border-primary/40 hover:bg-primary/5"
              >
                {merchant.imageUrl ? (
                  <img src={merchant.imageUrl} alt="" className="h-11 w-11 shrink-0 rounded-xl object-cover" />
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
