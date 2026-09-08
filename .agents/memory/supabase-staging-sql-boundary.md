---
name: Supabase staging SQL boundary
description: The connected Supabase integration exposes authenticated PostgREST access, not direct SQL execution for staging bootstrap.
---

The Supabase connector can verify exposed tables and application API reads, but applying or replaying the canonical bootstrap bundles still requires a direct PostgreSQL connection and `psql` (plus the project deployment tooling where required).

**Why:** A successful REST smoke test does not prove migration parity, idempotency, rollback, or the presence of objects missing from the PostgREST schema cache.

**How to apply:** Use the connector for non-destructive API smoke checks; use `scripts/validate-bootstrap-staging.sh` or `scripts/deploy-supabase-staging.sh` only when an isolated staging `SUPABASE_DB_URL` and `SUPABASE_PROJECT_REF` are available. Never infer SQL migration completion from REST table reads alone.