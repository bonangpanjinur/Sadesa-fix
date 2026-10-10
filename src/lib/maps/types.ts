export interface MapPoint {
  lat: number;
  lng: number;
}

export interface MapMarker extends MapPoint {
  id: string;
  label?: string;
  kind?: string;
}

export interface RoadRoute {
  distanceKm: number;
  durationMinutes: number;
  geometry: MapPoint[];
  provider: 'google' | 'fallback';
}
