# Audit Alur Refund End-to-End

**Tanggal:** 18 September 2026  
**Ruang lingkup:** Pengajuan refund oleh pembeli, respons merchant, mediasi admin, keputusan refund, dan settlement ke pembeli.

## Kesimpulan

Alur refund sudah memiliki fondasi yang benar: pembeli membuat request melalui RPC, merchant memberikan respons melalui RPC, admin memproses keputusan melalui RPC atomic, dan refund yang disetujui membuat settlement intent yang idempotent. Namun, sebelum perbaikan ini, alur belum memberikan batas yang cukup kuat pada mediasi admin dan belum membedakan status keputusan refund dari status pencairan dana.

Perbaikan pada commit ini menutup dua celah utama. Update status mediasi admin sekarang melewati RPC state guard dan tidak lagi melakukan update langsung dari frontend. Buyer dan merchant sekarang dapat melihat apakah refund yang disetujui masih menunggu pencairan, sudah selesai, atau gagal.

## Alur yang seharusnya

| Tahap | Aktor | Status dispute | Status refund | Hasil yang diharapkan |
|---|---|---|---|---|
| Pengajuan | Pembeli | `OPEN` | `PENDING` | Request tersimpan dan hanya dapat dilihat oleh buyer terkait, merchant terkait, dan admin. |
| Respons | Merchant | `MERCHANT_RESPONDED` | `PENDING` | Respons merchant tersimpan bersama waktu respons dan dapat dibaca buyer serta admin. |
| Mediasi | Admin | `IN_MEDIATION` | `PENDING` | Admin meninjau bukti, alasan, dan respons merchant tanpa mengubah keputusan finansial. |
| Persetujuan | Admin | `RESOLVED_REFUND` | `APPROVED` | Settlement intent dibuat dengan idempotency key. Dana belum dianggap cair. |
| Pencairan berhasil | Worker/provider | `RESOLVED_REFUND` | `APPROVED` | `settlement_status = COMPLETED`, order menjadi `REFUNDED`, dan saldo merchant dikurangi satu kali. |
| Pencairan gagal | Worker/provider | `RESOLVED_REFUND` | `APPROVED` | `settlement_status = FAILED`; kasus tetap terlihat sebagai refund disetujui tetapi perlu retry atau tindakan operasional. |
| Penolakan | Admin | `RESOLVED_REJECTED` | `REJECTED` | Tidak ada settlement dan alasan keputusan terlihat oleh buyer. |
| Penutupan | Admin | `CLOSED` | Tidak berubah | Kasus ditutup setelah keputusan dan pencairan selesai atau telah ditangani secara operasional. |

## Temuan audit

### 1. Update status mediasi admin dilakukan langsung dari frontend

Sebelumnya, Admin Dispute Center memanggil `.update({ dispute_status, admin_notes })` untuk status non-final. Pola ini melewati state transition guard dan tidak menyediakan satu kontrak server untuk memeriksa apakah kasus sudah terminal. Perbaikannya adalah RPC `update_refund_dispute_status`, yang mengunci baris refund, memvalidasi status mediasi, menolak pembukaan kembali kasus yang telah resolved, dan mewajibkan catatan ketika kasus ditutup.

### 2. Status `APPROVED` belum berarti uang sudah diterima buyer

Settlement hardening telah memisahkan `status = APPROVED` dari `settlement_status = PENDING`, tetapi UI buyer dan merchant sebelumnya hanya menampilkan status persetujuan. Akibatnya, buyer dapat mengira refund sudah cair padahal provider belum menyelesaikan transfer. UI sekarang menampilkan tiga kondisi pencairan: menunggu, berhasil, dan gagal.

### 3. Kegagalan pencairan masih membutuhkan operasi worker atau admin

RPC `complete_refund_settlement` sudah idempotent untuk callback sukses yang diulang. Namun, repository ini belum menunjukkan worker/provider callback yang menjalankan RPC tersebut atau tombol retry untuk settlement gagal. Karena itu, `FAILED` belum otomatis pulih. Hal ini harus diselesaikan pada integrasi provider dengan idempotency key `refund:<refund_request_id>` dan retry terkontrol.

### 4. Bukti refund masih menggunakan URL publik

Halaman buyer dan merchant menampilkan `evidence_urls` secara langsung. Audit sebelumnya juga mencatat bahwa bucket bukti seharusnya private dengan signed URL. Perubahan ini belum dilakukan pada commit ini karena membutuhkan migrasi storage dan verifikasi policy bucket di environment Supabase yang aktif.

### 5. Notifikasi SLA belum menjadi bagian dari state transition

Merchant UI menampilkan pesan bahwa respons diharapkan dalam 2x24 jam, tetapi belum terlihat scheduler atau notifikasi yang mengeskalasi request yang melewati SLA. Tanpa job tersebut, `OPEN` dapat tertahan tanpa jejak operasional selain daftar di dashboard.

## Perubahan pada commit ini

Perubahan database menambahkan `update_refund_dispute_status(uuid, text, text)`. Admin UI menggunakan RPC ini untuk transisi `OPEN`, `IN_MEDIATION`, dan `CLOSED`, sedangkan keputusan `RESOLVED_REFUND` dan `RESOLVED_REJECTED` tetap menggunakan `process_refund_decision` yang membuat settlement atau menolak request secara atomic.

Buyer UI menampilkan `settlement_status` setelah refund disetujui. Merchant UI menampilkan status pencairan pada detail komplain. Perubahan ini mencegah status persetujuan disalahartikan sebagai konfirmasi dana sudah diterima.

## Skenario uji minimum

1. Buyer membuat request valid dan request muncul sebagai `OPEN` atau `PENDING`.
2. Merchant mengirim respons dan request berubah menjadi `MERCHANT_RESPONDED`.
3. Admin mengubah request menjadi `IN_MEDIATION` melalui RPC, bukan update tabel langsung.
4. Admin menyetujui request dan hanya satu `refund_settlements` tercipta.
5. Buyer melihat status menunggu pencairan sebelum callback provider selesai.
6. Callback sukses yang sama dipanggil dua kali dan tidak mengurangi saldo merchant dua kali.
7. Callback gagal mengubah `settlement_status` menjadi `FAILED` dan tidak mengubah order menjadi `REFUNDED`.
8. Admin tidak dapat membuka kembali request yang sudah `RESOLVED_REFUND` atau `RESOLVED_REJECTED`.
9. Admin tidak dapat menutup kasus tanpa catatan.
10. Buyer tidak dapat melihat refund milik buyer lain dan merchant tidak dapat melihat merchant lain.

## Rekomendasi lanjutan

Prioritas berikutnya adalah menghubungkan callback provider dengan `complete_refund_settlement`, menambahkan retry settlement yang aman, serta memindahkan bukti refund ke bucket private. Setelah itu, tambahkan scheduler SLA untuk mengingatkan merchant dan membuat eskalasi otomatis ke admin.

## Referensi

[1]: https://github.com/bonangpanjinur/Sadesa-fix "Repository Sadesa-fix"
