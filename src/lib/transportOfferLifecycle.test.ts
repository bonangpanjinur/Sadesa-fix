import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261005123000_close_stale_transport_offers.sql'),
  'utf8',
);
const bootstrap = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/74_20261005123000_close_stale_transport_offers.sql'),
  'utf8',
);

describe('transport offer lifecycle safety contract', () => {
  it('closes pending passenger ride offers when the passenger cancels', () => {
    expect(migration).toContain("WHERE ride_id = p_ride_id");
    expect(migration).toContain("status = 'REJECTED'");
    expect(migration).toContain("status = 'PENDING'");
    expect(migration).toContain("status IN ('SEARCHING', 'ACCEPTED')");
  });

  it('invalidates competing passenger ride offers when one courier accepts', () => {
    expect(migration).toContain("SET status = 'ACCEPTED'");
    expect(migration).toContain("AND id <> v_offer.id");
    expect(migration).toContain('PERFORM pg_advisory_xact_lock(7210953184926001)');
  });

  it('invalidates every other delivery assignment after a winning acceptance', () => {
    expect(migration).toContain("WHERE order_id = v_order.id AND status = 'OFFERED' AND id <> p_assignment_id");
    expect(migration).toContain("rejection_reason = 'Pesanan sudah diambil kurir lain'");
    expect(migration).toContain("IF v_order.status IS DISTINCT FROM 'ASSIGNED'");
  });

  it('ships the same lifecycle fix in the bootstrap deployment bundle', () => {
    expect(bootstrap).toContain('CREATE OR REPLACE FUNCTION public.cancel_ride');
    expect(bootstrap).toContain('CREATE OR REPLACE FUNCTION public.accept_ride');
    expect(bootstrap).toContain('CREATE OR REPLACE FUNCTION public.respond_delivery_offer');
    expect(bootstrap).toContain("status = 'REJECTED'");
  });
});
