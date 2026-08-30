import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const allowedOrigins = new Set((Deno.env.get('ALLOWED_ORIGINS') ?? 'https://www.sadesa.id,https://sadesa.id')
  .split(',').map((origin) => origin.trim()).filter(Boolean))

function headers(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://www.sadesa.id',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Content-Type': 'application/json',
    'Vary': 'Origin',
  }
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: headers(req) })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(req) })
  if (!['GET', 'POST', 'DELETE'].includes(req.method)) return json(req, { error: 'Method not allowed' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const authHeader = req.headers.get('Authorization')
  if (!supabaseUrl || !serviceRoleKey || !anonKey || !authHeader?.startsWith('Bearer ')) {
    return json(req, { error: 'Authentication required' }, 401)
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: { user }, error: authError } = await authClient.auth.getUser()
  if (authError || !user) return json(req, { error: 'Invalid authentication token' }, 401)

  const db = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })

  if (req.method === 'GET') {
    const publicKey = Deno.env.get('VAPID_PUBLIC_KEY') ?? ''
    if (!publicKey) return json(req, { error: 'VAPID key unavailable' }, 503)
    return json(req, { publicKey })
  }

  if (req.method === 'DELETE') {
    const { endpoint } = await req.json().catch(() => ({}))
    if (typeof endpoint !== 'string' || endpoint.length < 10 || endpoint.length > 2048) {
      return json(req, { error: 'Invalid endpoint' }, 400)
    }
    const { error } = await db.from('push_subscriptions').delete().eq('user_id', user.id).eq('endpoint', endpoint)
    if (error) return json(req, { error: 'Unable to remove subscription' }, 500)
    return json(req, { success: true })
  }

  const { subscription } = await req.json().catch(() => ({}))
  const endpoint = subscription?.endpoint
  const p256dh = subscription?.keys?.p256dh
  const auth = subscription?.keys?.auth
  if (typeof endpoint !== 'string' || endpoint.length < 10 || endpoint.length > 2048
    || typeof p256dh !== 'string' || typeof auth !== 'string') {
    return json(req, { error: 'Invalid push subscription' }, 400)
  }

  const { error } = await db.from('push_subscriptions').upsert({
    user_id: user.id,
    endpoint,
    p256dh,
    auth,
    updated_at: new Date().toISOString(),
  }, { onConflict: 'user_id,endpoint' })
  if (error) return json(req, { error: 'Unable to save subscription' }, 500)
  return json(req, { success: true })
})
