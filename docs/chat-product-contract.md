# Kontrak Produk Chat SaDesa

**Status:** Disetujui untuk implementasi Fase 0–1  
**Tanggal:** 9 September 2026

## Cakupan MVP

Chat dua arah mendukung empat hubungan bisnis. Chat order mendukung pembeli–pedagang, pembeli–kurir, dan pedagang–kurir. Chat perjalanan mendukung penumpang–ojek melalui `ride_request_id`. Chat direct mendukung pembeli–pedagang dan bersifat unik untuk satu pasangan pembeli–pedagang.

Chat pra-order menggunakan konteks `direct`. Chat tersebut tidak memakai `order_id`. Chat ride tidak boleh menggunakan `order_id` sebagai pengganti `ride_request_id`.

## Participant dan authorization

Participant ditentukan server-side dari relasi bisnis. Client tidak boleh menentukan role, sender, receiver, atau participant. Buyer hanya dapat masuk ke direct conversation miliknya dengan merchant tertentu. Merchant tidak dapat melihat direct conversation buyer lain.

Untuk order chat, buyer, merchant terkait, dan courier yang ditugaskan ditentukan dari order. Untuk ride chat, passenger dan courier yang ditugaskan ditentukan dari ride request. Sebelum courier menerima ride, tidak ada direct chat passenger–courier.

## Message contract

MVP hanya mendukung pesan teks. Body wajib berisi 1–4.000 karakter setelah trim. Pesan immutable setelah insert. Client menggunakan `client_message_id` untuk retry idempotent. Attachment belum termasuk MVP.

## Retention contract

Pesan normal selama 0–13 hari sejak `created_at`. Pada hari ke-14, pesan masuk soft delete dan tidak lagi menampilkan isi kepada pengguna. Pada hari ke-30, row pesan dihapus permanen. Attachment, jika kelak diaktifkan, juga harus dihapus pada hard-delete.

Pengecualian untuk dispute, fraud, chargeback, atau kewajiban hukum memerlukan legal hold yang disetujui sebelum hard-delete. Retention tidak bergantung pada status order selesai atau ride selesai.

## UI terminology

| Konteks teknis | Label UI |
|---|---|
| `buyer_merchant` | Pembeli – Pedagang |
| `buyer_courier` | Pembeli – Kurir |
| `merchant_courier` | Pedagang – Kurir |
| `passenger_courier` | Penumpang – Ojek |

## Limits dan abuse controls

Batas awal adalah 30 pesan per menit per user pada conversation dan 4.000 karakter per pesan. Rate limit ditegakkan server-side. Report, block, dan attachment bukan bagian dari Fase 0–1 dan harus masuk hardening lanjutan.

## Acceptance criteria Fase 0

1. Semua context dan conversation type memiliki aturan participant.
2. Retention 14/30 hari tercatat sebagai kontrak resmi.
3. UI memakai istilah domain yang konsisten.
4. Kontrak memiliki representasi code dan unit test.
