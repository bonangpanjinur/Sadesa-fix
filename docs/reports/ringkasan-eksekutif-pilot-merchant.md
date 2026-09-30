# Ringkasan Eksekutif Persiapan Pilot Merchant SaDesa

**Tanggal status:** 8 September 2026  
**Ruang lingkup:** pilot terbatas 10–20 usaha  
**Status keputusan:** **Belum siap mulai pilot eksternal; siap masuk tahap persiapan staging dan instrumentasi pilot.**

## Ringkasan keputusan

SaDesa memiliki fondasi repository yang cukup untuk memulai validasi operasional, tetapi belum memiliki evidence staging dan data pilot yang diperlukan untuk menjalankan pilot merchant secara bertanggung jawab. Pilot tetap disetujui sebagai tujuan berikutnya, bukan sebagai aktivitas yang langsung dimulai di production.

Pilot harus berfungsi sebagai **uji kesiapan operasional**, bukan peluncuran komersial. Fokusnya adalah membuktikan bahwa marketplace gratis, POS berbayar dengan trial terbatas, katalog lintas kanal, stok per outlet, POS offline, QR meja, laporan, dan entitlement dapat berjalan tanpa duplikasi transaksi, kebocoran data tenant, saldo yang tidak dapat direkonsiliasi, atau gangguan terhadap marketplace ketika POS ditangguhkan.

Keputusan operasionalnya adalah menahan iklan berbayar, rollout luas, fee provider, payout otomatis, dan klaim laporan resmi sampai gate staging dan pilot terpenuhi. Kategori pilot dibatasi pada barang retail, makanan/minuman, dan jasa terjadwal. Jasa panggilan, sewa, wisata, dan ojek tetap menjadi kategori observasi atau feature flag sampai kontrak booking, kapasitas, dispute, payout, dan settlement tervalidasi.

## Status kesiapan saat ini

| Area | Evidence yang tersedia | Penilaian kesiapan |
|---|---|---|
| Kualitas repository | 161 test lulus, 20 test skipped, 46 test files lulus; production build lulus; lint lulus tanpa error | **Siap untuk persiapan staging** |
| Database dan deployment bundle | 28 deployment SQL tervalidasi; 213 migration dalam 28 bundle tervalidasi | **Siap diterapkan ke staging** |
| Keamanan data | Static RLS audit lulus dan tidak menemukan tabel tanpa RLS/policy dalam pemeriksaan repository | **Perlu verifikasi runtime di staging** |
| Dependency | Audit tidak lagi melaporkan advisory high/critical; tersisa satu advisory low pada `esbuild` dan satu moderate pada `@humanfs/node` | **Dapat dipakai untuk staging dengan mitigasi; belum bersih total** |
| POS online/offline | Kontrak recovery, queue, lease, conflict, dan checkpoint telah diuji secara unit | **Belum siap dibuktikan pada perangkat fisik** |
| Laporan dan rekonsiliasi | Kontrak laporan canonical, jurnal, hutang/piutang, dan snapshot rekonsiliasi tersedia di repository | **Belum lulus rekonsiliasi staging** |
| Fee dan monetisasi | Fee engine dan finance admin terpusat tersedia; ledger fee/payment production belum tersedia | **Jangan aktifkan fee provider atau payout otomatis** |
| API security smoke test | Script tersedia, tetapi `SUPABASE_TEST_URL` belum tersedia pada environment pemeriksaan | **Gate terbuka** |
| Pilot merchant | Belum ada data pilot 10–20 merchant | **Belum dimulai** |

> **Kesimpulan readiness:** repository berada pada tahap *engineering-ready for staging*, bukan *pilot-ready for external merchants*.

## Tujuan dan pertanyaan pilot

Pilot harus menjawab lima pertanyaan utama. Pertama, apakah merchant marketplace-only dapat membuat produk, menerima order, menyelesaikan fulfillment, dan menangani refund atau dispute tanpa membuat tenant POS. Kedua, apakah merchant yang mengaktifkan POS dapat memakai katalog yang sama tanpa produk, order, atau histori ganda. Ketiga, apakah kasir dapat menyelesaikan transaksi saat offline dan kemudian melakukan sinkronisasi tanpa duplikasi atau kehilangan transaksi. Keempat, apakah merchant dapat memahami perbedaan antara saldo kas, stok outlet, transaksi yang tersinkron, dan transaksi yang masih tertunda. Kelima, apakah support/admin dapat menangani konflik, suspend POS, refund, QR meja, dan rekonsiliasi tanpa mengedit histori transaksi secara langsung.

