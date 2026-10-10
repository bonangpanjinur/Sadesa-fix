# Audit Repository dan Rencana Implementasi Google Maps untuk PWA SaDesa

**Tanggal audit:** 11 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Branch saat audit:** `main`  
**Metode:** inspeksi statis source code, konfigurasi, dependency, struktur data, dan titik pemakaian peta. Audit ini belum mencakup pengukuran trafik produksi, billing Google Cloud, atau pengujian E2E terhadap domain produksi.

## 1. Ringkasan eksekutif

SaDesa adalah **Vite + React + TypeScript SPA/PWA** dengan Supabase sebagai database, auth, storage, realtime, dan Edge Functions. Repository sudah memiliki fondasi Google Maps, tetapi provider peta saat ini masih campuran:

- **Google Maps:** sudah dipakai sebagian pada flow transport/ride.
- **Leaflet + tile OpenStreetMap:** masih dipakai pada checkout, lokasi merchant, lokasi admin, katalog merchant, desa wisata, tracking order, dan tracking kurir.
- **Nominatim:** masih dipakai langsung dari browser untuk forward geocoding, reverse geocoding, dan autocomplete.
- **OSRM public:** masih dipakai langsung dari browser untuk rute kendaraan dan jarak pengiriman.

Kesimpulan utama:

> Migrasi ke Google Maps tidak dimulai dari nol. Loader, API key environment, input autocomplete, dan satu komponen peta Google sudah ada. Pekerjaan utama adalah menyatukan adapter provider, memindahkan request server-side yang sensitif/berbiaya, mengganti titik peta Leaflet secara bertahap, dan menambahkan pengendalian biaya serta pengujian.

## 2. Temuan audit repository

### 2.1 Stack dan arsitektur

| Area | Temuan |
|---|---|
| Frontend | Vite, React 18, TypeScript, React Router, Tailwind/shadcn |
| PWA | `vite-plugin-pwa` dengan `injectManifest`; route chunks dimuat lazy/on demand |
| Backend | Tidak ada Node/Express application server untuk request aplikasi; Supabase Edge Functions menjadi jalur backend |
| Data/Auth | Supabase client, RLS, realtime, storage, dan RPC |
| Map library | `leaflet`, `react-leaflet`, `@types/leaflet` masih menjadi dependency utama di banyak komponen |
| Google Maps | `@googlemaps/js-api-loader` sudah terpasang; type `@types/google.maps` juga tersedia |
| Environment | `VITE_GOOGLE_MAPS_API_KEY` sudah ada di `.env.example` |
| Deployment | SPA dibuild dan dilayani sebagai static output; secret server tidak boleh dimasukkan ke `VITE_*` |

### 2.2 Fondasi Google Maps yang sudah ada

#### Loader

File: `src/lib/googleMaps.ts`

Saat ini loader:

- memakai `@googlemaps/js-api-loader`;
- membaca `VITE_GOOGLE_MAPS_API_KEY`;
- memuat library `maps` dan `places`;
- memakai singleton promise agar loader tidak dipanggil berulang kali.

Hal yang perlu diperbaiki:

- API version dan library perlu dikelola terpusat melalui adapter.
- Error perlu dikategorikan menjadi `missing_key`, `api_disabled`, `billing`, `quota`, dan `network` agar UI serta observability dapat membedakannya.
- Loader perlu diuji pada PWA cold start, offline, dan instalasi standalone.
- Untuk komponen baru, hindari menambahkan loader Google secara terpisah.

#### Input alamat

File: `src/components/transport/GoogleAddressInput.tsx`

Sudah memakai Places Autocomplete dengan pembatasan negara Indonesia dan mengambil `formatted_address`, `geometry`, serta `name`.

Risiko/gap:

- Belum terlihat session token yang dikelola eksplisit untuk sesi autocomplete.
- Komponen hanya digunakan pada flow tertentu, belum menjadi input alamat bersama untuk checkout, merchant, admin, dan profil.
- Tidak ada telemetri provider atau penghitung usage di level aplikasi.
- Fallback menjadi text input, tetapi belum ada alur standar untuk memilih titik di peta ketika autocomplete gagal.

#### Peta ride

File: `src/components/transport/GoogleRideMap.tsx`

Sudah menyediakan:

- Google Maps map instance;
- marker pickup, tujuan, dan driver;
- polyline route;
- fit bounds;
- click map untuk memilih koordinat;
- fallback ke React Leaflet + tile OpenStreetMap ketika Google gagal atau API key tidak tersedia.

Risiko/gap:

- Nama komponen menunjukkan Google, tetapi implementasinya juga memuat Leaflet dan fallback OSM sehingga provider belum terabstraksi.
- Menggunakan `google.maps.Marker` legacy; perlu diputuskan migrasi ke marker modern atau adapter kompatibilitas.
- Marker dan polyline dibersihkan/dibuat ulang saat dependency berubah; perlu diuji agar tidak memicu remount/map load berlebihan.
- Rute diberikan dari service OSRM, bukan dari Google Routes API.
- Belum ada standar untuk attribution, consent/location privacy, quota, dan billing error.

### 2.3 Titik peta yang masih memakai Leaflet/OSM

