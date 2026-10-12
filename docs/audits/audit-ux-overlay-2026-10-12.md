# Laporan Audit UX Overlay — SaDesa

**Tanggal:** 2026-10-12  
**Cakupan:** primitive UI dan integrasi overlay global; admin; merchant/POS; halaman publik, pembeli, akun, checkout, order, explore, dan notifikasi; desa/kurir.  
**Metode:** sintesis hasil audit statis terstruktur lintas area. Setelah sintesis, beberapa temuan prioritas ditinjau kembali dan diperbaiki; daftar awal tetap mencatat temuan saat audit dilakukan.

## Ringkasan eksekutif

Setelah menggabungkan isu `ImageLightbox.tsx` yang disebut kembali dalam cakupan publik dengan temuan pada primitive bersama, laporan ini mencatat **42 isu unik: 0 Critical, 7 High, 29 Medium, dan 6 Low**. Beberapa entri sumber menggabungkan atau mengulang pola; hitungan unik di sini tidak menghitung duplikat sebagai masalah baru. Severity mengikuti hasil yang diberikan.

Prioritas tertinggi ialah mencegah penghapusan/perubahan status yang tidak disengaja, memperbaiki modal/filter yang tidak menjalankan atau mengekspos perilaku modal secara lengkap, menyediakan operasi keyboard untuk pilihan alamat/notifikasi, dan menolak nilai kosong yang dapat dikirim sebagai rekonsiliasi COD nol. Masalah label/nama aksesibel juga berulang. Risiko clipping dan lifecycle fokus tertentu masih memerlukan pengujian browser sebelum dampak runtime dianggap terverifikasi.

## Kategori bukti dan confidence

- **Bug statis terkonfirmasi:** kekurangan yang tampak langsung dalam bukti source, seperti handler hanya pointer, atribut label/nama tidak ada, atau alur delete langsung. Ini tidak berarti seluruh dampak pada semua browser/pembaca layar telah diuji.
- **Risiko—perlu tes browser:** source menunjukkan potensi masalah, tetapi hasil seperti clipping, perpindahan/pemulihan fokus, dismissal saat proses berjalan, atau perilaku runtime belum diuji.
- **Saran usability:** konsistensi/pengalaman yang dapat ditingkatkan dan tidak dinyatakan sebagai kegagalan aksesibilitas terbukti.
- **Confidence tinggi:** bukti source yang dirangkum spesifik dan langsung. **Sedang:** dampak bergantung pada perilaku runtime, viewport, atau teknologi bantu.

## High — 7 isu

### H-01 — Hapus foto galeri merchant tanpa konfirmasi
- **Jenis overlay/kontrol:** konfirmasi aksi destruktif.
- **Path:line:** `src/pages/merchant/MerchantGalleryPage.tsx:187–194` (pemanggilan pada 190; mutation pada 44–48).
- **Evidence:** Tombol Hapus langsung memanggil `deleteMutation.mutate(item.id)`; mutation menjalankan `.delete()` pada `merchant_gallery`, tanpa konfirmasi.
- **Dampak:** Salah tekan layar sentuh dapat langsung menghapus foto secara permanen.
- **Rekomendasi:** Gunakan `AlertDialog` yang mengidentifikasi foto, menyediakan Batal/Hapus, dan mempertahankan disabled/loading selama mutation.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### H-02 — Hapus brand POS langsung; tombol “×” tidak bernama
- **Jenis overlay/kontrol:** konfirmasi destruktif dan kontrol ikon.
- **Path:line:** `src/pages/pos/POSPengaturanPage.tsx:489–493` (fungsi delete pada 345–347).
- **Evidence:** Tombol hanya berisi karakter “×” dan langsung memanggil `deleteBrand(b.id)`; fungsi menjalankan `.delete().eq('id', id)`. Tidak ada konfirmasi atau nama aksesibel.
- **Dampak:** Salah tap dapat menghapus brand seketika; pembaca layar tidak mengetahui aksi tombol.
- **Rekomendasi:** Tambahkan nama kontekstual seperti “Hapus brand {nama}” dan konfirmasi `AlertDialog` sebelum penghapusan.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### H-03 — Filter sheet custom tidak diekspos/dioperasikan sebagai dialog modal
- **Jenis overlay:** filter sheet/modal.
- **Path:line:** `src/components/explore/FilterSheet.tsx:95–110, 122–124`.
- **Evidence:** Backdrop dan sheet adalah `motion.div`; sheet tidak memiliki role/nama/status modal. Tidak ada Escape atau focus management. Tombol tutup hanya ikon.
- **Dampak:** Teknologi bantu tidak memperoleh konteks modal; keyboard dapat mencapai konten belakang, tidak tersedia Escape, dan tombol tutup tidak bernama.
- **Rekomendasi:** Gunakan Dialog/Sheet bersama atau implementasikan semantik modal, lifecycle fokus, Escape/backdrop dismissal, dan nama tombol tutup.
- **Klasifikasi:** Kekurangan source terkonfirmasi; dampak fokus aktual perlu diuji di browser.
- **Confidence:** Tinggi untuk bukti source; sedang untuk perilaku runtime.

