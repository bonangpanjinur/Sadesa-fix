# Audit Scrollbar Dashboard Lain

**Tanggal audit:** 14 September 2026  
**Cakupan:** dashboard admin, desa, kurir, verifikator, dan POS.

## Hasil audit

Empat shell dashboard selain merchant memiliki pola yang berisiko menimbulkan scroll halaman ganda atau konten melewati viewport: root shell memakai `min-h-screen`/`min-h-[100dvh]`, wrapper flex utama belum selalu memiliki `min-h-0`, dan beberapa content/sidebar scroll region belum membatasi scroll chaining.

POS tidak memerlukan shell baru karena `POSLayout` menggunakan `MerchantLayout`; setelah perbaikan merchant, modul POS mewarisi kontrak viewport dan scrollbar tersebut. Halaman POS yang memerlukan scroll internal tetap memakai `fullWidth` dan container lokalnya.

## Perbaikan

| Shell | Perubahan |
|---|---|
| Admin | Root dikunci ke `h-dvh max-h-dvh overflow-hidden`; main diberi `min-h-0`, `overflow-y-auto`, `overscroll-contain`, dan `scrollbar-subtle`; sidebar diberi batas flex dan scroll yang sama. |
| Desa | Root dan wrapper utama dikunci ke viewport; content dan sidebar memakai scroll region bounded. |
| Kurir | Root dan wrapper utama dikunci ke viewport; main dan sidebar memakai scrollbar konsisten serta `overscroll-contain`. |
| Verifikator | Root dan wrapper utama dikunci ke viewport; content dan sidebar memakai scroll region bounded. |
| POS | Tidak diubah langsung; mewarisi `MerchantLayout`. |

## Kesimpulan

Dashboard lain memang memerlukan perbaikan scrollbar serupa. Perubahan ini membuat header/sidebar tetap berada di dalam viewport, memindahkan scroll ke panel konten, mencegah momentum scroll bocor ke parent, serta menyamakan tampilan scrollbar antar workspace.

## Verifikasi

`git diff --check` digunakan untuk memeriksa whitespace pada perubahan. Build/lint/test tetap bergantung pada perbaikan tooling dependency repository karena environment sebelumnya tidak dapat menjalankan `npm ci`, Corepack pnpm, maupun Bun.
