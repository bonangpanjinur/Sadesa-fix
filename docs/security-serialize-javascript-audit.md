# Audit serialize-javascript dan pnpm overrides

Tanggal audit: 2026-08-23.

## Advisory

GitHub Advisory GHSA-5c6j-r48x-rmvq menyatakan serialize-javascript versi <= 7.0.2 vulnerable terhadap code injection/RCE ketika input RegExp.flags atau Date.toISOString dikontrol attacker dan hasil serialisasi kemudian dievaluasi. Versi patched resmi adalah >= 7.0.3. Sumber: https://github.com/advisories/GHSA-5c6j-r48x-rmvq.

## pnpm configuration

Dokumentasi pnpm menyatakan overrides untuk dependency transitive dapat ditempatkan di bagian `overrides` pada `pnpm-workspace.yaml`. Root package tetap termasuk workspace walaupun packages tidak dikustomisasi. Sumber: https://pnpm.io/settings.

## Repository finding

Dependency graph aktif menunjukkan `@rollup/plugin-terser` memakai serialize-javascript 7.1.0, tetapi pnpm-lock.yaml masih menyimpan entry `serialize-javascript@6.0.2` di importer package plugin. pnpm audit memindai entry tersebut dan melaporkan satu high vulnerability walaupun `pnpm list` hanya menunjukkan jalur aktif ke 7.1.0.

Remediation perlu menghapus stale lock entry atau memperbarui dependency parent yang masih meminta 6.0.2; override global/selector major tidak menghapus entry karena lockfile masih mempertahankan snapshot lama.

## Follow-up dependency graph

The installed graph contains `@rollup/plugin-terser@0.4.4`, whose metadata declares `serialize-javascript: ^6.0.1`; the lockfile resolves it to 6.0.2. The latest `@rollup/plugin-terser@1.0.0` declares `serialize-javascript: ^7.0.3`. The parent package `workbox-build@7.4.0` declares `@rollup/plugin-terser: ^0.4.3`, so upgrading plugin-terser directly may require an override or a newer workbox-build/vite-plugin-pwa combination. GitHub advisory source: https://github.com/advisories/GHSA-5c6j-r48x-rmvq. pnpm settings source: https://pnpm.io/settings.
