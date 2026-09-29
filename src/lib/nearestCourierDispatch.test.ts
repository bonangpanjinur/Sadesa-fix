import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20260929011000_nearest_courier_sequential_ride_dispatch.sql'),
  'utf8',
);
const courierLayout = readFileSync(
  resolve(process.cwd(), 'src/components/courier/CourierLayout.tsx'),
  'utf8',
);
const courierRides = readFileSync(
  resolve(process.cwd(), 'src/pages/courier/CourierRidesPage.tsx'),
  'utf8',
);

describe('nearest courier sequential ride dispatch contract', () => {
  it('stores one pending offer per ride and expires it after 30 seconds', () => {
    expect(migration).toContain('ride_request_offers_one_attempt_per_courier');
    expect(migration).toContain("now() + interval '30 seconds'");
    expect(migration).toContain('idx_ride_request_offers_one_pending_per_ride');
  });

  it('selects only eligible, recently located couriers in ascending pickup distance', () => {
    expect(migration).toContain("c.registration_status = 'APPROVED'");
    expect(migration).toContain("c.last_location_update >= now() - interval '90 seconds'");
    expect(migration).toContain('ORDER BY ranked.distance_km ASC, ranked.id ASC');
    expect(migration).toContain('NOT EXISTS (\n        SELECT 1\n        FROM public.ride_request_offers concurrent_offer');
  });

  it('requires the targeted courier offer for acceptance and supports decline advancement', () => {
    expect(migration).toContain("AND status = 'PENDING'\n  FOR UPDATE");
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.decline_ride_request');
    expect(migration).toContain('PERFORM public.dispatch_next_ride_offer(p_ride_id);');
  });

  it('keeps expiry processing server-side when the optional RPC is unavailable', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.process_expired_ride_offers()');
    expect(courierLayout).not.toContain("process_expired_ride_offers");
    expect(courierRides).toContain("process_expired_ride_offers");
    expect(courierRides).toContain("supabase.rpc('decline_ride_request' as never");
  });

  it('renders only the currently targeted courier offer in the ride inbox', () => {
    expect(courierRides).toContain("from('ride_request_offers' as never)");
    expect(courierRides).toContain(".eq('courier_id', courierId!)");
    expect(courierRides).toContain(".eq('status', 'PENDING')");
    expect(courierRides).toContain(".gt('expires_at', new Date().toISOString())");
    expect(courierRides).not.toContain("from('ride_requests').select('*').eq('status', 'SEARCHING')");
  });
});
