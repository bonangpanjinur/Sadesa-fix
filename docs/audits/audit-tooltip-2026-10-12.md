# Audit Tooltip Lintas Role — 2026-10-12

## Cakupan

Audit statis mencakup implementasi tooltip Radix bersama, seluruh pemakaian `TooltipTrigger`/`TooltipContent`, penggunaan `title` native, navigasi bersama dan navigasi per role yang tersedia di `src/components` serta `src/pages`. Role/pengalaman aplikasi yang teridentifikasi meliputi publik/pembeli, admin, admin desa, pedagang, kurir, serta POS (berada di workspace pedagang). Tooltip grafik Recharts dan tooltip internal peta merupakan implementasi berbeda dan tidak dianggap sebagai komponen tooltip Radix.

## Temuan

| Prioritas | Area | Temuan | Status |
|---|---|---|---|
| P1 aksesibilitas | Pedagang/publik — `VerifiedBadge` tanpa label | Pemicu tooltip adalah elemen `<span>` tanpa `tabIndex`, nama aksesibel, atau peran; tooltip ikon-only hanya dapat ditemukan dengan pointer/hover. | Diperbaiki: pemicu kini dapat difokuskan keyboard dan memiliki nama/uraian aksesibel. |
| P1 aksesibilitas | Pedagang/publik — `VerifiedIcon` | Pemicu langsung berupa ikon SVG lucide yang bukan kontrol dan tidak dapat menerima fokus keyboard secara normal, tanpa nama aksesibel. | Diperbaiki dengan pembungkus fokusabel berperan `img`, label aksesibel, dan SVG dekoratif disembunyikan dari pembaca layar. |
| P2 konsistensi | Navigasi admin, desa, pedagang, kurir | Navigasi memakai label menu yang terlihat, bukan tooltip-only; tooltip label tidak diperlukan dalam keadaan normal. Tombol aksi cepat pedagang mengandalkan `title` native, yang tampil dengan jeda dan perilakunya bergantung browser. | Dicatat; tidak mengganti pola global tanpa bukti ada masalah UX atau spesifikasi desain. |
| P2 konsistensi | Tombol ikon/aksi lain | Banyak tombol memiliki `title`; sebagian juga memiliki `aria-label`, tetapi pola tidak seragam. `title` browser bukan pengganti label aksesibel atau tooltip konsisten. | Batasan tersisa: audit ini memperbaiki cacat tooltip bersama spesifik dan tidak mengubah semua tombol/fitur. |
| Informasional | Grafik dan peta | Tooltip Recharts serta `title` marker Leaflet adalah mekanisme library/HTML terpisah. Interaksi keyboard dan output aksesibilitas perlu pengujian khusus tiap visualisasi. | Belum diaudit secara interaksi runtime. |

## Perbaikan dan validasi

- Menambahkan fokus keyboard dan nama aksesibel ke badge ikon-only, sambil tetap mempertahankan tooltip penjelas yang sudah ada.
- Ikon murni disembunyikan dari pembaca layar agar tidak menduplikasi nama badge.
- Menambah tes regresi untuk badge `Populer`, ikon terverifikasi, dan memastikan badge berlabel yang terlihat tidak mendapat fokus ekstra.
- Tes komponen dan build harus dijalankan sebelum merge.

## Batasan

Ini audit kode statis, bukan audit manual browser/screen-reader seluruh halaman. Bahasa tooltip produk saat ini dominan Bahasa Indonesia; konsistensi lokalisasi mengikuti implementasi aplikasi yang ada. Belum ditemukan satu katalog tooltip pusat untuk semua fitur/role.
