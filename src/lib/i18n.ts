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
