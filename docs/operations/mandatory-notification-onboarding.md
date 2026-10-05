# Merchant Background Order Notifications

## What the app can and cannot do

SaDesa is a Progressive Web App (PWA), not a native Android foreground-service app. A browser/PWA cannot keep its page JavaScript or audio running indefinitely after the app is closed; Android and iOS control and may suspend or stop page processes to save power.

The supported way to receive orders while the page is backgrounded or closed is **Web Push**. The browser's service worker can display a system notification without keeping the app page alive, provided the device, browser subscription, and server delivery worker are all configured. Delivery can still be delayed or suppressed by OS battery/data restrictions, revoked permission, or a disconnected device.

In-app alarm audio is only available while the page is running and audio has been unlocked by a user gesture. When the app is closed, the user will get the operating system's notification behavior (sound/vibration depends on device notification settings), not continuous app audio.

## Merchant setup on the device

1. Open SaDesa in a supported, current browser over HTTPS. On Android, Chrome's **Install app** or **Add to Home screen** option provides an app-like launch surface. On iOS, add the site to the Home Screen if using Web Push.
2. Sign in to the merchant account on the device that will receive order alerts.
3. In the merchant page header, tap **Aktifkan Alarm & Notifikasi**. This user-initiated action requests notification permission, registers/reuses the browser's Push API subscription, and saves it for the signed-in account. Allow notifications when the browser asks.
4. Confirm the app reports that background notifications are active. If permission was previously denied, change the site's notification permission in browser settings to **Allow**, return to SaDesa, and tap the activation button again.
5. In the device's system settings, allow SaDesa/browser notifications and their sound. On Android, set SaDesa or the browser to **Unrestricted** battery use (wording varies by device), allow background data, and enable autostart/background operation when the manufacturer provides those controls. Battery Saver, Data Saver, or OEM task-killer settings can still delay delivery.
6. Place a test order from a separate test account, then background/close the PWA and verify the system notification arrives.

Do not expect the browser page itself to remain permanently running. The service worker is woken for a push event and displays the notification; it does not keep the full app process alive.

## Server prerequisites

A complete background notification path has three parts:

1. The order database trigger queues a `push` job for the merchant.
2. The `process-notification-queue` Edge Function polls and delivers queued jobs.
3. The registered PWA service worker handles the Web Push event and calls `showNotification`.

The Edge Function requires `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`. Deploy it and configure both as Edge Function secrets. The push-subscription endpoint must use the matching public VAPID key. The queue worker must also be invoked by a trusted scheduler (for example, Supabase Cron) on a recurring interval; deploying the function alone does not run it. **This repository does not define a scheduled invocation for `process-notification-queue`**, so the target project's scheduler and its secret/auth configuration must be verified separately before relying on closed-app alerts.

The worker treats missing VAPID credentials as a delivery failure so a queued job can be retried instead of being marked complete without a notification. Inspect Edge Function logs and notification-job status during the test. Never put a service-role key or worker secret in frontend code.

## Permission and security boundaries

- The app does not request notification permission automatically. A merchant must tap the activation button to trigger the browser prompt.
- The subscription is authenticated and stored for the signed-in user; do not share a device's subscription between merchant accounts.
- The app cannot change a browser permission from **Block** to **Allow** or override OS battery/data restrictions.
- A service worker and successful local build do not prove that the production VAPID secrets, scheduler, database trigger, and push subscription are configured.