### H-04 — Kartu alamat selectable hanya dapat dipilih dengan pointer
- **Jenis overlay/kontrol:** pemilih alamat.
- **Path:line:** `src/components/address/AddressCard.tsx:39–44`.
- **Evidence:** `Card` menerima `onClick` tetapi tidak memiliki role tombol/link, `tabIndex`, handler keyboard, atau atribut state terpilih.
- **Dampak:** Pengguna keyboard tidak dapat memilih alamat pada daftar alamat tersimpan maupun checkout.
- **Rekomendasi:** Gunakan tombol native terpisah dari aksi menu, atau kontrol button/radio yang fokusabel, mendukung Enter/Space, dan mengekspos state terpilih.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### H-05 — Baris notifikasi adalah `div` klik tanpa operasi keyboard
- **Jenis overlay/kontrol:** navigasi/aksi notifikasi.
- **Path:line:** `src/pages/NotificationsPage.tsx:224–237`.
- **Evidence:** Setiap notifikasi adalah `div` dengan `onClick`, tanpa focusability, semantik button/link, atau handler keyboard.
- **Dampak:** Pengguna keyboard tidak dapat membuka tujuan notifikasi atau menjalankan aksi utama untuk menandainya dibaca.
- **Rekomendasi:** Gunakan link/button native untuk aksi utama dan kontrol hapus terpisah; hindari elemen interaktif bersarang.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### H-06 — Keputusan keanggotaan dan booking tanpa konfirmasi eksplisit
- **Jenis overlay:** konfirmasi perubahan status sensitif.
- **Path:line:** `src/pages/desa/DesaKeanggotaanPage.tsx:236–242` (handler 99–107); perubahan booking `src/pages/desa/DesaPaketWisataPage.tsx:325–329`.
- **Evidence:** Tombol pending member langsung memanggil `handleVerify(id, true/false)` dan handler langsung menulis `APPROVED/REJECTED`. Aksi status booking juga langsung dijalankan.
- **Dampak:** Salah klik dapat mengubah keputusan anggota/booking tanpa langkah telaah atau pembatalan.
- **Rekomendasi:** Tambahkan `AlertDialog` yang mengidentifikasi pihak/booking dan state tujuan, dengan Batal; pertimbangkan field alasan untuk penolakan.
- **Klasifikasi:** Bug statis terkonfirmasi untuk tidak adanya konfirmasi.
- **Confidence:** Tinggi.

### H-07 — Nilai COD kosong dapat lolos sebagai nol
- **Jenis overlay/kontrol:** validasi form rekonsiliasi.
- **Path:line:** `src/pages/courier/CourierEarningsPage.tsx:121–124` (input 252).
- **Evidence:** Kode mengubah `collectedCash` dengan `Number()` dan hanya menolak nilai non-finite/negatif. Input tidak wajib; `Number('')` bernilai `0`, sehingga kosong lolos.
- **Dampak:** Rekonsiliasi dapat tersimpan sebagai nol tunai secara tidak sengaja.
- **Rekomendasi:** Tolak string kosong/whitespace sebelum konversi, jadikan input required, tampilkan error inline, dan fokus/umumkan error.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

## Medium — 29 isu

### M-01 — ImageLightbox tidak mempunyai nama dialog aksesibel
- **Jenis overlay:** dialog gambar.
- **Path:line:** `src/components/ui/ImageLightbox.tsx:51`.
- **Evidence:** `DialogContent` merender tombol ikon dan gambar ber-alt “Image n” pada 55–70, tanpa `DialogTitle` atau `aria-label` untuk dialog.
- **Dampak:** Alt gambar tidak menjadi nama dialog; identitas dialog mungkin tidak diumumkan pembaca layar.
- **Rekomendasi:** Tambahkan `DialogTitle` (boleh visually hidden) atau nama aksesibel pada konten, seperti label galeri dan indeks gambar.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-02 — Tombol navigasi/zoom ImageLightbox tidak bernama
- **Jenis overlay/kontrol:** kontrol dialog gambar.
- **Path:line:** `src/components/ui/ImageLightbox.tsx:77–120`.
- **Evidence:** Tombol kiri/kanan dan zoom hanya menampilkan ikon, tanpa teks atau `aria-label`.
- **Dampak:** Pembaca layar tidak mengetahui fungsi navigasi atau zoom.
- **Rekomendasi:** Beri label spesifik untuk foto sebelumnya/berikutnya, perkecil, dan perbesar; sertakan indeks gambar bila sesuai.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-03 — ImageLightbox terkontrol tidak menetapkan pemulihan fokus opener
- **Jenis overlay:** lifecycle fokus dialog.
- **Path:line:** `src/components/ui/ImageLightbox.tsx:50`; opener contoh `ReviewImageGallery` pada 22–27 dan 41.
- **Evidence:** Dialog terkontrol tidak memiliki `DialogTrigger` atau `onCloseAutoFocus`; opener contoh tombol biasa yang mengubah state.
- **Dampak:** Fokus berisiko tidak kembali ke pemicu setelah dialog ditutup.
- **Rekomendasi:** Simpan elemen opener via ref dan pulihkan fokus pada `onCloseAutoFocus`, atau integrasikan mekanisme trigger Radix yang sesuai.
- **Klasifikasi:** Risiko—perlu tes browser/keyboard untuk memastikan fokus aktual.
- **Confidence:** Sedang.

