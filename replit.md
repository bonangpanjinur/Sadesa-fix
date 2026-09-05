# DesaMart - Marketplace UMKM & Desa Wisata

## Project Overview
DesaMart is a multi-role e-commerce platform and tourism directory for Indonesian villages (UMKM). It supports multiple user roles: buyers, merchants, couriers, verifikators (village-level coordinators), and system administrators. It also includes a full POS SaaS module (6 phases) for merchant point-of-sale management.

## Tech Stack
- **Frontend**: React 18 + TypeScript
- **Build Tool**: Vite (port 5000)
- **Styling**: Tailwind CSS + shadcn/ui components
- **Backend/Database**: Supabase (PostgreSQL, Auth, Storage, Realtime)
- **Backend/API**: Supabase Edge Functions (the SPA has no local API server)
- **State Management**: TanStack Query (React Query)
- **Routing**: React Router
- **Package Manager**: pnpm 9.15.9 (the repository also contains a generated npm lockfile for compatibility)

## Project Structure
- `src/` - Main application source
  - `components/` - UI components by feature/role
  - `pages/` - Routed pages by user role (admin, merchant, courier, verifikator, buyer, desa, pos, ride)
  - `hooks/` - Custom React hooks
  - `integrations/supabase/` - Supabase client config and generated types
- `integrations/lovable/` - Stub (social OAuth disabled on Replit)
  - `lib/` - Utilities, API wrappers, i18n
  - `contexts/` - React Contexts (Auth, Cart, Whitelabel, POS)
  - `types/` - TypeScript definitions
- `supabase/` - DB migrations, bootstrap bundles, and Edge Functions
- `public/` - Static assets and PWA manifest

## Environment Variables (set in Replit Env Vars)
- `VITE_SUPABASE_URL` - Supabase project URL
- `VITE_SUPABASE_PUBLISHABLE_KEY` - Supabase anon/public key
- `VITE_SUPABASE_PROJECT_ID` - Supabase project ID
- Server-only Supabase service-role keys, payment secrets, callback tokens, database passwords, and signing keys belong in Supabase Edge Function secrets, never in `VITE_*` variables.

## Development
- Frontend dev server runs on port 5000 (host: 0.0.0.0)
- Replit uses one `Start application` workflow: `npm run dev`
- `pnpm dev` or `npm run dev` - Start Vite frontend dev server
- `pnpm build` or `npm run build` - Build for production
- `pnpm test` or `npm test` - Run tests

## User Roles
- `buyer` - Default role, browses and orders products
- `merchant` - Manages products, orders, and store settings
- `courier` - Handles deliveries and ride-hailing (Ojek Desa)
- `verifikator` - Village-level trade group coordinator
- `admin_desa` - Village administrator (tourism, desa dashboard)
- `admin` - System administrator (full access)

## POS SaaS Roles (within pos_tenants)
- `owner` - Full POS access
- `manager` - Management access
- `kasir` - Cashier
- `staff_gudang` - Warehouse staff
- `purchasing` - Purchasing team
- `finance` - Finance team
- `auditor` - Read-only auditor

## User Preferences
- Use Indonesian/English bilingual comments where relevant
- Follow existing role-based page/component organization
- App language: Indonesian (Bahasa Indonesia)
