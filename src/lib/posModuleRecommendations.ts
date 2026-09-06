export type POSBusinessType = 'online' | 'retail' | 'cafe' | 'multi_outlet' | 'simple';

export interface POSBusinessOption {
  id: POSBusinessType;
  label: string;
  description: string;
  icon: string;
}

export interface POSModuleOption {
  id: string;
  label: string;
  description: string;
}

export const POS_BUSINESS_OPTIONS: POSBusinessOption[] = [
  { id: 'online', label: 'Hanya online', description: 'Saya belum menerima pembayaran langsung di toko fisik.', icon: 'globe' },
  { id: 'retail', label: 'Toko retail', description: 'Pakaian, sembako, kerajinan, atau toko dengan produk fisik.', icon: 'shopping-bag' },
  { id: 'cafe', label: 'Kafe atau restoran', description: 'Butuh meja, menu QR, dapur, dan bahan baku.', icon: 'utensils' },
  { id: 'multi_outlet', label: 'Beberapa outlet', description: 'Mengelola kasir dan stok di lebih dari satu lokasi.', icon: 'store' },
  { id: 'simple', label: 'Usaha sederhana', description: 'Kasir ringan, stok dasar, transaksi, dan laporan harian.', icon: 'store' },
];

export const POS_MODULE_OPTIONS: POSModuleOption[] = [
  { id: 'cashier', label: 'Kasir', description: 'Terima pembayaran langsung dan kelola transaksi toko.' },
  { id: 'barcode', label: 'Barcode', description: 'Cari produk lebih cepat dengan scanner barcode.' },
  { id: 'variants', label: 'Varian produk', description: 'Kelola ukuran, warna, atau pilihan produk.' },
  { id: 'outlet_stock', label: 'Stok outlet', description: 'Pantau stok berdasarkan lokasi operasional.' },
  { id: 'purchasing', label: 'Pembelian & supplier', description: 'Catat pembelian dan utang supplier.' },
  { id: 'returns', label: 'Retur', description: 'Proses pengembalian barang dari transaksi toko.' },
  { id: 'multi_outlet', label: 'Multi-outlet', description: 'Kelola lebih dari satu outlet dan transfer stok.' },
  { id: 'sales_reports', label: 'Laporan penjualan', description: 'Lihat ringkasan penjualan dan performa kasir.' },
  { id: 'tables', label: 'Meja & dine-in', description: 'Kelola pesanan berdasarkan meja pelanggan.' },
  { id: 'qr_menu', label: 'Menu digital QR', description: 'Bagikan menu digital untuk pemesanan di tempat.' },
  { id: 'kds', label: 'KDS dapur', description: 'Kirim dan pantau pesanan di area dapur.' },
  { id: 'ingredients', label: 'Bahan baku', description: 'Pantau pemakaian bahan baku operasional.' },
  { id: 'recipes', label: 'Resep', description: 'Hubungkan menu dengan kebutuhan bahan baku.' },
  { id: 'shifts', label: 'Shift kasir', description: 'Buka, tutup, dan rekonsiliasi shift kasir.' },
];

const RECOMMENDED_MODULES: Record<POSBusinessType, string[]> = {
  online: [],
  retail: ['cashier', 'barcode', 'variants', 'outlet_stock', 'purchasing', 'returns', 'multi_outlet', 'sales_reports'],
  cafe: ['cashier', 'tables', 'qr_menu', 'kds', 'ingredients', 'recipes', 'shifts', 'sales_reports'],
  multi_outlet: ['cashier', 'barcode', 'outlet_stock', 'purchasing', 'returns', 'multi_outlet', 'sales_reports', 'shifts'],
  simple: ['cashier', 'outlet_stock', 'sales_reports'],
};

export function getRecommendedPOSModules(businessType: POSBusinessType) {
  return RECOMMENDED_MODULES[businessType];
}