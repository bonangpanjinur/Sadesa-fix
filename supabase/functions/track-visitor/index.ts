import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}

function firstHeader(req: Request, names: string[]) {
  for (const name of names) {
    const value = req.headers.get(name)?.split(',')[0]?.trim();
    if (value) return value;
  }
  return null;
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function classifyUserAgent(userAgent: string) {
  const ua = userAgent.toLowerCase();
  const deviceType = /mobile|android|iphone|ipad|ipod/.test(ua) ? 'mobile' : /tablet/.test(ua) ? 'tablet' : 'desktop';
  const browserName = /edg\//.test(ua) ? 'Edge' : /chrome\//.test(ua) ? 'Chrome' : /firefox\//.test(ua) ? 'Firefox' : /safari\//.test(ua) ? 'Safari' : 'Lainnya';
  const osName = /android/.test(ua) ? 'Android' : /iphone|ipad|ipod/.test(ua) ? 'iOS' : /windows/.test(ua) ? 'Windows' : /mac os/.test(ua) ? 'macOS' : /linux/.test(ua) ? 'Linux' : 'Lainnya';
  return { deviceType, browserName, osName };
}

async function lookupLocation(ip: string | null) {
  if (!ip || ip === '127.0.0.1' || ip === '::1') return {};
  try {
    const response = await fetch(`https://ipapi.co/${encodeURIComponent(ip)}/json/`, { signal: AbortSignal.timeout(1800) });
    if (!response.ok) return {};
    const data = await response.json();
    return {
      country_code: typeof data.country_code === 'string' ? data.country_code.slice(0, 8) : null,
      country_name: typeof data.country_name === 'string' ? data.country_name.slice(0, 120) : null,
      region_name: typeof data.region === 'string' ? data.region.slice(0, 120) : null,
      city_name: typeof data.city === 'string' ? data.city.slice(0, 120) : null,
      latitude: Number.isFinite(Number(data.latitude)) ? Number(data.latitude) : null,
      longitude: Number.isFinite(Number(data.longitude)) ? Number(data.longitude) : null,
    };
  } catch {
    return {};
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceRoleKey) return json({ error: 'Analytics is not configured' }, 503);

  let payload: { path?: unknown; page_title?: unknown; referrer?: unknown; visitor_id?: unknown };
  try { payload = await req.json(); } catch { return json({ error: 'Invalid JSON' }, 400); }
  const path = typeof payload.path === 'string' ? payload.path.slice(0, 500) : '';
  if (!path.startsWith('/') || path.startsWith('/admin') || path.startsWith('/auth')) return json({ ok: true, skipped: true });

  const ipAddress = firstHeader(req, ['cf-connecting-ip', 'x-real-ip', 'x-forwarded-for']);
  const userAgent = (req.headers.get('user-agent') ?? '').slice(0, 1000);
  const visitorId = typeof payload.visitor_id === 'string' && /^[a-zA-Z0-9_-]{16,128}$/.test(payload.visitor_id) ? payload.visitor_id : crypto.randomUUID();
  const visitorKey = await sha256(`${visitorId}|${ipAddress ?? 'unknown'}`);
  const location = await lookupLocation(ipAddress);
  const client = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  // Count a route at most once per visitor every 30 seconds. This protects the
  // public endpoint from refresh loops while preserving normal navigation.
  const { data: recentEvent } = await client.from('visitor_analytics_events')
    .select('id').eq('visitor_key', visitorKey).eq('path', path)
    .gte('occurred_at', new Date(Date.now() - 30_000).toISOString()).limit(1).maybeSingle();
  if (recentEvent) return json({ ok: true, deduplicated: true });

  let viewerId: string | null = null;
  const authHeader = req.headers.get('authorization');
  if (authHeader?.startsWith('Bearer ')) {
    const authClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY') ?? '', { global: { headers: { Authorization: authHeader } } });
    const { data } = await authClient.auth.getUser();
    viewerId = data.user?.id ?? null;
  }

  const { deviceType, browserName, osName } = classifyUserAgent(userAgent);
  const { error } = await client.from('visitor_analytics_events').insert({
    path,
    page_title: typeof payload.page_title === 'string' ? payload.page_title.slice(0, 250) : null,
    referrer: typeof payload.referrer === 'string' ? payload.referrer.slice(0, 1000) : null,
    visitor_key: visitorKey,
    viewer_id: viewerId,
    ip_address: ipAddress,
    user_agent: userAgent || null,
    device_type: deviceType,
    browser_name: browserName,
    os_name: osName,
    ...location,
  });
  if (error) return json({ error: 'Unable to record analytics event' }, 500);
  return json({ ok: true });
});
