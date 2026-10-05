---
name: Merchant time inputs
description: Handling operating-hour values shared between PostgreSQL and browser time inputs.
---

Normalize database time values to `HH:MM` before passing them into browser time controls. Treat `merchant_operating_hours` as the canonical weekly schedule; `merchants.open_time` and `close_time` are only a fallback for merchants without a row for the relevant day.

**Why:** PostgreSQL `TIME` values can arrive through Supabase as `HH:MM:SS`, while HTML time controls require `HH:MM`. Weekly rows also represent day-specific and overnight hours; writing legacy columns from general settings can silently make the two sources disagree.

**How to apply:** Normalize values when hydrating forms. Read open status through the shared weekly-schedule helper with legacy fallback. Save complete weekly schedules through the authorized atomic RPC; keep legacy columns synchronized only as a compatibility summary of the first open weekday.