import { useState, useCallback } from 'react';
import { callGoogleMapsFunction, type GoogleMapsGeocodeResult } from '@/lib/maps/googleMapsApi';

export interface GeocodingOptions {
  provider?: 'nominatim' | 'google';
}

export interface GeocodingResult {
  lat: number;
  lng: number;
  displayName?: string;
}

export interface AddressSuggestion extends GeocodingResult {
  id: string;
}

export interface ReverseGeocodingResult {
  province?: string;
  city?: string;
  district?: string;
  village?: string;
  displayName?: string;
  fullAddress?: string;
  postcode?: string;
}

export interface AddressSummary {
  province?: string;
  city?: string;
  district?: string;
  village?: string;
  detail?: string;
  coordinates?: { lat: number; lng: number };
}

// Nominatim API for geocoding (OpenStreetMap)
const NOMINATIM_URL = 'https://nominatim.openstreetmap.org';
const NOMINATIM_MIN_INTERVAL_MS = 1100;
const NOMINATIM_429_COOLDOWN_MS = 30_000;
const geocodingCache = new Map<string, unknown>();
const inFlightRequests = new Map<string, Promise<unknown | null>>();
let nextNominatimRequestAt = 0;
let nominatimCooldownUntil = 0;
let nominatimRequestQueue: Promise<void> = Promise.resolve();

async function fetchNominatim<T>(url: string, cacheKey: string): Promise<T | null> {
  if (geocodingCache.has(cacheKey)) return (geocodingCache.get(cacheKey) ?? null) as T | null;
  const existingRequest = inFlightRequests.get(cacheKey);
  if (existingRequest) return existingRequest as Promise<T | null>;

  const request = (async (): Promise<T | null> => {
    let releaseQueue!: () => void;
    const previousRequest = nominatimRequestQueue;
    nominatimRequestQueue = new Promise<void>((resolve) => { releaseQueue = resolve; });
    await previousRequest;

    try {
      if (Date.now() < nominatimCooldownUntil) return null;
      const waitMs = Math.max(0, nextNominatimRequestAt - Date.now());
      if (waitMs > 0) await new Promise((resolve) => setTimeout(resolve, waitMs));
      if (Date.now() < nominatimCooldownUntil) return null;

      nextNominatimRequestAt = Date.now() + NOMINATIM_MIN_INTERVAL_MS;
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 10_000);
      let response: Response;
      try {
        response = await fetch(url, { signal: controller.signal, headers: { Accept: 'application/json' } });
      } catch (error) {
        // Nominatim 429 responses may surface in browsers as CORS/network errors.
        // Back off on transport failures as well, and return a soft miss so
        // address entry and checkout remain usable without map lookup.
        nominatimCooldownUntil = Date.now() + NOMINATIM_429_COOLDOWN_MS;
        console.warn('Nominatim unavailable; geocoding paused temporarily', error instanceof Error ? error.message : 'network error');
        return null;
      } finally {
        clearTimeout(timeout);
      }

      if (response.status === 429) {
        const retryAfter = Number(response.headers.get('Retry-After'));
        const retryDelay = Number.isFinite(retryAfter) && retryAfter > 0
          ? Math.min(retryAfter * 1000, 5 * 60_000)
          : NOMINATIM_429_COOLDOWN_MS;
        nominatimCooldownUntil = Date.now() + retryDelay;
        console.warn('Nominatim rate limit reached; geocoding paused temporarily');
        return null;
      }
      if (!response.ok) {
        if (response.status >= 500) nominatimCooldownUntil = Date.now() + NOMINATIM_429_COOLDOWN_MS;
        return null;
      }

      const result = await response.json() as T;
      // Cache empty results too, so an unknown address is not queried on every render.
      geocodingCache.set(cacheKey, result);
      return result;
    } finally {
      releaseQueue();
    }
  })();

  inFlightRequests.set(cacheKey, request);
  try {
    return await request;
  } finally {
    inFlightRequests.delete(cacheKey);
  }
}

/**
 * Forward geocoding - convert address to coordinates
 */
