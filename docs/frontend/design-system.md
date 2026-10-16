# Design system SaDesa

Status: standar implementasi aktif. Dokumen ini menjelaskan token dan aturan yang ada sekarang; nilai baru dalam tabel adalah semantic type scale yang ditambahkan bersama dokumen ini. Jangan menganggap pola visual lama yang kebetulan sering muncul sebagai standar jika bertentangan dengan panduan ini.

## Tujuan dan prinsip

- SaDesa terasa hangat, mudah digunakan, dan terpercaya untuk marketplace UMKM/desa wisata, sekaligus efisien untuk alat operasional.
- Gunakan token semantik sebagai pilihan pertama. Hindari nilai warna literal dan ukuran arbitrer untuk keputusan desain yang berulang.
- Pertahankan kebutuhan khusus tiap role (buyer, merchant, admin, courier, POS, desa) lewat varian komponen yang bernama, bukan salinan pola visual yang berbeda-beda.
- Adopsi bertahap. Jangan lakukan global search/replace warna tanpa memastikan makna, kontras, dan state.

## Sumber kebenaran

| Concern | Sumber |
|---|---|
| Warna, surface, border, radius dasar, shadow dan font-size semantic | `src/index.css` |
| Utility Tailwind untuk token | `tailwind.config.ts` |
| Primitive UI bersama | `src/components/ui/` |
| Komposisi utility/class | `src/lib/utils.ts` (`cn`) |

Jika perlu mengubah token, ubah definisi pusat dan cek semua tema; jangan menambah salinan token lokal dalam fitur.

## Warna: pilih berdasarkan makna

- **Brand/aksi utama:** `bg-primary`, `text-primary`, `text-primary-foreground`, `ring-ring`. Warna brand utama saat ini merah hangat; jangan menggantinya dengan emerald hanya karena kelas tersebut banyak dipakai di legacy.
- **Success/online:** `bg-success`, `text-success`, `bg-status-online`, `text-status-online`.
- **Warning/pending:** `bg-warning`, `text-warning`, `bg-status-pending`, `text-status-pending`.
- **Error/destructive/offline:** `bg-destructive`, `text-destructive`, `bg-status-offline`, `text-status-offline`.
- **Informasi:** `bg-info`, `text-info`.
- **Surface dan teks:** `bg-background`, `bg-card`, `text-foreground`, `text-muted-foreground`, `border-border`, `bg-muted`.
- **Kategori/ulasan:** `text-category-*`, `text-gold` hanya untuk makna kategori/ratings.

Warna status bukan warna dekorasi. Jangan gunakan hijau untuk tombol aksi utama atau merah untuk aksen brand tanpa alasan produk yang disepakati. Untuk badge state, utamakan `Badge` dan variant semantik yang sudah ada (`success`, `warning`, `info`, `pending`, `online`, `offline`, `destructive`).

## Tipografi

Gunakan Manrope untuk sans/body dan Sora untuk heading/display. Utility Tailwind yang tersedia dari skala semantik:

| Utility | Peran | Ukuran | Contoh |
|---|---|---:|---|
| `text-display` | Angka/hero display, jarang | 32px | KPI hero atau landing headline |
| `text-page-title` | Judul halaman | 24px | Heading utama halaman |
| `text-section-title` | Judul section/card besar | 18px | Judul grup konten |
| `text-ui` | Judul kontrol/header ringkas | 16px | Header halaman bersama |
| `text-body` | Teks isi standar | 14px | Deskripsi/label panjang |
| `text-caption` | Metadata/teks sekunder kecil | 12px | Timestamp, helper text |
| `text-overline` | Label pendek/kategori | 11px | Label uppercase, gunakan seperlunya |

Skala merupakan default semantic, bukan larangan memakai ukuran Tailwind biasa. Kontrol density, print, chart, map, dan layout responsif boleh memakai ukuran lain dengan alasan konteks. Pertahankan HTML heading yang benar (`h1`–`h6`) untuk struktur dokumen, terlepas dari kelas visual.

## Layout, bentuk, elevasi, dan gerak

