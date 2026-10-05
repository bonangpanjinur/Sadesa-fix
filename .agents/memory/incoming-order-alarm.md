---
name: Incoming-order alarms
description: Product requirement for audible alerts to merchants and Ojek couriers.
---

Both merchants and Ojek couriers must receive audible alarms for incoming orders or targeted offers. Merchant alerts cover new, payment-pending, and confirmation-pending orders; courier alerts cover targeted ride and delivery offers.

**Why:** the user explicitly requires alarms for both audiences.

**How to apply:** Require a user-gesture audio activation modal for signed-in merchants and couriers, not buyers. Preserve role-specific alert paths; background sound remains controlled by browser and device notification settings.
