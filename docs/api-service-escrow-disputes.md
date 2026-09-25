# API Escrow dan Manajemen Sengketa Jasa

**Versi dokumen:** 1.0.0  
**Platform:** SaDesa  
**Backend:** Supabase Auth, PostgREST, PostgreSQL Row Level Security (RLS)  
**Bahasa:** Indonesia

Dokumen ini menjelaskan kontrak data dan pola integrasi untuk marketplace jasa SaDesa. Cakupannya meliputi katalog jasa, profil penyedia, permintaan pekerjaan, negosiasi, penitipan dana oleh admin, verifikasi bukti transfer, pencairan kepada penyedia, laporan keuangan, dan penyelesaian sengketa.

> **Batasan penting:** fitur jasa saat ini menggunakan Supabase Client dan PostgREST secara langsung. Repository belum menyediakan REST API custom atau Edge Function khusus escrow. Contoh `supabase.from(...)` di dokumen ini adalah kontrak aplikasi yang sudah digunakan. Operasi transfer bank aktual tetap dilakukan oleh admin atau payment gateway; sistem hanya menyimpan status, nominal, biaya, dan referensi operasionalnya.

## 1. Arsitektur dan prinsip escrow

Penyewa jasa tidak membayar langsung kepada penyedia. Penyewa mengirim pembayaran ke rekening atau kanal pembayaran admin, kemudian mengunggah bukti transfer. Admin memverifikasi bukti tersebut. Setelah diverifikasi, request dapat dilanjutkan ke tahap pengerjaan. Setelah pekerjaan selesai dan tidak ada sengketa, admin menandai payout sebagai `RELEASED` setelah memotong fee platform serta biaya transfer.

Alur ini memisahkan empat fakta keuangan yang berbeda:

1. **Nominal transaksi** adalah jumlah yang dibayar penyewa.
2. **Dana bruto payout** adalah nominal yang menjadi dasar pencairan kepada penyedia.
3. **Fee platform** adalah bagian untuk admin sesuai kebijakan layanan.
4. **Dana bersih penyedia** adalah dana bruto dikurangi fee platform dan biaya transfer.

Perubahan status pembayaran dan payout wajib dilakukan oleh admin melalui akun yang memiliki role `admin`. RLS database adalah kontrol terakhir; pembatasan route pada frontend bukan pengganti RLS.

## 2. Base URL, autentikasi, dan header

Base URL Supabase dibaca dari konfigurasi aplikasi sebagai `VITE_SUPABASE_URL`. Endpoint PostgREST menggunakan bentuk berikut:

```text
https://<project-ref>.supabase.co/rest/v1
```

Request dari browser menggunakan session Supabase yang aktif dan publishable key:

```http
apikey: <VITE_SUPABASE_PUBLISHABLE_KEY>
Authorization: Bearer <access_token>
Content-Type: application/json
Prefer: return=representation
```

Aplikasi memperoleh `access_token` dari session Supabase. Integrator tidak boleh menaruh `service_role` key di browser. Operasi backend terjadwal atau integrasi server-to-server harus menyimpan credential secara server-side dan tetap menghormati batas otorisasi.

Contoh inisialisasi client:

```ts
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
);
```

Contoh request langsung ke PostgREST:

```http
GET /rest/v1/service_requests?select=*&provider_id=eq.<provider_id>&order=created_at.desc
apikey: <publishable-key>
Authorization: Bearer <access-token>
```

Contoh pemanggilan yang direkomendasikan di aplikasi:

```ts
const { data, error } = await supabase
  .from('service_requests')
  .select('*')
  .eq('provider_id', providerId)
  .order('created_at', { ascending: false });
```

## 3. Identitas aktor dan hak akses

| Aktor | Hak utama |
|---|---|
| Penyewa jasa | Melihat kategori dan profil aktif, membuat request, mengirim pesan, mengunggah bukti pembayaran, membaca request yang diikutinya, dan membuka sengketa sebagai pihak transaksi. |
| Penyedia jasa | Mengelola profil dan keahliannya, membaca request yang ditujukan kepadanya, mengirim pesan, dan membaca payout serta sengketa yang melibatkannya. |
| Admin | Membaca dan mengubah bukti pembayaran, payout, kategori, subkategori, request, serta sengketa. Admin juga menulis keputusan ke audit log aplikasi. |
| Pengunjung | Membaca kategori, subkategori aktif, dan profil jasa aktif melalui policy publik. Operasi yang membutuhkan identitas memerlukan session. |

