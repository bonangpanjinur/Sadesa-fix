# Audit Alur Upload Bukti Pembayaran

**Tanggal:** 11 Oktober 2026  
**Scope:** Marketplace transfer manual — guest checkout dan user login  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Commit policy read terbaru:** `346b47de`

## Ringkasan eksekutif

Alur upload terdiri dari dua langkah yang harus berhasil secara berurutan:

1. Frontend mengunggah object ke bucket private `payment-proofs`.
2. Frontend mendaftarkan path object ke `orders.payment_proof_url` melalui RPC.

Untuk **user login**, desain path, RPC, dan policy upload sudah konsisten secara umum.

Untuk **guest**, terdapat blocker kontrak database:

> Frontend menyimpan path relatif bucket, misalnya `orders/{order_id}/{token_hash}/{filename}`, tetapi trigger `enforce_guest_checkout_payment_contract()` masih memvalidasi format URL yang mengandung `/payment-proofs/orders/...`.

Akibatnya upload object dapat berhasil, tetapi update order dapat ditolak oleh trigger. Kode kemudian mencoba menghapus object, namun guest tidak memiliki policy DELETE, sehingga berpotensi meninggalkan orphan object.

Selain itu, guest tidak dapat menampilkan kembali bukti yang sudah diunggah setelah reload karena bucket private tidak memberikan akses SELECT kepada role `anon`.

---

## 1. Alur user login

### 1.1 Membuka halaman pembayaran

`PaymentConfirmationPage`:

- Mengambil order dengan:

  ```ts
  .eq('id', orderId)
  .eq('buyer_id', user.id)
  ```

- Mengambil `payment_proof_url` dari order.
- Mengirim `guestAccessToken: undefined` ke `PaymentProofUpload`.

**Status:** Baik. Order dibatasi ke buyer yang sedang login.

### 1.2 Validasi file di browser

`PaymentProofUpload` memanggil:

```ts
validateFile(file, 5)
```

Validasi saat ini:

- MIME yang diterima: `image/jpeg`, `image/png`, `image/webp`, `image/gif`.
- Ukuran maksimum: 5 MB.
- Input HTML hanya mengiklankan JPG, PNG, dan WebP; GIF diterima oleh helper tetapi tidak ditampilkan sebagai opsi input.

**Catatan keamanan:** MIME type dan ukuran dari browser bukan trust boundary. Upload policy database membatasi path dan aktor, tetapi tidak memvalidasi magic bytes/isi file di server.

### 1.3 Path object

Karena tidak ada guest token, frontend membuat path prefix:

```text
orders/{order_id}
```

`uploadFile()` menambahkan nama object:

```text
orders/{order_id}/{timestamp}-{random}.{extension}
```

Contoh:

```text
orders/72d48326-9191-48e0-9959-b269d7d84490/1791718790047-91l2d.png
```

**Status:** Konsisten dengan policy authenticated marketplace upload.

### 1.4 Upload Storage

Frontend memanggil:

```ts
supabase.storage
  .from('payment-proofs')
  .upload(objectName, file, { cacheControl: '3600', upsert: false })
```

Policy yang seharusnya berlaku:

```sql
public.can_manage_payment_proof(name)
```

Fungsi tersebut memeriksa:

- user sudah authenticated;
- path dimulai dengan `orders`;
- order cocok;
- `orders.buyer_id = auth.uid()`;
- payment method adalah `TRANSFER`.

**Status:** Baik setelah policy upload production dipastikan menerapkan policy canonical.

### 1.5 Menyimpan path ke order

Frontend memanggil:

```ts
supabase.rpc('buyer_submit_payment_proof', {
  p_order_id: orderId,
  p_payment_proof_url: storedProofPath,
})
```

RPC memeriksa buyer dan status order, lalu menyimpan path.

**Temuan:** RPC login belum melakukan validasi ketat bahwa `p_payment_proof_url` benar-benar merupakan path canonical milik order. Storage upload memang dibatasi, tetapi RPC sebaiknya tetap menolak URL/path arbitrary agar kolom database tidak dapat diisi dengan referensi eksternal atau path order lain.

### 1.6 Jika RPC gagal

Frontend mencoba:

```ts
await deleteFile('payment-proofs', result.path)
```

Untuk user login, delete dapat berhasil hanya jika policy DELETE mengizinkan buyer/admin terhadap object tersebut.

**Catatan:** Jika delete gagal, object orphan tetap ada. Perlu job cleanup atau RPC cleanup yang aman.

### 1.7 Menampilkan ulang bukti

Frontend memanggil `getPaymentProofSignedUrl()`.

- Signed URL dibuat dari path relatif.
- Buyer diizinkan oleh `can_access_payment_proof()`.
- Merchant juga diizinkan jika `merchants.user_id = auth.uid()`.

