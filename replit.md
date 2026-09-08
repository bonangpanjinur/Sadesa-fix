# SaDesa development notes

## Run locally on Replit

This repository is a Vite + React + TypeScript SPA. The configured workflow is:

```sh
npm run dev
```

The application is served on port `5000`. The workspace uses Node.js 22 to
match the repository requirement (`>=22.13.0 <25`).

Install dependencies from the checked-in npm lockfile with:

```sh
npm ci
```

The project declares pnpm `9.15.9`, but the Replit runtime may expose a
different pnpm version and attempt a self-install. Use the npm lockfile and
the npm-compatible scripts in this workspace when that happens.

## Environment

The browser requires these public Supabase variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_SUPABASE_PROJECT_ID`

Only the publishable/anon key belongs in the frontend. Service-role keys,
payment secrets, webhook secrets, and private signing keys belong in Supabase
Edge Function configuration, never in `VITE_` variables.

## Quality checks

```sh
npx tsc --noEmit
npm run lint
npm test
npm run build
```

Database bootstrap bundles can be checked with:

```sh
npm run validate:db-bootstrap
```

The bootstrap manifest records the SHA-256 and byte size of each release
bundle. A passing local validation does not prove that the bundle has been
applied to Supabase staging or production; those environments require the
staging deployment and evidence workflow described in the business plan.