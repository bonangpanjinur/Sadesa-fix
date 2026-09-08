export interface RoutePoint {
  lat: number;
  lng: number;
}

export interface RoadRoute {
  distanceKm: number;
  durationMinutes: number;
  geometry: [number, number][];
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