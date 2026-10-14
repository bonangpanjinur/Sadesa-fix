import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261014174700_courier_background_ride_offers.sql'), 'utf8');
const acceptMigration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261005123000_close_stale_transport_offers.sql'), 'utf8');
const ridesPage = readFileSync(resolve(process.cwd(), 'src/pages/courier/CourierRidesPage.tsx'), 'utf8');
const bootstrapBundle = readFileSync(resolve(process.cwd(), 'supabase/bootstrap/123_20261014174700_courier_background_ride_offers.sql'), 'utf8');

describe('courier background ride offer contract', () => {
  it('uses last-known GPS for dispatch only within the approved five-minute window', () => {
    const dispatch = migration.slice(
      migration.indexOf('CREATE OR REPLACE FUNCTION public.dispatch_next_ride_offer'),
      migration.indexOf('REVOKE ALL ON FUNCTION public.dispatch_next_ride_offer'),
    );

    expect(dispatch).toContain("c.last_location_update >= now() - interval '5 minutes'");
    expect(dispatch).toContain("now() + interval '30 seconds'");
    expect(dispatch).toContain('Terima atau tolak dalam 30 detik.');
    expect(dispatch).toContain("'new_ride_request'");
  });

  it('keeps an offer readable only while live and within the bounded stale-location window', () => {
    const visibility = migration.slice(
      migration.indexOf('CREATE OR REPLACE FUNCTION public.courier_can_view_ride'),
      migration.indexOf('REVOKE ALL ON FUNCTION public.courier_can_view_ride'),
    );

    expect(visibility).toContain('offer.status = \'PENDING\'');
    expect(visibility).toContain('offer.expires_at > now()');
    expect(visibility).toContain("offered_courier.last_location_update >= now() - interval '5 minutes'");
  });

  it('preserves server-side fresh-GPS validation when the courier accepts', () => {
    expect(acceptMigration).toContain("v_courier.last_location_update < now() - interval '90 seconds'");
    expect(acceptMigration).toContain('v_courier.current_lat IS NULL OR v_courier.current_lng IS NULL');
  });

  it('obtains and persists a fresh GPS position before calling accept_ride', () => {
    const mutation = ridesPage.slice(
      ridesPage.indexOf('const acceptRideMutation = useMutation'),
      ridesPage.indexOf('const declineRideMutation = useMutation'),
    );
    const gpsRequestIndex = mutation.indexOf('navigator.geolocation.getCurrentPosition');
    const gpsPersistenceIndex = mutation.indexOf('last_location_update:', gpsRequestIndex);
    const acceptRpcIndex = mutation.indexOf("supabase.rpc('accept_ride'", gpsPersistenceIndex);

    expect(gpsRequestIndex).toBeGreaterThan(-1);
    expect(gpsPersistenceIndex).toBeGreaterThan(gpsRequestIndex);
    expect(acceptRpcIndex).toBeGreaterThan(gpsPersistenceIndex);
    expect(ridesPage).toContain('Tawaran ojek berlaku 30 detik. Saat menekan Terima, aplikasi akan meminta GPS terbaru sebelum menerima.');
    expect(bootstrapBundle).toContain("now() + interval '30 seconds'");
    expect(bootstrapBundle).toContain("last_location_update >= now() - interval '5 minutes'");
  });
});