### M-04 — Dialog verifikator tidak menyediakan deskripsi yang dirujuk
- **Jenis overlay:** dialog form.
- **Path:line:** `src/pages/verifikator/VerifikatorEarningsPage.tsx:532–563`; wrapper `src/components/ui/dialog.tsx:36–43`.
- **Evidence:** `DialogContent` diikuti `DialogTitle` dan form tanpa `DialogDescription` maupun `aria-describedby={undefined}`; wrapper meneruskan props.
- **Dampak:** Temuan sumber menyatakan relasi `aria-describedby` Radix dapat menunjuk ID deskripsi yang tidak ada, merusak asosiasi deskripsi dan menimbulkan peringatan development.
- **Rekomendasi:** Tambahkan deskripsi singkat formulir penarikan atau set `aria-describedby={undefined}` eksplisit jika deskripsi tidak diperlukan.
- **Klasifikasi:** Risiko source/runtime; konfirmasi peringatan dan relasi saat runtime.
- **Confidence:** Sedang.

### M-05 — Pemicu menu aksi admin tidak bernama
- **Jenis overlay:** pemicu dropdown/kontrol ikon.
- **Path:line:** `src/pages/admin/AdminUsersPage.tsx:610–611`; pola lain `AdminVillagesPage.tsx:197`, `AdminCodesPage.tsx:227`.
- **Evidence:** Pemicu hanya berisi `MoreHorizontal`, tanpa `aria-label` atau `title`; hasil juga mencatat tombol ikon admin lain tanpa nama.
- **Dampak:** Pembaca layar dapat mengumumkan tombol tanpa tujuan.
- **Rekomendasi:** Beri nama spesifik per objek, misalnya “Aksi untuk {nama pengguna}”, kepada tombol ikon tanpa teks.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-06 — Label Select alamat admin tidak terhubung dengan trigger
- **Jenis overlay:** Select alamat bertingkat.
- **Path:line:** `src/components/admin/AddressDropdowns.tsx:336–360` dan bidang berikutnya.
- **Evidence:** Label Provinsi adalah sibling Select tanpa `htmlFor`; `SelectTrigger` tidak memiliki `id`. Pola berulang pada Kabupaten/Kota dan bidang selanjutnya.
- **Dampak:** Nama field mungkin tidak diumumkan secara stabil, membuat kontrol alamat bertingkat sulit dibedakan.
- **Rekomendasi:** Beri ID unik dan hubungkan label jika didukung, atau gunakan `aria-labelledby`/`aria-label` pada keempat trigger.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-07 — Combobox kustom kode admin tidak memiliki state/pola keyboard lengkap
- **Jenis overlay:** combobox/popup pilihan.
- **Path:line:** `src/pages/admin/AdminCodesPage.tsx:281–314`.
- **Evidence:** Trigger memakai `role="combobox"` tanpa `aria-expanded`/`aria-controls`; popup berisi input dan tombol biasa, bukan opsi/listbox dengan state pilihan atau navigasi panah.
- **Dampak:** Semantik popup tidak akurat dan pengguna keyboard harus Tab melewati opsi satu per satu.
- **Rekomendasi:** Gunakan pola combobox/listbox teruji (misalnya Command/CommandItem) atau implementasikan state ARIA, navigasi panah, Enter/Escape, dan status opsi.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-08 — Pemilihan titik peta admin tidak menyediakan alternatif keyboard
- **Jenis overlay/kontrol:** pemilih lokasi.
- **Path:line:** `src/components/admin/AdminLocationPicker.tsx:27–30, 155`.
- **Evidence:** `MapClickHandler` hanya mendaftarkan event klik; tidak ada input koordinat/cara keyboard untuk memilih titik. “Lokasi Saya” hanya memilih lokasi perangkat.
- **Dampak:** Pengguna keyboard/switch/pembaca layar tidak memiliki cara setara memilih titik lain dengan presisi.
- **Rekomendasi:** Sediakan input latitude/longitude yang berlabel dan tervalidasi, sinkronkan ke peta, dan umumkan perubahan pilihan.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-09 — Penghapusan paket POS admin berlangsung tanpa konfirmasi
- **Jenis overlay/kontrol:** aksi destruktif.
- **Path:line:** `src/pages/admin/AdminPOSPage.tsx:321–325, 681`.
- **Evidence:** Handler langsung menghapus dari `pos_packages`; tombol Hapus paket memanggil handler tanpa `AlertDialog` atau kesempatan membatalkan.
- **Dampak:** Salah klik dapat menghapus konfigurasi paket tanpa pembatalan.
- **Rekomendasi:** Konfirmasi dengan nama paket dan konsekuensi yang jelas, Batal sebagai pilihan aman, serta aksi destruktif berlabel.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-10 — Dialog daftar held bills tidak dibatasi terhadap viewport
- **Jenis overlay:** dialog daftar dinamis.
- **Path:line:** `src/components/pos/kasir/POSHeldBills.tsx:16–30`.
- **Evidence:** `DialogContent` merender seluruh `heldBills` tanpa batas tinggi/scroll; dialog bersama diposisikan fixed di tengah tanpa batas tinggi bawaan.
- **Dampak:** Daftar panjang berisiko melampaui viewport, membuat item bawah atau kontrol penutup sulit dijangkau.
- **Rekomendasi:** Batasi tinggi dengan unit `100dvh`, jadikan daftar `overflow-y-auto`, dan pertahankan judul/penutup terlihat.
- **Klasifikasi:** Risiko—perlu tes browser pada layar pendek, mobile, landscape, dan daftar panjang.
- **Confidence:** Sedang.

