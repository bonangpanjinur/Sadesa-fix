import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261006100000_order_push_delivery_hardening.sql'),
  'utf8',
);
const bootstrap = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/80_20261006100000_order_push_delivery_hardening.sql'),
  'utf8',
);
const ordersHook = readFileSync(resolve(process.cwd(), 'src/hooks/useRealtimeOrders.ts'), 'utf8');
const notificationWorker = readFileSync(
  resolve(process.cwd(), 'supabase/functions/process-notification-queue/index.ts'),
  'utf8',
);

describe('push notification delivery hardening', () => {
  it('queues buyer order-status pushes from trusted database changes', () => {
    expect(migration).toContain("'order_status_update'");
    expect(migration).toContain('NEW.buyer_id');
    expect(migration).toContain('AFTER UPDATE OF status ON public.orders');
    expect(migration).toContain('OLD.status IS DISTINCT FROM NEW.status');
    expect(ordersHook).not.toContain("invoke('send-push-notification'");
  });

  it('dispatches targeted ride pushes immediately while retaining the cron fallback', () => {
    expect(migration).toContain('public.dispatch_notification_delivery_jobs()');
    expect(migration).toContain("NEW.template_key = 'new_ride_request'");
    expect(bootstrap).toContain('BEGIN SOURCE: 20261006100000_order_push_delivery_hardening.sql');
  });

  it('retries expired worker leases and cancels ride pushes for offers that are no longer active', () => {
    expect(notificationWorker).toContain('"recover_stuck_notification_delivery_jobs"');
    expect(notificationWorker).toContain('.gt("expires_at", new Date().toISOString())');
    expect(notificationWorker).toContain('.eq("status", "PENDING")');
    expect(notificationWorker).toContain('status: "cancelled"');
    expect(notificationWorker).toContain('ride?.status === "SEARCHING"');
  });
});