| Fitur | File/titik | Kondisi saat ini | Rencana |
|---|---|---|---|
| Checkout pilih lokasi | `src/components/checkout/LocationPicker.tsx` | Leaflet; klik peta; GPS; memanggil OSRM untuk jarak | Prioritas P0; ganti renderer ke Google, pertahankan kontrak koordinat |
| Lokasi merchant | `src/components/merchant/MerchantLocationPicker.tsx` | Leaflet | Ganti ke shared `GoogleLocationPicker` |
| Lokasi admin merchant/desa | `src/components/admin/AdminLocationPicker.tsx`, dialog merchant/village | Leaflet | Ganti ke shared picker dan reverse geocode terkontrol |
| Katalog toko/produk | `src/components/product/ProductMerchantMap.tsx`, `ProductsPage.tsx` | Leaflet; marker merchant dan posisi user | Ganti ke Google map dengan lazy loading dan marker clustering bila diperlukan |
| Tracking order | `src/components/CourierMap.tsx`, `OrderTrackingPage.tsx` | Leaflet; realtime courier location; OSRM route | Ganti renderer; realtime tetap dari Supabase |
| Tracking ride | `src/pages/ride/RideTrackingPage.tsx`, `CourierMap.tsx` | Leaflet | Satukan dengan map adapter tracking |
| Rute kurir | `src/components/courier/CourierRideRouteMap.tsx`, `CourierRidesPage.tsx` | Leaflet + route OSRM | Google map + Routes API server-side |
| Penugasan kurir | `src/components/merchant/CourierMapSelector.tsx`, `CourierAssignDialog.tsx` | Leaflet + OSRM | Google map + shared route client |
| Peta desa wisata | `src/components/village/TourismMap.tsx`, `src/pages/VillageDetailPage.tsx` | Leaflet | Ganti jika Google dipilih sebagai provider utama |
| Peta desa admin | `src/pages/desa/DesaPetaPage.tsx` | Leaflet | Ganti pada fase katalog/admin |
| Peta lokasi detail admin | `src/pages/admin/AdminMerchantDetailPage.tsx`, `AdminUserGeographyPage.tsx` | Leaflet | Ganti setelah komponen inti stabil |
| Navigasi eksternal kurir | `src/components/courier/NavigationButton.tsx` | Membuka Google Maps/OSM melalui URL | Tetap boleh; ini bukan Google Maps API load internal |
| URL lokasi profil | `src/components/account/ProfileEditor.tsx` | Menyimpan URL Google Maps dari koordinat | Tetap dipertahankan; validasi dan format perlu distandardisasi |

### 2.4 Geocoding dan routing saat ini

#### Geocoding

File: `src/hooks/useGeocoding.ts`

Saat ini Nominatim dipanggil langsung dari browser dengan:

- interval minimal 1,1 detik;
- cache in-memory;
- deduplikasi in-flight request;
- cooldown saat HTTP 429/network failure;
- forward geocoding;
- reverse geocoding;
- autocomplete lima hasil.

Masalah operasional:

- cache hilang saat reload/PWA restart;
- request langsung dari browser bergantung pada layanan public;
- tidak cocok sebagai fondasi geocoding produksi berskala besar;
- mapping nama wilayah Indonesia dapat berbeda antar-provider;
- belum ada rekonsiliasi hasil geocoding dengan data wilayah administratif dari database.

#### Routing

File: `src/lib/routeCalculation.ts`

Saat ini memakai `https://router.project-osrm.org` langsung dari browser. Sudah memiliki:

- validasi rentang koordinat;
- haversine fallback;
- abort signal;
- fallback ke jarak garis lurus;
- konversi GeoJSON `[lng, lat]` ke format Leaflet `[lat, lng]`.

Masalah operasional:

- request routing public tidak berada di bawah kontrol quota SaDesa;
- tidak ada cache lintas pengguna/session;
- checkout dapat memanggil rute setiap perubahan pin;
- belum ada batas jarak, debounce, dan kebijakan kapan rute harus dihitung ulang;
- belum ada adapter provider sehingga migrasi ke Google akan menyentuh banyak caller.

### 2.5 Data koordinat yang sudah tersedia

Schema/bootstrap sudah memiliki koordinat untuk beberapa domain penting:

- `merchants.location_lat`, `merchants.location_lng`;
- `villages.location_lat`, `villages.location_lng`;
- `tourism.location_lat`, `tourism.location_lng`;
- lokasi pengiriman/order;
- lokasi/current position kurir.

Index lokasi juga sudah terlihat pada bootstrap untuk merchant, village, dan tourism. Ini berarti migrasi tidak memerlukan perubahan model data besar untuk tahap pertama.

#### Kebijakan lokasi pedagang

Untuk kualitas pengantaran dan pengendalian request geocoding, **pedagang wajib memperbarui alamat usaha dan menyimpan titik koordinat berdasarkan GPS perangkatnya**. Alamat teks saja tidak dianggap cukup untuk merchant aktif.

Aturan yang direncanakan:

