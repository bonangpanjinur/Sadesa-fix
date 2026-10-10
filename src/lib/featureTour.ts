import type { AppRole } from '@/types/auth';

export type FeatureTourRole = 'buyer' | 'merchant' | 'courier';

export interface FeatureTourStep {
  id: string;
  title: string;
  description: string;
  href: string;
  linkLabel: string;
  target: 'page-title' | 'buyer-discover';
}

export const FEATURE_TOUR_STEPS: Record<FeatureTourRole, FeatureTourStep[]> = {
  buyer: [
    { id: 'discover', title: 'Temukan produk dan toko lokal', description: 'Pilih kategori di sini untuk mulai menjelajahi makanan, ojek, dan kebutuhan belanja lokal.', href: '/', linkLabel: 'Lihat kategori utama', target: 'buyer-discover' },
    { id: 'checkout', title: 'Keranjang dan checkout', description: 'Di Keranjang, tinjau produk pilihan, alamat pengantaran, dan lanjutkan ke pembayaran.', href: '/cart', linkLabel: 'Buka keranjang', target: 'page-title' },
    { id: 'orders', title: 'Pantau pesanan', description: 'Di Pesanan, lihat status order, pelacakan pengiriman, riwayat, dan tindakan lanjutan.', href: '/orders', linkLabel: 'Lihat pesanan', target: 'page-title' },
    { id: 'transport', title: 'Pesan ojek atau layanan antar', description: 'Halaman ini membantu Anda menemukan layanan perjalanan ojek atau pengiriman yang tersedia di wilayah Anda.', href: '/ride', linkLabel: 'Lihat layanan antar', target: 'page-title' },
    { id: 'tourism-services', title: 'Wisata dan jasa lokal', description: 'Jelajahi destinasi wisata dan layanan profesional yang ditawarkan mitra di sekitar Anda.', href: '/services', linkLabel: 'Jelajahi jasa', target: 'page-title' },
    { id: 'account-support', title: 'Akun, alamat, dan bantuan', description: 'Kelola profil serta alamat pengantaran dari halaman Akun. Pusat Bantuan tersedia dari menu dukungan.', href: '/account', linkLabel: 'Kelola akun', target: 'page-title' },
  ],
  merchant: [
    { id: 'merchant-dashboard', title: 'Dashboard toko', description: 'Ringkasan di dashboard menampilkan aktivitas dan kondisi toko Anda.', href: '/merchant', linkLabel: 'Lihat dashboard', target: 'page-title' },
    { id: 'merchant-orders', title: 'Kelola pesanan', description: 'Di Pesanan, terima, proses, dan pantau order pelanggan.', href: '/merchant/orders', linkLabel: 'Buka pesanan', target: 'page-title' },
    { id: 'merchant-catalog', title: 'Atur katalog dan stok', description: 'Tambah atau ubah produk, harga, foto, dan ketersediaan. Pantau stok agar katalog tetap akurat.', href: '/merchant/products', linkLabel: 'Kelola produk', target: 'page-title' },
    { id: 'merchant-fulfillment', title: 'Fulfillment, refund, dan chat', description: 'Kelola pengiriman bertahap, tinjau permintaan refund, dan koordinasikan pesanan melalui chat.', href: '/merchant/fulfillment', linkLabel: 'Buka fulfillment', target: 'page-title' },
    { id: 'merchant-promotions', title: 'Promosi dan pelanggan', description: 'Atur promo, flash sale, voucher, serta program loyalitas untuk pelanggan.', href: '/merchant/promo', linkLabel: 'Kelola promosi', target: 'page-title' },
    { id: 'merchant-insights', title: 'Laporan penjualan dan keuangan', description: 'Pantau performa penjualan, pengunjung, pemasukan, dan penarikan melalui laporan.', href: '/merchant/analytics', linkLabel: 'Lihat analitik', target: 'page-title' },
    { id: 'merchant-wallet', title: 'Saldo', description: 'Periksa saldo, komisi, tagihan, top-up, dan riwayat di halaman Saldo.', href: '/merchant/wallet', linkLabel: 'Buka Saldo', target: 'page-title' },
  ],
  courier: [
    { id: 'courier-dashboard', title: 'Dashboard dan status kerja', description: 'Dashboard merangkum aktivitas. Atur status kerja dan izin lokasi sebelum menerima tawaran.', href: '/courier', linkLabel: 'Buka dashboard', target: 'page-title' },
    { id: 'courier-rides', title: 'Ambil pekerjaan ojek', description: 'Di Ojek Desa, lihat tawaran perjalanan, informasi penumpang dan tujuan, lalu ikuti tahapan penyelesaian order.', href: '/courier/rides', linkLabel: 'Lihat pekerjaan ojek', target: 'page-title' },
    { id: 'courier-deliveries', title: 'Pengiriman barang', description: 'Di Pengiriman Barang, lihat tawaran antar paket atau order marketplace yang dapat Anda ambil dan selesaikan.', href: '/courier/deliveries', linkLabel: 'Lihat pengiriman', target: 'page-title' },
    { id: 'courier-earnings', title: 'Riwayat dan pendapatan', description: 'Periksa pekerjaan terdahulu, pendapatan, dan performa di halaman ini.', href: '/courier/earnings', linkLabel: 'Lihat pendapatan', target: 'page-title' },
    { id: 'courier-wallet', title: 'Saldo komisi dan top-up', description: 'Pantau potongan komisi, tagihan, top-up, dan riwayat wallet komisi.', href: '/courier/commission-wallet', linkLabel: 'Buka wallet komisi', target: 'page-title' },
    { id: 'courier-chat-withdrawal', title: 'Chat dan pencairan', description: 'Gunakan Chat untuk koordinasi order. Penarikan dan setoran operasional tersedia di menu keuangan.', href: '/courier/withdrawal', linkLabel: 'Buka penarikan', target: 'page-title' },
  ],
};

