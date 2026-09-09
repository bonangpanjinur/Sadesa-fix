import { supabase } from '@/integrations/supabase/client';

interface AssignCourierResult {
  success: boolean;
  courier?: {
    id: string;
    name: string;
    distance_km: number;
    vehicle_type: string;
  };
  error?: string;
  candidates_count?: number;
}

const API_BASE = '/api';

export async function autoAssignCourier(
  orderId: string,
  merchantLat?: number,
  merchantLng?: number,
  maxDistanceKm: number = 10
): Promise<AssignCourierResult> {
  try {
    const response = await fetch(`${API_BASE}/assign-courier`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        order_id: orderId,
        merchant_lat: merchantLat,
        merchant_lng: merchantLng,
        max_distance_km: maxDistanceKm,
      }),
    });

    if (!response.ok) {
      const err = await response.json().catch(() => ({ error: 'Failed to assign courier' }));
      return { success: false, error: err.error || 'Failed to assign courier' };
    }

    return response.json();
  } catch (err) {
    console.error('Error in autoAssignCourier:', err);
    return { success: false, error: 'Failed to assign courier' };
  }
}

export async function manualAssignCourier(
  orderId: string,
  courierId: string
): Promise<{ success: boolean; error?: string }> {
  try {
    const { error } = await supabase.rpc('create_delivery_offer' as never, {
      p_order_id: orderId,
      p_courier_id: courierId,
    });
    if (error) {
      console.error('Error assigning courier:', error);
      return { success: false, error: error.message || 'Gagal menugaskan kurir' };
    }
    return { success: true };
  } catch (err) {
    console.error('Error in manualAssignCourier:', err);
    return { success: false, error: 'Terjadi kesalahan' };
  }
}

export async function getAvailableCouriers(
  lat?: number,
  lng?: number,
  maxDistanceKm: number = 10
): Promise<Array<{
  id: string;
  name: string;
  vehicle_type: string;
  distance_km?: number;
  active_orders: number;
}>> {
  try {
    const { data: couriers, error } = await supabase
      .from('couriers')
      .select('id, name, vehicle_type, current_lat, current_lng, last_location_update')
      .eq('status', 'ACTIVE')
      .eq('registration_status', 'APPROVED')
      .eq('is_available', true)
      .gte('last_location_update', new Date(Date.now() - 5 * 60 * 1000).toISOString());

    if (error || !couriers) return [];

    const courierIds = couriers.map((c) => c.id);
    const { data: activeOrders } = await supabase
      .from('orders')
      .select('courier_id')
      .in('courier_id', courierIds)
      .in('status', ['ASSIGNED', 'PICKED_UP', 'SENT', 'ON_DELIVERY', 'DELIVERING']);

    const orderCounts: Record<string, number> = {};
    activeOrders?.forEach((o) => {
      orderCounts[o.courier_id] = (orderCounts[o.courier_id] || 0) + 1;
    });

    return couriers
      .map((c) => {
        let distance_km: number | undefined;
        if (lat && lng && c.current_lat && c.current_lng) {
          distance_km = calculateDistance(lat, lng, c.current_lat, c.current_lng);
        }
        return {
          id: c.id,
          name: c.name,
          vehicle_type: c.vehicle_type,
          distance_km,
          active_orders: orderCounts[c.id] || 0,
        };
      })
      .filter((c) => !c.distance_km || c.distance_km <= maxDistanceKm)
      .sort((a, b) => {
        if (a.distance_km && b.distance_km) {
          return a.distance_km - b.distance_km;
        }
        return a.active_orders - b.active_orders;
      });
  } catch (err) {
    console.error('Error getting available couriers:', err);
    return [];
  }
}

function calculateDistance(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}
