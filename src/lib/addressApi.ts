// Wilayah.id API for Indonesian regions
// Source: https://wilayah.id/
// Uses a same-origin/server proxy first, with a single Supabase proxy fallback.

export interface Region {
  code: string;
  name: string;
}

interface WilayahResponse {
  data: Region[];
  meta?: {
    administrative_area_level: number;
    updated_at: string;
  };
}

// Persistent cache using localStorage
const CACHE_PREFIX = 'address_cache_';
const CACHE_DURATION = 24 * 60 * 60 * 1000; // 24 hours

function getCacheKey(type: string, code?: string): string {
  return code ? `${type}-${code}` : type;
}

function getFromCache(key: string): Region[] | null {
  try {
    const cached = localStorage.getItem(CACHE_PREFIX + key);
    if (cached) {
      const { data, timestamp } = JSON.parse(cached);
      if (Date.now() - timestamp < CACHE_DURATION) {
        return data;
      }
      localStorage.removeItem(CACHE_PREFIX + key);
    }
  } catch (e) {
    console.warn('Cache read error:', e);
  }
  return null;
}

function setCache(key: string, data: Region[]): void {
  try {
    localStorage.setItem(CACHE_PREFIX + key, JSON.stringify({
      data,
      timestamp: Date.now()
    }));
  } catch (e) {
    console.warn('Cache write error:', e);
  }
}

// Static fallback data for provinces
const STATIC_PROVINCES: Region[] = [
  { code: "11", name: "Aceh" },
  { code: "12", name: "Sumatera Utara" },
  { code: "13", name: "Sumatera Barat" },
  { code: "14", name: "Riau" },
  { code: "15", name: "Jambi" },
  { code: "16", name: "Sumatera Selatan" },
  { code: "17", name: "Bengkulu" },
  { code: "18", name: "Lampung" },
  { code: "19", name: "Kepulauan Bangka Belitung" },
  { code: "21", name: "Kepulauan Riau" },
  { code: "31", name: "DKI Jakarta" },
  { code: "32", name: "Jawa Barat" },
  { code: "33", name: "Jawa Tengah" },
  { code: "34", name: "DI Yogyakarta" },
  { code: "35", name: "Jawa Timur" },
  { code: "36", name: "Banten" },
  { code: "51", name: "Bali" },
  { code: "52", name: "Nusa Tenggara Barat" },
  { code: "53", name: "Nusa Tenggara Timur" },
  { code: "61", name: "Kalimantan Barat" },
  { code: "62", name: "Kalimantan Tengah" },
  { code: "63", name: "Kalimantan Selatan" },
  { code: "64", name: "Kalimantan Timur" },
  { code: "65", name: "Kalimantan Utara" },
  { code: "71", name: "Sulawesi Utara" },
  { code: "72", name: "Sulawesi Tengah" },
  { code: "73", name: "Sulawesi Selatan" },
  { code: "74", name: "Sulawesi Tenggara" },
  { code: "75", name: "Gorontalo" },
  { code: "76", name: "Sulawesi Barat" },
  { code: "81", name: "Maluku" },
  { code: "82", name: "Maluku Utara" },
  { code: "91", name: "Papua" },
  { code: "92", name: "Papua Barat" },
  { code: "93", name: "Papua Selatan" },
  { code: "94", name: "Papua Tengah" },
  { code: "95", name: "Papua Pegunungan" },
  { code: "96", name: "Papua Barat Daya" },
];

let BASE_URL = 'https://wilayah.id/api';

// Try to load custom API URL from localStorage (cached from system settings)
try {
  const customApiUrl = localStorage.getItem('custom_address_api_url');
  if (customApiUrl) {
    BASE_URL = customApiUrl;
  }
} catch (e) {
  // Ignore localStorage errors
}

function toTitleCase(str: string): string {
  if (!str) return str;
  // If string is all uppercase, convert to title case
  if (str === str.toUpperCase()) {
    return str.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
  }
  return str;
}

export function setBaseUrl(url: string) {
  BASE_URL = url;
  try {
    localStorage.setItem('custom_address_api_url', url);
  } catch (err) { console.warn('[address] gagal menyimpan URL API wilayah:', err); }
}

