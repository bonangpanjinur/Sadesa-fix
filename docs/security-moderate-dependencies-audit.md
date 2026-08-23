# Audit moderate dependency advisories

Tanggal: 2026-08-23.

## Ringkasan hasil

Setelah pembaruan lockfile dan dependency langsung, `pnpm audit --json` melaporkan **0 critical, 0 high, 1 moderate, dan 2 low**. Production-only audit melaporkan **0 critical, 0 high, 0 moderate, dan 1 low**. Semua advisory DOMPurify, `qs`, `body-parser`, dan esbuild legacy dari `drizzle-kit` telah dihilangkan dari graph aktif. `drizzle-kit` dihapus karena tidak digunakan oleh source code maupun script project; `drizzle-orm` tidak terdeteksi di-import oleh aplikasi.

| Area | Status | Tindakan |
|---|---:|---|
| DOMPurify | Resolved | `dompurify@3.4.14` dipin langsung dan digunakan oleh `jspdf@4.2.1` |
| qs / body-parser | Resolved | `qs@6.15.3` dan `body-parser@2.3.0` dipin; Express 5.2.1 mengonsumsi versi yang sama |
| esbuild 0.18.20 | Resolved | Parent legacy `drizzle-kit` yang tidak dipakai dihapus |
| esbuild dev toolchain | Resolved | root dev dependency `esbuild@0.28.2`; Vite memakai patched 0.28.2 |
| React Router | Resolved | Dimigrasikan ke `react-router-dom@7.18.2`; future flags lama dihapus dari app dan tests |
| ajv 6.12.6 | Deferred / dev-only | Dibawa oleh ESLint 9 dan hanya berada di lint toolchain; tidak dipaksa ke ajv 8 karena major API tidak kompatibel |

## External findings

GitHub's DOMPurify advisory [GHSA-87xg-pxx2-7hvx](https://github.com/cure53/DOMPurify/security/advisories/GHSA-87xg-pxx2-7hvx) reports an XSS bypass in older DOMPurify releases involving `selectedcontent` re-cloning. The project now resolves DOMPurify to 3.4.14.

Netlify's [React Router security update](https://www.netlify.com/changelog/2026-07-23-react-router-security-vulnerabilities/) summarizes multiple issues and recommends React Router 7.18.0 or later for complete coverage. The project now uses `react-router-dom@7.18.2`. The obsolete v7 future flags were removed because React Router 7 enables the behavior by default and no longer exposes those props on `BrowserRouter` or `MemoryRouter`.

## Remaining moderate advisory

### ajv 6.12.6

The advisory is reachable through ESLint 9's development-only dependency graph. It concerns the `$data` option and ReDoS behavior. The application does not ship ESLint or Ajv in the browser bundle, and forcing Ajv 8 into ESLint's Ajv 6 dependency contract could break lint configuration. The safe action in this pass is to keep it isolated to development tooling, avoid `$data` schemas in project tooling, and revisit it when the ESLint major line provides a compatible upgrade.

## pnpm configuration

Security overrides are centralized in `pnpm-workspace.yaml`, the workspace-level configuration used by this repository. Direct pins for packages that must be present in the application graph are also recorded in `package.json`. The lockfile was regenerated with pnpm 9.15.9 after each dependency change.

## Verification command

```bash
pnpm install --frozen-lockfile
pnpm audit --json
pnpm list dompurify qs body-parser esbuild react-router-dom ajv --depth 8
```

The expected security gate for this pass is zero critical and high advisories. Moderate findings are explicitly tracked above with reachability and migration rationale.

## Follow-up backlog

The next security-focused change should revisit Ajv when the ESLint toolchain exposes a compatible patched dependency path. RLS staging integration tests remain required to validate cross-tenant mutation isolation against a real Supabase environment. The remaining large `POSKasirPage` bundle should also be split further in a dedicated performance pass.
