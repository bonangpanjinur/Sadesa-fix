---
name: Courier delivery offer lifecycle
description: State and visibility boundary for local courier delivery offers.
---

`ASSIGNED` means an offer is waiting for a courier decision. It must not establish the order's authoritative courier or expose buyer-facing courier chat/live tracking. `COURIER_ACCEPTED` is the first state that may establish those surfaces.

**Why:** A courier can reject or miss an offer, and the buyer must not contact or track a courier who has not accepted the job. Treating assignment as acceptance also hides the offer from the courier when nested order RLS is involved.

**How to apply:** Keep offer discovery behind a server-validated courier-offer RPC; set `orders.courier_id` only in the acceptance transition; gate buyer chat and live tracking on `COURIER_ACCEPTED` or later active-delivery states.