async function fetchViaLocalProxy(type: string, code: string | undefined, signal?: AbortSignal): Promise<Response | null> {
  const params = new URLSearchParams({ type });
  if (code) params.append('code', code);

  try {
    // Prefer the application's own proxy when the host provides one.
    const localResponse = await fetch(`/api/wilayah?${params.toString()}`, { signal });
    const contentType = localResponse.headers.get('content-type') || '';
    if (localResponse.ok && contentType.includes('application/json')) return localResponse;
  } catch (error) {
    if ((error as Error).name === 'AbortError') throw error;
  }

  try {
    const projectId = import.meta.env.VITE_SUPABASE_PROJECT_ID;
    if (!projectId) return null;
    const response = await fetch(
      `https://${projectId}.supabase.co/functions/v1/wilayah-proxy?${params.toString()}`,
      {
        // GET plus apikey is sufficient for a public Edge Function and avoids
        // the unnecessary Content-Type preflight from the old implementation.
        headers: { apikey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? '' },
        signal,
      },
    );
    if (response.ok) return response;
  } catch (error) {
    if ((error as Error).name === 'AbortError') throw error;
  }
  return null;
}

async function fetchWithFallbacks(type: string, code?: string): Promise<Region[]> {
  if (!['provinces', 'regencies', 'districts', 'villages'].includes(type)) return [];

  const controller = new AbortController();
  const { signal } = controller;

  // Auto-abort after 10s max
  const timeout = setTimeout(() => controller.abort(), 10000);

  try {
    // Third-party region APIs are not called directly from the browser because
    // their CORS headers are inconsistent. One user action now produces one
    // controlled proxy flow instead of several console errors.
    const response = await fetchViaLocalProxy(type, code, signal);
    if (!response) throw new Error('Wilayah proxy unavailable');
    const json = await response.json();
    const result = Array.isArray(json)
      ? json.map((item: { id?: string; code?: string; name: string }) => ({
          code: item.code ?? item.id ?? '',
          name: toTitleCase(item.name),
        }))
      : ((json as WilayahResponse).data || []);
    if (result.length === 0) throw new Error('Wilayah proxy returned an empty result');

    clearTimeout(timeout);
    controller.abort();
    return result;
  } catch {
    clearTimeout(timeout);
    if (type === 'provinces') return STATIC_PROVINCES;
    console.warn(`All fetch strategies failed for ${type}/${code}`);
    return [];
  }
}

export async function fetchProvinces(): Promise<Region[]> {
  const cacheKey = getCacheKey('provinces');
  const cached = getFromCache(cacheKey);
  if (cached) return cached;

  try {
    const data = await fetchWithFallbacks('provinces');
    if (data.length > 0) setCache(cacheKey, data);
    return data;
  } catch (error) {
    console.error('Error fetching provinces:', error);
    return STATIC_PROVINCES;
  }
}

export async function fetchRegencies(provinceCode: string): Promise<Region[]> {
  if (!provinceCode) return [];
  const cacheKey = getCacheKey('regencies', provinceCode);
  const cached = getFromCache(cacheKey);
  if (cached) return cached;

  try {
    const data = await fetchWithFallbacks('regencies', provinceCode);
    if (data.length > 0) setCache(cacheKey, data);
    return data;
  } catch (error) {
    console.error('Error fetching regencies:', error);
    return [];
  }
}

export async function fetchDistricts(regencyCode: string): Promise<Region[]> {
  if (!regencyCode) return [];
  const cacheKey = getCacheKey('districts', regencyCode);
  const cached = getFromCache(cacheKey);
  if (cached) return cached;

  try {
    const data = await fetchWithFallbacks('districts', regencyCode);
    if (data.length > 0) setCache(cacheKey, data);
    return data;
  } catch (error) {
    console.error('Error fetching districts:', error);
    return [];
  }
}

export async function fetchVillages(districtCode: string): Promise<Region[]> {
  if (!districtCode) return [];
  const cacheKey = getCacheKey('villages', districtCode);
  const cached = getFromCache(cacheKey);
  if (cached) return cached;

  try {
    const data = await fetchWithFallbacks('villages', districtCode);
    if (data.length > 0) setCache(cacheKey, data);
    return data;
  } catch (error) {
    console.error('Error fetching villages:', error);
    return [];
  }
}

export async function preloadAddressChain(
  provinceCode: string,
  cityCode: string,
  districtCode: string
): Promise<{
  provinces: Region[];
  cities: Region[];
  districts: Region[];
  villages: Region[];
}> {
  const [provinces, cities, districts, villages] = await Promise.all([
    fetchProvinces(),
    provinceCode ? fetchRegencies(provinceCode) : Promise.resolve([]),
    cityCode ? fetchDistricts(cityCode) : Promise.resolve([]),
    districtCode ? fetchVillages(districtCode) : Promise.resolve([]),
  ]);

  return { provinces, cities, districts, villages };
}

export function clearAddressCache(): void {
  Object.keys(localStorage)
    .filter(key => key.startsWith(CACHE_PREFIX))
    .forEach(key => localStorage.removeItem(key));
}
