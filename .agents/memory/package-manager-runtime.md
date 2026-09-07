---
name: Package manager runtime
description: Environment-specific package-manager mismatch observed during Replit setup.
---

The workspace currently exposes pnpm 10.26.1 while the repository declares pnpm 9.15.9. In this environment, invoking pnpm can try to self-install the pinned version and abort; npm remains usable for project scripts after dependencies are installed.

**Why:** The mismatch blocked the repository's pnpm validation command even though the application build, tests, and Python-based migration bundle validation were healthy.

**How to apply:** Check `pnpm --version` before relying on pnpm-specific commands. Do not change the repository's pinned package-manager policy solely to work around this runtime mismatch; use the project's npm-compatible scripts where safe and keep the discrepancy visible.

When using the managed Node package installer, verify `package.json` and `package-lock.json` afterward; it may reconcile unrelated lockfile metadata while installing a single package.

**Why:** A dependency repair during setup changed an unrelated ESLint root constraint in the npm lockfile even though the manifest was not intentionally changed.

**How to apply:** Review `git diff` after managed installs and restore unrelated lockfile changes before delivering code.

Vercel's pnpm build uses strict dependency resolution, so packages imported directly by a custom VitePWA service worker must be declared directly even when npm's hoisted local install makes them available transitively.

**Why:** The deployment build resolved the main app but failed while bundling `src/sw.ts` because Workbox packages were only transitive dependencies.

**How to apply:** When adding imports to service-worker or build-plugin code, add the package to `package.json` and keep both lockfiles synchronized before deploying.

The project engine requirement is Node 22.13+; the imported Replit runtime initially exposed Node 20, so the workspace module must use nodejs-22 for reliable install/build parity.

**Why:** npm install emitted engine warnings under Node 20 and the repository explicitly constrains Node to `>=22.13.0 <25`.

**How to apply:** Keep `.replit` on Node 22 when running this project, and re-check `node --version` before diagnosing dependency or build failures.