### M-11 — Label Select absensi POS tidak tertaut
- **Jenis overlay:** Select form.
- **Path:line:** `src/pages/pos/POSAbsensiPage.tsx:306–317`.
- **Evidence:** Label Karyawan dan Status tidak memiliki `htmlFor`; trigger tidak memiliki `id` atau `aria-label`.
- **Dampak:** Nama/tujuan combobox mungkin tidak diumumkan secara programatis.
- **Rekomendasi:** Beri ID trigger dan hubungkan label, atau gunakan `aria-labelledby`/`aria-label` eksplisit.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-12 — Konfirmasi hapus MerchantBundle memakai overlay custom non-dialog
- **Jenis overlay:** dialog konfirmasi destruktif.
- **Path:line:** `src/pages/merchant/MerchantBundlePage.tsx:547–558`.
- **Evidence:** Overlay berupa `div` fixed dan Card; tidak ada `role=dialog`, `aria-modal`, pengelolaan fokus, atau handler Escape.
- **Dampak:** Konteks modal tidak disampaikan dengan konsisten; fokus dapat berinteraksi dengan latar atau kehilangan orientasi.
- **Rekomendasi:** Ganti dengan `AlertDialog`; jika tetap custom, implementasikan semantik modal, focus trap/restore, fokus awal, dan Escape.
- **Klasifikasi:** Kekurangan source terkonfirmasi; dampak fokus perlu tes browser.
- **Confidence:** Tinggi untuk markup, sedang untuk dampak runtime.

### M-13 — Preview gambar merchant memakai lightbox custom non-dialog
- **Jenis overlay:** preview gambar/modal.
- **Path:line:** `src/pages/merchant/MerchantGalleryPage.tsx:240–259`.
- **Evidence:** Preview `div` fixed, bukan Dialog; tidak ada role dialog, `aria-modal`, focus management, atau Escape. Tombol tutup memiliki `aria-label`, backdrop menutup.
- **Dampak:** Fokus keyboard dapat tetap di konten belakang dan pembaca layar tidak diberi tahu preview modal aktif.
- **Rekomendasi:** Gunakan Dialog bernama atau implementasikan semantik modal lengkap, focus trap/restore, Escape, dan dismiss.
- **Klasifikasi:** Bug statis terkonfirmasi; uji fokus/dismiss di browser.
- **Confidence:** Tinggi untuk kekurangan source.

### M-14 — Header search overlay tidak mengurung/memulihkan fokus
- **Jenis overlay:** dialog pencarian custom.
- **Path:line:** `src/components/layout/Header.tsx:68–76, 176–180`.
- **Evidence:** Overlay `div role="dialog" aria-label="Pencarian SaDesa"`; efek hanya fokus ke input dan menutup dengan Escape. Tidak ada `aria-modal`, focus containment, atau restoration.
- **Dampak:** Keyboard dapat mencapai konten header/halaman di belakang overlay dan fokus tidak eksplisit kembali ke pemicu.
- **Rekomendasi:** Gunakan Radix Dialog/Sheet atau tambahkan semantik modal, focus trap, dan pemulihan fokus sambil mempertahankan dismissal.
- **Klasifikasi:** Risiko—perlu tes browser/keyboard untuk urutan dan pemulihan fokus.
- **Confidence:** Sedang.

