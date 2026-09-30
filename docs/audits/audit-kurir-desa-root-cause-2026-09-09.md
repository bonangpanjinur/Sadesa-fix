# Audit Akar Masalah Kurir Desa

**Tanggal:** 9 September 2026  
**Scope:** Merchant memilih Kurir Desa, pembuatan tawaran, kurir menerima/menolak, dan transisi status order.

## Kesimpulan utama

Kegagalan bukan terutama berasal dari tombol UI. Akar masalahnya adalah **kontrak database dan pipeline deployment tidak konsisten**. Repository memiliki beberapa migration workflow order yang dibuat di `supabase/bootstrap`, tetapi generator bundle deployment mengambil sumber dari `archive/supabase/migrations`. Akibatnya, migration RPC terbaru dapat berada di repository tetapi belum pernah diterapkan ke database production.

Hal ini menjelaskan mengapa frontend memanggil `merchant_transition_order` atau `create_delivery_offer`, tetapi database production dapat memiliki signature lama, overload ganda, atau fungsi yang belum ada. PostgREST kemudian mengembalikan HTTP 400 dan UI hanya menampilkan pesan umum “Gagal mengubah status”.

## Temuan terverifikasi

| Prioritas | Temuan | Dampak |
|---|---|---|
| P0 | `scripts/build-bootstrap-bundles.py` membaca `archive/supabase/migrations`, bukan migration tambahan langsung di `supabase/bootstrap`. | File workflow order 43–46 dapat tidak ikut bundle deployment. |
| P0 | Ada dua definisi/signature `merchant_transition_order`: versi 4 parameter pada migration `44_20260909190000...` dan versi 3 parameter pada `44_20260909193000...`. | PostgREST dapat gagal resolve RPC dan mengembalikan HTTP 400. |
| P0 | Migration `46_20260909203000_remove_merchant_transition_overload.sql` baru ada di working tree/repository dan harus benar-benar dijalankan pada database production. | Overload lama tetap aktif jika migration belum diterapkan. |
| P1 | Frontend merchant memakai `create_delivery_offer`, sedangkan migration lama memakai `merchant_offer_order_to_courier`. | Tawaran kurir gagal jika database belum memiliki RPC terbaru. |
| P1 | Frontend kurir memakai `respond_delivery_offer`, sedangkan migration lama memakai `courier_respond_to_order_offer`. | Tombol Ambil/Tolak gagal pada database dengan schema lama. |
| P1 | Status `COURIER_ACCEPTED` sebelumnya tidak masuk query order aktif dashboard kurir. | Kurir dapat menerima tawaran tetapi order tidak muncul untuk pickup. |
| P1 | Dashboard kurir sebelumnya melakukan update langsung ke tabel `orders`. | Transisi dapat ditolak RLS/constraint dan riwayat status tidak tercatat. |
| P2 | Terdapat duplicate timestamp prefix `44` pada migration order workflow. | Urutan masih deterministik secara lexical, tetapi rawan salah urut dan menyulitkan audit. |
| P2 | Error frontend hanya menampilkan pesan generik pada beberapa handler. | Pesan database yang membedakan fungsi hilang, sehingga diagnosis lambat. |

## Alur yang seharusnya aktif

1. Merchant berada pada status `PROCESSED` atau `READY` dan memilih Kurir Desa.
2. Merchant memanggil `create_delivery_offer(order_id, courier_id)`.
3. Database memvalidasi merchant, order, courier aktif/approved/available, serta daftar courier yang pernah menolak.
4. Order menjadi `ASSIGNED`, assignment menjadi `OFFERED`.
5. Kurir melihat row `delivery_assignments` berstatus `OFFERED`.
6. Kurir memanggil `respond_delivery_offer(assignment_id, true/false)`.
7. Jika menerima, assignment menjadi `ACCEPTED` dan order menjadi `COURIER_ACCEPTED`.
8. Kurir memanggil `courier_transition_order` untuk `PICKED_UP`, `SENT`, lalu `DELIVERED`.
9. Setiap perubahan dicatat pada `order_status_history`.

## Pemeriksaan yang harus dilakukan pada database production

Jalankan pemeriksaan read-only berikut pada SQL editor Supabase:

```sql
select n.nspname as schema_name,
       p.proname,
       pg_get_function_identity_arguments(p.oid) as identity_arguments,
       pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'merchant_transition_order',
    'create_delivery_offer',
    'respond_delivery_offer',
    'courier_transition_order'
  )
order by p.proname, identity_arguments;
```

Hasil yang benar harus hanya memiliki satu signature merchant berikut:

```text
merchant_transition_order(uuid, text, text)
```

dan harus memiliki fungsi:

```text
create_delivery_offer(uuid, uuid)
respond_delivery_offer(uuid, boolean, text)
courier_transition_order(uuid, text)
```

Periksa juga migration order workflow sudah diterapkan, termasuk kolom:

```sql
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'orders'
  and column_name in (
    'courier_rejected_ids', 'courier_accepted_at', 'status_updated_at',
    'self_delivery_attempt', 'self_delivery_fee_amount', 'self_delivery_fee_status'
  );
```

