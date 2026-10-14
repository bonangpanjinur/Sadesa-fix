import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');
const map = read('src/components/transport/GoogleRideMap.tsx');
const booking = read('src/pages/ride/RideBookingPage.tsx');
const driver = read('src/pages/courier/CourierRidesPage.tsx');
const migration = read('archive/supabase/migrations/20261014174600_ride_pickup_landmark.sql');
const bootstrap = read('supabase/bootstrap/122_20261014174600_ride_pickup_landmark.sql');

describe('Ojek pickup landmark and free map contract', () => {
  it('renders the passenger booking map with OSM tiles and no Google Maps loader', () => {
    expect(map).toContain('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(map).toContain('openstreetmap.org/copyright');
    expect(map).not.toContain('loadGoogleMaps');
    expect(map).not.toContain('google.maps');
  });

  it('requires a validated landmark and sends it to the backward-compatible server RPC', () => {
    expect(booking).toContain('normalizeRidePickupLandmark(pickupLandmark)');
    expect(booking).toContain('id="ride-pickup-landmark"');
    expect(booking).toContain("'create_ride_request_with_landmark'");
    expect(booking).toContain('p_pickup_landmark: normalizedLandmark');
    expect(migration).toContain('public.create_ride_request(');
    expect(migration).toContain("char_length(v_landmark) NOT BETWEEN 3 AND 240");
    expect(migration).toContain('ADD COLUMN IF NOT EXISTS pickup_landmark text');
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.create_ride_request_with_landmark');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.create_ride_request_with_landmark');
    expect(booking).not.toContain('p_estimated_fare');
  });

  it('makes the pickup note available to the targeted courier and to ride tracking', () => {
    expect(driver).toContain('activeRide.pickup_landmark');
    expect(driver).toContain('ride.pickup_landmark');
    expect(read('src/pages/ride/RideTrackingPage.tsx')).toContain('ride.pickup_landmark');
  });

  it('keeps the deployable bootstrap entrypoint present and checksummed by the manifest', () => {
    expect(bootstrap).toContain('create_ride_request_with_landmark');
    const manifest = JSON.parse(read('supabase/bootstrap/manifest.json')) as {
      bundles: Array<{ file: string; source_files: string[]; sha256: string }>;
    };
    expect(manifest.bundles.some((bundle) => (
      bundle.file === '122_20261014174600_ride_pickup_landmark.sql'
      && bundle.source_files.includes('20261014174600_ride_pickup_landmark.sql')
      && /^[a-f0-9]{64}$/.test(bundle.sha256)
    ))).toBe(true);
  });
});