### M-15 — Sort popup custom tidak memiliki semantik menu dan Escape
- **Jenis overlay:** dropdown sort.
- **Path:line:** `src/components/explore/SortDropdown.tsx:36–68` (dismiss pointer luar pada 59–62).
- **Evidence:** Trigger hanya mengekspos `aria-expanded`; popup `motion.div` tidak ber-role, berisi tombol, hanya ditutup klik luar, tanpa Escape.
- **Dampak:** Teknologi bantu tidak mengenali menu/item; keyboard tidak mendapat dismissal Escape atau interaksi panah menu.
- **Rekomendasi:** Ganti dengan Radix `DropdownMenu`/`Select` atau implementasikan semantik menu, navigasi panah, Escape, dan focus return.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-16 — Label Select alamat checkout tidak terhubung
- **Jenis overlay:** Select alamat bertingkat.
- **Path:line:** `src/components/AddressSelector.tsx:305–430`.
- **Evidence:** Label Provinsi pada 305 dan trigger pada 311 tidak memiliki `htmlFor`/`id`; pola berulang pada City, District, Village, dan detail.
- **Dampak:** Nama field dapat tidak diumumkan, membuat urutan alamat bertingkat ambigu.
- **Rekomendasi:** Hubungkan ID stabil dengan label atau pasang label ARIA terlokalisasi pada setiap trigger; labeli textarea detail.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-17 — Label penerima/telepon dialog alamat tidak terhubung
- **Jenis overlay:** form dialog alamat.
- **Path:line:** `src/components/address/AddressFormDialog.tsx:133–150`.
- **Evidence:** Label Nama Penerima/No. Telepon tidak memiliki `htmlFor` atau ID kontrol yang cocok; Input dan PhoneInput sibling.
- **Dampak:** Pembaca layar dapat menemui field tanpa label.
- **Rekomendasi:** Beri ID unik dan `htmlFor`; pastikan PhoneInput meneruskan ID ke input aktual.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-18 — Pemicu menu overflow kartu alamat tidak bernama
- **Jenis overlay:** dropdown menu aksi alamat.
- **Path:line:** `src/components/address/AddressCard.tsx:83–86`.
- **Evidence:** Trigger membungkus Button yang hanya berisi `MoreVertical`, tanpa label/teks tersembunyi.
- **Dampak:** Teknologi bantu mengumumkan tombol tanpa tujuan.
- **Rekomendasi:** Tambahkan label kontekstual, misalnya “Aksi alamat {label}”.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-19 — Tombol galeri gambar produk tidak bernama/menyatakan gambar aktif
- **Jenis overlay/kontrol:** pemilih gambar galeri.
- **Path:line:** `src/components/product/ProductImageGallery.tsx:52–85`.
- **Evidence:** Tombol dot tidak berlabel; thumbnail memakai `alt=""` dan tidak memiliki label atau state current/pressed.
- **Dampak:** Pengguna pembaca layar tidak dapat mengenali gambar yang dipilih atau aktif.
- **Rekomendasi:** Namai tiap kontrol dengan posisi/produk dan ekspos item aktif melalui `aria-current` atau `aria-pressed`.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-20 — Tombol hapus notifikasi tidak bernama
- **Jenis overlay/kontrol:** aksi ikon notifikasi.
- **Path:line:** `src/pages/NotificationsPage.tsx:263–271`.
- **Evidence:** Tombol hanya berisi ikon `Trash2`, tanpa label, title, atau teks tersembunyi.
- **Dampak:** Pembaca layar tidak dapat mengenali aksi hapus dan targetnya.
- **Rekomendasi:** Tambahkan label lokal seperti “Hapus notifikasi: {judul}”.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-21 — Kontrol hapus/kuantitas keranjang tidak bernama
- **Jenis overlay/kontrol:** kontrol item keranjang.
- **Path:line:** `src/pages/CartPage.tsx:307–330`.
- **Evidence:** Tombol remove, decrement, increment hanya berisi ikon `Trash2`/`Minus`/`Plus`, tanpa `aria-label`.
- **Dampak:** Aksi tiap item tidak dapat diidentifikasi dengan andal oleh teknologi bantu.
- **Rekomendasi:** Tambahkan label lokal yang menyebut nama produk dan aksi; sediakan konteks jumlah saat ini.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-22 — Kontrol hapus bukti refund tidak bernama
- **Jenis overlay/kontrol:** kontrol gambar dalam dialog refund.
- **Path:line:** `src/components/order/RefundRequestDialog.tsx:172–177`.
- **Evidence:** Tombol hapus preview hanya ikon X tanpa nama aksesibel atau konteks item.
- **Dampak:** Pengguna pembaca layar tidak mengetahui cara menghapus atau gambar yang terpengaruh.
- **Rekomendasi:** Tambahkan label lokal seperti “Hapus bukti foto {nomor}” dan indikator fokus terlihat.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-23 — Dialog refund tidak dibatasi terhadap viewport
- **Jenis overlay:** dialog form/bukti.
- **Path:line:** `src/components/order/RefundRequestDialog.tsx:128–189`.
- **Evidence:** `DialogContent` hanya memakai `max-w-md`; tidak ada `max-height`/overflow scroll sementara form dapat berisi teks dan sampai empat preview.
- **Dampak:** Pada layar pendek, landscape, atau zoom, konten/aksi berisiko melewati viewport.
- **Rekomendasi:** Batasi tinggi dengan unit viewport dinamis dan scroll body, dengan aksi tetap dapat dijangkau.
- **Klasifikasi:** Risiko—perlu tes browser pada viewport pendek, landscape, zoom, dan banyak preview.
- **Confidence:** Sedang.