RLS menggunakan `auth.uid()` dan helper `public.is_admin(auth.uid())`. Jangan mempercayai `provider_id`, `requester_id`, atau `opened_by` dari client tanpa pemeriksaan database.

## 4. Model data

### 4.1 `service_categories`

Menyimpan kategori jasa yang dapat diubah admin.

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid` | Primary key. |
| `name` | `text` | Nama kategori yang tampil di UI. |
| `slug` | `text` | Identifier unik yang stabil. |
| `description` | `text` | Deskripsi opsional. |
| `icon` | `text` | Nama ikon frontend. Default `Wrench`. |
| `is_active` | `boolean` | Menentukan apakah kategori terlihat publik. |
| `sort_order` | `integer` | Urutan tampilan. |
| `created_at`, `updated_at` | `timestamptz` | Metadata waktu. |

### 4.2 `service_subcategories`

Menyimpan keahlian yang dapat dipilih penyedia.

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid` | Primary key. |
| `category_id` | `uuid` | Foreign key ke `service_categories`. |
| `name` | `text` | Nama keahlian. |
| `slug` | `text` | Unik di dalam kategori. |
| `is_active` | `boolean` | Status publik. |
| `sort_order` | `integer` | Urutan tampilan. |

### 4.3 `service_profiles`

Profil publik penyedia jasa. Satu user hanya memiliki satu profil karena `provider_id` unik.

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid` | Primary key. |
| `provider_id` | `uuid` | User pemilik profil. |
| `provider_name` | `text` | Nama tampil. |
| `headline` | `text` | Judul layanan. |
| `bio` | `text` | Pengalaman dan deskripsi. |
| `village` | `text` | Area layanan. |
| `phone` | `text` | Nomor kontak opsional. |
| `min_price` | `numeric(14,2)` | Harga minimum, tidak boleh negatif. |
| `rating` | `numeric(3,2)` | Nilai 0 sampai 5. |
| `review_count` | `integer` | Jumlah ulasan. |
| `is_active` | `boolean` | Profil tampil atau tidak. |
| `is_verified` | `boolean` | Status verifikasi admin. |

### 4.4 `service_skills`

Relasi many-to-many antara profil dan subkategori. Kombinasi `profile_id` dan `subcategory_id` harus unik.

### 4.5 `service_requests`

Satu baris merepresentasikan satu pekerjaan jasa antara penyewa dan penyedia.

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid` | ID request. |
| `requester_id` | `uuid` | Penyewa jasa. |
| `provider_id` | `uuid` | Penyedia jasa. |
| `profile_id` | `uuid` | Profil jasa yang dipilih. |
| `subcategory_id` | `uuid` nullable | Keahlian yang diminta. |
| `title` | `text` | Judul kebutuhan. |
| `description` | `text` | Detail pekerjaan. |
| `location` | `text` | Lokasi pekerjaan. |
| `agreed_price` | `numeric(14,2)` nullable | Harga hasil negosiasi. |
| `platform_fee` | `numeric(14,2)` | Potongan admin. Default 0 sampai dihitung. |
| `transfer_fee` | `numeric(14,2)` | Biaya transfer. Default 0. |
| `provider_payout` | `numeric(14,2)` nullable | Estimasi atau nominal bersih penyedia. |
| `status` | `text` | Status lifecycle request. |
| `requester_approved` | `boolean` | Persetujuan penyewa. |
| `provider_approved` | `boolean` | Persetujuan penyedia. |
| `requester_completed` | `boolean` | Konfirmasi selesai dari penyewa. |
| `provider_completed` | `boolean` | Konfirmasi selesai dari penyedia. |

Status yang diizinkan oleh database adalah:

```text
NEGOTIATING
WAITING_PAYMENT
PAID_TO_ADMIN
APPROVED_TO_START
IN_PROGRESS
WAITING_CONFIRMATION
COMPLETED
DISPUTED
CANCELLED
REFUNDED
```

### 4.6 `service_messages`

Menyimpan pesan negosiasi. `proposed_price` dapat dipakai untuk mengirim tawaran harga tanpa mengubah harga kesepakatan sampai kedua pihak menyetujuinya.

| Kolom | Tipe | Keterangan |
|---|---|---|
| `request_id` | `uuid` | Request terkait. |
| `sender_id` | `uuid` | Pengirim pesan. Harus sama dengan user session. |
| `body` | `text` | Isi pesan. Wajib. |
| `proposed_price` | `numeric(14,2)` nullable | Tawaran harga opsional. |
| `created_at` | `timestamptz` | Waktu pengiriman. |

