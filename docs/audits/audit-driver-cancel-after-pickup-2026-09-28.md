# Audit Pembatalan Ojek oleh Driver Setelah Penjemputan

**Tanggal:** 28 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Ruang lingkup:** UI driver, RPC pembatalan, state machine ride, tracking penumpang, histori, earning, notifikasi, dan pemulihan tugas.

## Ringkasan eksekutif

Saat ini driver **memang dapat membatalkan perjalanan setelah penumpang dijemput**. Perilaku tersebut bukan hanya celah UI; backend juga secara eksplisit mengizinkannya.

Temuan paling penting:

- Tombol **Batalkan perjalanan** tampil pada status `ACCEPTED`, `PICKED_UP`, dan `IN_TRANSIT`.
- RPC `driver_cancel_ride` menerima ketiga status tersebut dan langsung mengubah ride menjadi terminal `CANCELED`.
- Setelah status `PICKED_UP`/`IN_TRANSIT`, tidak ada mekanisme otomatis untuk mencari driver pengganti.
- `driver_cancel_ride` tidak menulis histori status ride khusus dan tidak menyimpan identitas aktor pembatalan pada row ride; hanya `cancelled_at` dan `cancellation_reason` yang tersedia.
- Tidak ada kompensasi, refund/settlement policy, penalti driver, atau eskalasi insiden yang dipicu oleh pembatalan pasca-jemput.
- Penumpang menerima notifikasi, tetapi UI penumpang berhenti pada status batal dan tidak menawarkan pemulihan otomatis.

**Kesimpulan:** ini adalah risiko operasional **P0/P1**, karena penumpang sudah berada dalam kendaraan namun driver masih dapat mengakhiri perjalanan sepihak tanpa recovery terjamin.

## Bukti source

### 1. UI driver mengizinkan batal setelah pickup

`src/pages/courier/CourierRidesPage.tsx:451-454` menampilkan tombol batal untuk:

```ts
['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'].includes(activeRide.status)
```

Handler meminta alasan, lalu memanggil:

```ts
supabase.rpc('driver_cancel_ride', {
  p_ride_id: activeRide.id,
  p_reason: reason.trim(),
})
```

Tidak ada confirmation dialog khusus untuk status berisiko tinggi seperti `PICKED_UP` atau `IN_TRANSIT`; hanya `window.prompt` alasan.

### 2. Backend juga mengizinkan pembatalan pasca-jemput

Pada definisi `public.driver_cancel_ride` di bootstrap authoritative:

```sql
IF v_ride.status NOT IN ('ACCEPTED','PICKED_UP','IN_TRANSIT') THEN
  RAISE EXCEPTION 'Ride cannot be canceled from status %', v_ride.status;
END IF;
```

Kemudian ride langsung diubah menjadi terminal:

```sql
UPDATE public.ride_requests
SET status = 'CANCELED',
    cancelled_at = now(),
    cancellation_reason = v_reason,
    updated_at = now()
WHERE id = p_ride_id
RETURNING * INTO v_ride;
```

Artinya, membatasi tombol di frontend saja **tidak cukup**; guard RPC harus diubah.

### 3. State machine normal tidak menyediakan jalur batal setelah pickup

`transition_ride_status` hanya mengizinkan:

```text
ACCEPTED  -> PICKED_UP
PICKED_UP -> IN_TRANSIT
IN_TRANSIT -> COMPLETED
```

Pembatalan dikeluarkan dari RPC transisi normal dan dilakukan lewat RPC terpisah yang saat ini memperbolehkan semua status aktif, termasuk setelah pickup.

### 4. Penumpang tidak punya recovery otomatis

`RideTrackingPage.tsx` hanya mengizinkan pembatalan penumpang ketika statusnya:

```ts
const canCancel = ['SEARCHING', 'ACCEPTED'].includes(ride.status);
```

Setelah menerima notifikasi pembatalan driver, ride menjadi `CANCELED`, peta berhenti, dan tidak ada action untuk:

- mencari driver pengganti;
- mempertahankan tarif/booking;
- membuat insiden untuk admin;
- mengajukan refund atau kompensasi;
- menandai bahwa penumpang sudah ditinggalkan setelah pickup.

## Dampak bisnis dan operasional