export async function geocodeAddress(
  districtName: string,
  villageName: string,
  cityName?: string,
  provinceName?: string,
  options: GeocodingOptions = {},
): Promise<GeocodingResult | null> {
  try {
    // Build search query - prioritize more specific address parts
    const queryParts = [villageName, districtName, cityName, provinceName, 'Indonesia']
      .filter(Boolean);
    const query = queryParts.join(', ');

    if (options.provider === 'google') {
      try {
        const result = await callGoogleMapsFunction<GoogleMapsGeocodeResult | null>({
          action: 'geocode',
          address: query,
        });
        if (result && Number.isFinite(result.lat) && Number.isFinite(result.lng)) {
          return { lat: result.lat, lng: result.lng, displayName: result.displayName };
        }
      } catch {
        // Keep address entry usable while the server proxy or Google is down.
      }
    }
    
    const params = new URLSearchParams({
      q: query,
      format: 'json',
      limit: '1',
      countrycodes: 'id',
    });

    const results = await fetchNominatim<Array<{ lat: string; lon: string; display_name: string }>>(
      `${NOMINATIM_URL}/search?${params.toString()}`,
      `forward:${query}`,
    );
    
    if (results && results.length > 0) {
      return {
        lat: parseFloat(results[0].lat),
        lng: parseFloat(results[0].lon),
        displayName: results[0].display_name,
      };
    }
    
    // Fallback: Try with just district and city
    if (villageName) {
      const fallbackQuery = [districtName, cityName, provinceName, 'Indonesia']
        .filter(Boolean)
        .join(', ');
      
      const fallbackParams = new URLSearchParams({
        q: fallbackQuery,
        format: 'json',
        limit: '1',
        countrycodes: 'id',
      });

      const fallbackResults = await fetchNominatim<Array<{ lat: string; lon: string; display_name: string }>>(
        `${NOMINATIM_URL}/search?${fallbackParams.toString()}`,
        `forward:${fallbackQuery}`,
      );

      if (fallbackResults) {
        if (fallbackResults.length > 0) {
          return {
            lat: parseFloat(fallbackResults[0].lat),
            lng: parseFloat(fallbackResults[0].lon),
            displayName: fallbackResults[0].display_name,
          };
        }
      }
    }
    
    return null;
  } catch (error) {
    console.error('Geocoding error:', error);
    return null;
  }
}

/** Resolve an address typed directly by the user into map coordinates. */
export async function geocodeFreeformAddress(query: string): Promise<GeocodingResult | null> {
  const normalizedQuery = query.trim();
  if (normalizedQuery.length < 4) return null;

  try {
    const params = new URLSearchParams({
      q: `${normalizedQuery}, Indonesia`,
      format: 'json',
      limit: '1',
      countrycodes: 'id',
      addressdetails: '1',
    });
    const results = await fetchNominatim<Array<{ lat: string; lon: string; display_name: string }>>(
      `${NOMINATIM_URL}/search?${params.toString()}`,
      `freeform:${normalizedQuery.toLowerCase()}`,
    );
    const result = results?.[0];
    if (!result) return null;
    return { lat: Number(result.lat), lng: Number(result.lon), displayName: result.display_name };
  } catch (error) {
    console.error('Free-form geocoding error:', error);
    return null;
  }
}

/** Search a short list of Indonesian address suggestions for autocomplete. */
export async function searchAddressSuggestions(query: string): Promise<AddressSuggestion[]> {
  const normalizedQuery = query.trim();
  if (normalizedQuery.length < 3) return [];

  try {
    const params = new URLSearchParams({
      q: normalizedQuery,
      format: 'jsonv2',
      addressdetails: '1',
      limit: '5',
      countrycodes: 'id',
      'accept-language': 'id',
    });
    const results = await fetchNominatim<Array<{ place_id: number; lat: string; lon: string; display_name: string }>>(
      `${NOMINATIM_URL}/search?${params.toString()}`,
      `suggestions:${normalizedQuery.toLowerCase()}`,
    );
    return (results ?? []).map((result) => ({
      id: String(result.place_id),
      lat: Number(result.lat),
      lng: Number(result.lon),
      displayName: result.display_name,
    }));
  } catch (error) {
    console.warn('Nominatim autocomplete unavailable:', error);
    return [];
  }
}

/**
 * Reverse geocoding - convert coordinates to address
 */