### 4.7 `service_payment_proofs`

Menyimpan bukti transfer penyewa kepada admin.

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | `uuid` | ID bukti. |
| `request_id` | `uuid` | Request yang dibayar. |
| `uploaded_by` | `uuid` | Harus merupakan requester. |
| `amount` | `numeric(14,2)` | Nominal transfer, wajib lebih besar dari 0. |
| `transfer_reference` | `text` nullable | Referensi transfer. |
| `proof_url` | `text` nullable | URL objek bukti yang aman. |
| `status` | `text` | `PENDING`, `VERIFIED`, atau `REJECTED`. |
| `admin_note` | `text` nullable | Catatan verifikasi atau penolakan. |
| `verified_at` | `timestamptz` nullable | Waktu keputusan admin. |

### 4.8 `service_payouts`

Menyimpan satu payout untuk setiap request karena `request_id` unik.

| Kolom | Tipe | Keterangan |
|---|---|---|
| `request_id` | `uuid` | Request yang dicairkan. Unik. |
| `gross_amount` | `numeric(14,2)` | Dana bruto sebelum potongan. |
| `platform_fee` | `numeric(14,2)` | Fee admin. |
| `transfer_fee` | `numeric(14,2)` | Biaya transfer. |
| `net_amount` | `numeric(14,2)` | `gross_amount - platform_fee - transfer_fee`, minimum 0. |
| `status` | `text` | `PENDING`, `RELEASED`, atau `FAILED`. |
| `released_by` | `uuid` nullable | User admin yang melakukan pencairan. |
| `released_at` | `timestamptz` nullable | Waktu pencairan. |
| `note` | `text` nullable | Referensi atau catatan operasional. |

### 4.9 `service_disputes`

Menyimpan komplain transaksi jasa. Satu request hanya dapat memiliki satu sengketa aktif atau riwayat sengketa karena `request_id` unik.

| Kolom | Tipe | Keterangan |
|---|---|---|
| `request_id` | `uuid` | Request yang disengketakan. Unik. |
| `opened_by` | `uuid` | User yang membuka sengketa. |
| `requester_id` | `uuid` | Penyewa. |
| `provider_id` | `uuid` | Penyedia. |
| `reason` | `text` | Alasan komplain. Wajib. |
| `amount` | `numeric(14,2)` nullable | Nilai yang disengketakan. |
| `evidence_urls` | `jsonb` | Array URL bukti. Default `[]`. |
| `status` | `text` | Status resolusi. |
| `admin_note` | `text` nullable | Catatan proses mediasi. |
| `resolution` | `text` nullable | Keputusan akhir. |
| `resolved_by` | `uuid` nullable | Admin yang menyelesaikan. |
| `resolved_at` | `timestamptz` nullable | Waktu resolusi. |

Status sengketa yang diizinkan:

```text
OPEN
IN_REVIEW
WAITING_PARTIES
REFUND_APPROVED
RELEASE_APPROVED
RESOLVED
CLOSED
REJECTED
```

## 5. Operasi katalog dan profil

### 5.1 Membaca kategori aktif

```ts
const { data, error } = await supabase
  .from('service_categories')
  .select('id,name,slug,description,icon,sort_order')
  .eq('is_active', true)
  .order('sort_order');
```

Endpoint REST:

```http
GET /rest/v1/service_categories?select=id,name,slug,description,icon,sort_order&is_active=eq.true&order=sort_order.asc
```

Public dapat membaca kategori aktif. Perubahan kategori hanya boleh dilakukan admin.

### 5.2 Membaca subkategori kategori tertentu

```ts
const { data, error } = await supabase
  .from('service_subcategories')
  .select('id,category_id,name,slug,sort_order')
  .eq('category_id', categoryId)
  .eq('is_active', true)
  .order('sort_order');
```

### 5.3 Membaca profil penyedia

```ts
const { data, error } = await supabase
  .from('service_profiles')
  .select(`
    id,provider_id,provider_name,headline,bio,village,min_price,rating,review_count,is_verified,
    service_skills(subcategory_id,service_subcategories(name,category_id))
  `)
  .eq('is_active', true)
  .order('rating', { ascending: false });
```

Public hanya melihat profil aktif. Pemilik profil dan admin dapat membaca profil nonaktif mereka sendiri.

### 5.4 Membuat atau memperbarui profil penyedia

