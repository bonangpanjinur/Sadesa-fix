/**
 * Minimal i18n utility — no extra dependencies.
 *
 * Detects user language from localStorage("desamart.lang") or navigator.language.
 * Falls back to Indonesian ("id"), then to the key itself.
 *
 * Components subscribe via useTranslation() / useFormatters(); setLocale()
 * notifies them via useSyncExternalStore so the UI re-renders instantly.
 *
 * ────────────────────────────────────────────────────────────────────────
 *  KEY NAMING CONVENTION
 * ────────────────────────────────────────────────────────────────────────
 *  Format: <namespace>.<feature>[.<modifier>]
 *
 *  Approved namespaces (extend here, NOT ad-hoc in components):
 *   - common.*    → app-wide reusable copy (yes/no, save, cancel, loading…)
 *   - pod.*       → Proof-of-Delivery image component
 *   - order.*     → Order/shipping flow (status labels, ETA copy…)
 *   - settings.*  → Settings page
 *   - admin.*     → Admin dashboards
 *   - merchant.*  → Merchant-facing screens
 *   - courier.*   → Courier-facing screens
 *
 *  Rules:
 *   1. ALWAYS add the key to BOTH `id` and `en` dictionaries.
 *   2. Use lowercase dot.case. No camelCase segments after the first.
 *      ✅ order.status.delivered     ❌ order.statusDelivered
 *   3. Status enum keys map 1-to-1 to backend values, lowercased.
 *      e.g. backend "PICKED_UP" → key "order.status.picked_up".
 *   4. Never inline literal Indonesian/English strings in components for
 *      user-facing copy. If a string is missing a key, ADD the key.
 *   5. Reuse via `common.*` before introducing a feature-scoped duplicate.
 *
 *  When TypeScript complains about an unknown key, that's the convention
 *  enforcing itself — add the key to both dictionaries.
 * ────────────────────────────────────────────────────────────────────────
 */
import { useSyncExternalStore } from 'react';

export type Locale = 'id' | 'en';

const STORAGE_KEY = 'desamart.lang';

