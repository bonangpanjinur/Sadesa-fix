const FALLBACK_ORIGIN = 'https://www.sadesa.id';

export function getPushSubscriptionCorsHeaders(
  origin: string | null,
  allowedOrigins: ReadonlySet<string>,
): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': origin && allowedOrigins.has(origin) ? origin : FALLBACK_ORIGIN,
    'Access-Control-Allow-Headers': [
      'authorization',
      'x-client-info',
      'apikey',
      'content-type',
      'x-supabase-client-platform',
      'x-supabase-client-platform-version',
      'x-supabase-client-runtime',
      'x-supabase-client-runtime-version',
    ].join(', '),
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Content-Type': 'application/json',
    Vary: 'Origin',
  };
}

export function pushSubscriptionJsonResponse(
  origin: string | null,
  allowedOrigins: ReadonlySet<string>,
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: getPushSubscriptionCorsHeaders(origin, allowedOrigins),
  });
}
