
## Audit tambahan: checkout dan pembayaran

### Temuan

1. **Checkout melakukan refetch merchant** ketika `isXenditEnabled()` selesai karena `xenditAvailable` menjadi dependency effect merchant. Ini mengulang query merchant dan fallback payment settings.
2. **Halaman konfirmasi pembayaran memiliki waterfall**: order → merchant → fallback `admin_payment_info`. Fallback sebenarnya dapat dibaca paralel setelah order ditemukan.
3. **Submit checkout melakukan state update yang tidak dipakai** (`invoiceUrl`) tepat sebelum navigasi browser ke invoice, sehingga menambah satu render tanpa manfaat.
4. **Kompresi bukti pembayaran membuat object URL** dan sebelumnya tidak melepaskannya, yang dapat menahan memory pada perangkat mobile setelah beberapa kali memilih gambar.

### Perbaikan

- Query merchant checkout sekarang hanya bergantung pada merchant ID, memakai cancellation guard, dan pemilihan metode pembayaran dipisahkan ke effect kecil berdasarkan settings/provider.
- Query merchant dan `admin_payment_info` pada halaman pembayaran dijalankan dengan `Promise.all` setelah order terverifikasi.
- State `invoiceUrl` yang tidak pernah dirender dihapus.
- `URL.revokeObjectURL` ditambahkan pada jalur sukses dan error kompresi gambar.

### Validasi tambahan

| Pemeriksaan | Hasil |
|---|---:|
| `git diff --check` | PASS |
| `pnpm exec tsc --noEmit` | PASS |
| `pnpm lint` | PASS, 1 warning lama di `FoodFilterSheet.tsx` |
| Test checkout/payment terarah | PASS — 10/10 |
| `pnpm build` | PASS |

### File tambahan yang diubah

- `src/pages/CheckoutPage.tsx`
- `src/pages/PaymentConfirmationPage.tsx`
- `src/lib/storage.ts`
