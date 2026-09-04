import { Navigate, useLocation } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { usePOS, type POSRole } from '@/contexts/POSContext';
import type { AppRole } from '@/types/auth';

export type POSArea =
  | 'operations'
  | 'inventory'
  | 'finance'
  | 'workforce'
  | 'reports'
  | 'administration';

export interface POSMenuPermission {
  path: string;
  area: POSArea;
  roles: AppRole[];
  posRoles: POSRole[];
}

const ALL_APP_POS_ROLES: AppRole[] = ['admin', 'merchant'];
const OWNER_MANAGER: POSRole[] = ['owner', 'manager'];
const OPERATIONS: POSRole[] = ['owner', 'manager', 'kasir', 'auditor'];
const INVENTORY: POSRole[] = ['owner', 'manager', 'staff_gudang', 'purchasing'];
const FINANCE: POSRole[] = ['owner', 'manager', 'finance', 'auditor'];
const REPORTS: POSRole[] = ['owner', 'manager', 'finance', 'auditor'];
const WORKFORCE: POSRole[] = ['owner', 'manager', 'finance'];

export const POS_MENU_PERMISSIONS: POSMenuPermission[] = [
  { path: '/pos', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ALL_APP_POS_ROLES.length ? ['owner', 'manager', 'kasir', 'staff_gudang', 'purchasing', 'finance', 'auditor'] : [] },
  { path: '/pos/kasir', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/pos/transaksi', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: OPERATIONS },
  { path: '/pos/retur', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/pos/meja', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/pos/kds', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/pos/menu-qr', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/pos/kiosk', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'kasir'] },
  { path: '/pos/customer', area: 'operations', roles: ALL_APP_POS_ROLES, posRoles: OPERATIONS },
  { path: '/pos/produk', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/pos/kategori', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/pos/stok', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/pos/bahan-baku', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/pos/resep', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/pos/gudang', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/pos/transfer-stok', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/pos/supplier', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: INVENTORY },
  { path: '/pos/pembelian', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'purchasing'] },
  { path: '/pos/hutang', area: 'finance', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/pos/hutang-piutang', area: 'finance', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/pos/kas', area: 'finance', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/pos/akuntansi', area: 'finance', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/pos/laporan', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/pos/laporan/laba-rugi', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/pos/laporan/kasir', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/pos/laporan/stok', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: [...INVENTORY, 'finance', 'auditor'] },
  { path: '/pos/laporan/cashflow', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: FINANCE },
  { path: '/pos/laporan/outlet', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/pos/analitik', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/pos/analitik-produk', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: REPORTS },
  { path: '/pos/audit', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'auditor'] },
  { path: '/pos/akses', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/pos/promosi', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/pos/loyalty', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/pos/integrasi', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/pos/jadwal', area: 'workforce', roles: ALL_APP_POS_ROLES, posRoles: WORKFORCE },
  { path: '/pos/absensi', area: 'workforce', roles: ALL_APP_POS_ROLES, posRoles: WORKFORCE },
  { path: '/pos/penggajian', area: 'workforce', roles: ALL_APP_POS_ROLES, posRoles: ['owner', 'manager', 'finance'] },
  { path: '/pos/target-omzet', area: 'reports', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/pos/pengguna', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/pos/pengaturan', area: 'administration', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
  { path: '/pos/harga', area: 'inventory', roles: ALL_APP_POS_ROLES, posRoles: OWNER_MANAGER },
];

export function getPOSPermission(path: string): POSMenuPermission | undefined {
  return POS_MENU_PERMISSIONS.find((permission) => path === permission.path);
}

export function canAccessPOSPath(roles: AppRole[], path: string, posRole?: POSRole | null): boolean {
  // `/merchant/pos` is a compatibility URL only. Treat it as the canonical
  // cashier permission while the route itself performs an immediate redirect.
  const permissionPath = path === '/merchant/pos' ? '/pos/kasir' : path;
  const permission = getPOSPermission(permissionPath);
  if (!permission) return path === '/pos/setup' && roles.some((role) => ALL_APP_POS_ROLES.includes(role));
  if (!permission.roles.some((role) => roles.includes(role))) return false;
  return posRole ? permission.posRoles.includes(posRole) : true;
}

export function POSAccessRoute({ children }: { children: React.ReactNode }) {
  const { user, roles, rolesLoading } = useAuth();
  const { posRole, posRoleLoading } = usePOS();
  const location = useLocation();

  if (rolesLoading || (Boolean(user) && posRoleLoading)) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-3">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
          <p className="text-sm text-muted-foreground">Memeriksa akses POS...</p>
        </div>
      </div>
    );
  }

  if (!user) return <Navigate to="/auth" state={{ from: location }} replace />;
  if (!canAccessPOSPath(roles, location.pathname, posRole)) return <Navigate to="/unauthorized" replace />;
  return <>{children}</>;
}
