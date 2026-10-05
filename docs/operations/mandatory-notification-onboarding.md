# Merchant Background Order Notifications

## What the app can and cannot do

SaDesa is a Progressive Web App (PWA), not a native Android foreground-service app. A browser/PWA cannot keep its page JavaScript or audio running indefinitely after the app is closed; Android and iOS control and may suspend or stop page processes to save power.

The supported way to receive orders while the page is backgrounded or closed is **Web Push**. The browser's service worker can display a system notification without keeping the app page alive, provided the device, browser subscription, and server delivery worker are all configured. Delivery can still be delayed or suppressed by OS battery/data restrictions, revoked permission, or a disconnected device.

In-app alarm audio is only available while the page is running and audio has been unlocked by a user gesture. When the app is closed, the user will get the operating system's notification behavior (sound/vibration depends on device notification settings), not continuous app audio.

## Merchant setup on the device

1. Open SaDesa in a supported, current browser over HTTPS. On Android, Chrome's **Install app** or **Add to Home screen** option provides an app-like launch surface. On iOS, add the site to the Home Screen if using Web Push.
2. Sign in to the merchant account on the device that will receive order alerts. The first pointer or keyboard interaction in the merchant area silently unlocks foreground order audio; the browser may block audio until this gesture occurs.
3. In the merchant page header, tap **Aktifkan Alarm & Notifikasi** to request notification permission, register/reuse the browser's Push API subscription, and save it for the signed-in account. Allow notifications when the browser asks. This permission is only for system notifications; it is not requested by the silent audio unlock.
4. Confirm the app reports that background notifications are active. If permission was previously denied, change the site's notification permission in browser settings to **Allow**, return to SaDesa, and tap the activation button again.
5. In the device's system settings, allow SaDesa/browser notifications and their sound. On Android, set SaDesa or the browser to **Unrestricted** battery use (wording varies by device), allow background data, and enable autostart/background operation when the manufacturer provides those controls. Battery Saver, Data Saver, or OEM task-killer settings can still delay delivery.
6. Place a test order from a separate test account, then background/close the PWA and verify the system notification arrives.

Do not expect the browser page itself to remain permanently running. The service worker is woken for a push event and displays the notification; it does not keep the full app process alive.

## Server prerequisites

A complete background notification path has three parts:

1. The order database trigger queues a `push` job for the merchant.
2. The `process-notification-queue` Edge Function polls and delivers queued jobs.
3. The registered PWA service worker handles the Web Push event and calls `showNotification`.

The Edge Function requires `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, and `WORKER_CRON_SECRET` as Edge Function secrets. `push-subscription` must use the matching public VAPID key. The migration `20261005150000_notification_delivery_worker_cron.sql` schedules the worker every minute and reads its credentials from Supabase Vault; missing Vault values produce a warning and skip dispatch instead of exposing credentials or failing bootstrap.

Before applying that migration, add these named values in Supabase Vault:

- `sadesa_project_url`: the project's `https://<project-ref>.supabase.co` URL.
- `sadesa_publishable_key`: the project's publishable/anon key.
- `sadesa_notification_worker_secret`: the same random value configured as the Edge Function secret `WORKER_CRON_SECRET`.

Deploy `process-notification-queue` with the checked-in `verify_jwt = false` setting. Its handler still rejects requests without the matching `x-worker-secret`; the publishable key is not privileged. Configure the VAPID secrets before expecting push delivery; the worker retries missing VAPID or subscription failures instead of marking those jobs sent.

Verify that `cron.job` contains `sadesa-notification-delivery`, then create a test order after the merchant has activated push on that device. Check the Edge Function logs and `notification_delivery_jobs` status if the system notification does not arrive.

Never put a service-role key or worker secret in frontend code.

## Permission and security boundaries

- The app does not request notification permission automatically. A merchant must tap the activation button to trigger the browser prompt.
- The subscription is authenticated and stored for the signed-in user; do not share a device's subscription between merchant accounts.
- The app cannot change a browser permission from **Block** to **Allow** or override OS battery/data restrictions.
- A service worker and successful local build do not prove that the production VAPID secrets, scheduler, database trigger, and push subscription are configured.