Policy merchant production sebelumnya salah karena menggunakan `m.name` alih-alih path object. Perbaikannya sudah dibuat pada migration `104_20261011234500_fix_payment_proof_read_policy.sql` di commit `346b47de`.

---

## 2. Alur guest

### 2.1 Membuka halaman pembayaran

`PaymentConfirmationPage` mengambil token dari:

1. query parameter `guest_token`, atau
2. local guest checkout access.

Kemudian memanggil RPC:

```ts
get_guest_order_payment_context(orderId, guestToken)
```

RPC memvalidasi hash token dan masa berlaku token.

**Status:** Baik secara desain. Token mentah tidak disimpan sebagai hash di database flow checkout.

### 2.2 Path object guest

Frontend menghitung:

```ts
const tokenHash = await sha256Hex(guestAccessToken)
```

Lalu membuat path prefix:

```text
orders/{order_id}/{token_hash}
```

Object aktual menjadi:

```text
orders/{order_id}/{token_hash}/{timestamp}-{random}.{extension}
```

**Status:** Baik. Path mengikat object ke order dan hash token, bukan token mentah.

### 2.3 Policy upload guest

Migration `103_20261011223000_guest_payment_proof_upload.sql` memeriksa:

- `auth.role() = 'anon'`;
- prefix `orders`;
- tepat 4 segmen path;
- token hash 64 karakter hex;
- order memiliki `buyer_id IS NULL`;
- hash sama dengan `orders.guest_access_token_hash`;
- token belum expired;
- payment method `TRANSFER`;
- order belum selesai/dibatalkan.

**Status:** Baik dan cukup ketat untuk INSERT.

### 2.4 Menyimpan path guest ke order — BLOCKER

Frontend menyimpan path relatif:

```text
orders/{order_id}/{token_hash}/{filename}
```

Namun trigger pada migration `68_20261002210000_guest_checkout_hardening.sql` memvalidasi substring:

```sql
'/payment-proofs/orders/' || NEW.id || '/' || NEW.guest_access_token_hash || '/'
```

Trigger tersebut mengharapkan URL seperti:

```text
https://.../storage/v1/object/public/payment-proofs/orders/{order_id}/{token_hash}/{filename}
```

Padahal frontend sekarang menyimpan:

```text
orders/{order_id}/{token_hash}/{filename}
```

**Dampak:**

1. Storage INSERT dapat berhasil.
2. RPC `guest_submit_payment_proof()` meng-update `orders`.
3. Trigger dapat melempar `Guest payment proof is invalid`.
4. Frontend mencoba menghapus object.
5. Role `anon` tidak memiliki policy DELETE pada object payment proof.
6. Object orphan dapat tertinggal di bucket.

**Severity:** High — alur guest dapat terlihat gagal meskipun upload Storage berhasil.

### 2.5 Guest melihat bukti setelah upload

Setelah upload sukses, komponen menjalankan `getPaymentProofSignedUrl()` dengan client yang masih anonymous.

Bucket private dan policy read marketplace hanya berlaku untuk role `authenticated`. Migration guest terbaru secara eksplisit hanya membuat policy INSERT anon, bukan SELECT anon.

**Dampak:**

- Guest tidak dapat membaca ulang bukti melalui signed URL setelah reload.
- Pada render awal, komponen menggunakan fallback `proofUrl` mentah jika signed URL belum tersedia. Karena `proofUrl` adalah path relatif private, browser akan menganggapnya sebagai relative URL halaman dan gambar gagal dimuat.
- Ini berbeda dengan privacy intent yang melarang anonymous read, tetapi UX perlu ditangani secara eksplisit.

**Severity:** Medium/High tergantung requirement produk.

### 2.6 Guest mengganti bukti

UI mengizinkan “Ganti Bukti Pembayaran” ketika order belum selesai atau bukti ditolak.

Setiap upload membuat object baru. Object lama tidak otomatis dihapus setelah object baru berhasil disimpan.

**Dampak:** orphan object dan biaya Storage bertambah, terutama bila guest mengulang upload beberapa kali.

---

## 3. Temuan lintas alur

| ID | Severity | Temuan | Dampak |
|---|---|---|---|
| PP-01 | High | Trigger guest mengharapkan URL lengkap, frontend menyimpan path relatif | Guest upload dapat gagal pada langkah RPC setelah Storage upload sukses |
| PP-02 | High | Guest tidak punya DELETE setelah RPC gagal | Object orphan tertinggal |
| PP-03 | Medium/High | Guest tidak punya mekanisme read yang terotorisasi setelah upload | Bukti guest tidak tampil ulang setelah reload |
| PP-04 | Medium | `buyer_submit_payment_proof` belum memvalidasi path canonical secara ketat | Database dapat menyimpan referensi path arbitrary; resolver memang menolak sebagian, tetapi kontrak server lemah |
| PP-05 | Medium | Replacement tidak membersihkan object lama | Orphan object dan pemborosan Storage |
| PP-06 | Medium | Validasi hanya mengandalkan MIME/size browser | File spoofing dapat melewati validasi client |
| PP-07 | Low | `getPublicUrl()` dipanggil untuk bucket private | URL publik yang dihasilkan tidak dapat dipakai; menambah kebingungan implementasi |
| PP-08 | Low | Fallback `src={proofUrl}` memakai path private mentah | Browser melakukan request relative URL yang pasti salah jika signed URL belum tersedia |

