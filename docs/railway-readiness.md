# Railway and API Readiness Audit

Tanggal audit: 2026-08-23.

## Executive summary

Repository ini **siap untuk deployment frontend SPA di Railway** setelah konfigurasi container yang ditambahkan pada audit ini. Repository **bukan Node/Express API server**. Vite menghasilkan static assets, sedangkan database, auth, storage, realtime, dan privileged API berjalan melalui Supabase serta Supabase Edge Functions. Karena itu, deployment frontend ke Railway tidak otomatis mendeploy endpoint di `supabase/functions`.

| Area | Status | Catatan |
|---|---:|---|
| Vite production build | Ready | `pnpm build` lulus |
| Railway container | Ready locally | Dockerfile dan Caddyfile tersedia; Docker daemon sandbox tidak tersedia untuk image smoke test |
| SPA fallback | Ready | Caddy mengarahkan route yang tidak memiliki file ke `index.html` |
| Healthcheck | Ready | `GET /health` mengembalikan JSON `{"status":"ok"}` |
| Public runtime config | Guarded | Hanya variabel `VITE_*` publik yang masuk bundle |
| Server/API runtime | Separate | Supabase Edge Functions harus dideploy dan dikonfigurasi terpisah |
| Database migrations | Controlled | Jangan menjalankan migration dari frontend Railway |
| Production security audit | Passed baseline | 0 critical/high/moderate production advisories; 1 low tersisa |

## Railway files

`Dockerfile` memakai Node 22 untuk build dengan `pnpm install --frozen-lockfile`, lalu menyalin hanya `dist` ke image Caddy. `.dockerignore` mencegah `node_modules`, `.env`, `.git`, log, coverage, dan artifact lokal masuk ke build context. `Caddyfile` mendengarkan `PORT` yang disediakan Railway, menambahkan compression dan security headers dasar, menonaktifkan cache HTML, serta menyediakan SPA fallback. `railway.json` memilih Dockerfile builder, start command Caddy, healthcheck `/health`, dan restart policy.

Railway's current documentation states that `railway.json` is supported for legacy services but Config as Code is deprecated in favor of Infrastructure as Code, with legacy files retained until 2026-12-01. The repository can deploy with the current file, but a future migration to Railway Infrastructure as Code should be planned.

## Environment separation

Configure only these public build-time variables on the Railway frontend service:

| Variable | Scope | Required |
|---|---|---:|
| `VITE_SUPABASE_URL` | Browser/public | Yes |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Browser/public | Yes |
| `VITE_SUPABASE_PROJECT_ID` | Browser/public/integration metadata | Recommended |
| `PORT` | Railway-provided container variable | Automatic |

Never put `SUPABASE_SERVICE_ROLE_KEY`, Xendit secret key, Xendit callback token, database password, private signing key, or any server credential in a `VITE_*` variable. Those values belong only in Supabase Edge Function secrets. The client now fails explicitly when required public Supabase configuration is missing, without printing values to logs.

## API readiness

The frontend can call Supabase REST, Auth, Storage, Realtime, and Edge Functions when the Supabase project is configured correctly. Payment creation and webhook processing remain Supabase Edge Function responsibilities. The historical `/api/*` POS bridge is intentionally unavailable and returns a controlled error; it must not be treated as a Railway API endpoint.

Before enabling production payment traffic, deploy and verify the relevant Edge Functions, configure Xendit callbacks to the Supabase function URL, set function secrets, set Supabase Auth redirect URLs for the Railway domain, and confirm CORS/allowed-origin policy. Apply database migrations through a controlled staging/production workflow, not through the public frontend container.

## Deployment checklist

1. Create a Railway service from the GitHub repository and confirm Dockerfile builder selection.
2. Set only the three public `VITE_*` variables on the Railway frontend service. Railway's build must receive them because Vite replaces these values at build time.
3. Deploy and verify `GET /health` before testing the UI.
4. Configure the Railway domain in Supabase Auth redirect URLs and any application allowlists.
5. Deploy Supabase migrations and Edge Functions separately to staging first.
6. Test sign-in, RLS-protected reads/writes, Storage policies, Realtime, payment creation, duplicate webhook handling, and logout/session refresh.
7. Confirm that browser bundles contain no service-role key, Xendit secret, callback token, database password, or private signing key.
8. Add domain-level monitoring for Edge Function errors, payment webhook failures, and client observability events.

## Validation performed locally

`pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm test`, `pnpm build`, JSON parsing for `railway.json`, and `git diff --check` all passed. The test suite reported 16 files passed, 46 tests passed, and 11 intentionally skipped RLS staging tests. The production `POSKasirPage` chunk was 51,586 bytes and emitted no chunk warning. Docker image execution was not tested in the sandbox because the Docker daemon is unavailable.

## References

[1]: https://docs.railway.com/config-as-code/reference "Railway Config as Code Reference"
[2]: https://docs.railway.com/guides/react "Railway Deploy a React App"
[3]: https://vite.dev/guide/build "Vite Building for Production"
