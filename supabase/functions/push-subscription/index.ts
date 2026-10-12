import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import {
  getPushSubscriptionCorsHeaders,
  pushSubscriptionJsonResponse,
} from './http.ts'

const allowedOrigins = new Set((Deno.env.get('ALLOWED_ORIGINS') ?? 'https://www.sadesa.id,https://sadesa.id')
  .split(',').map((origin) => origin.trim()).filter(Boolean))

type PushSubscriptionInput = {
  endpoint?: unknown
  keys?: {
    p256dh?: unknown
    auth?: unknown
  } | null
}

function headers(req: Request): Record<string, string> {
  return getPushSubscriptionCorsHeaders(req.headers.get('Origin'), allowedOrigins)
}

function json(req: Request, body: unknown, status = 200) {
  return pushSubscriptionJsonResponse(req.headers.get('Origin'), allowedOrigins, body, status)
}

function getVapidConfiguration() {
  const publicKey = Deno.env.get('VAPID_PUBLIC_KEY') ?? ''
  const privateKeyConfigured = Boolean(Deno.env.get('VAPID_PRIVATE_KEY'))
  const missingVariables = [
    !publicKey && 'VAPID_PUBLIC_KEY',
    !privateKeyConfigured && 'VAPID_PRIVATE_KEY',
  ].filter((name): name is string => Boolean(name))

  return {
    publicKey: publicKey || null,
    publicKeyConfigured: Boolean(publicKey),
    privateKeyConfigured,
    vapidConfigured: Boolean(publicKey && privateKeyConfigured),
    missingVariables,
  }
}

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID()
  let stage = 'request'

  try {
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(req) })
    if (!['GET', 'POST', 'DELETE'].includes(req.method)) {
      return json(req, { error: 'Method not allowed' }, 405)
    }

    stage = 'load_auth_configuration'
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    if (!supabaseUrl || !anonKey) {
      return json(req, { error: 'Push authentication service is not configured' }, 503)
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return json(req, { error: 'Authentication required' }, 401)
    }

    stage = 'verify_user'
    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) return json(req, { error: 'Invalid authentication token' }, 401)

    if (req.method === 'GET') {
      stage = 'read_vapid_configuration'
      return json(req, getVapidConfiguration())
    }

    let subscriptionRequest: { action?: unknown; subscription?: PushSubscriptionInput } = {}
    if (req.method === 'POST') {
      stage = 'parse_subscription_request'
      subscriptionRequest = await req.json().catch(() => ({}))
      if (subscriptionRequest.action === 'get_vapid_config') {
        stage = 'read_vapid_configuration'
        return json(req, getVapidConfiguration())
      }
    }

    stage = 'load_subscription_database_configuration'
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    if (!serviceRoleKey) {
      return json(req, { error: 'Push subscription storage is not configured' }, 503)
    }

    stage = 'create_subscription_database_client'
    const db = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })

    if (req.method === 'DELETE') {
      stage = 'parse_delete_request'
      const { endpoint } = await req.json().catch(() => ({}))
      if (typeof endpoint !== 'string' || endpoint.length < 10 || endpoint.length > 2048) {
        return json(req, { error: 'Invalid endpoint' }, 400)
      }
      stage = 'delete_subscription'
      const { error } = await db.from('push_subscriptions').delete().eq('user_id', user.id).eq('endpoint', endpoint)
      if (error) {
        console.error('[push-subscription] database delete failed', { requestId, error })
        return json(req, { error: 'Unable to remove subscription', requestId }, 500)
      }
      return json(req, { success: true })
    }

    stage = 'validate_subscription_request'
    const { subscription } = subscriptionRequest
    const endpoint = subscription?.endpoint
    const p256dh = subscription?.keys?.p256dh
    const auth = subscription?.keys?.auth
    if (typeof endpoint !== 'string' || endpoint.length < 10 || endpoint.length > 2048
      || typeof p256dh !== 'string' || typeof auth !== 'string') {
      return json(req, { error: 'Invalid push subscription' }, 400)
    }

    stage = 'save_subscription'
    const { error } = await db.from('push_subscriptions').upsert({
      user_id: user.id,
      endpoint,
      p256dh,
      auth,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'user_id,endpoint' })
    if (error) {
      console.error('[push-subscription] database upsert failed', { requestId, error })
      return json(req, { error: 'Unable to save subscription', requestId }, 500)
    }
    return json(req, { success: true })
  } catch (error) {
    console.error(`[push-subscription] ${stage} failed`, { requestId, error })
    return json(req, { error: 'Internal server error', requestId }, 500)
  }
})
