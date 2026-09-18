import type { Product } from '@/types';
import { calculateDistance } from '@/hooks/useUserLocation';

export interface UserCoordinates {
  lat: number;
  lng: number;
}

export interface NearestOpenMerchant {
  merchantId: string;
  merchantName: string;
  distanceKm: number;
}

/**
 * Finds the nearest currently-open merchant from the products already loaded on
 * the homepage. A merchant is de-duplicated so its many products do not skew
 * the result.
 */
export function findNearestOpenMerchant(
  products: Product[],
  userLocation?: UserCoordinates | null,
): NearestOpenMerchant | null {
  if (!userLocation) return null;

  const merchants = new Map<string, NearestOpenMerchant>();
  for (const product of products) {
    if (product.isMerchantOpen !== true || product.locationLat == null || product.locationLng == null) continue;

    const distanceKm = calculateDistance(
      userLocation.lat,
      userLocation.lng,
      product.locationLat,
      product.locationLng,
    );
    const existing = merchants.get(product.merchantId);
    if (!existing || distanceKm < existing.distanceKm) {
      merchants.set(product.merchantId, {
        merchantId: product.merchantId,
        merchantName: product.merchantName || 'Merchant terdekat',
        distanceKm,
      });
    }
  }

  return [...merchants.values()].sort((a, b) => a.distanceKm - b.distanceKm)[0] ?? null;
}

export function formatDistance(distanceKm: number): string {
  if (distanceKm < 1) return `${Math.round(distanceKm * 1000)} m`;
  return `${distanceKm.toFixed(1).replace('.', ',')} km`;
}