- saat registrasi merchant, browser meminta izin lokasi dan pedagang menekan **Gunakan GPS**;
- koordinat GPS ditampilkan di peta agar pedagang dapat mengonfirmasi bahwa pin berada di lokasi usaha;
- alamat usaha wajib diperbarui/ditinjau sebelum merchant dapat diaktifkan atau menerima order;
- perubahan alamat wajib diikuti pengambilan koordinat GPS baru;
- koordinat tidak boleh diisi dengan angka perkiraan atau hasil geocoding saja sebagai jalur normal;
- jika permission GPS ditolak, akurasi tidak memadai, atau perangkat berada terlalu jauh dari titik usaha, proses disimpan sebagai belum terverifikasi dan merchant belum dapat diaktifkan;
- admin dapat melakukan koreksi/override melalui alur terotorisasi dengan alasan audit, bukan melalui edit diam-diam;
- pembeli tetap dapat melihat merchant yang belum lengkap hanya jika status produk/merchant memang diizinkan, tetapi checkout dan dispatch tidak boleh menganggap lokasinya valid;
- lokasi disimpan dengan waktu pembaruan, sumber, dan akurasi GPS bila browser menyediakannya.

Enforcement sebaiknya dilakukan di dua lapis:

1. **Frontend:** validasi UX, permission GPS, akurasi, marker confirmation, dan pesan tindakan yang jelas.
2. **Backend/RPC/RLS contract:** validasi `location_lat`, `location_lng`, dan status verifikasi sebelum aktivasi, publikasi storefront, atau menerima order. Validasi backend tidak boleh hanya bergantung pada React.

Data tambahan yang diperlukan untuk enforcement:

- `geocode_provider`;
- `geocoded_at`;
- `geocode_precision`;
- `location_accuracy_m`;
- `location_source` (`gps`, `admin_override`, atau `legacy`);
- `location_updated_at`;
- `location_verified_at`;
- `location_verification_status` (`pending`, `verified`, `rejected`);
- `route_provider`;
- `route_calculated_at`;
- cache route berdasarkan origin/destination/transport mode.

## 3. Gap dan risiko utama

### P0 — Harus diselesaikan sebelum production Google Maps

1. **API key browser belum dibatasi dalam repository/config contract.** Key di frontend memang dapat terlihat oleh pengguna, tetapi harus dibatasi berdasarkan domain dan API yang boleh dipakai.
2. **Tidak ada quota/budget guard di level operasional.** Google Cloud quota dan budget alert wajib disiapkan di luar source code.
3. **Provider belum konsisten.** Sebagian feature Google, sebagian Leaflet/OSM, sebagian Nominatim/OSRM.
4. **Routing dan geocoding masih dipanggil langsung dari browser.** Untuk Google Routes/Geocoding, gunakan Supabase Edge Functions agar secret server, cache, rate limit, dan audit lebih terkontrol.
5. **Belum ada test contract untuk map provider.** Banyak komponen mengandalkan Leaflet secara langsung sehingga migrasi berisiko regresi.
6. **Belum ada measurement penggunaan.** Tanpa metrik, estimasi biaya hanya asumsi.
7. **Belum ada enforcement bahwa lokasi merchant berasal dari GPS dan masih valid.** Koordinat merchant yang kosong atau lama dapat menyebabkan rute, jarak, dan dispatch tidak akurat.

### P1 — Penting untuk kualitas dan biaya

1. Debounce autocomplete dan session token.
2. Cache koordinat/alamat dan route.
3. Jangan menghitung rute setiap perubahan marker GPS.
4. Lazy-load Google Maps hanya pada route/fitur yang benar-benar menampilkan peta.
5. Pertahankan fallback UX jika Google gagal, tetapi jadikan provider fallback eksplisit dan terukur.
6. Validasi koordinat dan akurasi GPS sebelum menyimpan lokasi.
7. Uji PWA standalone, jaringan lambat, offline, permission GPS ditolak, dan API quota habis.

### P2 — Penyempurnaan tahap lanjutan

1. Marker clustering untuk katalog dengan banyak merchant.
2. Batched/virtualized marker updates untuk tracking banyak kurir.
3. Penyimpanan route cache server-side.
4. Dashboard penggunaan map per fitur dan estimasi biaya.
5. Penghapusan dependency Leaflet setelah seluruh consumer bermigrasi dan fallback tidak lagi diperlukan.

## 4. Arsitektur target yang disarankan

### 4.1 Prinsip

Gunakan Google Maps sebagai provider utama dengan kontrak internal yang tidak mengekspos detail provider ke seluruh komponen.

```text
React/PWA components
        |
        v
Map adapter + location contracts
        |
        +--> Google Maps JavaScript API (browser map rendering)
        |
        +--> Supabase Edge Function: geocode
        |
        +--> Supabase Edge Function: route
        |
        v
Supabase database/cache + Realtime
```

### 4.2 Kontrak internal yang disarankan

```ts
export type MapPoint = {
  lat: number;
  lng: number;
};

export type MapMarker = MapPoint & {
  id: string;
  label?: string;
  kind?: 'merchant' | 'courier' | 'pickup' | 'destination' | 'user' | 'tourism';
};

export type RoadRoute = {
  distanceKm: number;
  durationMinutes: number;
  geometry: MapPoint[];
  provider: 'google' | 'fallback';
};
```

Komponen bisnis hanya mengetahui `MapPoint`, `MapMarker`, dan `RoadRoute`; komponen tidak langsung mengimpor Leaflet atau memanggil OSRM.

