const allowedOrigins = new Set(['https://sadesa.id', 'https://www.sadesa.id']);

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin');
  return {
    'Access-Control-Allow-Origin': origin && allowedOrigins.has(origin) ? origin : 'https://www.sadesa.id',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, accept, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version, x-requested-with',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}

const EMSIFA_URL = 'https://www.emsifa.com/api-wilayah-indonesia/v2';

function normalizeV2Response(payload: unknown): { code: string; name: string }[] {
  if (typeof payload !== 'object' || payload === null || !('data' in payload) || !Array.isArray(payload.data)) {
    throw new Error('Unexpected EMSIFA v2 response: expected a data array');
  }

  return payload.data.map((item: unknown, index: number) => {
    if (typeof item !== 'object' || item === null || !('id' in item) || !('name' in item)
      || typeof item.id !== 'string' || typeof item.name !== 'string') {
      throw new Error(`Unexpected EMSIFA v2 region item at index ${index}`);
    }
    return { code: item.id, name: item.name };
  });
}

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req);
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== 'GET') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  try {
    const url = new URL(req.url);
    const type = url.searchParams.get('type');
    const code = url.searchParams.get('code');

    if (!type) {
      return new Response(
        JSON.stringify({ error: 'Missing type parameter' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    let emsifaUrl: string;
    switch (type) {
      case 'provinces':
        emsifaUrl = `${EMSIFA_URL}/provinces.json`;
        break;
      case 'regencies':
        if (!code) {
          return new Response(JSON.stringify({ error: 'Missing code parameter' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
        }
        emsifaUrl = `${EMSIFA_URL}/regencies/${code}.json`;
        break;
      case 'districts':
        if (!code) {
          return new Response(JSON.stringify({ error: 'Missing code parameter' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
        }
        emsifaUrl = `${EMSIFA_URL}/districts/${code}.json`;
        break;
      case 'villages':
        if (!code) {
          return new Response(JSON.stringify({ error: 'Missing code parameter' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
        }
        emsifaUrl = `${EMSIFA_URL}/villages/${code}.json`;
        break;
      default:
        return new Response(JSON.stringify({ error: 'Invalid type' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const codePatterns: Record<string, RegExp> = {
      regencies: /^\d{2}$/,
      districts: /^\d{2}\.\d{2}$/,
      villages: /^\d{2}\.\d{2}\.\d{2}$/,
    };
    if (code && codePatterns[type] && !codePatterns[type].test(code)) {
      return new Response(JSON.stringify({ error: 'Invalid code parameter' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    console.log('Fetching wilayah upstream', { type, hasCode: Boolean(code) });
    const response = await fetch(emsifaUrl, {
      headers: { 'Accept': 'application/json', 'User-Agent': 'DesaApp/1.0' },
    });

    if (!response.ok) {
      throw new Error(`emsifa returned ${response.status}`);
    }

    const json: unknown = await response.json();
    // EMSIFA v2 wraps results in { data, meta } and uses { id, name } items.
    // Keep the legacy proxy contract as a plain array of { code, name }.
    const data = normalizeV2Response(json);

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=86400' },
    });
  } catch (error) {
    console.error('Wilayah proxy failed', error instanceof Error ? error.message : 'unknown');
    return new Response(
      JSON.stringify({ error: 'Wilayah service unavailable' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
