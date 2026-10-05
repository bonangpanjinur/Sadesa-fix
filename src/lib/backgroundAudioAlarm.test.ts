import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const soundManager = readFileSync(resolve(process.cwd(), 'src/lib/orderNotificationSound.ts'), 'utf8');
const serviceWorker = readFileSync(resolve(process.cwd(), 'src/sw.ts'), 'utf8');
const courierLayout = readFileSync(resolve(process.cwd(), 'src/components/courier/CourierLayout.tsx'), 'utf8');
const merchantLayout = readFileSync(resolve(process.cwd(), 'src/components/merchant/MerchantLayout.tsx'), 'utf8');
const merchantPushMigration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261005124500_merchant_order_push_notification.sql'), 'utf8');
const merchantPushBundle = readFileSync(resolve(process.cwd(), 'supabase/bootstrap/75_20261005124500_merchant_order_push_notification.sql'), 'utf8');
const merchantSettingsPage = readFileSync(resolve(process.cwd(), 'src/pages/merchant/MerchantSettingsPage.tsx'), 'utf8');
const notificationWorker = readFileSync(resolve(process.cwd(), 'supabase/functions/process-notification-queue/index.ts'), 'utf8');
const merchantAlarmHook = readFileSync(resolve(process.cwd(), 'src/hooks/useMerchantOrderAlarm.ts'), 'utf8');
const audioPermissionModal = readFileSync(resolve(process.cwd(), 'src/components/audio/AudioPermissionModal.tsx'), 'utf8');
const audioPermissionHook = readFileSync(resolve(process.cwd(), 'src/hooks/useAudioPermission.ts'), 'utf8');
const audioManager = readFileSync(resolve(process.cwd(), 'src/lib/audioManager.ts'), 'utf8');
const notificationWorkerSchedule = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261005150000_notification_delivery_worker_cron.sql'), 'utf8');
const supabaseFunctionConfig = readFileSync(resolve(process.cwd(), 'supabase/config.toml'), 'utf8');
const orderAlarmSettingsControl = readFileSync(resolve(process.cwd(), 'src/components/notifications/OrderAlarmSettingsControl.tsx'), 'utf8');
const courierRideDispatch = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20260929011000_nearest_courier_sequential_ride_dispatch.sql'), 'utf8');
const courierDeliveryOfferPush = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20260929133000_courier_delivery_offer_push.sql'), 'utf8');