### 4.3 Pembagian API key

#### Browser key

Environment:

```text
VITE_GOOGLE_MAPS_API_KEY
```

Pembatasan Google Cloud:

- application restriction: HTTP referrers/domain SaDesa dan staging;
- API restriction minimal: Maps JavaScript API dan Places API yang memang dipakai browser;
- pisahkan key production dan staging;
- jangan pernah memakai browser key untuk Routes/Geocoding server endpoint.

#### Server/Edge Function key

Simpan sebagai secret Supabase Edge Function, bukan `VITE_*`:

```text
GOOGLE_MAPS_SERVER_API_KEY
```

Pembatasan:

- API restriction hanya Geocoding API dan Routes API;
- tidak dikirim ke browser;
- request dilindungi auth/rate limit sesuai kebutuhan feature;
- hasil dapat dicache berdasarkan input yang sudah dinormalisasi.

### 4.4 Kontrak lokasi merchant

Status lokasi merchant harus diperlakukan sebagai bagian dari kesiapan operasional, bukan sekadar field opsional pada form.

```text
Merchant baru/edit alamat
        |
        v
Minta GPS perangkat
        |
        +--> permission ditolak / akurasi buruk -> status pending, belum aktif
        |
        v
Tampilkan pin + alamat + akurasi
        |
        +--> pedagang konfirmasi -> simpan koordinat dan timestamp
        |
        v
Status verified -> merchant boleh aktif/menerima order
```

Nilai `location_source` dan `location_verification_status` harus disimpan bersama perubahan lokasi. Untuk merchant existing yang belum memiliki koordinat, tampilkan banner/checklist wajib dan arahkan ke pengaturan lokasi; jangan melakukan geocoding massal otomatis karena akan menambah biaya dan belum tentu menghasilkan titik usaha yang benar.

## 5. Rencana implementasi bertahap

### Prinsip pengelolaan setting dari Admin

Seluruh **setting operasional peta dan integrasi** akan dikelola dari dashboard admin, sehingga perubahan provider atau perilaku peta tidak memerlukan perubahan source code untuk setiap perubahan kecil.

Namun, API key tidak boleh disimpan sebagai teks biasa di tabel konfigurasi yang dapat dibaca frontend. Pembagiannya:

| Jenis setting | Dikelola dari Admin | Penyimpanan yang disarankan |
|---|---:|---|
| Provider aktif (`google`, `osm`, `custom`) | Ya | `app_settings` dengan RLS admin |
| Provider fallback | Ya | `app_settings` |
| Aktif/nonaktif peta per fitur | Ya | `app_settings` atau feature flags |
| Negara, bahasa, default center/zoom | Ya | `app_settings` |
| Radius pengiriman maksimal | Ya | `app_settings` tervalidasi |
| Jarak minimum untuk hitung ulang rute | Ya | `app_settings` |
| Interval update marker kurir | Ya | `app_settings` |
| Cache TTL geocode/route | Ya | `app_settings` |
| Ambang akurasi GPS merchant | Ya | `app_settings` |
| Mode rute (`driving`, dan seterusnya) | Ya | `app_settings` dengan allowlist |
| API key browser | Ya melalui alur rotasi | Secret store/Edge Function secret, bukan plain text frontend |
| API key server Routes/Geocoding | Ya melalui alur rotasi | Secret store/Edge Function secret, bukan database biasa |
| Domain/referrer yang diizinkan | Tidak hanya dari UI | Google Cloud Console/IaC, dengan catatan di Admin |
| Billing account dan kartu | Tidak | Google Cloud Billing; tidak diekspos ke aplikasi |

#### Fitur Admin Map & Integration Settings

Menu baru yang direncanakan: **Admin → Pengaturan → Peta & Integrasi**.

Subbagian:

1. **Provider peta**
   - provider utama;
   - provider fallback;
   - status koneksi;
   - tombol uji koneksi;
   - fitur yang menggunakan provider tersebut.
2. **API dan credential status**
   - status key browser/server: configured, missing, expired/invalid, quota error;
   - tanggal rotasi terakhir;
   - tombol mulai rotasi key;
   - tidak menampilkan nilai secret penuh.
3. **Feature routing**
   - checkout map;
   - tracking order;
   - tracking ride;
   - lokasi merchant;
   - katalog merchant/desa wisata;
   - admin geography.
4. **Pengendalian biaya**
   - budget bulanan internal;
   - peringatan penggunaan 50/80/100 persen;
   - quota aplikasi;
   - batas request per user/fitur;
   - status cache dan hit ratio.
5. **Aturan lokasi merchant**
   - GPS wajib atau mode pilot;
   - ambang akurasi GPS;
   - toleransi jarak konfirmasi;
   - status merchant lama yang belum memperbarui lokasi;
   - apakah merchant pending boleh menerima order.
6. **Cache dan performa**
   - TTL geocode;
   - TTL route;
   - threshold perubahan lokasi untuk recalculate;
   - minimum interval update courier marker;
   - maksimal marker pada satu map.
7. **Audit log**
   - siapa mengubah setting;
   - setting sebelum/sesudah;
   - waktu perubahan;
   - alasan perubahan;
   - hasil uji koneksi setelah perubahan.

