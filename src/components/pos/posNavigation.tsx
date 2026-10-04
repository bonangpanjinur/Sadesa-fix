import type { ReactNode } from 'react';
import {
  Archive,
  ArrowRightLeft,
  BarChart3,
  Banknote,
  BoxesIcon,
  Calendar,
  ChefHat,
  CheckCircle2,
  ChevronDown,
  ClipboardList,
  Clock,
  CreditCard,
  DollarSign,
  FlaskConical,
  Globe,
  GitCompare,
  KeyRound,
  Package,
  PieChart,
  QrCode,
  RotateCcw,
  Settings,
  Shield,
  ShoppingBag,
  ShoppingCart,
  Star,
  Store,
  Table2,
  Tag,
  Target,
  Ticket,
  TrendingUp,
  Truck,
  Tv2,
  UserCheck,
  UserCog,
  Users,
  Wallet,
  Warehouse,
  WifiOff,
} from 'lucide-react';

export interface POSSidebarItem {
  label: string;
  href: string;
  icon: ReactNode;
  badge?: number;
  moduleId?: string;
  scope?: 'merchant' | 'pos';
}

export interface POSSidebarCategory {
  id: string;
  label: string;
  icon: ReactNode;
  items: POSSidebarItem[];
}

/**
 * The canonical POS navigation for the merchant workspace.
 *
 * POS is intentionally embedded in MerchantSidebar. Keeping this data outside
 * of a sidebar component prevents a second POS navigation from drifting back
 * into the application.
 */