describe('courier background alarm contract', () => {
  it('requires an audio-activation click only from signed-in merchants and couriers', () => {
    expect(audioPermissionModal).toContain('isMerchant');
    expect(audioPermissionModal).toContain('isCourier');
    expect(audioPermissionModal).toContain('!authLoading');
    expect(audioPermissionModal).toContain('AKTIFKAN & UJI SUARA');
    expect(audioPermissionHook).toContain('isSupported && !isAudioEnabled()');
    expect(audioPermissionHook).toContain('setNeedsPermission(true)');
  });

  it('keeps a user-gesture-unlocked media fallback for hidden tabs', () => {
    expect(soundManager).toContain("new Audio('/notification.wav')");
    expect(soundManager).toContain('document.hidden');
    expect(soundManager).toContain('backgroundAudioUnlocked');
    expect(soundManager).toContain('unlockOrderNotificationAudio');
  });

  it('activates courier push and page alarm from a user gesture', () => {
    expect(courierLayout).toContain('unlockOrderNotificationAudio()');
    expect(courierLayout).toContain('subscribeToPush(user.id)');
    expect(courierLayout).toContain('Aktifkan Push &amp; Alarm');
  });

  it('queues push for targeted Ojek rides and delivery offers', () => {
    expect(courierRideDispatch).toContain("'new_ride_request'");
    expect(courierRideDispatch).toContain("'offer_id', v_offer_id::text");
    expect(courierDeliveryOfferPush).toContain("'new_delivery_offer'");
    expect(courierDeliveryOfferPush).toContain('AFTER INSERT ON public.delivery_assignments');
  });

  it('activates merchant Web Push from the merchant header gesture', () => {
    expect(merchantLayout).toContain('subscribeToPush(user.id)');
    expect(merchantLayout).toContain('Aktifkan Alarm &amp; Notifikasi');
    expect(merchantLayout).toContain('Izin audio dan langganan push tersimpan di perangkat ini');
  });

  it('automatically plays the merchant alarm for a newly pending realtime order', () => {
    expect(merchantAlarmHook).toContain("event: 'INSERT', schema: 'public', table: 'orders'");
    expect(merchantAlarmHook).toContain("void playOrderNotificationSound('merchant')");
    expect(merchantAlarmHook).toContain("const PENDING_STATUSES = ['NEW', 'PENDING_CONFIRMATION', 'PENDING_PAYMENT']");
  });

  it('reconciles unseen pending orders after realtime reconnects or the page resumes', () => {
    expect(merchantAlarmHook).toContain('seedPendingOrders(true)');
    expect(merchantAlarmHook).toContain("window.addEventListener('online', reconcileWhenResumed)");
    expect(merchantAlarmHook).toContain("document.addEventListener('visibilitychange', handleVisibilityChange)");
  });

  it('polls only the signed-in merchant inbox if Realtime silently misses a new order', () => {
    expect(merchantAlarmHook).toContain("setInterval(() =>");
    expect(merchantAlarmHook).toContain('reconcilePendingOrders(true)');
    expect(merchantAlarmHook).toContain(".eq('merchant_id', merchantId)");
    expect(merchantAlarmHook).toContain('window.clearInterval(refreshTimer)');
  });

  it('silently unlocks automatic order audio on the first merchant interaction', () => {
    expect(merchantLayout).toContain("addEventListener('pointerdown', unlockOnFirstInteraction, true)");
    expect(merchantLayout).toContain("addEventListener('keydown', unlockOnFirstInteraction, true)");
    expect(merchantLayout).toContain('unlockOrderNotificationAudio({ playConfirmationTone: false })');
    expect(audioManager).toContain('if (options.playConfirmationTone !== false) await playTestSound();');
  });

  it('retries suspended audio on focus/visibility recovery and flushes queued alerts', () => {
    expect(audioManager).toContain("window.addEventListener('focus', recoverWhenVisible)");
    expect(audioManager).toContain("window.addEventListener('pageshow', recoverWhenVisible)");
    expect(audioManager).toContain("document.addEventListener('visibilitychange', recoverWhenVisible)");
    expect(soundManager).toContain("subscribeAudioManager('statechange', flushPendingSoundAudiences)");
  });

  it('exposes the merchant alarm test control from store settings', () => {
    expect(merchantSettingsPage).toContain('OrderAlarmSettingsControl');
    expect(merchantSettingsPage).toContain('Pilih jenis suara dan volume, lalu uji');
    expect(orderAlarmSettingsControl).toContain('Ikuti Global');
    expect(orderAlarmSettingsControl).toContain('Perubahan di sini hanya berlaku pada perangkat');
    expect(orderAlarmSettingsControl).toContain('Saat aplikasi ditutup, suara mengikuti notifikasi sistem perangkat.');
  });

  it('queues merchant order push delivery on the server', () => {
    expect(merchantPushMigration).toContain("'new_merchant_order'");
    expect(merchantPushMigration).toContain("'push'");
    expect(merchantPushMigration).toContain('notification_delivery_jobs');
    expect(merchantPushMigration).toContain("'/merchant/orders?orderId=' || NEW.id::TEXT");
    expect(merchantPushMigration).toContain('CREATE TRIGGER order_notification_trigger');
    expect(merchantPushBundle).toContain('EXECUTE FUNCTION public.notify_order_change();\n$bootstrap_sql_merchant_order_push$;');
    expect(merchantPushBundle).not.toContain('$$$bootstrap_sql_merchant_order_push$;');
  });

  it('retries instead of acknowledging push jobs when VAPID configuration is missing', () => {
    expect(notificationWorker).toContain('if (!vapidPrivateKey || !vapidPublicKey)');
    expect(notificationWorker).toContain('throw new Error("VAPID keys are not configured")');
  });

  it('does not mark a push job successful when the recipient has no usable subscription', () => {
    expect(notificationWorker).toContain('No active push subscriptions for recipient');
    expect(notificationWorker).toContain('if (delivered === 0)');
  });

  it('schedules the queue worker using Vault-backed credentials and handler-level auth', () => {
    expect(notificationWorkerSchedule).toContain('cron.schedule');
    expect(notificationWorkerSchedule).toContain('net.http_post');
    expect(notificationWorkerSchedule).toContain('vault.decrypted_secrets');
    expect(notificationWorkerSchedule).toContain('sadesa_notification_worker_secret');
    expect(notificationWorkerSchedule).toContain('pg_net WITH SCHEMA extensions');
    expect(supabaseFunctionConfig).toContain('[functions.process-notification-queue]');
    expect(supabaseFunctionConfig).toContain('verify_jwt = false');
  });

  it('keeps Web Push as the fallback when the PWA is backgrounded or closed', () => {
    expect(serviceWorker).toContain("self.addEventListener('push'");
    expect(serviceWorker).toContain('showNotification');
    expect(serviceWorker).toContain('silent: false');
    expect(serviceWorker).toContain('vibrate: [...COURIER_ALARM_VIBRATION_PATTERN]');
    expect(serviceWorker).toContain('new_merchant_order');
    expect(serviceWorker).toContain('`merchant-order-${merchantOrderId}`');
    expect(serviceWorker).toContain('`delivery-offer-${deliveryAssignmentId}`');
    expect(serviceWorker).toContain('`ride-offer-${rideId}`');
    expect(serviceWorker).toContain('encodeURIComponent(merchantOrderId)');
  });
});