#### Aturan keamanan penggantian API key

Admin dapat memulai rotasi API key dari dashboard, tetapi browser tidak boleh menerima secret baru melalui konfigurasi publik. Alur yang direncanakan:

```text
Admin membuka Pengaturan Peta
        |
        v
Admin mengirim key baru melalui form HTTPS terlindungi
        |
        v
Edge Function terautentikasi menyimpan ke secret store
        |
        v
Edge Function menguji provider/key secara terbatas
        |
        +--> gagal: key lama tetap aktif, audit failure
        |
        v
Aktifkan versi key baru + catat audit + invalidasi cache konfigurasi
```

Ketentuan penting:

- nilai key tidak pernah ditulis ke log, response, atau tabel konfigurasi biasa;
- input key hanya dikirim melalui HTTPS dan Edge Function admin-only;
- rotasi harus mendukung rollback ke versi key sebelumnya;
- konfigurasi frontend hanya menerima status/versi/feature flag, bukan server secret;
- perubahan provider penting harus membuat audit log dan dapat memerlukan konfirmasi dua langkah;
- Google Cloud Console tetap menjadi tempat authoritative untuk billing, domain restriction, dan API restriction;
- dashboard admin hanya mengelola integrasi aplikasi dan memvalidasi statusnya.

#### Struktur konfigurasi yang disarankan

```ts
type MapRuntimeConfig = {
  primaryProvider: 'google' | 'osm' | 'custom';
  fallbackProvider: 'google' | 'osm' | 'none';
  features: {
    checkout: boolean;
    orderTracking: boolean;
    rideTracking: boolean;
    merchantLocation: boolean;
    catalog: boolean;
    tourism: boolean;
    adminGeography: boolean;
  };
  country: 'id';
  language: 'id' | 'en';
  routeMode: 'driving';
  geocodeCacheTtlHours: number;
  routeCacheTtlMinutes: number;
  routeRecalculateAfterMeters: number;
  courierMarkerMinIntervalSeconds: number;
  merchantGpsAccuracyMaxMeters: number;
  merchantLocationRequired: boolean;
  internalMonthlyBudgetUsd: number;
};
```

Semua nilai harus divalidasi dengan schema allowlist dan batas min/max. Admin tidak boleh dapat memasukkan URL provider arbitrary atau mode API yang tidak diizinkan tanpa proses review.

### Roadmap pengerjaan end-to-end

| Tahap | Fokus | Hasil wajib | Gate sebelum lanjut |
|---|---|---|---|
| 0 | Keputusan produk dan baseline | provider target, fallback, budget, domain, kebijakan GPS | scope disetujui |
| 1 | Google Cloud dan secret management | API aktif, key restriction, quota, budget alert, rotasi aman | key test lulus |
| 2 | Data contract dan Admin Settings | config schema, RLS, audit log, UI setting dasar | config read/write + audit lulus |
| 3 | Map adapter dan loader | satu kontrak map, lazy loader, error taxonomy | unit/component test lulus |
| 4 | Merchant GPS wajib | onboarding/edit alamat, verifikasi GPS, status pending/verified | backend enforcement lulus |
| 5 | Geocoding/autocomplete | shared input, Edge Function, cache, session token | checkout/address E2E lulus |
| 6 | Checkout dan jarak | Google map picker, route adapter, fallback | transaksi staging lulus |
| 7 | Merchant/admin master location | semua picker memakai shared adapter | CRUD + RLS lulus |
| 8 | Tracking order/kurir/ride | marker realtime, rute hemat, reconnect | tracking E2E lulus |
| 9 | Katalog/desa wisata/admin geography | seluruh map consumer non-transaksi | visual/performance lulus |
| 10 | Cost dashboard dan rollout | usage per SKU/fitur, canary, runbook | budget guard lulus |
| 11 | Cleanup dan production hardening | hapus direct OSRM/Nominatim/Leaflet sesuai keputusan | full quality gate lulus |

### Fase 0 — Persiapan Google Cloud dan baseline

**Tujuan:** memastikan billing, API, key, domain, dan quota siap sebelum perubahan UI besar.

Pekerjaan:

1. Buat/konfirmasi Google Cloud project khusus SaDesa.
2. Aktifkan Maps JavaScript API, Places API, Geocoding API, dan Routes API.
3. Buat browser key production dan staging.
4. Buat server key untuk Edge Functions.
5. Set HTTP referrer restriction dan API restriction.
6. Set quota harian dan budget alert.
7. Catat domain production, staging, dan localhost yang diizinkan.
8. Tambahkan dokumentasi deployment environment tanpa menuliskan nilai secret.
9. Tentukan apakah fallback Leaflet dipertahankan untuk kondisi API error atau hanya fallback text/coordinate.

**Output:** konfigurasi siap, key aman, budget/quota terpantau, dan daftar setting yang akan dikelola dari Admin sudah disepakati.

### Fase 1 — Adapter dan observability

**Tujuan:** mengisolasi provider sebelum mengganti banyak komponen.

Perubahan yang direncanakan:

