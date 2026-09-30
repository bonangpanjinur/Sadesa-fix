# Audit Scrollbar Dashboard Merchant

**Tanggal audit:** 14 September 2026  
**Cakupan:** shell `MerchantLayout`, navigasi `MerchantSidebar`, dan pola overflow pada halaman dashboard merchant.

## Ringkasan

Sebelum perbaikan, shell merchant belum memiliki kontrak scroll yang konsisten. Wrapper konten halaman biasa hanya menjadi flex child tanpa `min-h-0` dan tidak menetapkan scroll container, sehingga ukuran konten dapat mendorong parent dan menghasilkan perilaku scrollbar yang berbeda antar halaman. Mode `fullWidth` juga menggunakan `overflow-hidden`; pola ini aman hanya untuk halaman yang menyediakan scroll internal sendiri.

Sidebar merchant sudah mempunyai `min-h-0 flex-1 overflow-y-auto`, tetapi belum membatasi scroll chaining dan belum memakai gaya scrollbar yang sama dengan area konten.

## Perbaikan

| Area | Perubahan | Dampak |
|---|---|---|
| `MerchantLayout` | Menambahkan `min-h-0` pada flex shell dan content wrapper | Mencegah flex child mempertahankan tinggi intrinsik yang menyebabkan scroll ganda |
| Halaman merchant biasa | Menetapkan `overflow-y-auto overscroll-contain` pada content wrapper | Header tetap stabil dan halaman menggunakan satu scroll container yang jelas |
| Mode `fullWidth` | Mempertahankan `overflow-hidden`, menambahkan `min-h-0` pada wrapper internal | Tidak mematahkan halaman seperti chat/order yang memang memiliki scroll internal |
| Sidebar | Menambahkan `overscroll-contain` | Scroll menu tidak meneruskan momentum ke halaman utama ketika sudah mencapai batas |
| Semua area merchant | Menambahkan `.scrollbar-subtle` dengan scrollbar tipis, kontras moderat, hover state, dan `scrollbar-gutter: stable` | Scrollbar tetap terlihat dan tidak menyebabkan layout bergeser saat muncul |

## Temuan yang tidak diubah

`overflow-x-auto` pada tabel laporan/keuangan dan `max-h-* overflow-y-auto` pada dialog/list tetap dipertahankan karena merupakan scroll container lokal yang memang diperlukan. Audit ini tidak mengubah kontrak data, routing, atau perilaku bisnis.

## Verifikasi

Perubahan source telah diperiksa melalui `git diff`. Validasi awal menggunakan `npm ci` tidak dapat dimulai karena repository mendeklarasikan `pnpm@9.15.9` dan `package-lock.json` tidak sinkron dengan `package.json` (`tsx@4.21.0` vs `tsx@4.23.13`). Build/lint/test perlu dijalankan dengan lockfile pnpm yang sesuai.

## File yang berubah

- `src/components/merchant/MerchantLayout.tsx`
- `src/components/merchant/MerchantSidebar.tsx`
- `src/index.css`
- `docs/audits/audit-scrollbar-dashboard-merchant-2026-09-14.md`

## Audit error dashboard merchant (14 September 2026)

Log browser menunjukkan `POSDailySummaryCard` meminta relation `pos_unified_transaction_history`, tetapi relation tersebut tidak tersedia sehingga Supabase mengembalikan HTTP 404 dan React Query menandai kartu ringkasan POS sebagai gagal dimuat. Schema canonical proyek menggunakan tabel `pos_sales` dengan kolom `tenant_id`, `outlet_id`, `total`, `status`, dan `created_at`. Query kartu telah diarahkan ke `pos_sales` tanpa mengubah kontrak tampilan.
