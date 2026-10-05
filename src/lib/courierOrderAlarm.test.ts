import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const alarmHook = readFileSync(
  resolve(process.cwd(), 'src/hooks/useCourierOrderAlarm.ts'),
  'utf8',
);

describe('courier order alarm safety contract', () => {
  it('plays a sound for targeted new Ojek rides and delivery offers', () => {
    expect(alarmHook).toContain("void playOrderNotificationSound('courier')");
    expect(alarmHook).toContain("updatePending('ride', offer.ride_id, offer.status === 'PENDING')");
    expect(alarmHook).toContain("updatePending('order', offer.order_id, offer.status === 'OFFERED')");
  });

  it('requires an active courier status before sounding an alarm', () => {
    expect(alarmHook).toContain("courierRef.current?.status === 'ACTIVE'");
    expect(alarmHook).toContain("courierRef.current.registration_status === 'APPROVED'");
    expect(alarmHook).toContain('courierRef.current.is_available === true');
  });

  it('polls only targeted ride offers with a fresh expiry', () => {
    expect(alarmHook).toContain(".eq('courier_id', courierId)");
    expect(alarmHook).toContain(".eq('status', 'PENDING')");
    expect(alarmHook).toContain(".gt('expires_at', new Date().toISOString())");
  });

  it('polls only active delivery offers for the current courier', () => {
    expect(alarmHook).toContain(".from('delivery_assignments').select('order_id').eq('courier_id', courier.id).eq('status', 'OFFERED').gt('expires_at', new Date().toISOString())");
  });

  it('fails closed when targeted ride offers are unavailable', () => {
    expect(alarmHook).toContain('Never fall back to all SEARCHING rides');
    expect(alarmHook).toContain('return { ids: null, error: true };');
    expect(alarmHook).not.toContain(".from('ride_requests')\n        .select('id')\n        .eq('status', 'SEARCHING')");
    expect(alarmHook).not.toContain("table: 'ride_requests', filter: 'status=eq.SEARCHING'");
  });
});
