import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const soundManager = readFileSync(resolve(process.cwd(), 'src/lib/orderNotificationSound.ts'), 'utf8');
const serviceWorker = readFileSync(resolve(process.cwd(), 'src/sw.ts'), 'utf8');
const courierLayout = readFileSync(resolve(process.cwd(), 'src/components/courier/CourierLayout.tsx'), 'utf8');
const merchantLayout = readFileSync(resolve(process.cwd(), 'src/components/merchant/MerchantLayout.tsx'), 'utf8');
const merchantPushMigration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261005124500_merchant_order_push_notification.sql'), 'utf8');

describe('courier background alarm contract', () => {
  it('keeps a user-gesture-unlocked media fallback for hidden tabs', () => {
    expect(soundManager).toContain("new Audio('/notification.wav')");
    expect(soundManager).toContain('document.hidden');
    expect(soundManager).toContain('backgroundAudioUnlocked');
    expect(soundManager).toContain('unlockOrderNotificationAudio');
  });

  it('requires an explicit courier gesture to unlock background audio', () => {
    expect(courierLayout).toContain('unlockOrderNotificationAudio();');
    expect(courierLayout).toContain('Aktifkan Bunyi &amp; Getar');
  });

  it('activates merchant Web Push from the merchant header gesture', () => {
    expect(merchantLayout).toContain('subscribeToPush(user.id)');
    expect(merchantLayout).toContain('Aktifkan Alarm &amp; Notifikasi');
  });

  it('queues merchant order push delivery on the server', () => {
    expect(merchantPushMigration).toContain("'new_merchant_order'");
    expect(merchantPushMigration).toContain("'push'");
    expect(merchantPushMigration).toContain('notification_delivery_jobs');
  });

  it('keeps Web Push as the fallback when the PWA is backgrounded or closed', () => {
    expect(serviceWorker).toContain("self.addEventListener('push'");
    expect(serviceWorker).toContain('showNotification');
    expect(serviceWorker).toContain('silent: false');
    expect(serviceWorker).toContain('vibrate: [...COURIER_ALARM_VIBRATION_PATTERN]');
    expect(serviceWorker).toContain('new_merchant_order');
  });
});