### M-24 — Tombol kuantitas halaman produk tidak bernama
- **Jenis overlay/kontrol:** pengubah kuantitas.
- **Path:line:** `src/pages/ProductDetail.tsx:463–479`.
- **Evidence:** Tombol decrement/increment hanya berisi ikon Minus/Plus tanpa `aria-label`.
- **Dampak:** Pembaca layar tidak mengetahui aksi jumlah produk.
- **Rekomendasi:** Tambahkan label lokal seperti “Kurangi jumlah {produk}”/“Tambah jumlah {produk}”; pertimbangkan pengumuman jumlah sekarang.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-25 — Status update keanggotaan/booking error tidak diperiksa
- **Jenis overlay/kontrol:** hasil aksi perubahan status.
- **Path:line:** `src/pages/desa/DesaKeanggotaanPage.tsx:102–106`; pola serupa `src/pages/desa/DesaPaketWisataPage.tsx:178–182`.
- **Evidence:** Hasil update ditunggu tetapi error yang dikembalikan tidak diperiksa; eksekusi berlanjut ke toast sukses.
- **Dampak:** Gagalnya perubahan dapat dilaporkan sebagai sukses dan status tampilan menjadi menyesatkan.
- **Rekomendasi:** Periksa `{ error }`, tangani sebelum feedback sukses, dan pertahankan aksi disabled/error state sampai hasil diketahui.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-26 — Label form desa tidak terhubung ke kontrol
- **Jenis overlay/kontrol:** label form dan Select.
- **Path:line:** `src/pages/desa/DesaBroadcastPage.tsx:227–232`; pola di form event/guide/tourism/COD/POD; `DesaDonasiPage.tsx:335–344, 411–420`.
- **Evidence:** Label judul/pesan tidak memiliki `htmlFor` atau ID kontrol; pola sibling-label berulang. Select kategori juga tidak terhubung dan selector campaign tidak berlabel terlihat.
- **Dampak:** Teknologi bantu mungkin tidak mengumumkan nama field, menyulitkan pengisian dan koreksi.
- **Rekomendasi:** Beri ID dan `htmlFor` pada semua kontrol termasuk SelectTrigger; labeli selector campaign dan verifikasi accessibility tree.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-27 — Tombol aksi ikon desa/kurir tidak bernama spesifik
- **Jenis overlay/kontrol:** pemicu dropdown dan aksi ikon.
- **Path:line:** `src/pages/desa/DesaTourismPage.tsx:233`; pola lain di `DesaDonasiPage.tsx:306–316`, `DesaEventPage.tsx:271–275`, `DesaPemanduPage.tsx:208–210`, `src/components/courier/DeliveryProofDialog.tsx:66`.
- **Evidence:** Pemicu menu hanya `MoreHorizontal` tanpa nama; hasil menyebut tombol edit/hapus/visibility/share dan hapus foto yang juga berupa ikon tanpa nama.
- **Dampak:** Pengguna keyboard/pembaca layar tidak mengetahui aksi atau target tombol.
- **Rekomendasi:** Tambahkan label kontekstual, misalnya “Aksi untuk {nama wisata}”, “Edit {nama event}”, atau “Hapus foto bukti”.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### M-28 — Dialog form event desa tidak dibatasi untuk layar pendek
- **Jenis overlay:** dialog form.
- **Path:line:** `src/pages/desa/DesaEventPage.tsx:287–338`.
- **Evidence:** `DialogContent` hanya menetapkan `max-w-md`; form beberapa baris/footer tidak memiliki `max-h` atau overflow scroll.
- **Dampak:** Pada viewport mobile pendek/landscape, field atau aksi bawah berisiko tidak terjangkau.
- **Rekomendasi:** Batasi dimensi pada viewport dinamis, aktifkan scroll internal, dan uji layar sempit/pendek.
- **Klasifikasi:** Risiko—perlu tes browser untuk memastikan clipping.
- **Confidence:** Sedang.

### M-29 — DeliveryProofDialog dapat ditutup ketika upload/status sedang berjalan
- **Jenis overlay:** dialog upload dan perubahan status.
- **Path:line:** `src/components/courier/DeliveryProofDialog.tsx:62–71`.
- **Evidence:** `onOpenChange` selalu memanggil `onClose`; hanya tombol Batal yang disabled saat upload. Tombol close dan dismissal Radix Escape/outside tidak dijaga oleh `uploading`.
- **Dampak:** Dialog dapat hilang sementara upload/RPC terus berjalan; pengguna mungkin mengira aksi batal dan tidak melihat kegagalan selanjutnya.
- **Rekomendasi:** Cegah dismissal saat submit atau buat operasi benar-benar dapat dibatalkan; jika berlanjut, umumkan proses dan tampilkan hasilnya.
- **Klasifikasi:** Risiko—perlu tes browser/runtime saat proses in-flight.
- **Confidence:** Sedang.

## Low — 6 isu

### L-01 — Prompt/confirm native tidak konsisten dengan modal admin
- **Jenis overlay:** konfirmasi native browser.
- **Path:line:** `src/pages/admin/AdminPOSPage.tsx:406–415`; pembanding dialog aplikasi 1038–1049.
- **Evidence:** Suspend/cancel memakai `window.prompt`/`window.confirm`, sementara alur penolakan di halaman yang sama memakai Dialog kustom.
- **Dampak:** Tata letak, konteks, dan pengalaman konfirmasi berbeda antaraksi.
- **Rekomendasi:** Pertimbangkan Dialog/AlertDialog aplikasi dengan nama merchant, dampak, fokus awal, Batal, dan aksi jelas.
- **Klasifikasi:** Saran usability, bukan klaim bahwa dialog native sendiri tidak aksesibel.
- **Confidence:** Tinggi untuk perbedaan pola source.

