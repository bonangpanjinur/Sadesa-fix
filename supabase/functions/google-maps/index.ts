import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const allowedOrigins = new Set([
  'https://sadesa.id',
  'https://www.sadesa.id',
])
const routeCache = new Map<string, { expiresAt: number; value: RouteResult }>()
const geocodeCache = new Map<string, { expiresAt: number; value: GoogleGeocodeResult | null }>()
const CACHE_TTL_MS = 5 * 60_000
const CACHE_LIMIT = 256

interface Point {
  lat: number
  lng: number
}

interface RouteResult {
  distanceKm: number
  durationMinutes: number
  geometry: Point[]
  provider: 'google' | 'fallback'
}

interface GoogleGeocodeResult {
  lat: number
  lng: number
  displayName?: string
  fullAddress?: string
  province?: string
  city?: string
  district?: string
  village?: string
  postcode?: string
}

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://sadesa.id',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, accept, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  }
}

function jsonResponse(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}

function isPoint(value: unknown): value is Point {
  if (!value || typeof value !== 'object') return false
  const point = value as Record<string, unknown>
  return typeof point.lat === 'number' && Number.isFinite(point.lat)
    && typeof point.lng === 'number' && Number.isFinite(point.lng)
    && point.lat >= -11 && point.lat <= 6
    && point.lng >= 95 && point.lng <= 141
}

function cacheGet<T>(cache: Map<string, { expiresAt: number; value: T }>, key: string): T | null {
  const entry = cache.get(key)
  if (!entry) return null
  if (entry.expiresAt <= Date.now()) {
    cache.delete(key)
    return null
  }
  return entry.value
}

function cachePut<T>(cache: Map<string, { expiresAt: number; value: T }>, key: string, value: T): void {
  if (cache.size >= CACHE_LIMIT) {
    const oldestKey = cache.keys().next().value
    if (oldestKey) cache.delete(oldestKey)
  }
  cache.set(key, { value, expiresAt: Date.now() + CACHE_TTL_MS })
}

function routeKey(origin: Point, destination: Point): string {
  return [origin.lat, origin.lng, destination.lat, destination.lng]
    .map((coordinate) => coordinate.toFixed(5)).join(':')
}

async function hmacBucket(value: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value))
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function canUseGoogleMaps(req: Request): Promise<boolean> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) return false

  try {
    const ip = req.headers.get('cf-connecting-ip')
      ?? req.headers.get('x-real-ip')
      ?? req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
      ?? 'unknown'
    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const clientBucket = await hmacBucket(`client:${ip}`, serviceRoleKey)
    const globalBucket = await hmacBucket('global:google-maps', serviceRoleKey)
    const { data: clientAllowed, error: clientError } = await client.rpc('consume_google_maps_rate_limit', {
      p_bucket_key: clientBucket,
      p_limit: 30,
      p_window_seconds: 60,
    })
    if (clientError || clientAllowed !== true) return false

    const { data: globalAllowed, error: globalError } = await client.rpc('consume_google_maps_rate_limit', {
      p_bucket_key: globalBucket,
      p_limit: 100,
      p_window_seconds: 60,
    })
    return !globalError && globalAllowed === true
  } catch {
    // Fail closed for billable Google requests until the shared limiter is installed.
    return false
  }
}

function decodePolyline(encoded: string): Point[] {
  const points: Point[] = []
  let index = 0
  let latitude = 0
  let longitude = 0

  while (index < encoded.length && points.length < 10_000) {
    let result = 0
    let shift = 0
    let byte: number
    do {
      byte = encoded.charCodeAt(index++) - 63
      result |= (byte & 0x1f) << shift
      shift += 5
    } while (byte >= 0x20 && index < encoded.length)
    latitude += result & 1 ? ~(result >> 1) : result >> 1

    result = 0
    shift = 0
    do {
      byte = encoded.charCodeAt(index++) - 63
      result |= (byte & 0x1f) << shift
      shift += 5
    } while (byte >= 0x20 && index < encoded.length)
    longitude += result & 1 ? ~(result >> 1) : result >> 1
    points.push({ lat: latitude / 1e5, lng: longitude / 1e5 })
  }

  return points
}