```ts
const { data: profile, error } = await supabase
  .from('service_profiles')
  .upsert({
    provider_id: session.user.id,
    provider_name: 'Budi Teknisi',
    headline: 'Teknisi elektronik panggilan',
    bio: 'Perbaikan TV, kulkas, dan pompa air.',
    village: 'Desa Sukamaju',
    min_price: 75000,
    is_active: true,
  }, { onConflict: 'provider_id' })
  .select('id')
  .single();
```

Setelah profil dibuat, keahlian disimpan pada `service_skills`:

```ts
await supabase.from('service_skills').delete().eq('profile_id', profile.id);
await supabase.from('service_skills').insert([
  { profile_id: profile.id, subcategory_id: televisionSubcategoryId },
  { profile_id: profile.id, subcategory_id: refrigeratorSubcategoryId },
]);
```

Policy memastikan user hanya dapat mengelola profil dan keahliannya sendiri. Admin dapat mengubahnya untuk kebutuhan verifikasi atau moderasi.

## 6. Operasi request dan negosiasi

### 6.1 Membuat request jasa

```ts
const { data, error } = await supabase
  .from('service_requests')
  .insert({
    requester_id: session.user.id,
    provider_id: providerId,
    profile_id: profileId,
    subcategory_id: subcategoryId,
    title: 'TV tidak menyala',
    description: 'Televisi 32 inci mati total sejak kemarin.',
    location: 'Dusun Melati, Desa Sukamaju',
    agreed_price: null,
  })
  .select()
  .single();
```

Request baru berstatus `NEGOTIATING`. Client tidak boleh langsung menganggap harga sudah disepakati ketika `agreed_price` masih `null`.

### 6.2 Membaca request sebagai peserta

```ts
const { data, error } = await supabase
  .from('service_requests')
  .select('*')
  .or(`requester_id.eq.${userId},provider_id.eq.${userId}`)
  .order('created_at', { ascending: false });
```

RLS tetap memeriksa peserta. Query dengan filter yang terlalu luas tidak memberikan akses ke request milik user lain.

### 6.3 Mengirim pesan negosiasi

```ts
const { data, error } = await supabase
  .from('service_messages')
  .insert({
    request_id: requestId,
    sender_id: session.user.id,
    body: 'Saya bisa datang sore ini. Apakah setuju di Rp150.000?',
    proposed_price: 150000,
  })
  .select()
  .single();
```

Pengirim harus merupakan requester atau provider pada request tersebut. `proposed_price` hanya tawaran; integrasi harus memiliki langkah persetujuan eksplisit sebelum mengisi `agreed_price`.

### 6.4 Menetapkan harga dan status pembayaran

Setelah kedua pihak sepakat, integrasi yang memiliki otorisasi dapat memperbarui:

```ts
await supabase
  .from('service_requests')
  .update({
    agreed_price: 150000,
    platform_fee: 7500,
    transfer_fee: 2500,
    provider_payout: 140000,
    status: 'WAITING_PAYMENT',
    requester_approved: true,
    provider_approved: true,
  })
  .eq('id', requestId);
```

Perhitungan contoh di atas adalah:

```text
gross = 150.000
platform_fee = 7.500
transfer_fee = 2.500
provider_payout = 140.000
```

Implementasi produksi sebaiknya memindahkan perhitungan fee ke RPC atau server-side service agar client tidak dapat memanipulasi nominal.

## 7. Operasi pembayaran escrow

### 7.1 Mengunggah bukti transfer

File bukti sebaiknya diunggah ke storage private terlebih dahulu. Setelah URL atau storage path tersedia, requester membuat row bukti:

```ts
const { data, error } = await supabase
  .from('service_payment_proofs')
  .insert({
    request_id: requestId,
    uploaded_by: session.user.id,
    amount: 150000,
    transfer_reference: 'TRX-20260925-0001',
    proof_url: privateProofPath,
    status: 'PENDING',
  })
  .select()
  .single();
```

Policy insert hanya mengizinkan requester pada request yang bersangkutan. Admin membaca seluruh bukti melalui RLS admin.

### 7.2 Membaca antrean bukti admin

```ts
const { data, error } = await supabase
  .from('service_payment_proofs')
  .select(`
    *,
    request:service_requests(
      id,title,description,location,agreed_price,platform_fee,transfer_fee,
      provider_payout,status,provider_id,requester_id
    )
  `)
  .order('created_at', { ascending: false });
```

Pada dashboard admin, hanya row `PENDING` yang masuk antrean review. Integrasi dapat menambahkan filter PostgREST:

```http
GET /rest/v1/service_payment_proofs?select=*,request:service_requests(*)&status=eq.PENDING&order=created_at.desc
```

