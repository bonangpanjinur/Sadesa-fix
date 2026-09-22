export interface RoutePoint {
  lat: number;
  lng: number;
}

export interface RoadRoute {
  distanceKm: number;
  durationMinutes: number;
  geometry: [number, number][];
}

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
    geometry: (route.geometry?.coordinates ?? []).map(([lng, lat]) => [lat, lng]),
  };
}

/** Delivery distance follows the drivable road and never blocks checkout. */
export async function getDeliveryDistanceKm(
  from: RoutePoint,
  to: RoutePoint,
  signal?: AbortSignal,
): Promise<{ distanceKm: number; source: 'road' | 'straight-line' }> {
  if (!isValidRoutePoint(from) || !isValidRoutePoint(to)) {
    throw new Error('Koordinat pengiriman tidak valid');
  }
  try {
    const route = await getRoadRoute(from, to, signal);
    if (route && Number.isFinite(route.distanceKm) && route.distanceKm > 0) {
      return { distanceKm: route.distanceKm, source: 'road' };
    }
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    console.warn('Road distance unavailable; using straight-line distance', error);
  }
  return { distanceKm: haversineDistanceKm(from, to), source: 'straight-line' };
}