- refactor `src/lib/googleMaps.ts` menjadi loader/adapter terpusat;
- tambah `src/lib/maps/types.ts`;
- tambah `src/lib/maps/provider.ts`;
- tambah `src/lib/maps/metrics.ts` untuk event tanpa menyimpan data sensitif;
- tambah helper validasi dan normalisasi koordinat;
- ubah `src/lib/routeCalculation.ts` agar menjadi adapter, bukan client OSRM langsung;
- buat feature flag provider untuk staging/canary;
- tambahkan error taxonomy dan UI fallback standar.
- siapkan kontrak `MapRuntimeConfig` agar komponen tidak membaca environment/provider secara tersebar.

**Output:** seluruh feature baru memakai kontrak map internal.

### Fase 1B — Admin Map & Integration Settings

**Tujuan:** membuat semua setting operasional peta dapat diubah admin tanpa deploy frontend.

Pekerjaan:

1. Buat tabel/config namespace `map_runtime` dengan schema tervalidasi.
2. Buat RLS agar hanya role admin yang dapat mengubah setting.
3. Buat audit log before/after untuk setiap perubahan.
4. Buat halaman Admin → Pengaturan → Peta & Integrasi.
5. Buat preview status provider, key status, quota, dan cache.
6. Buat tombol **Test Provider** yang memanggil health check terbatas.
7. Buat feature toggles per map surface.
8. Buat form pengendalian biaya dan batas request.
9. Buat alur rotasi key melalui Edge Function/secret store.
10. Tambahkan versioning dan rollback konfigurasi.

**Output:** admin dapat mengubah provider, fallback, feature flag, batas biaya, cache, dan aturan GPS; secret tetap terlindungi.

### Fase 2 — Geocoding dan autocomplete

**Tujuan:** mengganti Nominatim untuk alamat yang dipakai dalam checkout dan administrasi.

Pekerjaan frontend:

- buat `GooglePlacesAddressInput` shared;
- gunakan debounce dan session token;
- filter `country: id`;
- ambil hanya field yang dibutuhkan;
- normalisasi hasil menjadi address + coordinates;
- sediakan input manual dan pilih titik peta sebagai fallback.

Pekerjaan Edge Function:

- `google-geocode` untuk forward/reverse geocoding;
- validasi payload dan rate limit;
- cache berdasarkan normalized query atau koordinat yang dibulatkan;
- mapping hasil Google ke `ReverseGeocodingResult` yang sekarang dipakai aplikasi;
- logging provider/status tanpa menyimpan alamat sensitif lebih dari kebutuhan bisnis.

Target consumer fase ini:

- `CheckoutAddressForm`;
- `AddressFormDialog`;
- `ProfileEditor`;
- `RegisterMerchantPage`;
- `MerchantSettingsPage`;
- `VillageAddDialog` dan `VillageEditDialog`;
- `RegisterCourierPage` bila membutuhkan koordinat dari alamat.

### Fase 3 — Checkout dan jarak pengiriman

**Tujuan:** memastikan biaya pengiriman memakai rute yang konsisten dan tidak membuat request berulang.

Pekerjaan:

1. Ganti renderer `LocationPicker` dengan `GoogleLocationPicker`.
2. Pertahankan kontrak `onChange({ lat, lng })` agar `CheckoutAddressForm` tidak berubah besar.
3. Setelah pin stabil, debounce perhitungan jarak.
4. Panggil `google-route` Edge Function hanya untuk origin/destination yang valid.
5. Simpan route result sementara di cache client dan server.
6. Batasi perhitungan ulang jika perubahan pin di bawah ambang tertentu.
7. Tetap gunakan haversine fallback untuk menjaga checkout tidak buntu.
8. Tampilkan status sumber jarak: Google route atau estimasi fallback.

**Kriteria selesai:** checkout dapat memilih GPS, klik peta, memilih alamat, menghitung jarak, dan tetap bisa lanjut ketika Google unavailable.

### Fase 4 — Merchant/admin location management

**Tujuan:** menyatukan semua form lokasi master data.

Consumer:

- `MerchantLocationPicker`;
- `AdminLocationPicker`;
- dialog tambah/edit merchant;
- dialog tambah/edit village;
- lokasi tourism bila formnya memiliki koordinat.

Pekerjaan:

- pakai komponen picker shared;
- jadikan pengambilan GPS perangkat sebagai langkah wajib pada registrasi merchant dan perubahan alamat usaha;
- tampilkan akurasi GPS, waktu pengambilan, alamat, dan pin sebelum tombol simpan diaktifkan;
- minta pedagang mengonfirmasi pin berada di lokasi usaha;
- simpan `location_source`, `location_accuracy_m`, `location_updated_at`, dan status verifikasi;
- blok aktivasi/penerimaan order merchant jika lokasi belum `verified`;
- tampilkan checklist migrasi untuk merchant existing yang belum memiliki lokasi;
- jangan memanggil geocoding berulang pada setiap render; geocode hanya saat pedagang menyimpan atau meminta alamat;
- tampilkan koordinat dan alamat hasil geocode;
- validasi rentang koordinat;
- validasi bahwa koordinat tidak kosong pada entity yang mewajibkan lokasi;
- simpan source dan accuracy bila tersedia;
- uji RLS/RPC agar perubahan lokasi hanya dapat dilakukan role yang berwenang.

### Fase 5 — Tracking kurir/order/ride

