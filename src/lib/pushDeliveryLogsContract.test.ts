import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261010170000_push_delivery_logs.sql'), 'utf8');
const adminSender = readFileSync(resolve(process.cwd(), 'supabase/functions/send-push-notification/index.ts'), 'utf8');
const queueWorker = readFileSync(resolve(process.cwd(), 'supabase/functions/process-notification-queue/index.ts'), 'utf8');
const adminPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminPushNotificationPage.tsx'), 'utf8');

describe('push delivery log contract', () => {
  it('restricts history to admins and publishes inserts to Supabase Realtime', () => {
    expect(migration).toContain('CREATE POLICY "Admins read push delivery logs"');
    expect(migration).toContain('USING (public.is_admin())');
    expect(migration).toContain('GRANT INSERT ON TABLE public.push_delivery_logs TO service_role');
    expect(migration).toContain('ALTER PUBLICATION supabase_realtime ADD TABLE public.push_delivery_logs');
    expect(migration).toContain("status IN ('sent', 'failed', 'expired')");
  });

  it('records direct admin sends and queued app pushes per subscription attempt', () => {
    expect(adminSender).toContain('source: "admin_test" | "admin_broadcast"');
    expect(adminSender).toContain('push_subscription_id: sub.id');
    expect(adminSender).toContain('status: "sent"');
    expect(adminSender).toContain('status: expired ? "expired" : "failed"');
    expect(queueWorker).toContain('source: "queue"');
    expect(queueWorker).toContain('push_subscription_id: subscription.id');
    expect(queueWorker).toContain('status: "expired"');
  });

  it('loads the latest 100 events and listens for live inserts in the admin dashboard', () => {
    expect(adminPage).toContain("from('push_delivery_logs')");
    expect(adminPage).toContain('.limit(100)');
    expect(adminPage).toContain(".on('postgres_changes'");
    expect(adminPage).toContain("table: 'push_delivery_logs'");
    expect(adminPage).toContain('Riwayat Pengiriman Push');
    expect(adminPage).toContain('Diterima layanan push');
  });
});