## Catatan deployment

`bash scripts/validate-migrations.sh` berhasil memvalidasi 48 file SQL, tetapi hanya memvalidasi file yang ada di `supabase/bootstrap`; validasi tersebut **tidak membuktikan migration sudah diterapkan ke production**. Manifest saat ini berakhir pada bundle `37_...` dan generator bundle memakai `archive/supabase/migrations`. Karena itu, menambahkan file hanya ke `supabase/bootstrap` tidak cukup untuk deployment yang menggunakan bundle archive.

Solusi deployment yang benar harus memilih salah satu pendekatan dan menerapkannya konsisten:

1. Menempatkan migration incremental 43–46 pada sumber migration resmi yang digunakan pipeline deployment, kemudian regenerasi manifest/bundle; atau
2. Menjalankan migration 43–46 secara eksplisit pada database production melalui migration runner resmi, lalu memastikan metadata migration tercatat.

Jangan menjalankan bootstrap penuh pada database production yang sudah memiliki history tanpa mengikuti prosedur migration incremental.

## Warning console yang bukan akar masalah

- `offline_sync capability_registration_failed / NotAllowedError`: permission browser; tidak menyebabkan RPC order gagal.
- `beforeinstallpromptevent.preventDefault`: PWA install flow; tidak menyebabkan status order gagal.
- Manifest `blob:` URL invalid: masalah preview/PWA manifest; tidak menyebabkan RPC 400.
- `DialogContent` missing Description: warning aksesibilitas; perlu diperbaiki, tetapi bukan penyebab transaksi Kurir Desa gagal.

## Rekomendasi prioritas

**P0:** Pastikan migration workflow benar-benar diterapkan pada production dan hapus overload lama `merchant_transition_order(uuid,text,text,boolean)`.  
**P0:** Setelah deployment, refresh schema cache PostgREST dan verifikasi signature RPC dengan query di atas.  
**P1:** Uji satu order nyata dari status `PROCESSED`: create offer, reject, offer courier lain, accept, pickup, sent, delivered.  
**P1:** Ubah handler frontend agar selalu menampilkan `error.message`, `error.code`, dan `error.details` pada mode non-production/log telemetry.  
**P2:** Satukan sumber migration dan hilangkan duplicate timestamp prefix agar masalah ini tidak berulang.

**Status audit:** akar masalah teridentifikasi; laporan ini tidak mengubah implementasi aplikasi maupun database production.


## Temuan final dari hasil query production dan tracing UI

Query production yang diberikan sudah menunjukkan signature RPC yang benar. Jadi overload RPC **bukan lagi masalah aktif** pada database saat ini.

Akar error yang tersisa ditemukan pada `src/pages/merchant/MerchantOrdersPage.tsx`:

```tsx
onClick={async () => {
  await handleUpdateStatus(selectedOrder.id, 'PROCESSED');
  setDetailDialogOpen(false);
  const order = orders.find(o => o.id === selectedOrder.id);
  if (order) viewOrderDetail({ ...order, status: 'PROCESSED' } as OrderRow);
}}
```

Blok tersebut berada di tampilan order yang **sudah berstatus `PROCESSED`**. Saat merchant menekan **Kurir Desa**, aplikasi kembali memanggil:

```text
merchant_transition_order(PROCESSED order, PROCESSED)
```

RPC canonical memang menolak transisi ini, sehingga Supabase mengembalikan HTTP 400. Setelah error, kode tetap melanjutkan proses karena hasil `handleUpdateStatus` tidak digunakan sebagai guard, sehingga UI terlihat seolah pemilihan kurir gagal secara umum.

### Alur yang benar

Untuk order yang sudah `PROCESSED`, klik **Kurir Desa** harus langsung membuka pemilih kurir dan memanggil:

```text
create_delivery_offer(order_id, courier_id)
```

Tidak boleh memanggil `merchant_transition_order(..., 'PROCESSED')` lagi.

### Perbaikan code yang diperlukan

1. Hapus pemanggilan `await handleUpdateStatus(selectedOrder.id, 'PROCESSED')` pada tombol Kurir Desa di blok `selectedOrder.status === 'PROCESSED'`.
2. Buka dialog assignment secara langsung dari order `selectedOrder`.
3. Jika tetap mempertahankan callback async, hentikan alur jika hasil transisi gagal; jangan membuka dialog setelah error.
4. Tambahkan guard di frontend agar status tujuan sama dengan status sekarang tidak dikirim ke RPC.
5. Perbaiki `OrderDetailsDialog` dengan pola yang sama jika tombol status `PROCESSED` masih meneruskan `SENT` langsung untuk order INTERNAL; order INTERNAL harus masuk pemilihan Kurir Desa, bukan langsung `SENT`.

Dengan hasil query production yang diberikan, **temuan PROCESSED → PROCESSED adalah penyebab paling langsung dan terverifikasi dari HTTP 400 saat klik Kurir Desa**.