Pilot **tidak** digunakan untuk menguji perluasan kategori sebanyak mungkin, mengoptimalkan akuisisi massal, menjual paket berbayar secara agresif, atau mengaktifkan payout dan fee provider sebelum ledger production tersedia.

## Komposisi merchant pilot

Target pilot adalah 10–20 merchant. Komposisi minimum yang direkomendasikan adalah sebagai berikut.

| Kelompok | Target | Contoh | Fokus validasi |
|---|---:|---|---|
| Barang retail | 4–6 | kelontong, oleh-oleh, pakaian, kerajinan | katalog, SKU/varian, stok outlet, pickup/kirim, POS kasir |
| Makanan/minuman | 4–6 | warung, kafe, katering, minuman | modifier, kesiapan produksi, pickup/delivery, QR meja bila tersedia |
| Jasa terjadwal | 2–4 | barbershop, pijat, fotografer, servis terjadwal | slot, durasi, pembatalan, provider, bukti selesai |
| Merchant marketplace-only | minimal 2 | usaha yang belum mengaktifkan POS | pemisahan marketplace dan POS, order, fulfillment, refund, dispute |

Satu merchant dapat memenuhi lebih dari satu karakteristik, tetapi minimal dua merchant harus tetap berada pada mode marketplace-only agar asumsi “POS bukan syarat marketplace” diuji secara nyata. Pilot tidak boleh memilih seluruh merchant dari satu desa, satu perangkat, atau satu tipe koneksi internet karena hal tersebut akan menyamarkan risiko operasional.

## Gate sebelum merchant diundang

Pilot eksternal hanya boleh dimulai setelah seluruh gate berikut memiliki evidence dan owner.

| Gate | Kriteria lulus | Evidence minimum |
|---|---|---|
| Staging deployment | Bundle Fase 2–5 diterapkan tanpa error dan dapat di-rollback | log deployment, checksum/bundle version, rollback note |
| Environment security | URL staging, publishable key, dan secret backend tervalidasi; tidak ada secret server-only di `VITE_*` | hasil `check-production-env`, konfigurasi secret manager |
| API security | Endpoint edge function menolak request tanpa token, token invalid, dan origin tidak diizinkan | hasil `security-api-smoke.sh` dengan `SUPABASE_TEST_URL` |
| Tenant isolation | Merchant/user/outlet tidak dapat membaca atau memutasi data tenant lain | hasil RLS runtime test dan negative test |
| POS offline | Transaksi offline memiliki request key, dapat dipulihkan setelah refresh/restart, dan tidak terduplikasi | log device test, queue state, reconciliation result |
| Stock integrity | Stock projection, reservasi, fulfillment, dan adjustment dapat direkonsiliasi | baseline report sebelum/sesudah test |
| Finance integrity | Kas, jurnal, hutang/piutang, fee snapshot, dan laporan canonical konsisten | snapshot laporan dan rekonsiliasi harian |
| Marketplace independence | Marketplace-only tetap menerima order; suspend POS tidak menutup toko publik | skenario test dan screenshot/log status |
| Support readiness | Ada owner, SLA, escalation path, rollback, dan incident template | runbook support dan simulasi insiden |

## Rencana pelaksanaan

### Tahap 1 — Persiapan staging

Tim engineering menerapkan bundle database ke staging, menjalankan test suite, build, lint, RLS audit runtime, API security smoke test, dan baseline report. Data uji harus mencakup merchant marketplace-only, merchant dengan satu outlet, merchant multi-outlet, kasir, produk dengan varian, order marketplace, transaksi POS, QR meja, refund, dan konflik offline.

### Tahap 2 — Onboarding terkendali

Setiap merchant menerima checklist setup yang sama. Merchant harus menyelesaikan profil usaha, minimal tiga produk atau layanan, harga, jam operasional, fulfillment, outlet, pengguna kasir bila diperlukan, dan simulasi satu order. Aktivasi pilot tidak dihitung dari pembuatan akun saja. Aktivasi dihitung setelah merchant menerbitkan listing, menerima order pertama, menyelesaikan fulfillment pertama, dan—untuk merchant POS—menyelesaikan transaksi POS pertama.

### Tahap 3 — Operasi terpantau

Pilot dijalankan dengan support prioritas dan observability aktif. Admin memantau order gagal, stok stale, queue conflict, transaksi yang tertunda, refund, dispute, QR meja, dan perubahan entitlement. Setiap insiden harus memiliki timestamp, merchant, tenant/outlet, request key atau order ID, dampak, tindakan pemulihan, dan status rekonsiliasi.