### 7.3 Memverifikasi bukti transfer

```ts
const { error } = await supabase
  .from('service_payment_proofs')
  .update({
    status: 'VERIFIED',
    admin_note: 'Nominal dan referensi transfer cocok.',
    verified_at: new Date().toISOString(),
  })
  .eq('id', proofId);

if (!error) {
  await supabase
    .from('service_requests')
    .update({ status: 'APPROVED_TO_START' })
    .eq('id', requestId);
}
```

Setelah verifikasi, penyedia dapat mulai bekerja. Integrasi sebaiknya menggunakan transaksi server-side atau RPC untuk memastikan update bukti dan request tidak terpisah bila salah satu operasi gagal.

### 7.4 Menolak bukti transfer

```ts
await supabase
  .from('service_payment_proofs')
  .update({
    status: 'REJECTED',
    admin_note: 'Bukti tidak terbaca. Silakan unggah ulang.',
    verified_at: null,
  })
  .eq('id', proofId);

await supabase
  .from('service_requests')
  .update({ status: 'WAITING_PAYMENT' })
  .eq('id', requestId);
```

Catatan penolakan harus cukup jelas agar requester dapat memperbaiki bukti tanpa membuka data sensitif yang tidak diperlukan.

## 8. Operasi payout penyedia

### 8.1 Membuat payout

Sistem menggunakan satu payout untuk satu request. Integrasi admin atau backend membuat row payout ketika request telah memenuhi syarat pencairan:

```ts
const gross = 150000;
const platformFee = 7500;
const transferFee = 2500;
const net = Math.max(0, gross - platformFee - transferFee);

const { data, error } = await supabase
  .from('service_payouts')
  .insert({
    request_id: requestId,
    gross_amount: gross,
    platform_fee: platformFee,
    transfer_fee: transferFee,
    net_amount: net,
    status: 'PENDING',
  })
  .select()
  .single();
```

Row payout harus dibuat hanya setelah pekerjaan berada pada tahap `WAITING_CONFIRMATION` atau aturan bisnis yang setara. Karena `request_id` unik, retry insert harus menangani error duplicate atau menggunakan upsert yang sesuai.

### 8.2 Membaca payout admin

```ts
const { data, error } = await supabase
  .from('service_payouts')
  .select('*,request:service_requests(title,location,status,provider_id,provider_payout)')
  .order('status', { ascending: true })
  .order('created_at', { ascending: false });
```

Admin dapat membaca semua payout. Penyedia hanya dapat membaca payout yang request-nya memiliki `provider_id` sama dengan user session.

### 8.3 Menandai payout sudah dicairkan

Operasi transfer bank aktual harus dilakukan terlebih dahulu oleh admin atau gateway. Setelah bukti transfer keluar tersedia, admin memperbarui row:

```ts
const { error } = await supabase
  .from('service_payouts')
  .update({
    status: 'RELEASED',
    gross_amount: 150000,
    platform_fee: 7500,
    transfer_fee: 2500,
    net_amount: 140000,
    released_by: adminUserId,
    released_at: new Date().toISOString(),
    note: 'Transfer bank admin ref WD-0001',
  })
  .eq('id', payoutId)
  .eq('status', 'PENDING');
```

Filter `status=eq.PENDING` membantu mencegah pencairan ulang akibat klik ganda. Backend yang lebih kuat harus menggunakan RPC dengan lock atau idempotency key.

Setelah update berhasil, request dapat ditandai `COMPLETED`:

```ts
await supabase
  .from('service_requests')
  .update({ status: 'COMPLETED' })
  .eq('id', requestId);
```

### 8.4 Membaca riwayat payout penyedia

```ts
const { data, error } = await supabase
  .from('service_requests')
  .select(`
    id,title,description,location,agreed_price,platform_fee,transfer_fee,
    provider_payout,status,created_at,
    service_payouts(id,gross_amount,platform_fee,transfer_fee,net_amount,status,released_at,created_at,note),
    service_payment_proofs(request_id,status,amount,created_at)
  `)
  .eq('provider_id', session.user.id)
  .order('created_at', { ascending: false });
```

Halaman `/services/provider-history` memakai pola ini secara terpisah melalui query request, payout, dan bukti pembayaran. Nilai bersih hanya boleh ditampilkan sebagai sudah diterima bila payout memiliki status `RELEASED`.

## 9. Manajemen sengketa

### 9.1 Membuka sengketa

Penyewa atau penyedia dapat membuat sengketa untuk request yang diikutinya:

