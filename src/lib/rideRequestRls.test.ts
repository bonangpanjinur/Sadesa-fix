import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migrationPath = 'archive/supabase/migrations/20260929160000_ride_requests_rls_recursion_fix.sql';
const migration = readFileSync(resolve(process.cwd(), migrationPath), 'utf8');
const bootstrap = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/58_20260929160000_ride_requests_rls_recursion_fix.sql'),
  'utf8',
);
const booking = readFileSync(resolve(process.cwd(), 'src/pages/ride/RideBookingPage.tsx'), 'utf8');
const tracking = readFileSync(resolve(process.cwd(), 'src/pages/ride/RideTrackingPage.tsx'), 'utf8');

describe('ride request RLS regression contract', () => {
  it('uses a locked-down SECURITY DEFINER helper rather than a self-referencing policy', () => {
    expect(migration).toContain('SECURITY DEFINER');
    expect(migration).toContain('SET search_path = pg_catalog, public');
    expect(migration).toContain('SET row_security = off');
    expect(migration).toContain('USING (public.courier_can_view_ride(id))');
    expect(migration).toContain("AND active_ride.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')");
  });

  it('serializes ride creation and rejects a second active ride for the same passenger', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.create_ride_request(');
    expect(migration).toContain("hashtextextended('ride_create_request:' || auth.uid()::text, 0)");
    expect(migration).toContain("active_ride.status IN ('SEARCHING', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')");
    expect(migration).toContain("USING ERRCODE = '23505'");
    expect(booking).toContain('/already has an active ride/i');
  });

  it('removes historical permissive searching policies before creating the targeted policy', () => {
    expect(migration).toContain('DROP POLICY IF EXISTS "Drivers can view searching rides"');
    expect(migration).toContain('DROP POLICY IF EXISTS "Couriers can view searching rides"');
    expect(migration).toContain('CREATE POLICY "Couriers can view assigned or targeted rides"');
    expect(migration).toContain("offer.status = 'PENDING'");
    expect(migration).toContain('offer.expires_at > now()');
  });

  it('keeps the deployable bootstrap bundle synchronized with the source migration', () => {
    expect(bootstrap).toContain(`BEGIN SOURCE: ${migrationPath.split('/').at(-1)} =====`);
    expect(bootstrap).toContain('public.courier_can_view_ride(p_ride_id uuid)');
    expect(bootstrap).toContain('DROP POLICY IF EXISTS "Drivers can view searching rides"');
  });

  it('fails closed when booking cannot verify an existing active ride', () => {
    expect(booking).toContain("setActiveRideCheckStatus('error')");
    expect(booking).toContain('activeRideCheckStatus === \'ready\' && !activeRide');
    expect(booking).toContain('Status perjalanan aktif tidak dapat diverifikasi');
    expect(booking).toContain('Coba lagi</Button>');
  });

  it('does not label a failed tracking read as a missing ride', () => {
    expect(tracking).toContain('rideLoadError');
    expect(tracking).toContain('Data perjalanan belum dapat dimuat');
    expect(tracking).toContain('Ini belum tentu berarti pesanan hilang');
    expect(tracking).toContain('Perjalanan tidak ditemukan atau Anda tidak memiliki akses.');
  });
});
