
## Remediasi P0 — selesai

Perbaikan diterapkan pada `src/pages/CheckoutPage.tsx`:

- `p_distance_km` sekarang mengirim `distanceKm` yang sama dengan perhitungan `shippingCost` di ringkasan checkout.
- Untuk `PICKUP`, nilai tetap `null` dan ongkir tetap Rp0.
- Tombol submit dan handler submit diblokir ketika rute pengiriman masih `calculating`, belum menghasilkan jarak positif, atau jarak belum tersedia.
- Regression test baru memastikan `p_distance_km` tidak kembali menjadi `null` untuk pengiriman non-pickup.

Validasi:

- 16 regression tests terkait checkout/rute/guest checkout lulus.
- `pnpm build` lulus.
- `pnpm lint` masih menemukan 15 error lama di file yang tidak terkait perubahan ini; tidak ada error lint pada `CheckoutPage.tsx` atau test baru.