export const POS_MENU_CATEGORIES: POSSidebarCategory[] = [
  {
    id: 'operasional',
    label: 'Operasional Toko',
    icon: <ShoppingCart className="h-4 w-4" />,
    items: [
      { label: 'Kasir', href: '/merchant/pos/kasir', icon: <ShoppingCart className="h-4 w-4" />, moduleId: 'cashier' },
      { label: 'Mode Kiosk', href: '/merchant/pos/kiosk', icon: <Store className="h-4 w-4" />, moduleId: 'cashier' },
      { label: 'Manajemen Meja', href: '/merchant/pos/meja', icon: <Table2 className="h-4 w-4" />, moduleId: 'tables' },
      { label: 'Menu Digital QR', href: '/merchant/pos/menu-qr', icon: <QrCode className="h-4 w-4" />, moduleId: 'qr_menu' },
      { label: 'KDS (Dapur)', href: '/merchant/pos/kds', icon: <Tv2 className="h-4 w-4" />, moduleId: 'kds' },
      { label: 'Transaksi Toko', href: '/merchant/pos/transaksi', icon: <ClipboardList className="h-4 w-4" />, moduleId: 'cashier' },
      { label: 'Retur Toko', href: '/merchant/pos/retur', icon: <RotateCcw className="h-4 w-4" />, moduleId: 'returns' },
      { label: 'Pembelian', href: '/merchant/pos/pembelian', icon: <ShoppingBag className="h-4 w-4" />, moduleId: 'purchasing' },
      { label: 'Kas Harian', href: '/merchant/pos/kas', icon: <Wallet className="h-4 w-4" />, moduleId: 'cashier' },
    ],
  },
  {
    id: 'inventori',
    label: 'Inventori & Pembelian',
    icon: <Package className="h-4 w-4" />,
    items: [
      { label: 'Katalog Produk', href: '/merchant/products', icon: <Package className="h-4 w-4" />, scope: 'merchant' },
      { label: 'Bahan Baku', href: '/merchant/pos/bahan-baku', icon: <FlaskConical className="h-4 w-4" />, moduleId: 'ingredients' },
      { label: 'Resep Produk', href: '/merchant/pos/resep', icon: <ChefHat className="h-4 w-4" />, moduleId: 'recipes' },
      { label: 'Kategori Produk', href: '/merchant/pos/kategori', icon: <Tag className="h-4 w-4" /> },
      { label: 'Supplier', href: '/merchant/pos/supplier', icon: <Truck className="h-4 w-4" />, moduleId: 'purchasing' },
      { label: 'Hutang Supplier', href: '/merchant/pos/hutang', icon: <CreditCard className="h-4 w-4" />, moduleId: 'purchasing' },
      { label: 'Stok Outlet', href: '/merchant/pos/stok', icon: <Archive className="h-4 w-4" />, moduleId: 'outlet_stock' },
      { label: 'Transfer Stok', href: '/merchant/pos/transfer-stok', icon: <ArrowRightLeft className="h-4 w-4" />, moduleId: 'multi_outlet' },
      { label: 'Multi-Gudang', href: '/merchant/pos/gudang', icon: <Warehouse className="h-4 w-4" />, moduleId: 'multi_outlet' },
    ],
  },
  {
    id: 'pelanggan',
    label: 'Promosi & Pelanggan',
    icon: <Users className="h-4 w-4" />,
    items: [
      { label: 'Pelanggan', href: '/merchant/pos/customer', icon: <Users className="h-4 w-4" /> },
      { label: 'Promosi & Voucher', href: '/merchant/pos/promosi', icon: <Ticket className="h-4 w-4" /> },
      { label: 'Program Loyalty', href: '/merchant/pos/loyalty', icon: <Star className="h-4 w-4" /> },
      { label: 'Analitik Pelanggan', href: '/merchant/pos/analitik', icon: <PieChart className="h-4 w-4" />, moduleId: 'sales_reports' },
    ],
  },
  {
    id: 'laporan',
    label: 'Analitik & Laporan',
    icon: <BarChart3 className="h-4 w-4" />,
    items: [
      { label: 'Laporan Penjualan', href: '/merchant/pos/laporan', icon: <BarChart3 className="h-4 w-4" />, moduleId: 'sales_reports' },
      { label: 'Lap. Laba Rugi', href: '/merchant/pos/laporan/laba-rugi', icon: <TrendingUp className="h-4 w-4" />, moduleId: 'sales_reports' },
      { label: 'Lap. Per Kasir', href: '/merchant/pos/laporan/kasir', icon: <UserCheck className="h-4 w-4" />, moduleId: 'sales_reports' },
      { label: 'Laporan Stok', href: '/merchant/pos/laporan/stok', icon: <BoxesIcon className="h-4 w-4" />, moduleId: 'outlet_stock' },
      { label: 'Lap. Cashflow', href: '/merchant/pos/laporan/cashflow', icon: <Banknote className="h-4 w-4" />, moduleId: 'sales_reports' },
      { label: 'Lap. Outlet', href: '/merchant/pos/laporan/outlet', icon: <GitCompare className="h-4 w-4" />, moduleId: 'multi_outlet' },
      { label: 'Analitik Produk', href: '/merchant/pos/analitik-produk', icon: <TrendingUp className="h-4 w-4" />, moduleId: 'sales_reports' },
    ],
  },
  {
    id: 'sdm-keuangan',
    label: 'Keuangan & Tim',
    icon: <Wallet className="h-4 w-4" />,
    items: [
      { label: 'Hutang & Piutang', href: '/merchant/pos/hutang-piutang', icon: <CreditCard className="h-4 w-4" /> },
      { label: 'Ekspor Akuntansi', href: '/merchant/pos/akuntansi', icon: <CheckCircle2 className="h-4 w-4" /> },
      { label: 'Jadwal Shift', href: '/merchant/pos/jadwal', icon: <Calendar className="h-4 w-4" /> },
      { label: 'Absensi', href: '/merchant/pos/absensi', icon: <Clock className="h-4 w-4" /> },
      { label: 'Penggajian', href: '/merchant/pos/penggajian', icon: <DollarSign className="h-4 w-4" /> },
      { label: 'Target Omzet', href: '/merchant/pos/target-omzet', icon: <Target className="h-4 w-4" /> },
    ],
  },
  {
    id: 'administrasi',
    label: 'Administrasi & Integrasi',
    icon: <Settings className="h-4 w-4" />,
    items: [
      { label: 'Langganan & Paket POS', href: '/merchant/pos/harga', icon: <CreditCard className="h-4 w-4" /> },
      { label: 'Audit Trail', href: '/merchant/pos/audit', icon: <Shield className="h-4 w-4" /> },
      { label: 'Offline Conflict Center', href: '/merchant/pos/offline-conflicts', icon: <WifiOff className="h-4 w-4" /> },
      { label: 'Manajemen Akses', href: '/merchant/pos/akses', icon: <KeyRound className="h-4 w-4" /> },
      { label: 'Pengguna & Kasir', href: '/merchant/pos/pengguna', icon: <UserCog className="h-4 w-4" /> },
      { label: 'Integrasi Marketplace', href: '/merchant/pos/integrasi', icon: <Globe className="h-4 w-4" /> },
      { label: 'Pengaturan Operasional', href: '/merchant/pos/pengaturan', icon: <Settings className="h-4 w-4" /> },
    ],
  },
];

export function isPOSItemActive(pathname: string, href: string) {
  return href === '/merchant/pos' ? pathname === href : pathname.startsWith(href);
}

export function getPOSNavigationItem(pathname: string) {
  return POS_MENU_CATEGORIES
    .flatMap((category) => category.items)
    .find((item) => item.href === pathname);
}
