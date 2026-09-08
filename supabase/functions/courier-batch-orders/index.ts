import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const allowedOrigins = new Set(
  (Deno.env.get('ALLOWED_ORIGINS') ?? 'https://sadesa.id')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
)

const AVAILABLE_STATUSES = ['PROCESSING', 'PROCESSED', 'READY']
const ACTIVE_STATUSES = ['ASSIGNED', 'PICKED_UP', 'SENT', 'DELIVERING']

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://sadesa.id',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json',
    'Vary': 'Origin',
  }
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(req) })
}

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) })
  if (req.method !== 'POST') return json(req, { error: 'Method not allowed' }, 405)

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const authorization = req.headers.get('Authorization')

    if (!supabaseUrl || !serviceRoleKey || !anonKey || !authorization?.startsWith('Bearer ')) {
      return json(req, { error: 'Authentication required' }, 401)
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) return json(req, { error: 'Invalid authentication token' }, 401)

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { action = 'available', limit = 12, order_ids: orderIds } = await req.json().catch(() => ({}))

    const { data: courier, error: courierError } = await adminClient
      .from('couriers')
      .select('id, name, status, registration_status')
      .eq('user_id', user.id)
      .maybeSingle()

    if (courierError || !courier || courier.registration_status !== 'APPROVED' || courier.status !== 'ACTIVE') {
      return json(req, { error: 'Kurir tidak aktif atau belum disetujui' }, 403)
    }

    const { count: activeCount, error: activeError } = await adminClient
      .from('orders')
      .select('id', { count: 'exact', head: true })
      .eq('courier_id', courier.id)
      .in('status', ACTIVE_STATUSES)
    if (activeError) return json(req, { error: 'Gagal menghitung pesanan aktif' }, 500)

    const canAccept = Math.max(0, 3 - (activeCount ?? 0))

    if (action === 'available') {
      const requestedLimit = Number(limit)
      const safeLimit = Number.isFinite(requestedLimit) ? Math.min(Math.max(Math.trunc(requestedLimit), 1), 12) : 12
      const { data: orders, error: ordersError } = await adminClient
        .from('orders')
        .select('id, total, status, created_at, delivery_address, delivery_name, merchant_id')
        .is('courier_id', null)
        .in('status', AVAILABLE_STATUSES)
        .order('created_at', { ascending: true })
        .limit(safeLimit)

      if (ordersError) return json(req, { error: 'Gagal memuat pesanan yang tersedia' }, 500)

      const merchantIds = [...new Set((orders ?? []).map((order) => order.merchant_id).filter(isUuid))]
      const { data: merchants } = merchantIds.length
        ? await adminClient.from('merchants').select('id, name, address').in('id', merchantIds)
        : { data: [] }
      const merchantMap = new Map((merchants ?? []).map((merchant) => [merchant.id, merchant]))

      return json(req, {
        orders: (orders ?? []).map((order) => {
          const merchant = merchantMap.get(order.merchant_id)
          return {
            id: order.id,
            total: order.total,
            status: order.status,
            created_at: order.created_at,
            shipping_address: order.delivery_address,
            buyer_name: order.delivery_name,
            merchant_name: merchant?.name ?? null,
            merchant_address: merchant?.address ?? null,
          }
        }),
        can_accept: canAccept,
      })
    }

    if (action !== 'accept') return json(req, { error: 'Action batching tidak dikenal' }, 400)
    if (!Array.isArray(orderIds) || orderIds.length < 2 || orderIds.length > 3 || !orderIds.every(isUuid)) {
      return json(req, { error: 'Pilih 2–3 pesanan yang valid' }, 400)
    }
    const uniqueOrderIds = [...new Set(orderIds)]
    if (uniqueOrderIds.length !== orderIds.length) return json(req, { error: 'Pesanan tidak boleh duplikat' }, 400)
    if (uniqueOrderIds.length > canAccept) {
      return json(req, { error: `Kurir hanya dapat menerima ${canAccept} pesanan lagi` }, 409)
    }

    const { data: availableOrders, error: availableError } = await adminClient
      .from('orders')
      .select('id')
      .in('id', uniqueOrderIds)
      .is('courier_id', null)
      .in('status', AVAILABLE_STATUSES)
    if (availableError) return json(req, { error: 'Gagal memeriksa ketersediaan pesanan' }, 500)
    if ((availableOrders ?? []).length !== uniqueOrderIds.length) {
      return json(req, { error: 'Sebagian pesanan sudah diambil atau tidak lagi tersedia' }, 409)
    }

    const { data: claimedOrders, error: claimError } = await adminClient
      .from('orders')
      .update({
        courier_id: courier.id,
        status: 'ASSIGNED',
        assigned_at: new Date().toISOString(),
      })
      .in('id', uniqueOrderIds)
      .is('courier_id', null)
      .select('id')

    if (claimError) return json(req, { error: 'Gagal menerima pesanan' }, 500)
    if ((claimedOrders ?? []).length !== uniqueOrderIds.length) {
      return json(req, { error: 'Sebagian pesanan baru saja diambil kurir lain' }, 409)
    }

    const { data: courierUser } = await adminClient
      .from('couriers')
      .select('user_id')
      .eq('id', courier.id)
      .maybeSingle()
    if (courierUser?.user_id) {
      await adminClient.from('notifications').insert({
        user_id: courierUser.user_id,
        title: 'Pesanan Batch Baru',
        message: `${uniqueOrderIds.length} pesanan berhasil ditambahkan ke pengiriman Anda.`,
        type: 'order',
        link: '/courier',
      })
    }

    return json(req, {
      message: `${uniqueOrderIds.length} pesanan berhasil di-batch!`,
      order_ids: uniqueOrderIds,
    })
  } catch (error) {
    console.error('Error in courier-batch-orders:', error)
    return json(req, { error: 'Terjadi kesalahan pada layanan batching' }, 500)
  }
})