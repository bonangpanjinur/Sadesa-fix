// EMSIFA v2 region data. Proxy and direct fallback are normalized to the
// same { code, name } client contract.

export interface Region {
  code: string;
  name: string;
}

interface WilayahResponse {
  data: Array<{ id?: string; code?: string; name: string }>;
  meta?: Record<string, unknown>;
}

// Persistent cache using localStorage
const CACHE_PREFIX = 'address_cache_v2_';
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

const EMSIFA_V2_API_URL = 'https://www.emsifa.com/api-wilayah-indonesia/v2';

function toTitleCase(str: string): string {
  if (!str) return str;
  // If string is all uppercase, convert to title case
  if (str === str.toUpperCase()) {
    return str.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
  }
  return str;
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
    if (projectId) {
      const response = await fetch(
        `https://${projectId}.supabase.co/functions/v1/wilayah-proxy?${params.toString()}`,
        {
          // GET plus apikey is sufficient for a public Edge Function and avoids
          // the unnecessary Content-Type preflight from the old implementation.
          headers: { apikey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? '' },
          signal,
        },
      );
      if (response.ok && (response.headers.get('content-type') || '').includes('application/json')) {
        return response;
      }
    }
  } catch (error) {
    if ((error as Error).name === 'AbortError') throw error;
  }

  try {
    // Direct v2 is retained only as fallback while a deployment's proxy is
    // missing or still returning the old, undotted v1 region codes.
    const upstreamUrl = `${EMSIFA_V2_API_URL}/${type === 'provinces' ? 'provinces' : `${type}/${encodeURIComponent(code ?? '')}`}.json`;
    const response = await fetch(upstreamUrl, {
      headers: { Accept: 'application/json' },
      signal,
    });
    const contentType = response.headers.get('content-type') || '';
    if (response.ok && contentType.includes('application/json')) return response;
  } catch (error) {
    if ((error as Error).name === 'AbortError') throw error;
  }

  return null;
}

function normalizeRegionPayload(json: unknown): Region[] {
  const items = Array.isArray(json) ? json : (json as WilayahResponse | null)?.data;
  if (!Array.isArray(items)) return [];

  return items.flatMap((item) => {
    if (!item || typeof item !== 'object' || typeof item.name !== 'string') return [];
    const code = item.code ?? item.id;
    if (typeof code !== 'string') return [];
    return [{ code, name: toTitleCase(item.name) }];
  });
}

function hasV2Codes(type: string, data: Region[]): boolean {
  if (data.length === 0) return false;
  if (type === 'provinces') return data.length >= 38 && data.every(({ code }) => /^\d{2}$/.test(code));

  const codePatterns: Record<string, RegExp> = {
    regencies: /^\d{2}\.\d{2}$/,
    districts: /^\d{2}\.\d{2}\.\d{2}$/,
    villages: /^\d{2}\.\d{2}\.\d{2}\.\d{4}$/,
  };
  const pattern = codePatterns[type];
  return Boolean(pattern && data.every(({ code }) => pattern.test(code)));
}

async function fetchWithFallbacks(type: string, code?: string): Promise<Region[]> {
  if (!['provinces', 'regencies', 'districts', 'villages'].includes(type)) return [];

  const controller = new AbortController();
  const { signal } = controller;

  // Auto-abort after 10s max
  const timeout = setTimeout(() => controller.abort(), 10000);

  try {
    // Prefer Supabase. If a deployment still serves v1 codes, fetch v2 rather
    // than showing the incomplete legacy dataset.
    const response = await fetchViaLocalProxy(type, code, signal);
    let result: Region[] = response ? normalizeRegionPayload(await response.json()) : [];
    if (!hasV2Codes(type, result)) {
      const endpoint = type === 'provinces' ? 'provinces' : `${type}/${encodeURIComponent(code ?? '')}`;
      const v2Response = await fetch(`${EMSIFA_V2_API_URL}/${endpoint}.json`, {
        headers: { Accept: 'application/json' },
        signal,
      });
      if (!v2Response.ok) throw new Error(`EMSIFA v2 returned ${v2Response.status}`);
      result = normalizeRegionPayload(await v2Response.json());
    }
    if (!hasV2Codes(type, result)) throw new Error('EMSIFA v2 returned an invalid or empty region list');

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
