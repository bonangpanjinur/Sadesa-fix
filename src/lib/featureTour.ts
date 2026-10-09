import type { AppRole } from '@/types/auth';

export type FeatureTourRole = 'buyer' | 'merchant' | 'courier';

export interface FeatureTourStep {
  id: string;
  title: string;
  description: string;
  href: string;
  linkLabel: string;
}

export const FEATURE_TOUR_STEPS: Record<FeatureTourRole, FeatureTourStep[]> = {
  buyer: [
    { id: 'discover', title: 'Temukan produk dan toko lokal', description: 'Jelajahi katalog, cari barang atau makanan, lalu buka halaman toko untuk melihat produk dan detailnya.', href: '/products', linkLabel: 'Jelajahi produk' },
    { id: 'checkout', title: 'Keranjang dan checkout', description: 'Produk pilihan tersimpan di keranjang. Periksa alamat pengantaran, pilih metode pembayaran, lalu pantau proses pesanan.', href: '/cart', linkLabel: 'Buka keranjang' },
    { id: 'orders', title: 'Pantau pesanan', description: 'Lihat status pesanan, pelacakan pengiriman, riwayat, dan tindakan lanjutan dari halaman Pesanan.', href: '/orders', linkLabel: 'Lihat pesanan' },
    { id: 'transport', title: 'Pesan ojek atau layanan antar', description: 'Gunakan menu transportasi untuk memesan perjalanan ojek atau layanan pengiriman yang tersedia di wilayah Anda.', href: '/ride', linkLabel: 'Lihat layanan antar' },
    { id: 'tourism-services', title: 'Wisata dan jasa lokal', description: 'Temukan destinasi wisata, layanan profesional, dan kebutuhan lain yang ditawarkan mitra di sekitar Anda.', href: '/services', linkLabel: 'Jelajahi jasa' },
    { id: 'account-support', title: 'Akun, alamat, dan bantuan', description: 'Kelola profil serta alamat pengantaran dari Akun. Jika membutuhkan bantuan, buka Pusat Bantuan dari menu dukungan.', href: '/account', linkLabel: 'Kelola akun' },
  ],
  merchant: [
    { id: 'merchant-orders', title: 'Kelola pesanan', description: 'Dashboard menampilkan aktivitas toko. Buka Pesanan untuk menerima, memproses, dan memantau order pelanggan.', href: '/merchant/orders', linkLabel: 'Buka pesanan' },
    { id: 'merchant-catalog', title: 'Atur katalog dan stok', description: 'Tambah atau ubah produk, harga, foto, dan ketersediaan. Pantau stok menipis agar katalog tetap akurat.', href: '/merchant/products', linkLabel: 'Kelola produk' },
    { id: 'merchant-fulfillment', title: 'Fulfillment, refund, dan chat', description: 'Gunakan Fulfillment untuk pengiriman bertahap, Refund untuk meninjau permintaan pengembalian, dan Chat untuk pelanggan.', href: '/merchant/fulfillment', linkLabel: 'Buka fulfillment' },
    { id: 'merchant-promotions', title: 'Promosi dan pelanggan', description: 'Buat promo, flash sale, voucher, dan program loyalitas untuk membantu pelanggan menemukan serta membeli produk Anda.', href: '/merchant/promo', linkLabel: 'Kelola promosi' },
    { id: 'merchant-insights', title: 'Laporan penjualan dan keuangan', description: 'Gunakan analitik dan laporan keuangan untuk memantau performa penjualan, pengunjung, pemasukan, dan penarikan.', href: '/merchant/analytics', linkLabel: 'Lihat analitik' },
    { id: 'merchant-wallet', title: 'Saldo komisi dan top-up', description: 'Wallet menampilkan saldo, komisi, tagihan, dan riwayat. Top-up menambah saldo; paket kuota lama hanya tersedia sebagai histori.', href: '/merchant/wallet', linkLabel: 'Buka wallet' },
  ],
  courier: [
    { id: 'courier-dashboard', title: 'Dashboard dan status kerja', description: 'Dashboard merangkum aktivitas. Pastikan status dan izin lokasi sesuai sebelum menerima penawaran pekerjaan.', href: '/courier', linkLabel: 'Buka dashboard' },
    { id: 'courier-rides', title: 'Ambil pekerjaan ojek', description: 'Di Ojek Desa, lihat penawaran perjalanan, informasi penumpang dan tujuan, lalu ikuti tahapan penyelesaian order.', href: '/courier/rides', linkLabel: 'Lihat pekerjaan ojek' },
    { id: 'courier-deliveries', title: 'Pengiriman barang', description: 'Menu Pengiriman Barang berisi penawaran antar paket atau order marketplace yang dapat Anda ambil dan selesaikan.', href: '/courier/deliveries', linkLabel: 'Lihat pengiriman' },
    { id: 'courier-earnings', title: 'Riwayat dan pendapatan', description: 'Periksa pekerjaan terdahulu, pendapatan, dan performa untuk memahami aktivitas serta hasil kerja Anda.', href: '/courier/earnings', linkLabel: 'Lihat pendapatan' },
    { id: 'courier-wallet', title: 'Saldo komisi dan top-up', description: 'Wallet komisi terpisah dari Setor Saldo operasional. Pantau potongan komisi, tagihan, top-up, dan riwayat wallet.', href: '/courier/commission-wallet', linkLabel: 'Buka wallet komisi' },
    { id: 'courier-chat-withdrawal', title: 'Chat dan pencairan', description: 'Gunakan Chat untuk koordinasi order. Penarikan saldo dan setoran operasional tersedia di menu keuangan masing-masing.', href: '/courier/withdrawal', linkLabel: 'Buka penarikan' },
  ],
};

const STAFF_ROLES: AppRole[] = ['admin', 'admin_desa', 'verifikator'];
const MERCHANT_WORKSPACE_ROUTES = [
  '/merchant/orders', '/merchant/fulfillment', '/merchant/refunds', '/merchant/chat', '/merchant/products',
  '/merchant/store', '/merchant/stock', '/merchant/price-book', '/merchant/gallery', '/merchant/bundle',
  '/merchant/preorder', '/merchant/grosir', '/merchant/promo', '/merchant/flash-sale', '/merchant/scheduled-promo',
  '/merchant/vouchers', '/merchant/loyalty-rules', '/merchant/reviews', '/merchant/notifikasi-wa', '/merchant/iklan',
  '/merchant/analytics', '/merchant/visitor-stats', '/merchant/insight', '/merchant/finance', '/merchant/pajak',
  '/merchant/import-export', '/merchant/withdrawal', '/merchant/dues', '/merchant/wallet', '/merchant/subscription',
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

export function getFeatureTourStorageKey(userId: string, role: FeatureTourRole): string {
  return `sadesa:feature-tour:v1:${userId}:${role}`;
}

export function getFeatureTourSessionKey(userId: string, role: FeatureTourRole): string {
  return `sadesa:feature-tour-deferred:v1:${userId}:${role}`;
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
