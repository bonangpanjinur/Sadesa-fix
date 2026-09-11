# SaDesa - Marketplace UMKM & Desa Wisata
 
SaDesa adalah marketplace UMKM dan destinasi wisata desa di Indonesia.

## Tech Stack

- **Frontend**: Vite, React, TypeScript
- **UI Components**: shadcn-ui, Tailwind CSS
- **Database & Auth**: Supabase
- **Backend/API**: Supabase Edge Functions
- **PWA**: vite-plugin-pwa

## Getting Started

### Prerequisites

- Node.js 22.13+ and pnpm 9.15.9

### Installation

```sh
git clone https://github.com/bonangpanjinur/remix-of-umkm-sadesa.git
cd remix-of-umkm-sadesa
pnpm install --frozen-lockfile
cp .env.example .env
pnpm dev
```

Set the three public Supabase variables in `.env`: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_SUPABASE_PROJECT_ID`. The browser bundle must only receive the publishable/anon key. Supabase RLS remains the authority for data access.

## API and Security Model

The repository is a Vite SPA; it does **not** contain a Node/Express application server. Database, authentication, storage, realtime, and API calls run through Supabase. Payment and privileged operations run through Supabase Edge Functions. Deploying the SPA to Railway does not automatically deploy Edge Functions; deploy and configure those functions separately with the Supabase CLI or Supabase dashboard.

Server-only variables such as `SUPABASE_SERVICE_ROLE_KEY`, Xendit secret keys, callback tokens, database passwords, and private signing keys must never use the `VITE_` prefix and must never be included in the frontend build. Configure them only in the Supabase Edge Function environment. Review `supabase/functions` and the P0/P1 migration documentation before enabling payment production traffic.

## Railway Deployment

This repository includes `Dockerfile`, `Caddyfile`, `.dockerignore`, and `railway.json`. Railway builds the Vite app in a Node 22 build stage and serves the immutable `dist` output with Caddy. Caddy listens on Railway's injected `$PORT`, serves `/health` for deployment health checks, supports SPA fallback to `index.html`, compresses responses, and disables HTML caching so users receive current asset manifests after deployments.

In Railway, deploy from the GitHub repository using the Dockerfile builder. Configure these **public build-time variables** on the Railway service:

| Variable | Required | Purpose |
|---|---:|---|
| `VITE_SUPABASE_URL` | Yes | Supabase project URL |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Yes | Browser-safe publishable/anon key |
| `VITE_SUPABASE_PROJECT_ID` | Recommended | Project identification used by integrations |

Do not configure Supabase service-role keys or payment provider secrets on the Railway frontend service. Those belong to Supabase Edge Functions. Railway supplies `PORT` automatically; the Caddy container uses it without requiring a hard-coded production port.

After deployment, verify `/health`, sign-in, public storefront reads, a protected read/write under RLS, storage access, realtime behavior, and calls to each required Supabase Edge Function. Configure the production Supabase Auth redirect URL and allowed origins for the generated Railway domain. Do not run database migrations automatically from the public frontend service; apply migrations through a controlled staging/production database workflow.

## Quality Gates

```sh
pnpm exec tsc --noEmit
pnpm lint
pnpm test
pnpm build
pnpm audit --audit-level high
```

For staging RLS tests, use `scripts/run-rls-staging.sh` with staging-only credentials and fixture users. Never point the integration suite at production unless a separate, explicitly approved test project is being used.