| Prioritas | Temuan | Dampak |
|---|---|---|
| **P0** | Driver dapat membatalkan pada `PICKED_UP`/`IN_TRANSIT` | Penumpang dapat terlantar setelah masuk kendaraan; layanan tidak menjamin penyelesaian perjalanan |
| **P0** | Tidak ada reassign setelah pickup | Order berakhir terminal dan tidak ada driver pengganti yang otomatis menangani penumpang |
| **P1** | Tidak ada penalti/flag/incident workflow | Driver dapat berulang kali membatalkan pasca-jemput tanpa kontrol operasional yang terlihat |
| **P1** | Tidak ada histori status ride khusus | Sulit melakukan dispute, investigasi, SLA, dan rekonsiliasi siapa/kenapa membatalkan |
| **P1** | Tidak ada refund/compensation contract | Penanganan uang dan kompensasi penumpang menjadi manual/tidak terdefinisi |
| **P2** | Hanya alasan bebas sampai 500 karakter | Alasan tidak terstruktur sehingga sulit dianalisis dan dipakai untuk kebijakan |
| **P2** | Tidak ada confirmation khusus pasca-pickup | Risiko salah tekan atau pembatalan tanpa konfirmasi dampak serius |

## Rekomendasi kebijakan

### Opsi yang direkomendasikan untuk produksi

1. **Driver hanya boleh membatalkan sebelum pickup:** status `ACCEPTED` saja.
2. Setelah `PICKED_UP` atau `IN_TRANSIT`, tombol batal driver diganti menjadi **Laporkan masalah / Minta bantuan admin**.
3. RPC `driver_cancel_ride` menolak `PICKED_UP` dan `IN_TRANSIT` secara server-side.
4. Jika terjadi kecelakaan, kendaraan rusak, penumpang tidak aman, atau keadaan darurat, driver membuat incident yang dapat diputuskan admin.
5. Admin dapat membatalkan dengan alasan terstruktur dan sistem membuat outcome yang jelas: refund, kompensasi, reassign, atau penutupan insiden.

### Jika bisnis tetap ingin mengizinkan pembatalan darurat

Jangan mengubahnya menjadi `CANCELED` biasa. Gunakan alur khusus:

```text
PICKED_UP / IN_TRANSIT
  -> DRIVER_INCIDENT_REPORTED
  -> ADMIN_REVIEW
  -> REASSIGN_PENDING / REFUND_PENDING / COMPLETED_BY_ADMIN
```

Alur minimum harus mencatat:

- `cancelled_by`/`reported_by`;
- reason code terstruktur;
- catatan bebas;
- timestamp dan lokasi terakhir driver;
- bukti foto atau lampiran bila relevan;
- incident ID;
- status refund/kompensasi;
- apakah penumpang berhasil dipindahkan ke driver baru.

## Rencana perbaikan yang disarankan

### P0 — Tutup pembatalan pasca-pickup

- Ubah RPC agar hanya menerima `ACCEPTED` untuk pembatalan biasa.
- Sembunyikan tombol batal pada `PICKED_UP` dan `IN_TRANSIT`.
- Tambahkan test yang memastikan authenticated driver tidak dapat membatalkan pada dua status tersebut.
- Tambahkan confirmation dialog untuk pembatalan pada `ACCEPTED`.

### P1 — Sediakan recovery

- Tambahkan RPC incident driver setelah pickup.
- Notifikasi penumpang dengan status yang jelas, bukan hanya “dibatalkan”.
- Buat queue admin untuk insiden aktif.
- Tambahkan jalur refund/kompensasi yang idempotent.
- Tentukan apakah reassign pasca-pickup aman secara bisnis dan bagaimana handoff penumpang diverifikasi.

### P1 — Perkuat audit dan anti-abuse

- Tambahkan `ride_status_history` atau gunakan tabel event yang sudah ada secara konsisten.
- Catat actor, previous status, new status, reason code, free-text note, dan metadata.
- Tambahkan counter pembatalan driver dan threshold review/suspend.
- Pastikan pembatalan tidak membuat earning `PENDING`; earning saat ini hanya dibuat pada `COMPLETED`, tetapi outcome pembatalan tetap perlu tercatat untuk laporan performa.

## Keputusan yang dibutuhkan sebelum implementasi

Perubahan guard server-side bergantung pada kebijakan bisnis:

- **Default aman yang direkomendasikan:** driver tidak dapat membatalkan setelah `PICKED_UP`; gunakan incident/admin workflow.
- **Alternatif:** tetap mengizinkan pembatalan darurat, tetapi wajib melalui incident workflow dengan recovery dan kompensasi.

Tanpa salah satu kebijakan tersebut, status `CANCELED` setelah pickup akan tetap menjadi terminal failure yang meninggalkan penumpang tanpa pemulihan terjamin.
