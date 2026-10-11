---
name: Google Maps rollout
description: User-approved scope and operating constraints for the Google Maps pilot.
---

The current pilot may send checkout address and pin data through the server to Google Maps for geocoding and route-distance estimates. Use the route distance for the checkout delivery estimate and retain OpenStreetMap as the fallback. Keep other map surfaces on their existing providers until a later rollout decision. The browser key is intended for `sadesa.id` and `www.sadesa.id`; configure those referrer restrictions in Google Cloud. The user approved a staging monthly budget ceiling of IDR 2,000,000. This is not a configured Google Cloud quota or spend control.

**Why:** the user explicitly selected Google Maps for checkout only, named the permitted browser domains, and set the staging budget ceiling to IDR 2,000,000/month.

**How to apply:** preserve this scope when migrating maps or deploying the Google Maps Edge Function. Keep billable calls disabled until Google Cloud API/referrer restrictions and request quotas enforce the approved budget; budget alerts alone do not cap Maps Platform usage.