```ts
const { data, error } = await supabase
  .from('service_disputes')
  .insert({
    request_id: requestId,
    opened_by: session.user.id,
    requester_id: requesterId,
    provider_id: providerId,
    reason: 'Pekerjaan belum selesai dan perangkat masih mengalami masalah.',
    amount: 150000,
    evidence_urls: [privateEvidencePath],
    status: 'OPEN',
  })
  .select()
  .single();
```

Policy memastikan `opened_by` sama dengan user session dan user tersebut adalah requester atau provider. Karena `request_id` unik, request yang sudah memiliki sengketa tidak boleh dibuatkan sengketa kedua tanpa kebijakan khusus.

Setelah sengketa dibuat, integrasi sebaiknya mengubah request menjadi `DISPUTED` melalui operasi yang aman:

```ts
await supabase
  .from('service_requests')
  .update({ status: 'DISPUTED' })
  .eq('id', requestId);
```

### 9.2 Membaca antrean sengketa admin

```ts
const { data, error } = await supabase
  .from('service_disputes')
  .select(`
    *,
    request:service_requests(
      title,description,location,status,agreed_price,provider_payout
    )
  `)
  .order('created_at', { ascending: false });
```

Antrean aktif biasanya difilter dengan status berikut:

```http
GET /rest/v1/service_disputes?select=*,request:service_requests(*)&status=in.(OPEN,IN_REVIEW,WAITING_PARTIES)&order=created_at.desc
```

### 9.3 Mengubah status ke review atau menunggu pihak

```ts
await supabase
  .from('service_disputes')
  .update({
    status: 'IN_REVIEW',
    admin_note: 'Admin sedang memeriksa bukti dan riwayat chat.',
  })
  .eq('id', disputeId);
```

Gunakan `WAITING_PARTIES` bila admin membutuhkan klarifikasi dari penyewa atau penyedia. Catatan harus menjelaskan informasi yang diminta dan batas waktu respons bila platform menerapkan SLA.

### 9.4 Keputusan refund

```ts
await supabase
  .from('service_disputes')
  .update({
    status: 'REFUND_APPROVED',
    admin_note: 'Bukti mendukung komplain penyewa.',
    resolution: 'Refund penuh disetujui.',
    resolved_at: new Date().toISOString(),
  })
  .eq('id', disputeId);

await supabase
  .from('service_requests')
  .update({ status: 'REFUNDED' })
  .eq('id', requestId);
```

Status `REFUND_APPROVED` mencatat keputusan. Transfer refund aktual harus dilakukan oleh admin atau payment gateway, lalu referensinya sebaiknya disimpan pada `resolution` atau ledger refund yang terpisah.

### 9.5 Keputusan pencairan kepada penyedia

```ts
await supabase
  .from('service_disputes')
  .update({
    status: 'RELEASE_APPROVED',
    admin_note: 'Komplain tidak terbukti setelah kedua pihak memberi klarifikasi.',
    resolution: 'Pencairan kepada penyedia disetujui.',
    resolved_at: new Date().toISOString(),
  })
  .eq('id', disputeId);

await supabase
  .from('service_requests')
  .update({ status: 'WAITING_CONFIRMATION' })
  .eq('id', requestId);
```

Keputusan ini tidak otomatis menandai payout `RELEASED`. Admin tetap harus memproses payout pada dashboard escrow setelah memastikan syarat pencairan terpenuhi.

### 9.6 Menutup sengketa

```ts
await supabase
  .from('service_disputes')
  .update({
    status: 'CLOSED',
    admin_note: 'Kasus ditutup setelah refund dan pemberitahuan selesai.',
    resolution: 'Kasus selesai.',
    resolved_at: new Date().toISOString(),
  })
  .eq('id', disputeId);
```

Pada integrasi server-side, isi juga `resolved_by` dengan ID admin. UI dashboard saat ini menyimpan keputusan dan catatan; pengisian `resolved_by` sebaiknya ditambahkan ke RPC atomik agar identitas admin selalu tercatat di database.

## 10. Lifecycle end-to-end

Urutan normal transaksi adalah sebagai berikut:

1. Penyewa memilih profil dan subkategori.
2. Sistem membuat `service_requests` dengan status `NEGOTIATING`.
3. Kedua pihak bernegosiasi melalui `service_messages`.
4. Harga final, fee, dan payout dihitung.
5. Request menjadi `WAITING_PAYMENT`.
6. Penyewa mentransfer dana ke admin dan membuat `service_payment_proofs` dengan status `PENDING`.
7. Admin memeriksa bukti. Jika valid, status bukti menjadi `VERIFIED` dan request menjadi `APPROVED_TO_START`.
8. Penyedia mengerjakan layanan. Request dapat bergerak ke `IN_PROGRESS`.
9. Kedua pihak memberikan konfirmasi. Request menjadi `WAITING_CONFIRMATION` atau `COMPLETED` sesuai aturan produk.
10. Sistem atau admin membuat `service_payouts` berstatus `PENDING`.
11. Admin memotong fee, melakukan transfer kepada penyedia, lalu mengubah payout menjadi `RELEASED`.
12. Request ditandai `COMPLETED` dan penyedia melihat status pencairan pada riwayat transaksi.

Jika muncul komplain sebelum payout dilepas:

1. Salah satu pihak membuat `service_disputes` berstatus `OPEN`.
2. Request ditandai `DISPUTED`.
3. Admin mengubah sengketa menjadi `IN_REVIEW` atau `WAITING_PARTIES`.
4. Admin memilih `REFUND_APPROVED`, `RELEASE_APPROVED`, `REJECTED`, atau `RESOLVED`.
5. Sistem memperbarui request sesuai keputusan dan menyimpan catatan audit.
6. Transfer refund atau payout aktual dilakukan melalui proses keuangan yang sesuai.

## 11. Laporan keuangan bulanan

Dashboard `/admin/services` memiliki tab **Laporan Bulanan**. Rekap menghitung bukti transfer berstatus `VERIFIED` berdasarkan bulan `service_payment_proofs.created_at`. Payout dihitung berdasarkan `released_at`, atau `created_at` bila `released_at` belum tersedia.

Metrik yang ditampilkan adalah:

- Total transaksi jasa.
- Jumlah transaksi terverifikasi.
- Potongan fee admin.
- Biaya transfer.
- Dana bersih penyedia.
- Gross payout.

Ekspor CSV berisi kolom berikut:

```text
Tanggal, Request ID, Pekerjaan, Total Transaksi, Fee Admin,
Biaya Transfer, Bersih Penyedia, Status
```

Contoh query agregasi server-side:

```ts
const { data: payouts, error } = await supabase
  .from('service_payouts')
  .select('request_id,gross_amount,platform_fee,transfer_fee,net_amount,status,released_at,created_at')
  .gte('released_at', '2026-09-01T00:00:00.000Z')
  .lt('released_at', '2026-10-01T00:00:00.000Z');
```

Untuk laporan resmi, gunakan nilai payout yang sudah `RELEASED` dan simpan snapshot laporan. Query UI adalah laporan operasional, bukan pengganti ledger akuntansi immutable.

## 12. RLS dan keamanan data

RLS yang diterapkan pada bootstrap memiliki aturan berikut:

| Tabel | Public | Peserta | Admin |
|---|---|---|---|
| `service_categories` | Baca row aktif | Baca row aktif | CRUD |
| `service_subcategories` | Baca row aktif | Baca row aktif | CRUD |
| `service_profiles` | Baca profil aktif | Kelola profil sendiri | CRUD |
| `service_skills` | Baca | Kelola skill pada profil sendiri | CRUD |
| `service_requests` | Tidak | Baca dan update request yang diikuti | Baca dan update semua |
| `service_messages` | Tidak | Baca dan insert pada request yang diikuti | Baca |
| `service_payment_proofs` | Tidak | Requester insert; peserta baca | Baca dan update |
| `service_payouts` | Tidak | Peserta baca payout terkait | CRUD |
| `service_disputes` | Tidak | Peserta baca dan peserta terkait insert | Baca, update, delete |

Integrasi wajib menerapkan aturan berikut:

- Jangan mengirim `service_role` key ke browser.
- Jangan mempercayai status yang datang dari client tanpa validasi transition di server.
- Jangan menganggap `proof_url` publik. Gunakan storage private dan signed URL bila bukti memuat data rekening.
- Jangan menampilkan bukti transfer kepada user yang bukan peserta atau admin.
- Jangan mengubah `net_amount` dari UI tanpa menghitung ulang gross, fee, dan biaya transfer.
- Gunakan idempotency key atau RPC atomik untuk verifikasi dan payout agar retry jaringan tidak menggandakan efek finansial.
- Simpan referensi transfer bank dan audit action untuk setiap perubahan keuangan.
- Jangan menutup sengketa tanpa catatan keputusan yang dapat dijelaskan.

## 13. Error handling dan idempotensi