---

## 4. Rekomendasi perbaikan

### Prioritas P0 — perbaiki kontrak guest path

Ubah trigger agar menerima canonical bucket-relative path:

```text
orders/{order_id}/{guest_token_hash}/{filename}
```

Validasi sebaiknya menggunakan segment/path yang terstruktur, bukan substring URL. Trigger harus memastikan:

- segmen pertama `orders`;
- segmen kedua adalah order UUID;
- segmen ketiga sama dengan `guest_access_token_hash`;
- segmen keempat tidak kosong;
- order guest masih valid dan transfer-only.

Jangan hanya menambahkan `position('orders/...')` tanpa parsing karena substring dapat dipalsukan.

### Prioritas P0 — sediakan cleanup server-side

Karena guest tidak boleh diberi DELETE umum, gunakan salah satu:

1. RPC `guest_delete_payment_proof(p_order_id, p_guest_access_token, p_path)` yang memvalidasi token dan path lalu menghapus via mekanisme server-side; atau
2. Jangan delete dari browser guest; tandai object orphan dan bersihkan lewat scheduled service-role job.

### Prioritas P1 — pilih desain read guest secara eksplisit

Pilihan aman:

- tetap melarang guest read dan jangan menampilkan preview setelah upload; atau
- buat Edge Function/RPC terkontrol yang memvalidasi guest token lalu mengeluarkan signed URL singkat.

Jangan membuat bucket public dan jangan menambahkan SELECT anon berbasis order ID saja.

### Prioritas P1 — validasi path pada RPC login dan guest

RPC harus menerima hanya path canonical yang sesuai order dan aktor. Untuk login:

```text
orders/{order_id}/{filename}
```

Untuk guest:

```text
orders/{order_id}/{token_hash}/{filename}
```

Path harus berasal dari bucket yang benar dan tidak boleh berupa arbitrary external URL.

### Prioritas P2 — replacement cleanup

Setelah object baru dan RPC berhasil:

- simpan path lama;
- hapus path lama melalui mekanisme server-side yang sesuai;
- jika cleanup gagal, catat observability event untuk job cleanup.

### Prioritas P2 — perbaiki state UI

Jangan gunakan path private mentah sebagai `img.src` fallback. Gunakan state eksplisit:

- loading signed URL;
- loaded;
- unavailable;
- retry.

---

## 5. Acceptance test yang disarankan

### Guest — sukses

- Guest transfer order valid dapat upload PNG/JPG/WebP.
- Storage object dibuat di `orders/{id}/{hash}/{file}`.
- RPC menyimpan path relatif tersebut.
- Trigger menerima path relatif.
- Merchant dapat membuat signed URL dan melihat image.

### Guest — keamanan

- Guest A tidak dapat upload ke order B.
- Guest dengan token expired ditolak.
- Guest tidak dapat mengubah `payment_proof_url` dengan path order lain.
- Guest tidak dapat membaca bukti order lain.
- Guest tidak memiliki DELETE arbitrary.

### Login — sukses

- Buyer dapat upload ke order miliknya sendiri.
- Buyer tidak dapat upload ke order buyer lain.
- Merchant pemilik order dapat membuat signed URL.
- Admin dapat membuat signed URL.
- User non-owner mendapat penolakan yang tidak membocorkan object.

### Failure/cleanup

- Jika RPC gagal setelah upload, object tidak dibiarkan tanpa strategi cleanup.
- Replacement tidak meninggalkan object lama tanpa batas.
- Signed URL error menampilkan state retry, bukan raw relative path.

---

## Kesimpulan

- **User login:** alur upload sudah hampir benar; masalah production yang ditemukan sebelumnya adalah policy SELECT merchant yang salah dan sudah disiapkan perbaikannya pada commit `346b47de`.
- **Guest:** path Storage dan policy INSERT sudah dirancang baik, tetapi trigger database masih tidak kompatibel dengan path relatif yang sekarang disimpan frontend. Ini adalah blocker utama yang harus diperbaiki sebelum guest payment proof dianggap stabil.
- **Kebijakan read guest:** perlu keputusan produk/keamanan. Bucket private sebaiknya dipertahankan; jika guest perlu preview, gunakan signed URL singkat berbasis token tervalidasi, bukan public bucket.
