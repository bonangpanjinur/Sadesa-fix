---
name: Merchant time inputs
description: Handling operating-hour values shared between PostgreSQL and browser time inputs.
---

Normalize merchant operating-hour values to `HH:MM` before passing them into browser forms or strict client validation.

**Why:** PostgreSQL `TIME` values can arrive through Supabase as `HH:MM:SS`, while the HTML time control and merchant settings schema use `HH:MM`; validating the raw database value causes a false save failure.

**How to apply:** When hydrating merchant settings, trim a valid database time to its first five characters. Keep the stored database column as `TIME` and continue sending the normalized form value on save.