const dictionaries = {
  id: {
    // common.*
    'common.loading': 'Memuat',
    'common.retry': 'Coba lagi',
    'common.cancel': 'Batal',
    'common.save': 'Simpan',

    // pod.* (Proof of Delivery image)
    'pod.unavailable': 'Gambar tidak tersedia',
    'pod.loadFailed': 'Gagal memuat, coba lagi',
    'pod.retry': 'Muat ulang',
    'pod.loading': 'Memuat gambar',
    'pod.alt': 'Bukti Pengiriman',

    // order.status.*  (keys mirror backend enum values, lowercased)
    'order.status.new': 'Menunggu Kurir',
    'order.status.processing': 'Menunggu Kurir',
    'order.status.processed': 'Sedang Diproses',
    'order.status.assigned': 'Menunggu Kurir Menerima',
    'order.status.courier_accepted': 'Kurir Menuju Toko',
    'order.status.picked_up': 'Kurir Mengambil Pesanan',
    'order.status.sent': 'Kurir Sedang Mengantar',
    'order.status.on_delivery': 'Kurir Sedang Mengantar',
    'order.status.delivering': 'Penjual Sedang Mengantar',
    'order.status.delivered': 'Pesanan Terkirim',
    'order.status.done': 'Pesanan Terkirim',
    'order.status.canceled': 'Dibatalkan',
    'order.status.cancelled': 'Dibatalkan',
    'order.cancelled.title': 'Pengiriman dibatalkan',
    'order.cancelled.generic': 'Pesanan kurir tidak dapat diproses.',
    'order.cancelled.tryAgain': 'Silakan buat pesanan baru jika masih membutuhkan pengiriman.',

    // order.step.*  (progress timeline labels)
    'order.step.created': 'Pesanan Dibuat',
    'order.step.processed': 'Sedang Diproses',
    'order.step.assigned': 'Tawaran Dikirim ke Kurir',
    'order.step.picked_up': 'Pesanan Diambil',
    'order.step.delivered': 'Sampai Tujuan',
    'order.step.inProgress': 'Sedang berlangsung',

    // order.eta.*
    'order.eta.label': 'Estimasi tiba',

    // shipping.* (ongkir & ringkasan biaya)
    'shipping.subtotal': 'Subtotal',
    'shipping.fee': 'Ongkir',
    'shipping.feeLong': 'Ongkos kirim',
    'shipping.calculatedAtCheckout': 'Dihitung saat checkout',
    'shipping.free': 'Gratis ongkir!',
    'shipping.freeMinOrder': 'Gratis ongkir! (min. belanja {min})',
    'shipping.voucherDiscount': 'Diskon Voucher',
    'shipping.codServiceFee': 'Biaya Layanan COD',
    'shipping.total': 'Total',
    'shipping.payVia': 'Bayar via',
    'shipping.distanceLabel': 'Jarak pengiriman',
    'shipping.estimatedFee': 'Estimasi ongkir',
    'shipping.etaLabel': 'Estimasi tiba',
    'shipping.etaMinutes': '{min}-{max} menit',
    'shipping.etaHours': '{min}-{max} jam',
    'shipping.method': 'Metode Pengiriman',
    'shipping.pickup': 'Ambil Sendiri',
    'shipping.pickupDesc': 'Ambil langsung di toko',
    'shipping.delivery': 'Kurir Desa',
    'shipping.deliveryDesc': 'Dikirim ke alamat Anda',
    'shipping.freeLabel': 'Gratis',

    'checkout.title': 'Checkout',
    'checkout.step.order': 'Pesanan',
    'checkout.steps': 'Tahapan checkout',
    'checkout.step.address': 'Alamat',
    'checkout.step.delivery': 'Pengiriman',
    'checkout.step.payment': 'Bayar',
    'checkout.empty.title': 'Belum ada produk untuk checkout',
    'checkout.empty.description': 'Keranjang Anda kosong atau belum ada produk yang dipilih. Pilih produk terlebih dahulu untuk melanjutkan.',
    'checkout.empty.backToCart': 'Kembali ke keranjang',
    'checkout.empty.continueShopping': 'Lanjut belanja',
    'checkout.multiStore.title': 'Checkout hanya dapat memproses satu toko per pesanan.',
    'checkout.multiStore.description': 'Pilih produk dari satu toko di keranjang, atau buat pesanan terpisah.',
    'checkout.multiStore.action': 'Kembali ke keranjang dan pilih satu toko',
    'checkout.multiStore.inline': 'Checkout hanya tersedia untuk satu toko.',
    'checkout.multiStore.adjust': 'Atur di keranjang',
    'checkout.orderSummary': 'Ringkasan Pesanan',
    'checkout.productCount': '{count} produk',
    'checkout.itemTopping': '+ {name} × {quantity} per produk ({price})',
    'checkout.address.title': 'Alamat Pengiriman',
    'checkout.address.recipientInfo': 'Info Penerima',
    'checkout.address.region': 'Wilayah Alamat',
    'checkout.address.regionHint': 'Pilih berurutan agar alamat cepat terisi',
    'checkout.address.complete': 'Lengkap',
    'checkout.address.name': 'Nama Penerima',
    'checkout.address.namePlaceholder': 'Nama lengkap penerima',
    'checkout.address.phone': 'No. Telepon (WhatsApp)',
    'checkout.address.saving': 'Alamat lengkap sedang disimpan ke profil...',
    'checkout.address.saved': 'Alamat berhasil disimpan ke profil Anda.',
    'checkout.address.saveError': 'Alamat belum tersimpan ke profil.',
    'checkout.address.retry': 'Coba lagi',
    'checkout.address.locationTitle': 'Titik Lokasi Pengiriman',
    'checkout.address.locationDetected': 'Terdeteksi',
    'checkout.address.summaryDetected': 'Alamat Terdeteksi:',
    'checkout.address.postalCode': 'Kode Pos:',
    'checkout.address.detailTitle': 'Detail Alamat',
    'checkout.address.detailHint': 'Nomor rumah dan patokan membantu kurir',
    'checkout.address.detailLabel': 'Nomor Rumah, Patokan, atau Informasi Tambahan',
    'checkout.address.detailPlaceholder': 'Contoh: Rumah nomor 42, depan toko kelontong, sebelah masjid',
    'checkout.address.detailHelp': 'Informasi ini membantu kurir menemukan lokasi Anda dengan lebih mudah ({count}/500)',
    'checkout.address.regionDetected': 'Wilayah Terdeteksi:',
    'checkout.payment.title': 'Metode Pembayaran',
    'checkout.payment.transfer': 'Transfer Bank',
    'checkout.payment.transferToSeller': 'Transfer ke rekening penjual',
    'checkout.payment.oneStoreOnly': 'Tersedia untuk checkout satu toko saja',
    'checkout.payment.accountInfo': 'Informasi Rekening:',
    'checkout.payment.online': 'Bayar Online',
    'checkout.payment.onlineMethods': 'QRIS, Transfer Bank, E-Wallet',
    'checkout.voucher.loginRequired': 'Voucher akun dan diskon tersimpan hanya tersedia setelah login.',
    'checkout.voucher.oneStoreOnly': 'Voucher hanya dapat digunakan untuk checkout satu toko.',
    'checkout.notes.label': 'Catatan (opsional)',
    'checkout.notes.placeholder': 'Catatan untuk penjual...',
    'checkout.cta.processing': 'Memproses...',
    'checkout.cta.checkingStore': 'Memeriksa Toko...',
    'checkout.cta.storeUnverified': 'Ketersediaan Belum Terverifikasi',
    'checkout.cta.storeClosed': 'Ada Toko Tutup',
    'checkout.cta.stockUnavailable': 'Stok Tidak Tersedia',
    'checkout.cta.placeOrder': 'Pesan',
    'checkout.cta.guestOrder': 'Pesan tanpa Login',
    'checkout.cta.addressNeeded': 'Lengkapi wilayah alamat dan tentukan titik lokasi di peta untuk melanjutkan.',
    'checkout.cta.stockHelp': 'Stok produk atau topping sudah habis. Kembali ke keranjang dan sesuaikan jumlahnya sebelum checkout.',
    'checkout.form.errorTitle': 'Data belum lengkap',
    'checkout.form.errorDescription': 'Silakan lengkapi form checkout',
    'checkout.validation.name': 'Nama minimal 2 karakter',
    'checkout.validation.phone': 'Nomor telepon tidak valid',
    'checkout.validation.province': 'Pilih provinsi',
    'checkout.validation.city': 'Pilih kota/kabupaten',
    'checkout.validation.district': 'Pilih kecamatan',
    'checkout.validation.village': 'Pilih kelurahan/desa',
    'checkout.validation.location': 'Tentukan titik lokasi pengiriman di peta',
    'checkout.validation.expedition': 'Alamat ini wajib menggunakan ekspedisi.',
    'checkout.location.useGps': 'Lokasi Saya',
    'checkout.location.gpsShort': 'GPS',
    'checkout.location.gpsTitle': 'Gunakan GPS untuk mendeteksi lokasi Anda saat ini',
    'checkout.location.gpsUnsupported': 'Browser tidak mendukung geolokasi',
    'checkout.location.gpsFailed': 'Gagal mendapatkan lokasi. Anda tetap bisa memilih titik secara manual di peta.',
    'checkout.location.instructions': 'Cara mengatur titik lokasi',
    'checkout.location.manualStart': 'Alamat manual akan memberi titik awal secara otomatis.',
    'checkout.location.refine': 'Gunakan GPS atau ketuk peta untuk memperhalus titik.',
    'checkout.location.selected': 'Lokasi Dipilih',
    'checkout.location.latitude': 'Latitude',
    'checkout.location.longitude': 'Longitude',
    'checkout.location.accuracy': 'Perkiraan akurasi: ~5-10m (GPS/Peta)',
    'checkout.location.none': 'Belum ada lokasi dipilih',
    'checkout.location.clickToStart': 'Klik pada peta atau gunakan "Lokasi Saya" untuk memulai',
    'checkout.savedAddress.pick': 'Pilih Alamat Profil atau Tersimpan',
    'address.loadFailed': 'Gagal memuat data alamat',
    'address.provinceUnavailable': 'Tidak dapat memuat data provinsi',
    'address.provinceFailed': 'Gagal memuat data provinsi',
    'address.villageFailed': 'Gagal memuat data desa/kelurahan. Silakan coba lagi.',
    'address.retry': 'Coba Lagi',
    'address.stepHint': 'Isi dari atas ke bawah: provinsi, kota/kabupaten, kecamatan, lalu desa/kelurahan.',
    'address.province': 'Provinsi',
    'address.city': 'Kota/Kabupaten',
    'address.district': 'Kecamatan',
    'address.village': 'Kelurahan/Desa',
    'address.detail': 'Detail Alamat (RT/RW, Nama Jalan, dll)',
    'address.detailPlaceholder': 'Contoh: Jl. Merdeka No. 10, RT 01/RW 02',
    'address.loadingProvince': 'Memuat provinsi...',
    'address.loadingCity': 'Memuat kota...',
    'address.loadingDistrict': 'Memuat kecamatan...',
    'address.loadingVillage': 'Memuat desa...',
    'address.selectProvince': 'Pilih Provinsi',
    'address.selectCity': 'Pilih Kota/Kabupaten',
    'address.selectDistrict': 'Pilih Kecamatan',
    'address.selectVillage': 'Pilih Kelurahan/Desa',
    'address.villageUnavailable': 'Data desa tidak tersedia',
    'address.villageEmpty': 'Tidak ada data desa',
    'address.chooseDistrict': 'Pilih kecamatan terlebih dahulu',
    'address.villageHelp': 'Jika data desa tidak muncul, coba pilih ulang kecamatan atau refresh halaman.',
    'install.title': 'Install Aplikasi SaDesa',
    'install.description': 'Akses lebih cepat dari homescreen dan tetap nyaman saat koneksi tidak stabil.',
    'install.dismiss': 'Tutup pengingat instalasi',
    'install.now': 'Install Sekarang',
    'install.how': 'Cara Install',
    'install.later': 'Nanti',

    // settings.language.*
    'settings.title': 'Pengaturan',
    'settings.description': 'Kelola preferensi aplikasi',
    'settings.back': 'Kembali',
    'settings.push.title': 'Notifikasi Push',
    'settings.push.description': 'Terima notifikasi untuk pesanan, promo, dan update penting',
    'settings.push.loading': 'Memeriksa status...',
    'settings.push.unsupported': 'Browser tidak mendukung notifikasi push',
    'settings.push.permission_denied': 'Notifikasi diblokir di browser Anda',
    'settings.push.permission_help': 'Untuk mengaktifkan, buka pengaturan browser dan izinkan notifikasi untuk situs ini.',
    'settings.push.required': 'Wajib aktif untuk menerima pesanan ojek.',
    'settings.push.description_inline': 'Terima notifikasi pesanan dan update penting',
    'settings.push.active': 'Notifikasi aktif',
    'settings.push.login_required': 'Silakan login terlebih dahulu',
    'settings.push.enabled': 'Notifikasi push diaktifkan',
    'settings.push.enable_failed': 'Gagal mengaktifkan notifikasi',
    'settings.push.disabled': 'Notifikasi push dinonaktifkan',
    'settings.push.disable_failed': 'Gagal menonaktifkan notifikasi',
    'settings.push.error': 'Terjadi kesalahan',
    'settings.push.status_failed': 'Status notifikasi belum dapat diperiksa.',
    'settings.push.refresh': 'Perbarui subscription',
    'settings.push.refreshing': 'Memperbarui...',
    'settings.push.refreshed': 'Subscription push diperbarui',
    'settings.push.refresh_failed': 'Gagal memperbarui subscription',
    'settings.privacy.title': 'Privasi & Keamanan',
    'settings.privacy.description': 'Kelola data dan keamanan akun Anda',
    'settings.password.change': 'Ubah Password',
    'settings.password.new': 'Password Baru',
    'settings.password.confirm': 'Konfirmasi Password',
    'settings.password.placeholder': 'Min. 8 karakter, huruf besar, kecil, dan angka',
    'settings.password.confirm_placeholder': 'Ulangi password baru',
    'settings.password.policy_error': 'Password harus minimal 8 karakter dan mengandung huruf besar, huruf kecil, serta angka.',
    'settings.password.mismatch': 'Password tidak cocok',
    'settings.password.changed': 'Password berhasil diubah',
    'settings.password.update_failed': 'Gagal mengubah password',
    'settings.password.save': 'Simpan',
    'settings.password.saving': 'Menyimpan...',
    'settings.password.cancel': 'Batal',
    'settings.privacy.policy': 'Kebijakan Privasi',
    'settings.privacy.terms': 'Syarat & Ketentuan',
    'settings.footer': 'SaDesa v1.0.0 • Platform UMKM Desa',
    'settings.language.title': 'Bahasa',
    'settings.language.description': 'Pilih bahasa tampilan aplikasi',
    'settings.language.active': 'Bahasa Aktif',
    'settings.language.id': 'Bahasa Indonesia',
    'settings.language.en': 'English',

    // common.language.* (for header switcher menu)
    'common.language.switch': 'Ubah bahasa',
  },
  en: {
    'common.loading': 'Loading',
    'common.retry': 'Retry',
    'common.cancel': 'Cancel',
    'common.save': 'Save',

    'pod.unavailable': 'Image not available',
    'pod.loadFailed': 'Failed to load, please try again',
    'pod.retry': 'Reload',
    'pod.loading': 'Loading image',
    'pod.alt': 'Proof of delivery',

    'order.status.new': 'Waiting for courier',
    'order.status.processing': 'Waiting for courier',
    'order.status.processed': 'Being processed',
    'order.status.assigned': 'Waiting for courier acceptance',
    'order.status.courier_accepted': 'Courier heading to store',
    'order.status.picked_up': 'Courier picked up order',
    'order.status.sent': 'Courier on delivery',
    'order.status.on_delivery': 'Courier on delivery',
    'order.status.delivering': 'Seller is delivering',
    'order.status.delivered': 'Order delivered',
    'order.status.done': 'Order delivered',
    'order.status.canceled': 'Canceled',
    'order.status.cancelled': 'Canceled',
    'order.cancelled.title': 'Delivery canceled',
    'order.cancelled.generic': 'The courier order could not be completed.',
    'order.cancelled.tryAgain': 'Please place a new order if you still need delivery.',

    'order.step.created': 'Order placed',
    'order.step.processed': 'Being processed',
    'order.step.assigned': 'Courier assigned',
    'order.step.picked_up': 'Order picked up',
    'order.step.delivered': 'Arrived',
    'order.step.inProgress': 'In progress',

    'order.eta.label': 'ETA',

    'shipping.subtotal': 'Subtotal',
    'shipping.fee': 'Shipping',
    'shipping.feeLong': 'Shipping fee',
    'shipping.calculatedAtCheckout': 'Calculated at checkout',
    'shipping.free': 'Free shipping!',
    'shipping.freeMinOrder': 'Free shipping! (min. order {min})',
    'shipping.voucherDiscount': 'Voucher discount',
    'shipping.codServiceFee': 'COD service fee',
    'shipping.total': 'Total',
    'shipping.payVia': 'Pay via',
    'shipping.distanceLabel': 'Delivery distance',
    'shipping.estimatedFee': 'Estimated shipping',
    'shipping.etaLabel': 'ETA',
    'shipping.etaMinutes': '{min}-{max} min',
    'shipping.etaHours': '{min}-{max} hr',
    'shipping.method': 'Delivery Method',
    'shipping.pickup': 'Self Pickup',
    'shipping.pickupDesc': 'Pick up at the store',
    'shipping.delivery': 'Village Courier',
    'shipping.deliveryDesc': 'Delivered to your address',
    'shipping.freeLabel': 'Free',

    'checkout.title': 'Checkout',
    'checkout.step.order': 'Order',
    'checkout.steps': 'Checkout steps',
    'checkout.step.address': 'Address',
    'checkout.step.delivery': 'Delivery',
    'checkout.step.payment': 'Payment',
    'checkout.empty.title': 'No items to check out',
    'checkout.empty.description': 'Your cart is empty or no items are selected. Choose products before continuing.',
    'checkout.empty.backToCart': 'Back to cart',
    'checkout.empty.continueShopping': 'Continue shopping',
    'checkout.multiStore.title': 'Checkout can process only one store per order.',
    'checkout.multiStore.description': 'Choose products from one store in your cart, or place separate orders.',
    'checkout.multiStore.action': 'Back to cart and choose one store',
    'checkout.multiStore.inline': 'Checkout is available for one store at a time.',
    'checkout.multiStore.adjust': 'Manage in cart',
    'checkout.orderSummary': 'Order Summary',
    'checkout.productCount': '{count} items',
    'checkout.itemTopping': '+ {name} × {quantity} per item ({price})',
    'checkout.address.title': 'Delivery Address',
    'checkout.address.recipientInfo': 'Recipient Information',
    'checkout.address.region': 'Address Region',
    'checkout.address.regionHint': 'Choose each region in order to fill the address.',
    'checkout.address.complete': 'Complete',
    'checkout.address.name': 'Recipient Name',
    'checkout.address.namePlaceholder': 'Recipient full name',
    'checkout.address.phone': 'Phone (WhatsApp)',
    'checkout.address.saving': 'Saving complete address to your profile...',
    'checkout.address.saved': 'Address saved to your profile.',
    'checkout.address.saveError': 'Address was not saved to your profile.',
    'checkout.address.retry': 'Retry',
    'checkout.address.locationTitle': 'Delivery Location Pin',
    'checkout.address.locationDetected': 'Detected',
    'checkout.address.summaryDetected': 'Detected Address:',
    'checkout.address.postalCode': 'Postal Code:',
    'checkout.address.detailTitle': 'Address Details',
    'checkout.address.detailHint': 'A house number or landmark helps the courier.',
    'checkout.address.detailLabel': 'House Number, Landmark, or Additional Information',
    'checkout.address.detailPlaceholder': 'Example: House 42, across from the grocery shop, beside the mosque',
    'checkout.address.detailHelp': 'This helps the courier find you ({count}/500)',
    'checkout.address.regionDetected': 'Detected Region:',
    'checkout.payment.title': 'Payment Method',
    'checkout.payment.transfer': 'Bank Transfer',
    'checkout.payment.transferToSeller': 'Transfer to the seller’s account',
    'checkout.payment.oneStoreOnly': 'Available for single-store checkout only',
    'checkout.payment.accountInfo': 'Bank Account Information:',
    'checkout.payment.online': 'Pay Online',
    'checkout.payment.onlineMethods': 'QRIS, bank transfer, e-wallet',
    'checkout.voucher.loginRequired': 'Account vouchers and saved discounts are available after signing in.',
    'checkout.voucher.oneStoreOnly': 'Vouchers can only be used for a single-store checkout.',
    'checkout.notes.label': 'Note (optional)',
    'checkout.notes.placeholder': 'Note for the seller...',
    'checkout.cta.processing': 'Processing...',
    'checkout.cta.checkingStore': 'Checking store...',
    'checkout.cta.storeUnverified': 'Store Availability Not Verified',
    'checkout.cta.storeClosed': 'A Store Is Closed',
    'checkout.cta.stockUnavailable': 'Stock Unavailable',
    'checkout.cta.placeOrder': 'Place Order',
    'checkout.cta.guestOrder': 'Order without Signing In',
    'checkout.cta.addressNeeded': 'Complete the address regions and set a delivery pin on the map to continue.',
    'checkout.cta.stockHelp': 'A product or topping is out of stock. Return to your cart and adjust the quantity before checkout.',
    'checkout.form.errorTitle': 'Incomplete information',
    'checkout.form.errorDescription': 'Please complete the checkout form.',
    'checkout.validation.name': 'Name must contain at least 2 characters',
    'checkout.validation.phone': 'Invalid phone number',
    'checkout.validation.province': 'Choose a province',
    'checkout.validation.city': 'Choose a city/regency',
    'checkout.validation.district': 'Choose a district',
    'checkout.validation.village': 'Choose a village/urban village',
    'checkout.validation.location': 'Set the delivery location pin on the map',
    'checkout.validation.expedition': 'This address must use an expedition service.',
    'checkout.location.useGps': 'My Location',
    'checkout.location.gpsShort': 'GPS',
    'checkout.location.gpsTitle': 'Use GPS to detect your current location',
    'checkout.location.gpsUnsupported': 'This browser does not support geolocation',
    'checkout.location.gpsFailed': 'Could not get your location. You can still choose a point manually on the map.',
    'checkout.location.instructions': 'How to set a location pin',
    'checkout.location.manualStart': 'Your typed address will set an initial map point automatically.',
    'checkout.location.refine': 'Use GPS or tap the map to refine the point.',
    'checkout.location.selected': 'Location Selected',
    'checkout.location.latitude': 'Latitude',
    'checkout.location.longitude': 'Longitude',
    'checkout.location.accuracy': 'Estimated accuracy: ~5-10m (GPS/Map)',
    'checkout.location.none': 'No location selected yet',
    'checkout.location.clickToStart': 'Click the map or use "My Location" to get started',
    'checkout.savedAddress.pick': 'Choose a Profile or Saved Address',
    'address.loadFailed': 'Failed to load address data',
    'address.provinceUnavailable': 'Could not load province data',
    'address.provinceFailed': 'Failed to load province data',
    'address.villageFailed': 'Failed to load village data. Please try again.',
    'address.retry': 'Retry',
    'address.stepHint': 'Choose from top to bottom: province, city/regency, district, then village/urban village.',
    'address.province': 'Province',
    'address.city': 'City/Regency',
    'address.district': 'District',
    'address.village': 'Village/Urban Village',
    'address.detail': 'Address Details (street, neighborhood, etc.)',
    'address.detailPlaceholder': 'Example: Merdeka St. No. 10, Neighborhood 01/02',
    'address.loadingProvince': 'Loading provinces...',
    'address.loadingCity': 'Loading cities...',
    'address.loadingDistrict': 'Loading districts...',
    'address.loadingVillage': 'Loading villages...',
    'address.selectProvince': 'Select Province',
    'address.selectCity': 'Select City/Regency',
    'address.selectDistrict': 'Select District',
    'address.selectVillage': 'Select Village/Urban Village',
    'address.villageUnavailable': 'Village data unavailable',
    'address.villageEmpty': 'No village data',
    'address.chooseDistrict': 'Select a district first',
    'address.villageHelp': 'If village data is missing, reselect the district or refresh the page.',
    'install.title': 'Install SaDesa',
    'install.description': 'Open SaDesa faster from your home screen, even with an unstable connection.',
    'install.dismiss': 'Dismiss install reminder',
    'install.now': 'Install Now',
    'install.how': 'How to Install',
    'install.later': 'Later',

    'settings.title': 'Settings',
    'settings.description': 'Manage your app preferences',
    'settings.back': 'Back',
    'settings.push.title': 'Push Notifications',
    'settings.push.description': 'Get notifications for orders, promotions, and important updates',
    'settings.push.loading': 'Checking status...',
    'settings.push.unsupported': 'This browser does not support push notifications',
    'settings.push.permission_denied': 'Notifications are blocked in your browser',
    'settings.push.permission_help': 'To enable notifications, open your browser settings and allow notifications for this site.',
    'settings.push.required': 'Required to receive ride orders.',
    'settings.push.description_inline': 'Get notifications about orders and important updates',
    'settings.push.active': 'Notifications are active',
    'settings.push.login_required': 'Please sign in first',
    'settings.push.enabled': 'Push notifications enabled',
    'settings.push.enable_failed': 'Failed to enable notifications',
    'settings.push.disabled': 'Push notifications disabled',
    'settings.push.disable_failed': 'Failed to disable notifications',
    'settings.push.error': 'An error occurred',
    'settings.push.status_failed': 'Unable to check notification status.',
    'settings.push.refresh': 'Refresh subscription',
    'settings.push.refreshing': 'Refreshing...',
    'settings.push.refreshed': 'Push subscription refreshed',
    'settings.push.refresh_failed': 'Failed to refresh push subscription',
    'settings.privacy.title': 'Privacy & Security',
    'settings.privacy.description': 'Manage your data and account security',
    'settings.password.change': 'Change password',
    'settings.password.new': 'New password',
    'settings.password.confirm': 'Confirm password',
    'settings.password.placeholder': 'At least 8 characters, uppercase, lowercase, and number',
    'settings.password.confirm_placeholder': 'Enter the new password again',
    'settings.password.policy_error': 'Password must be at least 8 characters and include uppercase, lowercase, and numeric characters.',
    'settings.password.mismatch': 'Passwords do not match',
    'settings.password.changed': 'Password changed successfully',
    'settings.password.update_failed': 'Failed to change password',
    'settings.password.save': 'Save',
    'settings.password.saving': 'Saving...',
    'settings.password.cancel': 'Cancel',
    'settings.privacy.policy': 'Privacy Policy',
    'settings.privacy.terms': 'Terms & Conditions',
    'settings.footer': 'SaDesa v1.0.0 • Village MSME Platform',
    'settings.language.title': 'Language',
    'settings.language.description': 'Choose the app display language',
    'settings.language.active': 'Active language',
    'settings.language.id': 'Bahasa Indonesia',
    'settings.language.en': 'English',

    'common.language.switch': 'Change language',
  },
} as const satisfies Record<Locale, Record<string, string>>;

