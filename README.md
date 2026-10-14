# SaDesa - Marketplace UMKM & Desa Wisata

SaDesa adalah marketplace UMKM dan destinasi wisata desa di Indonesia.

## Tech Stack

- **Frontend**: Vite, React, TypeScript
- **UI Components**: shadcn-ui, Tailwind CSS
- **Database & Auth**: Supabase
- **Backend/API**: Supabase Edge Functions
- **PWA**: vite-plugin-pwa

## Documentation

Browse the [documentation index](docs/README.md) for API references, plans, audits, pentest and testing reports, operations, security, and database guidance.

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

## Web Push (VAPID)

SaDesa mengirim notifikasi browser/PWA melalui **Web Push dengan VAPID**, bukan melalui email. Broadcast admin menggunakan Edge Function `send-push-notification`; browser memperoleh public key saat membuat subscription melalui `push-subscription`. Jangan menambahkan kunci ke `.env` frontend, `VITE_*`, atau konfigurasi build Railway.

### Buat dan simpan pasangan kunci

Gunakan pasangan public/private yang sama untuk fungsi subscription dan pengiriman pada satu proyek Supabase. Buat pasangan sekali untuk setiap environment (misalnya staging dan production) dan simpan hasilnya di password manager atau secret manager:

```sh
pnpm exec web-push generate-vapid-keys --json
```

> Perintah tersebut mencetak `publicKey` dan `privateKey`. Jangan commit, kirim lewat chat, atau menaruh output di log. Jangan mengganti pasangan yang sedang dipakai tanpa rencana rotasi: browser mungkin perlu membuat ulang subscription setelah public key berubah.

Di komputer tepercaya, simpan nilai dalam file sementara dengan izin terbatas **di luar repository**. Ganti placeholder dengan nilai hasil generator:

```sh
mkdir -p "$HOME/.config/sadesa"
chmod 700 "$HOME/.config/sadesa"
umask 077
$EDITOR "$HOME/.config/sadesa/vapid.env"
```

Isi file tersebut dalam format berikut:

```dotenv
VAPID_PUBLIC_KEY=<publicKey>
VAPID_PRIVATE_KEY=<privateKey>
```

Kemudian login ke Supabase CLI dan kirim file itu sebagai Edge Function secrets. Ambil project ref dari Supabase Dashboard → **Project Settings → General**:

```sh
supabase login
export SUPABASE_PROJECT_REF="your-project-ref"
supabase secrets set \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --env-file "$HOME/.config/sadesa/vapid.env"
```

Hapus file sementara setelah nilainya disimpan aman untuk pemulihan:

```sh
rm -f "$HOME/.config/sadesa/vapid.env"
```

Deploy endpoint yang membaca konfigurasi VAPID:

```sh
supabase functions deploy push-subscription --project-ref "$SUPABASE_PROJECT_REF"
supabase functions deploy send-push-notification --project-ref "$SUPABASE_PROJECT_REF"
```

### Verifikasi

1. Masuk sebagai admin dan buka `/admin/push-notification` → tab **Konfigurasi**. Status **Variabel VAPID tersedia** hanya memastikan kedua variabel ditemukan; status tersebut tidak menguji pengiriman ke provider.
2. Aktifkan notifikasi di browser/PWA perangkat uji yang sudah login, lalu kirim **uji notifikasi** hanya ke perangkat tersebut. Pastikan subscription tersimpan dan notifikasi sistem diterima.
3. Lakukan broadcast setelah uji berhasil. Broadcast hanya dikirim sebagai Web Push kepada perangkat yang memiliki subscription aktif—bukan surat elektronik.

Untuk antrean notifikasi pesanan/chat, konfigurasi worker dan Supabase Vault juga diperlukan; ikuti [panduan operasional notifikasi](docs/operations/mandatory-notification-onboarding.md#konfigurasi-server-dan-verifikasi-staging). Jangan pernah memasukkan `VAPID_PRIVATE_KEY`, service-role key, atau worker secret ke Git maupun browser.

## Service Marketplace

The service marketplace supports verified provider profiles, buyer requests and price negotiation, manual payment-proof review, work-completion confirmation, disputes, and admin payout/refund reconciliation. Transaction state changes are validated by database RPCs; direct browser writes to protected transaction tables are not permitted. Bank transfers and refunds are performed outside the application and recorded with their actual transfer references. A service payment gateway is not integrated yet.

For the data model, RPC parameters, lifecycle, security rules, and deployment requirements, see the [service marketplace API and escrow guide](docs/api/api-service-escrow-disputes.md). The current application routes are `/services`, `/services/requests`, `/services/provider-history`, `/admin/services`, and `/admin/service-disputes`. Apply the service bootstrap migrations in manifest order through the controlled staging/production workflow; merging frontend and SQL files does not apply migrations to a live Supabase project.

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