export async function reverseGeocode(
  lat: number,
  lng: number,
  options: GeocodingOptions = {},
): Promise<ReverseGeocodingResult | null> {
  try {
    if (options.provider === 'google') {
      try {
        const result = await callGoogleMapsFunction<GoogleMapsGeocodeResult | null>({
          action: 'reverse-geocode',
          point: { lat, lng },
        });
        if (result) {
          return {
            province: result.province,
            city: result.city,
            district: result.district,
            village: result.village,
            displayName: result.displayName,
            fullAddress: result.fullAddress ?? result.displayName,
            postcode: result.postcode,
          };
        }
      } catch {
        // Fall back to the existing provider; do not block checkout address entry.
      }
    }

    const params = new URLSearchParams({
      lat: lat.toString(),
      lon: lng.toString(),
      format: 'json',
      addressdetails: '1',
      'accept-language': 'id',
    });

    const result = await fetchNominatim<{ address?: Record<string, string>; display_name?: string }>(
      `${NOMINATIM_URL}/reverse?${params.toString()}`,
      `reverse:${lat.toFixed(5)},${lng.toFixed(5)}`,
    );
    
    if (result.address) {
      const addr = result.address;
      
      // Extract address components with priority order for Indonesian regions
      const province = addr.state || addr.province;
      const city = addr.city || addr.county || addr.municipality || addr.regency;
      const district = addr.suburb || addr.subdistrict || addr.district || addr.town;
      const village = addr.village || addr.neighbourhood || addr.hamlet || addr.locality;
      const postcode = addr.postcode;
      
      return {
        province,
        city,
        district,
        village,
        displayName: result.display_name,
        fullAddress: result.display_name,
        postcode,
      };
    }
    
    return null;
  } catch (error) {
    console.error('Reverse geocoding error:', error);
    return null;
  }
}

/**
 * Format address summary for display
 */
export function formatAddressSummary(address: ReverseGeocodingResult | null): string {
  if (!address) return 'Alamat tidak terdeteksi';
  
  const parts: string[] = [];
  
  if (address.village) parts.push(address.village);
  if (address.district) parts.push(`Kec. ${address.district}`);
  if (address.city) parts.push(`Kota ${address.city}`);
  if (address.province) {
    // Remove 'Provinsi' prefix if present
    const provinceName = address.province.replace(/^Provinsi\s+/i, '');
    parts.push(`Prov. ${provinceName}`);
  }
  
  return parts.join(', ');
}

/**
 * Get address summary from coordinates (optimized for display)
 */
export async function getAddressSummary(lat: number, lng: number): Promise<AddressSummary | null> {
  try {
    const result = await reverseGeocode(lat, lng);
    
    if (!result) return null;
    
    return {
      province: result.province?.replace(/^Provinsi\s+/i, ''),
      city: result.city?.replace(/^Kota\s+|^Kab\.\s+/i, ''),
      district: result.district,
      village: result.village,
      coordinates: { lat, lng },
    };
  } catch (error) {
    console.error('Error getting address summary:', error);
    return null;
  }
}

/**
 * Hook for using geocoding functionality
 */
export function useGeocoding(options: GeocodingOptions = {}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const provider = options.provider;

  const getCoordinatesFromAddress = useCallback(async (
    districtName: string,
    villageName: string,
    cityName?: string,
    provinceName?: string
  ): Promise<GeocodingResult | null> => {
    setLoading(true);
    setError(null);
    
    try {
      const result = await geocodeAddress(districtName, villageName, cityName, provinceName, { provider });
      return result;
    } catch (err) {
      setError('Gagal mendapatkan koordinat');
      return null;
    } finally {
      setLoading(false);
    }
  }, [provider]);

  const getAddressFromCoordinates = useCallback(async (
    lat: number,
    lng: number
  ): Promise<ReverseGeocodingResult | null> => {
    setLoading(true);
    setError(null);
    
    try {
      const result = await reverseGeocode(lat, lng, { provider });
      return result;
    } catch (err) {
      setError('Gagal mendapatkan alamat');
      return null;
    } finally {
      setLoading(false);
    }
  }, [provider]);

  return {
    loading,
    error,
    getCoordinatesFromAddress,
    getAddressFromCoordinates,
  };
}