### L-02 — Tombol hapus item transfer stok tidak bernama
- **Jenis overlay/kontrol:** aksi ikon pada tabel.
- **Path:line:** `src/pages/pos/POSTransferStokPage.tsx:551–553`.
- **Evidence:** Tombol berukuran ikon hanya berisi `Trash2`, tanpa teks, `aria-label`, atau `title`, dan memanggil `removeItem(idx)`.
- **Dampak:** Pembaca layar tidak dapat mengidentifikasi item yang dihapus di antara beberapa baris.
- **Rekomendasi:** Tambahkan label seperti “Hapus {nama produk} dari transfer” dan pastikan target sentuh memadai.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### L-03 — Disclosure alamat tersimpan tidak mengekspos expanded state
- **Jenis overlay/kontrol:** disclosure/picker alamat.
- **Path:line:** `src/components/checkout/CheckoutAddressForm.tsx:485–495`.
- **Evidence:** Tombol mengubah `showSavedAddresses` tanpa `aria-expanded` atau `aria-controls`.
- **Dampak:** Pembaca layar tidak diberi tahu apakah daftar terbuka atau konten yang dikendalikan.
- **Rekomendasi:** Tambahkan `aria-expanded` dan `aria-controls` yang menunjuk ID container daftar.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### L-04 — Grup alasan RadioGroup pembatalan tidak dinamai programatis
- **Jenis overlay:** grup pilihan dalam dialog.
- **Path:line:** `src/components/order/OrderCancelDialog.tsx:97–98`.
- **Evidence:** Label “Alasan Pembatalan” tidak dihubungkan dengan RadioGroup melalui `htmlFor`, `aria-labelledby`, atau `aria-label`.
- **Dampak:** Label pilihan individual ada, tetapi konteks pertanyaan grup dapat tidak diumumkan.
- **Rekomendasi:** Beri ID pada label dan gunakan `aria-labelledby`, atau struktur fieldset/legend setara.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### L-05 — State pilihan topping hanya ditunjukkan secara visual
- **Jenis overlay/kontrol:** toggle topping.
- **Path:line:** `src/pages/ProductDetail.tsx:429–443`.
- **Evidence:** Pilihan mengubah kelas border/background tanpa mengekspos `aria-pressed` atau state checked.
- **Dampak:** Pengguna nonvisual tidak mengetahui apakah topping terpilih.
- **Rekomendasi:** Gunakan `aria-pressed={Boolean(selected)}` atau checkbox berlabel.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

### L-06 — Pilihan filter explore tidak mengekspos state terpilih
- **Jenis overlay/kontrol:** tombol toggle filter.
- **Path:line:** `src/components/explore/FilterSheet.tsx:140–209`.
- **Evidence:** Pilihan price, district, rating dibedakan melalui styling tanpa `aria-pressed`/checked.
- **Dampak:** Teknologi bantu tidak mengumumkan filter aktif.
- **Rekomendasi:** Ekspos state dengan `aria-pressed` atau semantik checkbox/radio; umumkan hitungan aktif.
- **Klasifikasi:** Bug statis terkonfirmasi.
- **Confidence:** Tinggi.

## Cakupan, strengths, dan limitations

| Area audit dari sumber | File dilaporkan ditinjau | Catatan cakupan |
|---|---:|---|
| Primitive UI bersama/integrasi overlay global | 17 | 13 TSX, `package.json`, `index.css`, `App.css`, `tailwind.config.ts`; dist Radix dibaca sebagai bukti pendukung dan tidak dihitung. |
| Admin | 84 | 74 memuat istilah/pola terkait; 59 memuat overlay/select JSX yang terdeteksi. |
| Merchant/POS | 145 | Seluruh file pada empat direktori yang disebut dalam hasil. |
| Publik/pembeli/akun/checkout/order/explore/notifikasi | 35 | Pemeriksaan penuh atau targeted line ranges dan pencarian pola; subdirektori admin/merchant/desa/courier/POS dikecualikan. |
| Desa/kurir | 41 | Semua file pada empat direktori yang disebut dipindai. |
| **Jumlah hitungan area** | **322** | Penjumlahan cakupan area, bukan klaim 322 file unik; metode dan area bisa berbeda/bertumpang tindih. |

**Strengths yang dicatat sumber:** wrapper Radix yang ditinjau meneruskan ref/tipe primitive atau memakai primitive langsung; komponen Dialog/AlertDialog/Popover/DropdownMenu/Select umumnya memanfaatkan pola keyboard, fokus, dismissal, portal, dan positioning Radix. Dialog biasa memiliki overlay dan tombol close dengan teks `sr-only`; komponen Title/Description tersedia. `App.tsx` memasang `TooltipProvider` global dan Toaster/Sonner di provider aplikasi. Banyak pilihan menu/select memakai primitive bersama; beberapa alur destruktif sudah memakai AlertDialog dengan title, deskripsi, dan Batal. Select membatasi tinggi daftar dan popover/menu/select memakai positioning primitive. Sejumlah form menghubungkan label/error; beberapa dialog kasir/checkout membatasi tinggi dan mengelola scroll; drawer mobile merchant dilaporkan memiliki modal semantics, keyboard handling, scroll lock, dan focus restoration.

**Limitations:** Audit sumber tidak menjalankan browser/device matrix, axe, keyboard/switch langsung, atau pembaca layar. Focus trap/restore, Escape, nested overlay, clipping layar kecil, dan dismissal saat proses asynchronous belum diuji manual; risiko tersebut diberi klasifikasi dan confidence yang sesuai. Angka file berasal dari metodologi sumber yang beragam (pemeriksaan penuh/targeted, pencarian, atau cakupan direktori), jadi bukan jaminan inspeksi baris demi baris atas file unik. Temuan pola dari contoh tidak membuktikan semua instance sejenis di seluruh aplikasi telah diuji. Perbaikan kode setelah audit diuji dengan tes terpilih, ESLint, dan build produksi; hasil itu bukan pengganti uji browser manual.

## Rencana perbaikan berdasar risiko

