import { supabase, SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/integrations/supabase/client';

export interface GoogleMapsFunctionRoute {
  distanceKm: number;
  durationMinutes: number;
  geometry: Array<{ lat: number; lng: number }>;
  provider: 'google' | 'fallback';
}

export interface GoogleMapsGeocodeResult {
  lat: number;
  lng: number;
  displayName?: string;
  province?: string;
  city?: string;
  district?: string;
  village?: string;
  postcode?: string;
  fullAddress?: string;
}

async function getAuthorizationHeader(): Promise<string> {
  const { data, error } = await supabase.auth.getSession();
  if (error) throw new Error('Sesi lokasi tidak dapat diverifikasi');
  return `Bearer ${data.session?.access_token || SUPABASE_PUBLISHABLE_KEY}`;
}

export async function callGoogleMapsFunction<T>(
  body: Record<string, unknown>,
  signal?: AbortSignal,
): Promise<T> {
  const authorization = await getAuthorizationHeader();
  const response = await fetch(`${SUPABASE_URL}/functions/v1/google-maps`, {
    method: 'POST',
    headers: {
      Authorization: authorization,
      apikey: SUPABASE_PUBLISHABLE_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
    signal,
  });

  if (!response.ok) {
    throw new Error(`Maps service returned ${response.status}`);
  }

  return await response.json() as T;
}
