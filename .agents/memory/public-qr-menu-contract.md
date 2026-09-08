---
name: Public QR menu contract
description: Customer QR menu uses scoped Supabase RPCs and a dedicated table-order stock reservation lifecycle.
---

Public QR/menu pages must not depend on the retired POS bridge. The customer read, create-order, and status flows use SECURITY DEFINER RPCs that validate active POS entitlement, tenant, outlet, active/non-cleaning table, active products, and server-side prices.

**Why:** POS tables and stock have tenant RLS intended for authenticated operators, while QR customers are anonymous; direct table reads would either fail or risk leaking scope. Order creation also needs atomic stock reservation and lifecycle release/consume behavior.

**How to apply:** Keep ordinary `/menu/:tenantId` calls table-free, require a valid outlet-linked table for order creation, keep `source = 'table_qr'`, and apply the QR bootstrap migration before testing customer flow in staging.