### Tahap 4 — Review dan keputusan rollout

Setelah periode observasi yang disepakati, tim membandingkan metrik terhadap kriteria keluar. Keputusan dapat berupa lanjut ke gelombang berikutnya, perpanjang pilot dengan scope yang sama, batasi fitur tertentu, atau hentikan sementara pilot. Penambahan kategori bukan keputusan default; kategori hanya dibuka bila alur order, fulfillment, dispute, settlement, dan unit economics-nya memiliki evidence.

## Metrik keberhasilan

| Dimensi | Metrik | Cara membaca |
|---|---|---|
| Aktivasi | persentase merchant yang menerbitkan listing, menerima order pertama, dan menyelesaikan fulfillment pertama | mengukur nilai awal, bukan sekadar signup |
| POS | persentase merchant POS yang menyelesaikan setup dan transaksi POS pertama | mengukur activation-to-value |
| Reliabilitas | sync success rate, jumlah conflict, jumlah dead-letter, dan waktu pemulihan | mengukur ketahanan offline dan integrasi |
| Integritas | transaksi duplikat, order tanpa stok, saldo tidak seimbang, dan selisih rekonsiliasi | target duplikasi dan selisih material adalah nol |
| Operasional | waktu penyelesaian tiket, refund, dispute, dan insiden | mengukur kesiapan support/admin |
| Produk | merchant aktif mingguan, order selesai, repeat order, dan penggunaan fitur POS | mengukur manfaat nyata |
| Risiko | false positive, abuse flag, kegagalan payout, dan suspend yang salah | menjaga agar kontrol tidak merusak operasi |
| Ekonomi | GMV, biaya support per merchant, biaya infrastruktur, dan indikasi willingness-to-pay | menjadi input keputusan monetisasi, bukan klaim pendapatan |

Metrik harus dicatat per merchant, kategori, kanal, tenant, outlet, dan periode. Angka agregat tidak cukup untuk menemukan konflik tenant, outlet, atau perangkat tertentu.

## Kriteria penghentian sementara

Pilot harus dihentikan sementara bila ditemukan kebocoran data antar-tenant, transaksi offline terduplikasi, stok negatif yang tidak dapat dijelaskan, saldo atau jurnal yang tidak dapat direkonsiliasi, payout yang dilepas sebelum aturan fulfillment, refund tanpa audit, QR meja yang dapat mengakses outlet lain, atau insiden keamanan yang belum memiliki containment. Pilot juga harus dihentikan bila support tidak mampu merespons insiden sesuai SLA atau rollback tidak dapat dilakukan dengan aman.

Merchant tidak boleh dikenai fee provider, dipotong payout otomatis, atau diarahkan untuk memperlakukan laporan estimasi sebagai laporan resmi selama ledger dan rekonsiliasi production belum lulus.

## Keputusan yang diminta dari pimpinan

Pimpinan perlu menyetujui empat hal. Pertama, menyetujui pilot terbatas 10–20 merchant dengan scope kategori retail, makanan/minuman, dan jasa terjadwal. Kedua, menyetujui bahwa staging deployment, API security, RLS runtime, offline device test, dan rekonsiliasi adalah gate wajib sebelum merchant eksternal masuk. Ketiga, menyetujui penundaan fee provider, payout otomatis, perluasan kategori, dan iklan berbayar sampai hasil pilot tersedia. Keempat, menunjuk owner accountable untuk engineering, product, operations/support, finance/reconciliation, dan security.

## Kesimpulan eksekutif

SaDesa tidak perlu menambah banyak fitur sebelum pilot. Prioritas saat ini adalah membuktikan integritas dan pemulihan pada environment staging serta perangkat nyata. Dengan scope pilot yang sempit, merchant yang beragam, metrik yang terukur, dan kriteria penghentian yang tegas, SaDesa dapat memperoleh evidence yang cukup untuk memutuskan apakah produk siap diperluas tanpa mengorbankan kepercayaan merchant, ketepatan stok, atau integritas keuangan.

## Referensi

[1]: ../plans/rencana-bisnis-marketplace-pos-umkm.md "Rencana bisnis marketplace POS UMKM SaDesa"
[2]: ../../src/lib/feeEngine.ts "Fee engine SaDesa"
[3]: ../../scripts/audit-rls-static.py "Static RLS audit SaDesa"
[4]: ../../scripts/security-api-smoke.sh "API security smoke test SaDesa"
