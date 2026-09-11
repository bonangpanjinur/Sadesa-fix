import type { AppRole } from '@/types/auth';
import type { POSRole } from '@/contexts/POSContext';

export type POSArea = 'operations' | 'inventory' | 'finance' | 'workforce' | 'reports' | 'administration';
export interface POSMenuPermission { path: string; area: POSArea; roles: AppRole[]; posRoles: POSRole[]; moduleId?: string; }

const ALL_APP_POS_ROLES: AppRole[] = ['admin', 'merchant'];
const OWNER_MANAGER: POSRole[] = ['owner', 'manager'];
const OPERATIONS: POSRole[] = ['owner', 'manager', 'kasir', 'auditor'];
const INVENTORY: POSRole[] = ['owner', 'manager', 'staff_gudang', 'purchasing'];
const FINANCE: POSRole[] = ['owner', 'manager', 'finance', 'auditor'];
const REPORTS: POSRole[] = ['owner', 'manager', 'finance', 'auditor'];
const WORKFORCE: POSRole[] = ['owner', 'manager', 'finance'];

export const POS_MENU_PERMISSIONS: POSMenuPermission[] = [
  { path: '/merchant/pos', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir', 'staff_gudang', 'purchasing', 'finance', 'auditor'] },
  { path: '/merchant/pos/kasir', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/merchant/pos/transaksi', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: OPERATIONS },
  { path: '/merchant/pos/retur', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/merchant/pos/meja', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/merchant/pos/kds', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/merchant/pos/menu-qr', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/merchant/pos/kiosk', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/merchant/pos/customer', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: OPERATIONS },
  { path: '/merchant/pos/produk', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/merchant/pos/kategori', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/merchant/pos/stok', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/merchant/pos/bahan-baku', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/merchant/pos/resep', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/merchant/pos/gudang', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/merchant/pos/transfer-stok', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/merchant/pos/supplier', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/merchant/pos/pembelian', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'purchasing'] },
  { path: '/merchant/pos/hutang', area: 'finance', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/merchant/pos/hutang-piutang', area: 'finance', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/merchant/pos/kas', area: 'finance', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/merchant/pos/akuntansi', area: 'finance', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/merchant/pos/laporan', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/merchant/pos/laporan/laba-rugi', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/merchant/pos/laporan/kasir', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/merchant/pos/laporan/stok', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: [...INVENTORY, 'finance', 'auditor'] },
  { path: '/merchant/pos/laporan/cashflow', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/merchant/pos/laporan/outlet', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/merchant/pos/analitik', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/merchant/pos/analitik-produk', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/merchant/pos/audit', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'auditor'] },
  { path: '/merchant/pos/akses', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/merchant/pos/promosi', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/merchant/pos/loyalty', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/merchant/pos/integrasi', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/merchant/pos/jadwal', area: 'workforce', roles: ALL_APP_POS_ROLES, posRoles: WORKFORCE },
  { path: '/merchant/pos/absensi', area: 'workforce', roles: ALL_APP_POS_ROLES, posRoles: WORKFORCE },
  { path: '/merchant/pos/penggajian', area: 'workforce', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'finance'] },
  { path: '/merchant/pos/target-omzet', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/merchant/pos/pengguna', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/merchant/pos/pengaturan', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/merchant/pos/harga', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
];

export function getPOSPermission(path: string): POSMenuPermission | undefined { return POS_MENU_PERMISSIONS.find((permission) => path === permission.path); }
export function canAccessPOSPath(roles: AppRole[], path: string, posRole?: POSRole | null): boolean {
  const permissionPath = path.replace(/^\/pos(?=\/|$)/, '/merchant/pos');
  const permission = getPOSPermission(permissionPath);
  if (!permission) return permissionPath === '/merchant/pos/setup' && roles.some((role) => ALL_APP_POS_ROLES.includes(role));
  if (!permission.roles.some((role) => roles.includes(role))) return false;
  return posRole ? permission.posRoles.includes(posRole) : true;
}
