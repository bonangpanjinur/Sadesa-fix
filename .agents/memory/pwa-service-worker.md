---
name: PWA service worker
description: Durable PWA architecture decision for combining Workbox caching with push notifications.
---

The app uses one injected Workbox service worker as the source of truth for both precaching/runtime caching and push notification events. The app registers it through the generated virtual PWA registration module in production.

**Why:** A separate static push-only worker and a generated Workbox worker can overwrite or compete with each other, leaving PWABuilder unable to confirm the app's service-worker support.

**How to apply:** Keep future caching and push-notification changes in the injected worker/config together; validate the built `dist/manifest.webmanifest` and `dist/sw.js`, not only development mode.