---
name: Courier money mutation boundary
description: Courier and COD financial/security fields need server-side, column-scoped mutation paths.
---

Row-level ownership checks alone are not sufficient for courier money or trust data. Self-service updates must be restricted to explicitly safe fields or replaced with server-side RPCs that validate the state transition; balances, approval/status, commission, trust score, and COD eligibility must never be client-authoritative.

**Why:** A policy named for location or profile ownership can still authorize a broad row update if column privileges are not separately constrained, and a client-side trust/eligibility mutation can be tampered with even when the UI is correct.

**How to apply:** Treat courier assignment, location, delivery state, deposits, withdrawals, COD reconciliation, earnings, trust score, approval/status, and bank details as separate server-validated contracts. Require staging integration tests with two couriers, a buyer, and a merchant before enabling real-money pilot.