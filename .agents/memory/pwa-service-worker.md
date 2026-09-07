---
name: PWA service worker
description: Durable PWA architecture decision for combining Workbox caching with push notifications.
---

The app uses one injected Workbox service worker as the source of truth for both precaching/runtime caching and push notification events. The app registers it through the generated virtual PWA registration module in production.

**Why:** A separate static push-only worker and a generated Workbox worker can overwrite or compete with each other, leaving PWABuilder unable to confirm the app's service-worker support.

**How to apply:** Keep future caching and push-notification changes in the injected worker/config together; validate the built `dist/manifest.webmanifest` and `dist/sw.js`, not only development mode.

PWABuilder results can continue showing missing manifest fields when its URL points to an older deployment; local source and preview changes do not update the scanned public URL until a new build is published.

**Why:** The development-served manifest contained the requested metadata while the user's PWABuilder screenshots still showed the previous warnings.

**How to apply:** After PWA metadata changes, publish a fresh production build, then rescan the exact manifest URL and clear any cached report before judging the result.

When a PWA analyzer does not detect a worker despite a generated `sw.js`, an explicit production `navigator.serviceWorker.register('/sw.js', { scope: '/' })` is a reliable fallback to make registration observable; keep update behavior in the worker itself.

**Why:** Analyzer output showed no service worker while the generated worker already contained Workbox precaching and push handlers.

**How to apply:** Prefer a literal production registration when analyzer detection matters, and validate the built bundle contains both the registration call and `/sw.js`.