async function googleRoute(origin: Point, destination: Point, apiKey: string): Promise<RouteResult | null> {
  const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
    },
    body: JSON.stringify({
      origin: { location: { latLng: { latitude: origin.lat, longitude: origin.lng } } },
      destination: { location: { latLng: { latitude: destination.lat, longitude: destination.lng } } },
      travelMode: 'DRIVE',
      routingPreference: 'TRAFFIC_UNAWARE',
      computeAlternativeRoutes: false,
      languageCode: 'id-ID',
      units: 'METRIC',
    }),
    signal: AbortSignal.timeout(8_000),
  })
  if (!response.ok) {
    console.warn('Google route request failed', { status: response.status })
    return null
  }

  const payload = await response.json() as {
    routes?: Array<{ distanceMeters?: number; duration?: string; polyline?: { encodedPolyline?: string } }>
  }
  const route = payload.routes?.[0]
  const durationSeconds = Number(route?.duration?.replace(/s$/, ''))
  if (!route || !Number.isFinite(route.distanceMeters) || !Number.isFinite(durationSeconds)) return null

  return {
    distanceKm: Number(route.distanceMeters) / 1000,
    durationMinutes: Math.max(1, Math.ceil(durationSeconds / 60)),
    geometry: route.polyline?.encodedPolyline ? decodePolyline(route.polyline.encodedPolyline) : [],
    provider: 'google',
  }
}

async function fallbackRoute(origin: Point, destination: Point): Promise<RouteResult | null> {
  const coordinates = `${origin.lng},${origin.lat};${destination.lng},${destination.lat}`
  try {
    const response = await fetch(
      `https://router.project-osrm.org/route/v1/driving/${coordinates}?overview=full&geometries=geojson`,
      { signal: AbortSignal.timeout(8_000), headers: { Accept: 'application/json' } },
    )
    if (!response.ok) return null
    const payload = await response.json() as {
      code?: string
      routes?: Array<{
        distance?: number
        duration?: number
        geometry?: { coordinates?: Array<[number, number]> }
      }>
    }
    const route = payload.routes?.[0]
    if (payload.code !== 'Ok' || !route || !Number.isFinite(route.distance) || !Number.isFinite(route.duration)) {
      return null
    }
    return {
      distanceKm: Number(route.distance) / 1000,
      durationMinutes: Math.max(1, Math.ceil(Number(route.duration) / 60)),
      geometry: (route.geometry?.coordinates ?? []).map(([lng, lat]) => ({ lat, lng })),
      provider: 'fallback',
    }
  } catch {
    return null
  }
}

function componentName(
  components: Array<{ long_name: string; short_name: string; types: string[] }>,
  ...types: string[]
): string | undefined {
  return components.find((component) => types.some((type) => component.types.includes(type)))?.long_name
}

function normalizeGoogleAddress(result: {
  geometry?: { location?: { lat?: number; lng?: number } }
  formatted_address?: string
  address_components?: Array<{ long_name: string; short_name: string; types: string[] }>
}): GoogleGeocodeResult | null {
  const lat = result.geometry?.location?.lat
  const lng = result.geometry?.location?.lng
  if (typeof lat !== 'number' || typeof lng !== 'number' || !isPoint({ lat, lng })) return null
  const components = result.address_components ?? []
  const displayName = result.formatted_address
  return {
    lat,
    lng,
    displayName,
    fullAddress: displayName,
    province: componentName(components, 'administrative_area_level_1'),
    city: componentName(components, 'administrative_area_level_2', 'locality'),
    district: componentName(components, 'administrative_area_level_3', 'sublocality_level_1'),
    village: componentName(components, 'administrative_area_level_4', 'sublocality_level_2', 'neighborhood'),
    postcode: componentName(components, 'postal_code'),
  }
}

