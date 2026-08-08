# Analisis Error Frontend & Rencana Perbaikan

## Hasil Analisis

### Yang sudah sehat
- TypeScript: `tsgo --noEmit` **0 error**.
- Halaman publik (`/`, `/products`, `/shops`, `/cart`, `/auth`, `/tourism`, `/notifications`) dimuat tanpa error console dan tanpa request HTTP gagal.

### Error P0 — 29 pemanggilan `/api/*` ke server Express yang sudah tidak ada
Setelah client backend dipindah ke client resmi, folder `server/` tidak lagi ikut ter-deploy, tapi kode frontend masih memanggil endpoint Express-nya. Diverifikasi langsung: `POST /api/pos/merchant-quotas` dan `GET /api/wilayah` sama-sama balas **HTTP 500** (proxy Vite menunjuk `localhost:3001` yang mati).

Dampak per fitur:

| Fitur | File | Akibat |
|---|---|---|
| Kuota merchant + deduksi kuota saat order | `src/hooks/useMerchantQuota.ts` (3 call) | Cek kuota selalu gagal, kuota tidak pernah dikurangi setelah order |
| Notifikasi kuota habis | `src/hooks/useMerchantQuota.ts` | Tidak terkirim |
| Menu digital publik + status order QR | `src/pages/MenuPublicPage.tsx`, `src/pages/OrderStatusPage.tsx` | Halaman menu QR kosong |
| QRPay (kasir + konfirmasi pembeli) | `src/components/pos/kasir/QRPayDialog.tsx`, `src/pages/QRPayConfirmPage.tsx` | Alur bayar QR mati total |
| Push notification admin (VAPID/send/broadcast) | `src/pages/admin/AdminPushNotificationPage.tsx` | Semua aksi gagal |
| Statistik realtime admin | `src/hooks/useAdminRealtime.ts` | Grafik jam/menit kosong |
| SSE (KDS & notifikasi order QR) | `src/pages/pos/POSKDSPage.tsx`, `src/hooks/useQROrderNotifications.ts` | Tidak ada update realtime |
| Sinkronisasi POS offline | `src/hooks/usePOSOfflineSync.ts` | Antrian offline tidak pernah tersinkron |
| Verifikasi merchant desa | `src/pages/desa/DesaMerchantPage.tsx` | Tombol verifikasi gagal |
| Test WhatsApp | `src/pages/admin/AdminWhatsAppPage.tsx` | Gagal |
| Cetak thermal WiFi | `src/lib/thermalPrinter.ts` | Gagal (fitur perangkat lokal) |
| Wilayah (provinsi/kota) | `src/lib/addressApi.ts` | Masih jalan — sudah ada fallback edge function + sumber langsung |

### Error P1 — pelanggaran aturan React Hooks
`src/pages/CheckoutPage.tsx:601` memanggil `useMerchantQuotaForOrder()` di dalam `handleSubmit`, di dalam loop. Fungsinya bukan hook (hanya `fetch`), tapi namanya diawali `use` sehingga melanggar aturan hooks dan berisiko error saat build/lint di CI.

### Error P2 — kualitas kode (1042 temuan ESLint)
- `no-explicit-any`: 1006 (mayoritas di halaman POS)
- `react-hooks/exhaustive-deps`: 112 — beberapa berpotensi bug nyata (data tidak refetch / listener basi), mis. `POSContext`, `useSavedAddresses`, `CheckoutAddressForm`, `CourierMap`
- `no-empty`: 16 blok `catch {}` yang menelan error tanpa jejak
- `prefer-const`: 10, `ban-ts-comment`: 2, `no-useless-escape`: 2

### Konfigurasi
`vite.config.ts` masih mem-proxy `/api` ke `localhost:3001` dan `port: 5000` (dev nyata di 8080) — menyamarkan kegagalan `/api` saat dev.

---

## Rencana Perbaikan

### Fase 1 — Hilangkan ketergantungan `/api/*` (P0)
1. **Kuota merchant** — ganti 3 call di `useMerchantQuota.ts` menjadi query/RPC langsung ke backend (`merchant_subscriptions` + RPC `deduct_merchant_quota` / `send_notification`).
2. **QRPay** — pindahkan `create`/`status`/`cancel`/`confirm` ke edge function `qrpay`, lalu panggil via `supabase.functions.invoke` di `QRPayDialog.tsx` dan `QRPayConfirmPage.tsx`.
3. **Menu digital & status order QR** — `MenuPublicPage.tsx` dan `OrderStatusPage.tsx` membaca langsung dari tabel POS (produk, meja, order) dengan policy publik yang sesuai; pembuatan order lewat edge function.
4. **Push notification admin** — arahkan ke edge function `send-push-notification` yang sudah ada; simpan VAPID sebagai secret, bukan endpoint Express.
5. **Statistik admin realtime** — hitung agregat jam/menit lewat query/RPC ke `orders` menggantikan `/api/admin/stats/*`.
6. **SSE → Realtime** — `POSKDSPage.tsx` dan `useQROrderNotifications.ts` beralih ke channel realtime `postgres_changes` (pola yang sudah dipakai `useRealtimeOrders`).
7. **Sinkron POS offline** — `usePOSOfflineSync.ts` menulis transaksi antrean langsung ke tabel POS.
8. **Verifikasi merchant desa** — update status merchant langsung dari client dengan policy verifikator.
9. **Fitur yang memang butuh server lokal** (cetak thermal WiFi, test WhatsApp) — beri pesan jelas "hanya tersedia di perangkat dengan server lokal" alih-alih gagal senyap.

### Fase 2 — Stabilitas (P1)
10. Rename `useMerchantQuotaForOrder` → `deductMerchantQuota` (fungsi biasa), perbarui pemanggil di `CheckoutPage.tsx` sehingga pelanggaran rules-of-hooks hilang.
11. Perbaiki `exhaustive-deps` pada berkas berdampak data: `POSContext.tsx`, `useSavedAddresses.ts`, `CheckoutAddressForm.tsx`, `CourierMap.tsx`, `useChatUnread.ts`, `useChatNotification.ts`.
12. Isi 16 `catch {}` kosong dengan `console.warn` beserta konteks agar kegagalan terlacak.

### Fase 3 — Kebersihan kode & konfigurasi (P2)
13. Hapus proxy `/api` dan samakan `port` di `vite.config.ts`; bersihkan `runtimeCaching` service worker untuk pola `/api/db/*` yang tidak lagi ada.
14. Perbaiki `prefer-const`, `ban-ts-comment`, `no-useless-escape` (perbaikan mekanis, aman).
15. Kurangi `no-explicit-any` bertahap dengan tipe dari skema database, dimulai dari file terburuk (`POSKasirPage`, `POSPromosiPage`, `POSTransferStokPage`).

### Catatan teknis
- Verifikasi tiap penggantian dengan `tsgo --noEmit` plus pemuatan halaman via browser headless (console + request gagal) sebelum lanjut ke item berikutnya.
- Folder `server/` dipertahankan sementara sebagai referensi logika saat memindahkan endpoint, dan dihapus setelah Fase 1 tuntas.

**Perkiraan: ~20 file frontend diubah, 2-3 edge function baru/diperluas, kemungkinan 1 migrasi SQL untuk policy publik menu QR.**
