import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20260929140000_auto_cancel_unanswered_transport_orders.sql'),
  'utf8',
);

describe('automatic timeout cancellation for ojek and direct courier orders', () => {
  it('uses the same five-minute response window for rides and direct courier orders', () => {
    expect(migration.match(/now\(\) - interval '5 minutes'/g)).toHaveLength(3);
    expect(migration).toContain("r.status = 'SEARCHING'");
    expect(migration).toContain("o.status = 'ASSIGNED'");
    expect(migration).toContain("o.service_type = 'COURIER_DELIVERY'");
  });

  it('does not cancel scheduled pickups, accepted rides, or accepted courier assignments', () => {
    expect(migration).toContain("COALESCE(o.scheduled_pickup, false) = false");
    expect(migration).toContain("r.driver_id IS NULL");
    expect(migration).toContain("accepted.status = 'ACCEPTED'");
    expect(migration).toContain("v_order.status <> 'ASSIGNED'");
  });

  it('closes stale offers and writes an auditable automatic cancellation for direct courier orders', () => {
    expect(migration).toContain("SET status = 'EXPIRED'");
    expect(migration).toContain("ride.status <> 'SEARCHING' OR ride.driver_id IS NOT NULL");
    expect(migration).toContain("SET status = 'CANCELED'");
    expect(migration).toContain("cancellation_type = 'SYSTEM'");
    expect(migration).toContain('INSERT INTO public.order_status_history');
    expect(migration).toContain('PERFORM public.send_notification');
  });

  it('serializes ride acceptance and skips conflicting courier transactions', () => {
    expect(migration).toContain('pg_try_advisory_xact_lock(7210953184926001)');
    expect(migration).toContain('FOR UPDATE SKIP LOCKED');
    expect(migration).toContain('FOR UPDATE NOWAIT');
    expect(migration).toContain('WHEN lock_not_available');
  });

  it('runs independently from browser sessions once per minute', () => {
    expect(migration).toContain('auto-cancel-unanswered-transport-orders');
    expect(migration).toContain("'* * * * *'");
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.auto_cancel_unanswered_transport_orders() TO service_role');
  });
});
