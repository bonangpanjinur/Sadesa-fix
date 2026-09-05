---
name: Package manager runtime
description: Environment-specific package-manager mismatch observed during Replit setup.
---

The workspace currently exposes pnpm 10.26.1 while the repository declares pnpm 9.15.9. In this environment, invoking pnpm can try to self-install the pinned version and abort; npm remains usable for project scripts after dependencies are installed.

**Why:** The mismatch blocked the repository's pnpm validation command even though the application build, tests, and Python-based migration bundle validation were healthy.

**How to apply:** Check `pnpm --version` before relying on pnpm-specific commands. Do not change the repository's pinned package-manager policy solely to work around this runtime mismatch; use the project's npm-compatible scripts where safe and keep the discrepancy visible.