async function googleGeocode(query: string, apiKey: string): Promise<GoogleGeocodeResult | null> {
  const cacheKey = await hmacBucket(`address:${query.toLocaleLowerCase('id-ID')}`, apiKey)
  const cached = cacheGet(geocodeCache, cacheKey)
  if (cached !== null) return cached

  const url = new URL('https://maps.googleapis.com/maps/api/geocode/json')
  url.searchParams.set('address', query)
  url.searchParams.set('key', apiKey)
  url.searchParams.set('region', 'id')
  url.searchParams.set('language', 'id')
  const response = await fetch(url, { signal: AbortSignal.timeout(8_000) })
  if (!response.ok) return null
  const payload = await response.json() as {
    status?: string
    results?: Array<Parameters<typeof normalizeGoogleAddress>[0]>
  }
  const result = payload.status === 'OK' ? normalizeGoogleAddress(payload.results?.[0] ?? {}) : null
  cachePut(geocodeCache, cacheKey, result)
  return result
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers })
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Method not allowed' }, 405)

  const origin = req.headers.get('Origin')
  if (origin && !allowedOrigins.has(origin)) return jsonResponse(req, { error: 'Origin not allowed' }, 403)
  if (!req.headers.get('Authorization')?.startsWith('Bearer ') || !req.headers.get('apikey')) {
    return jsonResponse(req, { error: 'Supabase client headers required' }, 401)
  }
  const contentLength = Number(req.headers.get('Content-Length') ?? 0)
  if (contentLength > 8_192) return jsonResponse(req, { error: 'Request too large' }, 413)

  let parsedBody: unknown
  try {
    parsedBody = await req.json()
  } catch {
    return jsonResponse(req, { error: 'Invalid JSON body' }, 400)
  }
  if (!parsedBody || typeof parsedBody !== 'object' || Array.isArray(parsedBody)) {
    return jsonResponse(req, { error: 'Invalid request body' }, 400)
  }
  const body = parsedBody as Record<string, unknown>

  const action = body.action
  const apiKey = Deno.env.get('GOOGLE_MAPS_SERVER_API_KEY') ?? ''

  if (action === 'route') {
    const originPoint = body.origin
    const destinationPoint = body.destination
    if (!isPoint(originPoint) || !isPoint(destinationPoint)) {
      return jsonResponse(req, { error: 'Valid Indonesian route coordinates are required' }, 400)
    }

    const key = routeKey(originPoint, destinationPoint)
    const cached = cacheGet(routeCache, key)
    if (cached) return jsonResponse(req, cached)

    const rateAllowed = apiKey ? await canUseGoogleMaps(req) : false
    if (apiKey && rateAllowed) {
      try {
        const route = await googleRoute(originPoint, destinationPoint, apiKey)
        if (route) {
          cachePut(routeCache, key, route)
          return jsonResponse(req, route)
        }
      } catch {
        console.warn('Google route provider unavailable')
      }
    }

    const route = await fallbackRoute(originPoint, destinationPoint)
    if (!route) return jsonResponse(req, { error: 'Route service unavailable' }, 503)
    cachePut(routeCache, key, route)
    return jsonResponse(req, route)
  }

  if (action === 'geocode' || action === 'reverse-geocode') {
    if (!apiKey) {
      return jsonResponse(req, { error: 'Google geocoding is not available' }, 503)
    }

    let query: string
    if (action === 'geocode') {
      if (typeof body.address !== 'string' || body.address.trim().length < 4 || body.address.length > 500) {
        return jsonResponse(req, { error: 'Valid address text is required' }, 400)
      }
      query = body.address.trim()
    } else {
      if (!isPoint(body.point)) return jsonResponse(req, { error: 'Valid Indonesian coordinates are required' }, 400)
      query = `${body.point.lat},${body.point.lng}`
    }

    try {
      const cacheKey = await hmacBucket(`address:${query.toLocaleLowerCase('id-ID')}`, apiKey)
      const cached = cacheGet(geocodeCache, cacheKey)
      if (cached) return jsonResponse(req, cached)
      if (!(await canUseGoogleMaps(req))) {
        return jsonResponse(req, { error: 'Google geocoding is rate limited or unavailable' }, 503)
      }
      const result = await googleGeocode(query, apiKey)
      return result ? jsonResponse(req, result) : jsonResponse(req, null, 404)
    } catch {
      return jsonResponse(req, { error: 'Google geocoding unavailable' }, 503)
    }
  }

  return jsonResponse(req, { error: 'Unsupported maps action' }, 400)
})
