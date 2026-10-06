---
name: Ride-offer push timing
description: Keep push delivery aligned with the short lifetime of targeted Ojek offers.
---

Targeted ride offers expire after 30 seconds, so their push jobs must trigger the queue worker immediately rather than depending only on the once-per-minute cron. The worker must also verify the specific offer is still pending and unexpired before sending, and cancel stale jobs instead of retrying them.

**Why:** the cron interval can exceed the offer lifetime, causing couriers to receive useless pushes or no push for an otherwise active offer.

**How to apply:** Preserve event-triggered dispatch for `new_ride_request` jobs and retain the scheduled worker as a fallback for retries and queue recovery.
