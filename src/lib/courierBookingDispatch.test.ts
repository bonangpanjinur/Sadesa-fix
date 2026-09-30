import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20260930100000_harden_courier_booking_dispatch.sql'),
  'utf8',
);
const bootstrap = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/59_20260930100000_harden_courier_booking_dispatch.sql'),
  'utf8',
);

describe('courier booking dispatch hardening contract', () => {
  it('requires a fresh GPS heartbeat before direct assignment', () => {
    expect(migration).toContain("c.last_location_update >= now() - interval '90 seconds'");
    expect(migration).toContain("c.current_lat IS NOT NULL");
    expect(migration).toContain("c.current_lng IS NOT NULL");
  });

  it('does not assign a courier with an active passenger ride', () => {
    expect(migration).toContain("r.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')");
    expect(migration).toContain('r.driver_id = c.id');
  });

  it('does not assign a courier holding another delivery offer', () => {
    expect(migration).toContain("da.status IN ('OFFERED', 'ACCEPTED')");
    expect(migration).toContain('da.courier_id = c.id');
  });

  it('keeps the deployable bootstrap copy identical to the source migration', () => {
    expect(bootstrap).toBe(migration);
  });
});
