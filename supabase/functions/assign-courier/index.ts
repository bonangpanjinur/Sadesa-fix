import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const allowedOrigins = new Set((Deno.env.get('ALLOWED_ORIGINS') ?? 'https://sadesa.id')
  .split(',').map((origin) => origin.trim()).filter(Boolean));

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? '';
  return {
    'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://sadesa.id',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

interface CourierCandidate {
  id: string
  name: string
  current_lat: number
  current_lng: number
  vehicle_type: string
  active_orders: number
  distance_km: number
}

// Haversine formula to calculate distance between two coordinates
function calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371 // Earth's radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a = 
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: getCorsHeaders(req) })
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' },
    })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const authHeader = req.headers.get('Authorization')

    if (!supabaseUrl || !serviceRoleKey || !anonKey || !authHeader?.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Authentication required' }),
        { status: 401, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false }
    })
    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication token' }),
        { status: 401, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    const { order_id, merchant_lat, merchant_lng, max_distance_km = 10 } = await req.json()
    const maxDistance = Number(max_distance_km);
    if (typeof order_id !== 'string' || order_id.length > 80
      || !Number.isFinite(maxDistance) || maxDistance <= 0 || maxDistance > 100) {
      return new Response(JSON.stringify({ error: 'Invalid courier assignment request' }), {
        status: 400, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' },
      })
    }
    if ((merchant_lat !== undefined && (!Number.isFinite(Number(merchant_lat)) || Math.abs(Number(merchant_lat)) > 90))
      || (merchant_lng !== undefined && (!Number.isFinite(Number(merchant_lng)) || Math.abs(Number(merchant_lng)) > 180))) {
      return new Response(JSON.stringify({ error: 'Invalid merchant coordinates' }), {
        status: 400, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' },
      })
    }

    if (!order_id) {
      return new Response(
        JSON.stringify({ error: 'order_id is required' }),
        { status: 400, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // Check if order exists and is in correct status
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, status, courier_id, merchant_id')
      .eq('id', order_id)
      .single()

    if (orderError || !order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    if (!['PROCESSING', 'PROCESSED', 'READY'].includes(order.status)) {
      return new Response(
        JSON.stringify({ error: `Order status ${order.status} cannot be assigned to a courier` }),
        { status: 409, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    const [{ data: adminRole }, { data: ownedMerchant }] = await Promise.all([
      supabase
        .from('user_roles')
        .select('role')
        .eq('user_id', user.id)
        .eq('role', 'admin')
        .maybeSingle(),
      supabase
        .from('merchants')
        .select('id')
        .eq('id', order.merchant_id)
        .eq('user_id', user.id)
        .maybeSingle(),
    ])

    if (!adminRole && !ownedMerchant) {
      return new Response(
        JSON.stringify({ error: 'You are not allowed to assign a courier for this order' }),
        { status: 403, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    if (order.courier_id) {
      return new Response(
        JSON.stringify({ error: 'Order already has courier assigned', courier_id: order.courier_id }),
        { status: 400, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // Get merchant location if not provided
    let pickupLat = merchant_lat
    let pickupLng = merchant_lng

    if (!pickupLat || !pickupLng) {
      // Try to get from merchant's village or use default
      const { data: merchant } = await supabase
        .from('merchants')
        .select('address, city, district')
        .eq('id', order.merchant_id)
        .single()
      
      // For now, use a default location if not provided
      // In production, this should geocode the merchant's address
      pickupLat = pickupLat || -6.9175  // Default to Bandung
      pickupLng = pickupLng || 107.6191
    }

    // Find available couriers
    const { data: couriers, error: courierError } = await supabase
      .from('couriers')
      .select('id, name, current_lat, current_lng, vehicle_type')
      .eq('status', 'ACTIVE')
      .eq('registration_status', 'APPROVED')
      .eq('is_available', true)
      .not('current_lat', 'is', null)
      .not('current_lng', 'is', null)
      .gte('last_location_update', new Date(Date.now() - 5 * 60 * 1000).toISOString())

    if (courierError || !couriers || couriers.length === 0) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'No available couriers found',
          couriers_checked: 0
        }),
        { status: 200, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // Get active order counts for each courier
    const courierIds = couriers.map(c => c.id)
    const { data: activeOrders } = await supabase
      .from('orders')
      .select('courier_id')
      .in('courier_id', courierIds)
      .in('status', ['ASSIGNED', 'PICKED_UP', 'SENT', 'ON_DELIVERY', 'DELIVERING'])

    const orderCounts: Record<string, number> = {}
    activeOrders?.forEach(o => {
      orderCounts[o.courier_id] = (orderCounts[o.courier_id] || 0) + 1
    })

    // Calculate distances and score couriers
    const candidates: CourierCandidate[] = couriers
      .map(c => ({
        id: c.id,
        name: c.name,
        current_lat: c.current_lat!,
        current_lng: c.current_lng!,
        vehicle_type: c.vehicle_type,
        active_orders: orderCounts[c.id] || 0,
        distance_km: calculateDistance(
          c.current_lat!,
          c.current_lng!,
          pickupLat,
          pickupLng
        )
      }))
      .filter(c => c.distance_km <= maxDistance)
      .filter(c => c.active_orders < 3) // Max 3 concurrent orders per courier
      .sort((a, b) => {
        // Score based on distance (primary) and active orders (secondary)
        const scoreA = a.distance_km + (a.active_orders * 2)
        const scoreB = b.distance_km + (b.active_orders * 2)
        return scoreA - scoreB
      })

    if (candidates.length === 0) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'No suitable couriers within range',
          couriers_checked: couriers.length,
          max_distance_km: maxDistance
        }),
        { status: 200, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // Assign the best candidate
    const bestCourier = candidates[0]

    const { data: assignment, error: assignmentError } = await supabase
      .from('delivery_assignments')
      .insert({ order_id, courier_id: bestCourier.id, created_by: user.id })
      .select('id')
      .single()

    if (assignmentError) {
      console.error('Error creating courier offer:', assignmentError)
      return new Response(
        JSON.stringify({ error: 'Failed to create courier offer' }),
        { status: 500, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    const { error: orderError } = await supabase
      .from('orders')
      .update({ status: 'ASSIGNED', status_updated_at: new Date().toISOString() })
      .eq('id', order_id)
      .in('status', ['PROCESSING', 'PROCESSED', 'READY'])

    if (orderError) {
      console.error('Error marking order as offered:', orderError)
      return new Response(
        JSON.stringify({ error: 'Failed to mark order as offered' }),
        { status: 500, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // Create notification for courier
    const { data: courierData } = await supabase
      .from('couriers')
      .select('user_id')
      .eq('id', bestCourier.id)
      .single()

    if (courierData?.user_id) {
      await supabase.from('notifications').insert({
        user_id: courierData.user_id,
        title: 'Tawaran Pengiriman Baru',
        message: `Ada tawaran pengiriman baru #${order_id.slice(0, 8).toUpperCase()}. Pilih Terima atau Tolak.`,
        type: 'order',
        link: `/courier/rides?orderId=${order_id}`
      })
    }

    return new Response(
      JSON.stringify({
        success: true,
        courier: {
          id: bestCourier.id,
          name: bestCourier.name,
          distance_km: Math.round(bestCourier.distance_km * 10) / 10,
          vehicle_type: bestCourier.vehicle_type
        },
        candidates_count: candidates.length,
        assignment_id: assignment.id,
        dispatch_status: 'OFFERED'
      }),
      { status: 200, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error in assign-courier:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
    )
  }
})
