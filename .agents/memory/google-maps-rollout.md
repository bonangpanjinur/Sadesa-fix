---
name: Google Maps rollout
description: User-approved scope and operating constraints for the Google Maps pilot.
---

The current pilot may send checkout address and pin data through the server to Google Maps for geocoding and route-distance estimates. Use the route distance for the checkout delivery estimate and retain OpenStreetMap as the fallback. Keep other map surfaces on their existing providers until a later rollout decision. The browser key is intended for `sadesa.id` and `www.sadesa.id`; configure those referrer restrictions in Google Cloud. A monthly budget was not supplied, so do not set or imply a user-approved spend limit.

**Why:** the user explicitly selected Google Maps for checkout only, named the permitted browser domains, and left the monthly budget unanswered.

**How to apply:** preserve this scope when migrating maps or deploying the Google Maps Edge Function. Before enabling billable production use, apply server-side rate limits, configure Google Cloud API/referrer restrictions and quotas, and use a user-approved budget.