**Tujuan:** mempertahankan realtime marker tetapi mengganti renderer dan routing.

Consumer:

- `CourierMap`;
- `CourierRideRouteMap`;
- `CourierMapSelector`;
- `OrderTrackingPage`;
- `RideTrackingPage`;
- `CourierRidesPage`;
- halaman merchant yang melihat kurir.

Pekerjaan:

1. Realtime lokasi tetap memakai Supabase Realtime.
2. Update posisi marker secara in-place; jangan remount seluruh map.
3. Hanya hitung rute ulang ketika tujuan berubah atau posisi berpindah melewati threshold.
4. Gunakan Routes Essentials untuk rute standar.
5. Hindari traffic-aware/Pro pada MVP kecuali ada kebutuhan bisnis dan budget yang disetujui.
6. Tampilkan fallback garis lurus/route terakhir jika request gagal.
7. Batasi jumlah marker dan update rate pada admin map.
8. Uji reconnect, tab background, PWA resume, dan courier offline.

### Fase 6 — Katalog, desa wisata, dan admin geography

**Tujuan:** mengganti peta eksplorasi yang tidak kritis terhadap transaksi.

Consumer:

- `ProductMerchantMap`;
- `TourismMap`;
- `DesaPetaPage`;
- `AdminMerchantDetailPage`;
- `AdminUserGeographyPage`.

Pekerjaan:

- lazy-load map route;
- marker hanya untuk entity yang sedang terlihat/terpilih;
- clustering jika jumlah marker tinggi;
- cache koordinat dari database;
- jangan reverse geocode setiap marker;
- tetap sediakan daftar/card agar fitur tidak bergantung total pada peta.

### Fase 7 — Cleanup dan cost hardening

Setelah seluruh consumer stabil:

- hapus pemakaian langsung `react-leaflet` dari feature production;
- hapus request langsung Nominatim/OSRM;
- hapus dependency Leaflet jika tidak ada lagi consumer;
- hapus fallback OSM hanya jika keputusan produk menyetujuinya;
- audit bundle size dan lazy chunks;
- lakukan review Google Cloud usage per SKU;
- perbarui runbook incident untuk `OVER_QUERY_LIMIT`, billing disabled, dan API key referrer mismatch.

## 6. Strategi biaya untuk 2.000 pengguna PWA

Perkiraan biaya tidak dapat dihitung dari jumlah akun saja. Telemetri perlu mencatat minimal:

- successful dynamic map loads;
- autocomplete requests/session;
- geocode requests;
- route requests;
- error/quota responses;
- feature/route yang memicu request.

Asumsi desain hemat:

- map hanya dimuat di checkout, tracking, katalog map, dan halaman admin yang membutuhkan;
- koordinat merchant/desa disimpan di database;
- alamat yang sama tidak di-geocode ulang;
- route hanya dihitung saat origin/destination berubah signifikan;
- marker realtime tidak memanggil Routes API setiap update GPS;
- Routes Essentials dipakai sebelum Pro/Enterprise.

Dengan asumsi tersebut, target awal yang layak dijadikan guardrail adalah:

```text
Budget alert awal: US$50/bulan
Budget alert utama: US$100/bulan
Review manual: US$150/bulan
```

Nominal aktual harus dikonfirmasi dari Google Cloud Billing karena tergantung negara billing, SKU, volume, pajak, dan konfigurasi API.

## 7. Rencana pengujian

### Unit/contract test

- normalisasi `MapPoint`;
- validasi latitude/longitude;
- haversine fallback;
- route adapter sukses/gagal/timeout;
- geocode response mapping;
- deduplikasi/cache request;
- threshold route recalculation;
- session autocomplete lifecycle;
- provider error taxonomy.

### Component test

- Google map loading;
- API key tidak tersedia;
- billing/quota error;
- klik peta memilih koordinat;
- GPS berhasil/ditolak/timeout;
- autocomplete memilih place tanpa geometry;
- marker update tanpa remount;
- empty state dan fallback.

### Integration/E2E

- checkout: pilih alamat melalui autocomplete;
- checkout: pilih lokasi melalui GPS;
- checkout: klik peta dan hitung jarak;
- merchant: simpan lokasi;
- admin: simpan lokasi village/merchant;
- buyer: melihat tracking courier realtime;
- courier: melihat rute order;
- ride: pickup/destination dan route;
- PWA cold start dan standalone mode;
- jaringan lambat/offline lalu recovery;
- domain staging dengan key restriction;
- production build tanpa server secret di bundle.

### Verifikasi keamanan

- scan `dist` untuk memastikan `GOOGLE_MAPS_SERVER_API_KEY` tidak muncul;
- verifikasi browser key hanya diizinkan pada domain yang benar;
- verifikasi Routes/Geocoding tidak bisa dipanggil memakai browser key jika policy mewajibkan server key;
- cek RLS/RPC lokasi;
- cek rate limit Edge Functions;
- jangan log alamat lengkap atau token API.

## 8. Kriteria penerimaan implementasi

Implementasi dianggap siap pilot apabila:

- seluruh feature utama memakai map adapter bersama;
- checkout, merchant, admin, tracking, dan ride memiliki behavior yang konsisten;
- Google Maps gagal tidak menyebabkan checkout atau tracking crash;
- tidak ada request langsung Nominatim/OSRM dari feature yang sudah dimigrasikan;
- route tidak dihitung ulang pada setiap update marker;
- autocomplete menggunakan sesi/debounce yang benar;
- browser/server key terpisah dan dibatasi;
- quota serta budget alert aktif;
- semua lokasi memiliki validasi koordinat;
- unit, component, build, lint, dan test terkait map lulus;
- penggunaan SKU dapat dilihat dan dipetakan kembali ke feature aplikasi;
- merchant baru tidak dapat aktif tanpa alamat usaha dan koordinat GPS yang terverifikasi;
- merchant existing tanpa koordinat mendapat status pending dan checklist pembaruan yang jelas;
- perubahan alamat mewajibkan pengambilan GPS baru dan memperbarui timestamp/status verifikasi;
- backend/RPC menolak aktivasi atau penerimaan order dengan lokasi merchant yang belum valid;
- permission GPS ditolak, timeout, dan akurasi buruk memiliki alur pemulihan yang dapat dipahami pedagang;
- PWA tetap dapat dibuka dan menampilkan fallback yang jelas pada jaringan buruk.

## 9. Urutan implementasi yang direkomendasikan

Urutan paling aman dan berdampak langsung:

1. **Fase 0:** Google Cloud, key, quota, budget, domain.
2. **Fase 1:** adapter, type contract, error, observability.
3. **Fase 2:** shared autocomplete/geocoding.
4. **Fase 3:** checkout location picker dan delivery distance.
5. **Fase 4:** merchant/admin location forms.
6. **Fase 5:** order/courier/ride tracking.
7. **Fase 6:** katalog, tourism, dan admin geography.
8. **Fase 7:** cleanup dependency dan cost hardening.

Jangan langsung mengganti semua komponen Leaflet dalam satu perubahan besar. Checkout dan tracking memiliki dampak bisnis paling tinggi, sehingga perlu dimigrasikan setelah adapter dan geocoding contract teruji.

## 10. File yang kemungkinan berubah

### Fondasi

- `src/lib/googleMaps.ts`
- `src/lib/routeCalculation.ts`
- `src/hooks/useGeocoding.ts`
- file baru `src/lib/maps/types.ts`
- file baru `src/lib/maps/provider.ts`
- file baru `src/lib/maps/cache.ts`
- file baru `src/lib/maps/metrics.ts`
- `.env.example`

### UI lokasi dan peta

- `src/components/transport/GoogleAddressInput.tsx`
- `src/components/transport/GoogleRideMap.tsx`
- `src/components/checkout/LocationPicker.tsx`
- `src/components/merchant/MerchantLocationPicker.tsx`
- `src/components/admin/AdminLocationPicker.tsx`
- `src/components/product/ProductMerchantMap.tsx`
- `src/components/CourierMap.tsx`
- `src/components/courier/CourierRideRouteMap.tsx`
- `src/components/merchant/CourierMapSelector.tsx`
- `src/components/village/TourismMap.tsx`

### Edge Functions dan database

- file baru Supabase Edge Function untuk geocoding;
- file baru Supabase Edge Function untuk routes;
- migration/cache table hanya jika cache persisten diperlukan;
- policy/rate-limit contract sesuai pola Edge Functions yang sudah ada.

## 11. Keputusan yang perlu dikonfirmasi sebelum coding

1. Apakah **semua peta** harus pindah ke Google, atau hanya checkout, tracking, ride, dan admin?
2. Apakah fallback Leaflet/OSM dipertahankan selama masa pilot?
3. Apakah perhitungan biaya pengiriman harus memakai rute Google secara authoritative, atau Google hanya untuk visualisasi sementara?
4. Apakah alamat pengguna boleh dikirim ke Edge Function Google untuk reverse geocoding, dengan logging minimal?
5. Domain production dan staging apa saja yang akan diizinkan pada browser key?
6. Budget maksimal bulanan yang disetujui untuk Google Maps berapa?

**Kebijakan produk yang sudah ditetapkan:** pedagang wajib memperbarui alamat usaha dan menyimpan titik koordinat memakai GPS perangkatnya. Detail ambang akurasi, toleransi jarak dari titik usaha, serta apakah merchant lama diblokir dari menerima order atau hanya dari aktivasi ulang perlu ditetapkan saat implementasi backend.

## 12. Referensi resmi

- [Google Maps Platform global pricing](https://developers.google.com/maps/billing-and-pricing/pricing)
- [Google Maps Platform SKU details](https://developers.google.com/maps/billing-and-pricing/sku-details)
- [Maps JavaScript API usage and billing](https://developers.google.com/maps/documentation/javascript/usage-and-billing)
- [Places API usage and billing](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing)
- [Geocoding API usage and billing](https://developers.google.com/maps/documentation/geocoding/usage-and-billing)
- [Google Maps API security best practices](https://developers.google.com/maps/api-security-best-practices)
- [Google Maps Platform pricing overview](https://mapsplatform.google.com/pricing/)

## Status

**Status:** Audit selesai, implementasi belum dimulai.  
**Rekomendasi:** mulai dari Fase 0–1, lalu implementasikan checkout sebagai pilot pertama sebelum migrasi seluruh peta.
