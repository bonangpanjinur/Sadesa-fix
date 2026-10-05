---
name: Supabase Edge Function CORS triage
description: Distinguish gateway CORS behavior from authenticated Edge Function runtime failures.
---

When debugging a browser CORS error against a Supabase Edge Function, test `OPTIONS` and the actual request separately. A preflight can succeed, and an unauthenticated request can return a gateway-generated 401 with CORS headers, while an authenticated handler request still fails. A 5xx response without `Access-Control-Allow-Origin` can be a runtime exception whose response bypassed the handler's CORS wrapper, rather than an origin-policy failure.

**Why:** Production push-subscription returned a successful preflight and a CORS-enabled unauthenticated 401, while the reported authenticated GET returned 500 without CORS. The unauthenticated probe could not reveal the failing authenticated path.

**How to apply:** Reproduce with a valid session or inspect matching Edge Function logs. Keep a top-level error boundary that logs a correlation ID and returns an error response with the same CORS headers; do not claim the underlying exception is fixed until the authenticated path is verified.