- Gunakan skala spacing bawaan Tailwind (`p-4`, `gap-3`, dan seterusnya); hindari angka arbitrer jika nilai skala standar memadai.
- Radius komponen umum gunakan `rounded-sm`, `rounded-md`, atau `rounded-lg` yang bersumber dari `--radius`; `rounded-2xl`/`rounded-3xl` untuk surface besar/ilustratif secara terpilih.
- Pilih shadow token `shadow-sm`, `shadow-md`, `shadow-lg`, atau `shadow-brand`; hindari shadow literal yang mengulang pola umum.
- Hormati prefers-reduced-motion. Animasi dekoratif tidak boleh menghalangi informasi atau aksi.
- Peta, chart, barcode, invoice/print, gambar, dan integrasi pihak ketiga dapat memerlukan presisi lokal; jangan paksa class utility biasa jika merusak fungsi.

## Komponen dan state

1. Pakai primitive `src/components/ui/` sebelum membuat primitive baru. Untuk perilaku bisnis, buat komponen domain di folder domain yang sesuai dan komposisikan primitive bersama.
2. Perluas varian dengan nama berdasarkan tujuan (`success`, `warning`, `compact`) bila pola berulang. Hindari variant lokal yang hanya mengubah warna lewat string tanpa kontrak.
3. Interaksi harus mendefinisikan default, hover, focus-visible, active, disabled, loading, error, dan success sesuai relevansi. Gunakan token ring dan semantic color.
4. State kosong/loading/error harus tetap terbaca dan membantu pengguna; jangan menyamakan error dengan empty state.
5. Kontrol harus memiliki label yang dapat diakses, target sentuh yang layak, urutan keyboard, dan focus indicator. Jangan mengandalkan warna saja untuk menyampaikan status.

## Dark mode dan aksesibilitas

Stylesheet menyediakan variabel `.dark`; class semantic mengikuti token tema jika token dark tersedia. Kelas palette literal dapat melewati tema. Jika fitur menggunakan dark mode, uji setiap state (normal, hover, focus, disabled, loading, error/success) dalam light dan dark. Jangan mengklaim kepatuhan kontras tanpa pengukuran pada kombinasi foreground/background aktual; validasi teks normal dan komponen interaktif terhadap WCAG AA.

## Pengecualian dan kontribusi

Nilai literal/arbitrer boleh dipakai bila benar-benar dibutuhkan (mis. koordinat/peta, chart dengan palet domain, print, asset brand, nilai hasil data). Batasi pada lingkup komponen, beri komentar singkat bila alasannya tidak jelas, dan hindari memperkenalkan pengecualian untuk pola UI berulang.

Saat membuat atau mengubah UI:

- gunakan semantic colors dan type roles di atas;
- cek apakah primitive/variant bersama sudah ada;
- verifikasi viewport sempit dan lebar serta loading/empty/error/focus yang relevan;
- migrasikan legacy pada komponen yang sedang disentuh, bukan dengan perubahan global berisiko;
- perbarui dokumen ini bila token atau kontrak bersama berubah.

## Adopsi legacy

Kode lama masih memuat palette Tailwind langsung dan nilai arbitrer. Itu bukan alasan untuk migrasi massal tanpa review. Prioritaskan komponen bersama yang berdampak luas (Button, badge/status, field, navigasi, card), lalu layar utama buyer dan operasional. Saat menyentuh file legacy, ganti kelas warna berdasarkan **makna** (brand vs success vs warning), bukan pencarian-ganti shade. Untuk perubahan visual luas, tambahkan screenshot/visual regression pada alur representatif.

## Checklist review

- [ ] Warna berasal dari peran semantik, bukan pemilihan shade ad hoc.
- [ ] Tipografi sesuai hierarki dan memakai utility semantic bila cocok.
- [ ] Spacing/radius/elevasi menggunakan skala bersama jika tersedia.
- [ ] Primitive/variant bersama digunakan ulang; tidak ada duplikasi tanpa alasan.
- [ ] Hover, focus-visible, disabled, loading, error/empty tersedia sesuai konteks.
- [ ] Status tidak disampaikan lewat warna saja; label/icon turut menjelaskan.
- [ ] Tampilan responsif dan, bila didukung, dark mode telah diperiksa.
- [ ] Nilai literal/arbitrer yang diperlukan memiliki alasan dan lingkup sempit.
