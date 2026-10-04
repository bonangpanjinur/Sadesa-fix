# SaDesa development notes

## Run locally on Replit

This repository is a Vite + React + TypeScript SPA. The configured workflow is:

```sh
npm run dev
```

The application is served on port `5000`. The workspace uses Node.js 22 to
match the repository requirement (`>=22.13.0 <25`).
Use Replit's Run button to start the `Start application` workflow and open
the preview. Vite listens on all interfaces and accepts Replit's proxy host.

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

The imported workspace already supplies these public Supabase settings.
Keep the existing backend; starting this frontend does not apply database
migrations or deploy Supabase Edge Functions.

The passenger ride map also requires `VITE_GOOGLE_MAPS_API_KEY`, with Maps
JavaScript API and Places API enabled and browser-domain restrictions.
This optional map setting is not required to start the public storefront.

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

## Local delivery rule

Marketplace checkout uses `INTERNAL` for local ojek/kurir delivery and
`EXPEDITION` when the destination is more than 10 km away, in a different
kecamatan, or in a different kabupaten/kota from the merchant. The checkout
automatically selects and locks the expedition option when a restriction
applies. The database bootstrap includes the same validation so direct order
inserts cannot bypass the rule.