---
name: Courier rating sources
description: The shared rating contract for courier profiles across delivery and Ojek Desa flows.
---

Courier profile rating statistics must include both completed marketplace delivery ratings and completed Ojek ride ratings. The two flows use separate records, but buyers see and drivers own one courier reputation.

**Why:** The previous implementation only aggregated `courier_ratings`, so a driver with ride reviews appeared as “Baru” and drivers had no unified review view.

**How to apply:** Any future rating, review, profile-summary, or driver-history work must preserve the unified aggregate and clearly label the source as Pengiriman or Ojek when showing individual feedback.