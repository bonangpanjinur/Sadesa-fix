# Security Release Audit

## Scope

Audit ini mencakup RLS dan storage policy pada migration Supabase, tenant isolation pada tabel POS/marketplace/CRM/payment, privilege `SECURITY DEFINER` RPC, webhook/worker authentication, CORS dan rate-limit smoke test, secret exposure, dependency advisories, Railway/Caddy headers, PWA device session control, dan quality gate aplikasi.

## Static findings

Static parser menemukan **146 tabel** pada migration, seluruhnya memiliki `ENABLE ROW LEVEL SECURITY`, dan **145 tabel memiliki policy**. Dua tabel tanpa policy adalah `payment_invoice_requests` dan `pos_sale_requests`; keduanya memakai deny-by-default RLS dan grant service-role/server path, sehingga browser tidak dapat membaca atau menulis request idempotency secara langsung. Ini adalah desain yang diharapkan untuk tabel internal transaksi.

Tabel tenant-sensitive POS, payment, CRM, notification, warehouse, fulfillment, loyalty, approval, dan PWA telah terdeteksi memiliki RLS serta policy. Audit privilege menambahkan revoke eksplisit untuk public/anon pada RPC checkout, payment webhook, loyalty earn/redeem, CRM dispatcher, dan trigger recovery yang tidak boleh dipanggil langsung oleh browser.

## Security controls

| Control | Status | Catatan |
|---|---|---|
| Tenant/outlet authorization | Pass static | RPC memeriksa user, tenant, outlet, atau role admin sesuai operasi. |
| Transaction atomicity | Pass static | Checkout, stock transfer, stock adjustment, refund decision, loyalty mutation, dan payment webhook berjalan melalui RPC transaction path. |
| Idempotency | Pass static | POS request, invoice, payment webhook, notification delivery, dan loyalty earn/redeem memiliki request/event key. |
| RLS coverage | Pass static | 146/146 tabel database terdeteksi ENABLE RLS. Dua tabel internal sengaja deny-by-default tanpa policy. |
| SECURITY DEFINER search path | Pass static | Recent functions menggunakan `SET search_path = public`; execute privilege kritis direstrict. |
| Webhook/worker auth | Pass static | Worker memakai `x-worker-secret` atau service-role bearer; payment webhook memakai provider callback verification. |
| Secret exposure | Pass static | Tidak ditemukan secret production pada tracked files; `VITE_*` dibatasi untuk public Supabase config. |
| Upload controls | Pass static | File validation, storage ownership policy, dan observability redaction tersedia. |
| PWA session control | Pass static | Device registration, heartbeat, revoked status, admin revoke, tenant scope, dan last sync tersedia. |
| Dependency audit | Review required | `pnpm audit --audit-level high` menemukan 3 advisories: 2 low dan 1 moderate; tidak ada critical/high. |

## Required staging gates

Static audit tidak dapat menggantikan database execution. Sebelum production, jalankan migration ke project staging lalu jalankan RLS mutation test lintas tenant, RPC checkout, price-book effective price, loyalty idempotency/concurrency, payment webhook duplicate, refund/stock approval, PWA device revoke, API CORS/auth/rate-limit smoke test, dan backup restore drill.

Staging must be a separate Supabase project. Jangan gunakan service-role key di browser. Jalankan `scripts/deploy-supabase-staging.sh` hanya dengan `SUPABASE_TARGET_LABEL=staging`. Jika Supabase CLI, project ref, atau fixture credentials belum tersedia, release status tetap **NO-GO untuk production verification** walaupun static/local gates lulus.

## Local evidence

- `pnpm exec tsc --noEmit`: passed.
- `pnpm lint`: passed.
- `pnpm test`: 17 test files passed; 48 tests passed; 14 skipped.
- `pnpm build`: passed.
- `scripts/validate-migrations.sh`: 181 migration files validated.
- `scripts/audit-rls-static.py`: 146/146 tables RLS-enabled.
- `pnpm audit --audit-level high`: no high/critical advisories; 2 low and 1 moderate remain for review.

## Release decision

**Conditional GO for local build and code review; NO-GO for production release until Supabase staging execution, API smoke test, and backup restore drill are completed.**