Supabase mengembalikan object `{ data, error }`. Integrasi harus memeriksa `error` setiap operasi dan tidak menganggap request berhasil hanya karena promise selesai.

Contoh helper:

```ts
async function requireSuccess<T>(operation: PromiseLike<{ data: T; error: { message: string } | null }>) {
  const { data, error } = await operation;
  if (error) throw new Error(error.message);
  return data;
}
```

Kondisi yang perlu ditangani:

| Kondisi | Penanganan |
|---|---|
| `401` atau session expired | Minta user login ulang. Jangan retry tanpa batas. |
| `403` atau RLS violation | Hentikan operasi dan tampilkan akses ditolak. Jangan menurunkan kontrol ke client. |
| `409` atau unique violation | Periksa apakah operasi sebelumnya sudah berhasil. Khusus payout dan dispute, baca row existing sebelum retry. |
| `422` atau check constraint | Validasi nominal, status, dan field wajib sebelum request. |
| Network timeout | Retry hanya pada operasi idempotent atau dengan idempotency key. |
| Update bukti berhasil tetapi update request gagal | Tandai sebagai exception operasional dan rekonsiliasi melalui admin; jangan mengulangi transfer secara otomatis. |

Untuk operasi keuangan yang terdiri dari beberapa update, RPC PostgreSQL adalah pilihan yang lebih aman daripada dua request browser berturut-turut. RPC dapat mengunci row, memeriksa status lama, menulis status baru, dan membuat audit event dalam satu transaksi.

## 14. Referensi implementasi repository

| Komponen | Lokasi |
|---|---|
| SQL marketplace jasa | [`supabase/bootstrap/36_20260925010000_service_marketplace.sql`](../supabase/bootstrap/36_20260925010000_service_marketplace.sql) |
| SQL sengketa jasa | [`supabase/bootstrap/37_20260925011000_service_disputes.sql`](../supabase/bootstrap/37_20260925011000_service_disputes.sql) |
| Katalog dan profil jasa | [`src/pages/ServicesPage.tsx`](../src/pages/ServicesPage.tsx) |
| Dashboard escrow dan laporan | [`src/pages/admin/AdminServicesPage.tsx`](../src/pages/admin/AdminServicesPage.tsx) |
| Dashboard resolusi sengketa | [`src/pages/admin/AdminServiceDisputesPage.tsx`](../src/pages/admin/AdminServiceDisputesPage.tsx) |
| Riwayat penyedia jasa | [`src/pages/ServiceProviderHistoryPage.tsx`](../src/pages/ServiceProviderHistoryPage.tsx) |
| Routing | [`src/App.tsx`](../src/App.tsx) |
| Menu admin | [`src/components/admin/AdminSidebar.tsx`](../src/components/admin/AdminSidebar.tsx) |

## 15. Checklist integrasi

Sebelum mengaktifkan integrasi di production, pastikan hal berikut sudah dipenuhi:

- Session Supabase dan publishable key dikonfigurasi.
- Bootstrap SQL dijalankan berurutan, terutama file marketplace jasa sebelum file sengketa jasa.
- Storage bucket private untuk bukti transfer dan evidence sudah tersedia.
- Signed URL digunakan untuk menampilkan file private.
- Perhitungan fee dipindahkan ke server-side atau RPC atomik.
- Pembuatan payout dilakukan satu kali per request.
- Transfer bank aktual memiliki nomor referensi yang disimpan pada `service_payouts.note` atau ledger khusus.
- Admin action diverifikasi melalui audit log.
- Transisi `REFUND_APPROVED` dan `RELEASE_APPROVED` diuji bersama request, payout, dan notifikasi.
- Retry jaringan tidak menghasilkan payout atau refund ganda.
- Laporan bulanan direkonsiliasi dengan mutasi rekening admin.
- Sengketa yang sudah memiliki keputusan tidak dapat kembali ke status aktif tanpa prosedur koreksi admin.

## References

[1]: https://supabase.com/docs/guides/database/postgres/row-level-security "Supabase Row Level Security"
[2]: https://supabase.com/docs/reference/javascript/select "Supabase JavaScript select()"
[3]: https://supabase.com/docs/reference/javascript/insert "Supabase JavaScript insert()"
[4]: https://supabase.com/docs/reference/javascript/update "Supabase JavaScript update()"
[5]: https://supabase.com/docs/guides/storage/access-control "Supabase Storage Access Control"
[6]: https://supabase.com/docs/guides/auth/sessions "Supabase Auth Sessions"