export const PUBLIC_BUYER_FEATURE_TOUR_STEPS = FEATURE_TOUR_STEPS.buyer.filter(
  (step) => step.id !== 'orders' && step.id !== 'account-support',
);

const STAFF_ROLES: AppRole[] = ['admin', 'admin_desa', 'verifikator'];
const MERCHANT_WORKSPACE_ROUTES = [
  '/merchant/orders', '/merchant/fulfillment', '/merchant/refunds', '/merchant/chat', '/merchant/products',
  '/merchant/store', '/merchant/stock', '/merchant/price-book', '/merchant/gallery', '/merchant/bundle',
  '/merchant/preorder', '/merchant/grosir', '/merchant/promo', '/merchant/flash-sale', '/merchant/scheduled-promo',
  '/merchant/vouchers', '/merchant/loyalty-rules', '/merchant/reviews', '/merchant/notifikasi-wa', '/merchant/iklan',
  '/merchant/analytics', '/merchant/visitor-stats', '/merchant/insight', '/merchant/finance', '/merchant/pajak',
  '/merchant/import-export', '/merchant/withdrawal', '/merchant/dues', '/merchant/wallet',
  '/merchant/settings', '/merchant/pos',
];
const BUYER_WORKSPACE_ROUTES = [
  '/products', '/product', '/tourism', '/village', '/merchant', '/shops', '/search', '/cart', '/orders',
  '/account', '/profile', '/addresses', '/ride', '/services', '/wishlist', '/reviews', '/recently-viewed',
  '/buyer', '/flash-sale', '/compare', '/loyalty', '/vouchers', '/rekomendasi', '/cashback', '/referral', '/support', '/langganan',
];

function matchesRoute(pathname: string, route: string): boolean {
  return pathname === route || pathname.startsWith(`${route}/`);
}

/** Select a role-specific tour only on its workspace; internal admin/staff never see it. */
export function getFeatureTourRole(roles: readonly AppRole[], pathname: string): FeatureTourRole | null {
  if (roles.some((role) => STAFF_ROLES.includes(role))) return null;
  const normalizedPath = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
  if (normalizedPath === '/merchant' || MERCHANT_WORKSPACE_ROUTES.some((route) => matchesRoute(normalizedPath, route))) {
    return roles.includes('merchant') ? 'merchant' : null;
  }
  if (normalizedPath === '/courier' || normalizedPath.startsWith('/courier/')) {
    return roles.includes('courier') ? 'courier' : null;
  }
  if (['/auth', '/login', '/register', '/forgot-password', '/reset-password', '/checkout', '/qrpay', '/account-deletion']
    .some((route) => matchesRoute(normalizedPath, route))) return null;
  if (normalizedPath === '/' || BUYER_WORKSPACE_ROUTES.some((route) => matchesRoute(normalizedPath, route))) {
    return roles.includes('buyer') ? 'buyer' : null;
  }
  return null;
}

/** Unauthenticated visitors use the public buyer guide; staff workspaces remain excluded. */
export function getFeatureTourRoleForVisitor(
  roles: readonly AppRole[],
  pathname: string,
  isAuthenticated: boolean,
): FeatureTourRole | null {
  if (isAuthenticated) return getFeatureTourRole(roles, pathname);
  const normalizedPath = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
  if (['/orders', '/account', '/profile', '/addresses'].some((route) => matchesRoute(normalizedPath, route))) {
    return null;
  }
  return getFeatureTourRole(['buyer'], pathname);
}

export function getFeatureTourStorageKey(userId: string, role: FeatureTourRole): string {
  return `sadesa:feature-tour:v2:${userId}:${role}`;
}

export function getFeatureTourSessionKey(userId: string, role: FeatureTourRole): string {
  return `sadesa:feature-tour-deferred:v2:${userId}:${role}`;
}

type KeyValueStorage = Pick<Storage, 'getItem' | 'setItem'>;

export function readSeenFeatureTips(storage: KeyValueStorage, key: string): string[] {
  try {
    const saved = storage.getItem(key);
    if (!saved) return [];
    const value: unknown = JSON.parse(saved);
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : [];
  } catch {
    return [];
  }
}

/** Start a guide automatically only before its first tip has ever been displayed. */
export function shouldAutoStartFeatureTour(storage: KeyValueStorage, key: string): boolean {
  return readSeenFeatureTips(storage, key).length === 0;
}

export function markFeatureTipSeen(storage: KeyValueStorage, key: string, stepId: string): string[] {
  const seen = readSeenFeatureTips(storage, key);
  if (seen.includes(stepId)) return seen;
  const next = [...seen, stepId];
  try {
    storage.setItem(key, JSON.stringify(next));
  } catch {
    // Tour storage is optional; the app remains usable when browser storage is blocked.
  }
  return next;
}

export function getFirstUnseenFeatureTip<T extends { id: string }>(steps: readonly T[], seenIds: readonly string[]): T | undefined {
  return steps.find((step) => !seenIds.includes(step.id));
}
