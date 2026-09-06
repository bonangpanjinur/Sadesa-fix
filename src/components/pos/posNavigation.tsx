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
  LayoutDashboard,
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
    label: 'Operasional',
    icon: <ShoppingCart className="h-4 w-4" />,
    items: [
      { label: 'Dashboard POS', href: '/merchant/pos', icon: <LayoutDashboard className="h-4 w-4" /> },
      { label: 'Kasir', href: '/merchant/pos/kasir', icon: <ShoppingCart className="h-4 w-4" /> },
      { label: 'Mode Kiosk', href: '/merchant/pos/kiosk', icon: <Store className="h-4 w-4" /> },
      { label: 'Manajemen Meja', href: '/merchant/pos/meja', icon: <Table2 className="h-4 w-4" /> },
      { label: 'Menu Digital QR', href: '/merchant/pos/menu-qr', icon: <QrCode className="h-4 w-4" /> },
      { label: 'KDS (Dapur)', href: '/merchant/pos/kds', icon: <Tv2 className="h-4 w-4" /> },
      { label: 'Transaksi POS', href: '/merchant/pos/transaksi', icon: <ClipboardList className="h-4 w-4" /> },
      { label: 'Retur POS', href: '/merchant/pos/retur', icon: <RotateCcw className="h-4 w-4" /> },
      { label: 'Pembelian POS', href: '/merchant/pos/pembelian', icon: <ShoppingBag className="h-4 w-4" /> },
      { label: 'Kas Harian POS', href: '/merchant/pos/kas', icon: <Wallet className="h-4 w-4" /> },
    ],
  },
  {
    id: 'inventori',
    label: 'Inventori & Pembelian',
    icon: <Package className="h-4 w-4" />,
    items: [
      { label: 'Harga POS', href: '/merchant/pos/harga', icon: <Tag className="h-4 w-4" /> },
      { label: 'Bahan Baku', href: '/merchant/pos/bahan-baku', icon: <FlaskConical className="h-4 w-4" /> },
      { label: 'Resep Produk', href: '/merchant/pos/resep', icon: <ChefHat className="h-4 w-4" /> },
      { label: 'Kategori POS', href: '/merchant/pos/kategori', icon: <Tag className="h-4 w-4" /> },
      { label: 'Supplier', href: '/merchant/pos/supplier', icon: <Truck className="h-4 w-4" /> },
      { label: 'Hutang Supplier', href: '/merchant/pos/hutang', icon: <CreditCard className="h-4 w-4" /> },
      { label: 'Stok POS', href: '/merchant/pos/stok', icon: <Archive className="h-4 w-4" /> },
      { label: 'Transfer Stok', href: '/merchant/pos/transfer-stok', icon: <ArrowRightLeft className="h-4 w-4" /> },
      { label: 'Multi-Gudang', href: '/merchant/pos/gudang', icon: <Warehouse className="h-4 w-4" /> },
    ],
  },
  {
    id: 'pelanggan',
    label: 'Pelanggan & Marketing POS',
    icon: <Users className="h-4 w-4" />,
    items: [
      { label: 'Customer POS', href: '/merchant/pos/customer', icon: <Users className="h-4 w-4" /> },
      { label: 'Promosi & Voucher POS', href: '/merchant/pos/promosi', icon: <Ticket className="h-4 w-4" /> },
      { label: 'Program Loyalty POS', href: '/merchant/pos/loyalty', icon: <Star className="h-4 w-4" /> },
      { label: 'Analitik Pelanggan POS', href: '/merchant/pos/analitik', icon: <PieChart className="h-4 w-4" /> },
    ],
  },
  {
    id: 'laporan',
    label: 'Laporan & Analitik POS',
    icon: <BarChart3 className="h-4 w-4" />,
    items: [
      { label: 'Lap. Penjualan POS', href: '/merchant/pos/laporan', icon: <BarChart3 className="h-4 w-4" /> },
      { label: 'Lap. Laba Rugi', href: '/merchant/pos/laporan/laba-rugi', icon: <TrendingUp className="h-4 w-4" /> },
      { label: 'Lap. Per Kasir', href: '/merchant/pos/laporan/kasir', icon: <UserCheck className="h-4 w-4" /> },
      { label: 'Lap. Stok POS', href: '/merchant/pos/laporan/stok', icon: <BoxesIcon className="h-4 w-4" /> },
      { label: 'Lap. Cashflow', href: '/merchant/pos/laporan/cashflow', icon: <Banknote className="h-4 w-4" /> },
      { label: 'Lap. Outlet', href: '/merchant/pos/laporan/outlet', icon: <GitCompare className="h-4 w-4" /> },
      { label: 'Analitik Produk POS', href: '/merchant/pos/analitik-produk', icon: <TrendingUp className="h-4 w-4" /> },
    ],
  },
  {
    id: 'sdm-keuangan',
    label: 'Keuangan & SDM POS',
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
    label: 'Administrasi & Integrasi POS',
    icon: <Settings className="h-4 w-4" />,
    items: [
      { label: 'Audit Trail', href: '/merchant/pos/audit', icon: <Shield className="h-4 w-4" /> },
      { label: 'Offline Conflict Center', href: '/merchant/pos/offline-conflicts', icon: <WifiOff className="h-4 w-4" /> },
      { label: 'Manajemen Akses', href: '/merchant/pos/akses', icon: <KeyRound className="h-4 w-4" /> },
      { label: 'Pengguna POS', href: '/merchant/pos/pengguna', icon: <UserCog className="h-4 w-4" /> },
      { label: 'Integrasi Marketplace', href: '/merchant/pos/integrasi', icon: <Globe className="h-4 w-4" /> },
      { label: 'Pengaturan POS', href: '/merchant/pos/pengaturan', icon: <Settings className="h-4 w-4" /> },
    ],
  },
];

export function isPOSItemActive(pathname: string, href: string) {
  return href === '/merchant/pos' ? pathname === href : pathname.startsWith(href);
}