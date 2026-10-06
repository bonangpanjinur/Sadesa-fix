---
name: Supabase staging SQL boundary
description: The connected Supabase integration exposes authenticated PostgREST access, not direct SQL execution for staging bootstrap.
---

The Supabase connector can verify exposed tables and application API reads, but applying or replaying the canonical bootstrap bundles still requires a direct PostgreSQL connection and `psql` (plus the project deployment tooling where required).

**Why:** A successful REST smoke test does not prove migration parity, idempotency, rollback, or the presence of objects missing from the PostgREST schema cache.

**How to apply:** Use the connector for non-destructive API smoke checks; use `scripts/validate-bootstrap-staging.sh` or `scripts/deploy-supabase-staging.sh` only when an isolated staging `SUPABASE_DB_URL` and `SUPABASE_PROJECT_REF` are available. Never infer SQL migration completion from REST table reads alone.

For Edge Function deployment without linking the local Supabase project, pass the staging ref explicitly to `supabase functions deploy` and use `--use-api`. The CLI still requires `SUPABASE_ACCESS_TOKEN` to be a valid Supabase Personal Access Token in the current `sbp_…` format; SQL can already be applied successfully through `SUPABASE_DB_URL` even when function deployment authentication fails.

**Why:** Database access and Supabase Management API access are separate credentials and separate deployment steps.

**How to apply:** Keep the PAT in Replit Secrets, never inspect or print it, and verify the worker deployment separately from the SQL migration result.