1. **P0 — Cegah kehilangan data dan status salah:** tambahkan konfirmasi pada hapus foto galeri dan brand POS serta keputusan keanggotaan/booking; validasi input COD kosong. Pastikan identitas objek/konsekuensi jelas, Batal tersedia, loading mencegah pengiriman ganda, dan hasil/error benar.
2. **P1 — Pulihkan operasi keyboard/modal:** ganti FilterSheet custom dengan Dialog/Sheet bersama; jadikan kartu alamat kontrol native; jadikan baris notifikasi link/button. Perbaiki combobox kode, alternatif keyboard pemilih peta, sort popup, dan overlay custom merchant/header.
3. **P1 — Nama, label, dan state aksesibel:** prioritaskan nama tombol ikon, hubungan label Select/form, nama ImageLightbox dan tombol kontrolnya, disclosure `aria-expanded`, serta state topping/filter/galeri. Verifikasi nama/state pada accessibility tree.
4. **P2 — Jangkauan viewport dan proses asynchronous:** uji held bills, refund, dan dialog event di layar ponsel pendek, landscape, zoom, konten panjang. Uji focus trap/restore/Escape header search dan ImageLightbox serta dismissal DeliveryProof ketika upload/RPC berlangsung.
5. **P3 — Konsistensi UX:** pertimbangkan mengganti prompt/confirm native yang berbeda-beda dengan dialog aplikasi untuk alur suspend/cancel; ini rekomendasi konsistensi, bukan klaim native prompt sebagai bug.
6. **Verifikasi:** setelah perbaikan, lakukan keyboard-only, pembaca layar, pemeriksaan state/nama, serta viewport matrix di browser. Pemeriksaan otomatis dapat melengkapi, bukan menggantikan, pengujian manual.

## Gagal / blocker

**Gagal: []** — tidak ada kegagalan atau blocker dalam hasil terstruktur yang diberikan.

## Tindak lanjut implementasi setelah audit

Perbaikan berikut diterapkan pada temuan prioritas. Dari **42 isu unik** pada audit awal, 13 temuan telah ditangani melalui tindak lanjut; **29 temuan masih terbuka** dan memerlukan perubahan/pengujian lanjutan.

| Temuan | Tindak lanjut | Verifikasi |
|---|---|---|
| H-03, L-06 — filter sheet | Mengganti overlay pointer-only dengan `Dialog` Radix bernama, deskripsi tersembunyi, fokus/dismiss standar, tombol tutup bersama; mempertahankan sheet responsif, menambah `aria-pressed` pada opsi dan sinkronisasi nilai saat dibuka. | Tes modal, state pilihan, dan Escape lulus. |
| H-07 — rekonsiliasi COD | Menolak input kosong/whitespace sebelum konversi angka dan menolak nilai tidak valid/negatif dengan pesan error, sehingga string kosong tidak berubah menjadi nol. | ESLint dan build lulus; belum ada tes unit khusus validasi COD. |
| H-01, M-13 — Merchant Gallery | Preview custom diganti dengan Dialog bernama, dismissal Escape/backdrop dan focus management; thumbnail menjadi tombol berlabel. Hapus foto kini memakai AlertDialog, menunjukkan foto terpilih, mencegah klik ganda, dan memulihkan fokus/fallback setelah penghapusan. | ESLint dan build lulus; belum ada tes komponen khusus alur galeri. |
| H-02 — brand POS | Tombol hapus diberi nama/target 32×32 px dan konfirmasi menyebut brand; proses menunggu, error dilaporkan, dan fokus dipulihkan ke pemicu atau tombol Tambah Brand. | ESLint dan build lulus; belum ada tes komponen khusus alur brand. |
| H-04, M-18 — AddressCard | Pemilih alamat menjadi tombol native dengan `aria-pressed`; pemicu menu aksi mendapat nama berdasarkan label dan penerima. | Dua tes AddressCard lulus untuk callback, state terpilih, dan nama pemicu. |
| H-05, M-20 — notifikasi | Aksi utama menjadi tombol fokusabel; hapus dipisahkan sebagai tombol bernama sehingga tidak ada interaksi bersarang. | ESLint dan build lulus; belum ada tes komponen halaman notifikasi. |
| H-06 — keanggotaan/booking desa | Keputusan verifikasi/penolakan dan perubahan status booking kini meminta konfirmasi berisi objek serta status tujuan; operasi memeriksa error, mempertahankan dialog saat gagal, dan mengunci aksi saat proses. | ESLint dan build lulus; belum ada tes komponen khusus alur status desa. |
| M-01–M-03 — ImageLightbox bersama | Menambahkan judul dan deskripsi dialog, nama kontrol close/navigasi/zoom/thumbnail, pemicu gambar yang fokusabel bernama, serta pemulihan fokus melalui ref pemicu. Menghindari tombol tutup duplikat pada wrapper dialog. | Tes nama dialog/kontrol dan pemulihan fokus lulus. |
| Dialog bersama | Tombol tutup seluruh dialog diperbesar menjadi target 32×32 px, fokus terlihat, dan nama aksesibel dilokalkan ke “Tutup dialog”. | Dicakup tes label pada filter modal; build dan lint lulus. |

**Verifikasi tindak lanjut terbaru:** 12 tes terpilih pada 5 berkas tes lulus; ESLint pada seluruh berkas kode yang berubah, `git diff --check`, dan build produksi lulus. Tidak ada pengujian manual browser, screen reader, atau viewport matrix dalam sesi ini.
