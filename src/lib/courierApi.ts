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

export interface AuthorizedCourierContact {
  id: string;
  user_id: string | null;
  name: string;
  phone: string;
  vehicle_type: string;
  vehicle_plate: string | null;
  photo_url: string;
  rating_avg: number | null;
  rating_count: number | null;
  current_lat: number | null;
  current_lng: number | null;
}

/** Read driver contact data through the scoped RPC, never from couriers directly. */
export async function getAuthorizedCourierContact(
  courierId: string,
  context: { orderId?: string; rideId?: string } = {},
): Promise<AuthorizedCourierContact | null> {
  const { data, error } = await supabase.rpc('get_courier_contact' as never, {
    p_courier_id: courierId,
    p_order_id: context.orderId ?? null,
    p_ride_id: context.rideId ?? null,
  } as never);
  if (error || !data) return null;
  const row = Array.isArray(data) ? data[0] : data;
  return (row as AuthorizedCourierContact | undefined) ?? null;
}

export async function autoAssignCourier(
  orderId: string,
  merchantLat?: number,
  merchantLng?: number,
  maxDistanceKm: number = 10,
): Promise<AssignCourierResult> {
  try {
    void merchantLat;
    void merchantLng;
    void maxDistanceKm;
    const { data, error } = await supabase.rpc('dispatch_merchant_order' as never, {
      p_order_id: orderId,
    } as never);
    if (error) return { success: false, error: error.message || 'Gagal menugaskan kurir' };
    const result = data as { dispatch_status?: string; courier_id?: string } | null;
    if (result?.dispatch_status !== 'OFFERED') {
      return { success: false, error: 'Belum ada kurir aktif yang tersedia di sekitar toko' };
    }
    return {
      success: true,
      courier: result.courier_id ? {
        id: result.courier_id,
        name: 'Kurir terdekat',
        distance_km: 0,
        vehicle_type: 'motor',
      } : undefined,
    };
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
      .eq('is_available', true);

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
