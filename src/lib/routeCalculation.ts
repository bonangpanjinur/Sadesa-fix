import { callGoogleMapsFunction, type GoogleMapsFunctionRoute } from '@/lib/maps/googleMapsApi';
import type { MapPoint, RoadRoute } from '@/lib/maps/types';

export type RoutePoint = MapPoint;
export type { RoadRoute } from '@/lib/maps/types';

/** Straight-line distance is the safe fallback when routing is unavailable. */
export function haversineDistanceKm(from: RoutePoint, to: RoutePoint): number {
  const radius = 6371;
  const dLat = (to.lat - from.lat) * Math.PI / 180;
  const dLng = (to.lng - from.lng) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(from.lat * Math.PI / 180) * Math.cos(to.lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function isValidRoutePoint(point: RoutePoint | null | undefined): point is RoutePoint {
  return Boolean(point && Number.isFinite(point.lat) && Number.isFinite(point.lng)
    && point.lat >= -90 && point.lat <= 90 && point.lng >= -180 && point.lng <= 180);
}

interface OsrmRouteResponse {
  code?: string;
  routes?: Array<{
    distance: number;
    duration: number;
    geometry?: {
      coordinates?: Array<[number, number]>;
    };
  }>;
}

/**
 * Get a drivable route from the public OSRM service.
 * OSRM returns GeoJSON coordinates as [longitude, latitude], while Leaflet
 * expects [latitude, longitude].
 */
export async function getRoadRoute(
  from: RoutePoint,
  to: RoutePoint,
  signal?: AbortSignal,
): Promise<RoadRoute | null> {
  if (!isValidRoutePoint(from) || !isValidRoutePoint(to)) {
    throw new Error('Koordinat rute tidak valid');
  }
  const params = `${from.lng},${from.lat};${to.lng},${to.lat}`;
  const response = await fetch(
    `https://router.project-osrm.org/route/v1/driving/${params}?overview=full&geometries=geojson`,
    { signal },
  );

  if (!response.ok) {
    throw new Error(`Route service returned ${response.status}`);
  }

  const payload = (await response.json()) as OsrmRouteResponse;
  const route = payload.routes?.[0];

  if (payload.code !== 'Ok' || !route) {
    return null;
  }

  return {
    distanceKm: route.distance / 1000,
    durationMinutes: Math.max(1, Math.ceil(route.duration / 60)),
    geometry: (route.geometry?.coordinates ?? []).map(([lng, lat]) => ({ lat, lng })),
    provider: 'fallback',
  };
}

const ROUTE_CACHE_TTL_MS = 5 * 60_000;
const ROUTE_CACHE_LIMIT = 200;
const routeCache = new Map<string, { route: RoadRoute; expiresAt: number }>();

function routeCacheKey(from: RoutePoint, to: RoutePoint): string {
  return [from.lat, from.lng, to.lat, to.lng].map((coordinate) => coordinate.toFixed(5)).join(':');
}

function rememberRoute(key: string, route: RoadRoute): void {
  if (routeCache.size >= ROUTE_CACHE_LIMIT) {
    const oldestKey = routeCache.keys().next().value;
    if (oldestKey) routeCache.delete(oldestKey);
  }
  routeCache.set(key, { route, expiresAt: Date.now() + ROUTE_CACHE_TTL_MS });
}

/** Google Routes is called through the server function; no server key reaches the browser. */
export async function getGoogleRoadRoute(
  from: RoutePoint,
  to: RoutePoint,
  signal?: AbortSignal,
): Promise<RoadRoute | null> {
  if (!isValidRoutePoint(from) || !isValidRoutePoint(to)) {
    throw new Error('Koordinat rute tidak valid');
  }

  const key = routeCacheKey(from, to);
  const cached = routeCache.get(key);
  if (cached && cached.expiresAt > Date.now()) return cached.route;
  if (cached) routeCache.delete(key);

  const result = await callGoogleMapsFunction<GoogleMapsFunctionRoute>({
    action: 'route',
    origin: from,
    destination: to,
  }, signal);

  if (!Number.isFinite(result.distanceKm) || result.distanceKm <= 0
    || !Number.isFinite(result.durationMinutes) || result.durationMinutes <= 0
    || !Array.isArray(result.geometry)
    || result.geometry.some((point) => !isValidRoutePoint(point))
    || (result.provider !== 'google' && result.provider !== 'fallback')) {
    throw new Error('Maps service returned an invalid route');
  }

  const route: RoadRoute = {
    distanceKm: result.distanceKm,
    durationMinutes: result.durationMinutes,
    geometry: result.geometry,
    provider: result.provider,
  };
  rememberRoute(key, route);
  return route;
}

/** Checkout prefers Google road distance and degrades to road/straight-line estimates. */
export async function getDeliveryDistanceKm(
  from: RoutePoint,
  to: RoutePoint,
  signal?: AbortSignal,
): Promise<{ distanceKm: number; source: 'google' | 'fallback' | 'straight-line' }> {
  if (!isValidRoutePoint(from) || !isValidRoutePoint(to)) {
    throw new Error('Koordinat pengiriman tidak valid');
  }
  try {
    const route = await getGoogleRoadRoute(from, to, signal);
    if (route && Number.isFinite(route.distanceKm) && route.distanceKm > 0) {
      return { distanceKm: route.distanceKm, source: route.provider };
    }
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    if (signal?.aborted) throw new DOMException('The operation was aborted', 'AbortError');
  }

  try {
    const fallbackRoute = await getRoadRoute(from, to, signal);
    if (fallbackRoute && Number.isFinite(fallbackRoute.distanceKm) && fallbackRoute.distanceKm > 0) {
      return { distanceKm: fallbackRoute.distanceKm, source: 'fallback' };
    }
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    if (signal?.aborted) throw new DOMException('The operation was aborted', 'AbortError');
  }

  return { distanceKm: haversineDistanceKm(from, to), source: 'straight-line' };
}