export type TranslationKey = keyof (typeof dictionaries)['id'];

function detectLocale(): Locale {
  if (typeof window === 'undefined') return 'id';
  const stored = window.localStorage?.getItem(STORAGE_KEY);
  if (stored === 'id' || stored === 'en') return stored;
  const nav = window.navigator?.language?.toLowerCase() ?? '';
  if (nav.startsWith('en')) return 'en';
  return 'id';
}

let currentLocale: Locale = detectLocale();
const listeners = new Set<() => void>();

export function getLocale(): Locale {
  return currentLocale;
}

export function setLocale(locale: Locale): void {
  if (locale === currentLocale) return;
  currentLocale = locale;
  try {
    window.localStorage?.setItem(STORAGE_KEY, locale);
  } catch {
    /* ignore */
  }
  listeners.forEach((l) => l());
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function translate(
  key: TranslationKey,
  locale: Locale = currentLocale,
  vars?: Record<string, string | number>,
): string {
  const raw = dictionaries[locale]?.[key] ?? dictionaries.id[key] ?? key;
  if (!vars) return raw;
  return raw.replace(/\{(\w+)\}/g, (_, k) => (vars[k] !== undefined ? String(vars[k]) : `{${k}}`));
}

/**
 * Map a backend order status (e.g. "PICKED_UP") to a localized label.
 * Unknown statuses fall through to the raw value so they remain debuggable.
 */
export function translateOrderStatus(status: string, locale: Locale = currentLocale): string {
  const key = `order.status.${status.toLowerCase()}` as TranslationKey;
  if ((dictionaries[locale] as Record<string, string>)[key]) return translate(key, locale);
  return status;
}

export function useTranslation() {
  const locale = useSyncExternalStore(subscribe, getLocale, () => 'id' as Locale);
  return {
    locale,
    t: (key: TranslationKey, vars?: Record<string, string | number>) =>
      translate(key, locale, vars),
    tStatus: (status: string) => translateOrderStatus(status, locale),
    setLocale,
  };
}

// ──────────────────────────────────────────────────────────────────────
//  Locale-aware formatters (currency, dates, numbers)
// ──────────────────────────────────────────────────────────────────────

const LOCALE_TAG: Record<Locale, string> = { id: 'id-ID', en: 'en-US' };

/** IDR is project-wide currency; only the locale formatting differs. */
export function formatCurrency(amount: number, locale: Locale = currentLocale): string {
  return new Intl.NumberFormat(LOCALE_TAG[locale], {
    style: 'currency',
    currency: 'IDR',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amount);
}

export function formatNumber(value: number, locale: Locale = currentLocale): string {
  return new Intl.NumberFormat(LOCALE_TAG[locale]).format(value);
}

export function formatDate(
  input: string | number | Date,
  options: Intl.DateTimeFormatOptions = { dateStyle: 'medium' },
  locale: Locale = currentLocale,
): string {
  const date = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(LOCALE_TAG[locale], options).format(date);
}

export function formatTime(
  input: string | number | Date,
  locale: Locale = currentLocale,
): string {
  return formatDate(input, { hour: '2-digit', minute: '2-digit' }, locale);
}

export function formatDateTime(
  input: string | number | Date,
  locale: Locale = currentLocale,
): string {
  return formatDate(input, { dateStyle: 'medium', timeStyle: 'short' }, locale);
}

/** Reactive formatters hook — re-renders on setLocale. */
export function useFormatters() {
  const locale = useSyncExternalStore(subscribe, getLocale, () => 'id' as Locale);
  return {
    locale,
    formatCurrency: (n: number) => formatCurrency(n, locale),
    formatNumber: (n: number) => formatNumber(n, locale),
    formatDate: (d: string | number | Date, o?: Intl.DateTimeFormatOptions) =>
      formatDate(d, o, locale),
    formatTime: (d: string | number | Date) => formatTime(d, locale),
    formatDateTime: (d: string | number | Date) => formatDateTime(d, locale),
  };
}
