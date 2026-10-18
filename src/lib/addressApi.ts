// EMSIFA v2 region data. Proxy and direct fallback are normalized to the
// same { code, name } client contract.
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/integrations/supabase/client';

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

const EMSIFA_V2_API_URL = 'https://www.emsifa.com/api-wilayah-indonesia/v2';

function toTitleCase(str: string): string {
  if (!str) return str;
  // If string is all uppercase, convert to title case
  if (str === str.toUpperCase()) {
    return str.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
  }
  return str;
}

function toEmsifaV2Code(code: string): string {
  if (/^\d{2}(?:\.\d{2}){1,2}(?:\.\d{4})?$/.test(code)) return code;
  if (/^\d{10}$/.test(code)) return code.replace(/^(\d{2})(\d{2})(\d{2})(\d{4})$/, '$1.$2.$3.$4');
  if (/^\d{6}$/.test(code)) return code.replace(/^(\d{2})(\d{2})(\d{2})$/, '$1.$2.$3');
  if (/^\d{4}$/.test(code)) return code.replace(/^(\d{2})(\d{2})$/, '$1.$2');
  return code;
}

function toLegacyRegionCode(code: string): string {
  return /^\d{2}(?:\.\d{2}){1,2}(?:\.\d{4})?$/.test(code) ? code.replace(/\./g, '') : code;
}

async function fetchViaSupabaseProxy(type: string, code: string | undefined, signal?: AbortSignal): Promise<Response | null> {
  const params = new URLSearchParams({ type });
  if (code) params.append('code', toEmsifaV2Code(code));
  try {
    const response = await fetch(`${SUPABASE_URL}/functions/v1/wilayah-proxy?${params.toString()}`, {
      headers: { apikey: SUPABASE_PUBLISHABLE_KEY },
      signal,
    });
    if (response.ok && (response.headers.get('content-type') || '').includes('application/json')) {
      return response;
    }
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
    // Prefer the Supabase function, then request EMSIFA v2 directly if the
    // function is not deployed or still serves the old, undotted v1 codes.
    const response = await fetchViaSupabaseProxy(type, code, signal);
    let result: Region[] = response ? normalizeRegionPayload(await response.json()) : [];
    if (!hasV2Codes(type, result)) {
      const v2Code = code ? toEmsifaV2Code(code) : '';
      const endpoint = type === 'provinces' ? 'provinces' : `${type}/${encodeURIComponent(v2Code)}`;
      const v2Response = await fetch(`${EMSIFA_V2_API_URL}/${endpoint}.json`, {
        headers: { Accept: 'application/json' },
        signal,
      });
      if (!v2Response.ok) throw new Error(`EMSIFA v2 returned ${v2Response.status}`);
      result = normalizeRegionPayload(await v2Response.json());
    }
    if (!hasV2Codes(type, result)) throw new Error('EMSIFA v2 returned an invalid or empty region list');
    // Keep existing database/form IDs stable. Only the lookup source is v2.
    result = result.map(({ code: regionCode, name }) => ({ code: toLegacyRegionCode(regionCode), name }));

    clearTimeout(timeout);
    controller.abort();
    return result;
  } catch {
    clearTimeout(timeout);
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
    return [];
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
