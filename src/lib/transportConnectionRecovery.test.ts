import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20260929150000_transport_connection_drop_offer_recovery.sql'),
  'utf8',
);

describe('transport offer recovery when courier connection drops', () => {
  it('offers direct courier work only to an available courier with a fresh location heartbeat', () => {
    expect(migration).toContain("c.is_available IS TRUE");
    expect(migration).toContain("c.last_location_update >= now() - interval '90 seconds'");
    expect(migration).toContain("c.current_lat IS NOT NULL");
    expect(migration).toContain("c.current_lng IS NOT NULL");
  });

  it('expires stale courier offers, records the failed courier, and clears the tentative assignment', () => {
    expect(migration).toContain("SET status = 'EXPIRED'");
    expect(migration).toContain("Offer dilepas otomatis karena koneksi driver atau heartbeat lokasi terputus.");
    expect(migration).toContain("array_append(COALESCE(courier_rejected_ids");
    expect(migration).toContain("courier_id = NULL");
    expect(migration).toContain("assigned_at = NULL");
  });

  it('retries ride dispatch from the server when no unexpired offer remains', () => {
    expect(migration).toContain('public.dispatch_next_ride_offer(v_ride_id)');
    expect(migration).toContain("r.status = 'SEARCHING'");
    expect(migration).toContain("pending_offer.expires_at > now()");
    expect(migration).toContain("r.created_at > now() - interval '5 minutes'");
  });

  it('retries direct courier dispatch without relying on a buyer or driver page', () => {
    expect(migration).toContain('public.dispatch_courier_order_internal(v_order_id)');
    expect(migration).toContain("GRANT EXECUTE ON FUNCTION public.process_unresponsive_transport_offers() TO service_role");
    expect(migration).toContain("LIMIT 100");
  });

  it('preserves the five-minute order deadline and runs recovery before auto-cancel', () => {
    expect(migration).toContain("v_order.created_at <= now() - interval '5 minutes'");
    const retryAt = migration.indexOf('PERFORM public.process_unresponsive_transport_offers();');
    const cancelAt = migration.indexOf('PERFORM public.auto_cancel_unanswered_transport_orders();');
    expect(retryAt).toBeGreaterThanOrEqual(0);
    expect(cancelAt).toBeGreaterThan(retryAt);
    expect(migration).toContain("'* * * * *'");
  });

  it('keeps the buyer/admin RPC authorization and hides the internal dispatcher from client roles', () => {
    expect(migration).toContain('(buyer_id = auth.uid() OR public.is_admin())');
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.dispatch_courier_order_internal(uuid) FROM PUBLIC, anon, authenticated');
  });
});
