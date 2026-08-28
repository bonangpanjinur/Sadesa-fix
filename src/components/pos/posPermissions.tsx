import { Navigate, useLocation } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
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
}

const POS_ROLES: AppRole[] = ['admin', 'merchant'];
const FINANCE_ROLES: AppRole[] = ['admin', 'merchant'];

export const POS_MENU_PERMISSIONS: POSMenuPermission[] = [
  { path: '/pos', area: 'operations', roles: POS_ROLES },
  { path: '/pos/kasir', area: 'operations', roles: POS_ROLES },
  { path: '/pos/transaksi', area: 'operations', roles: POS_ROLES },
  { path: '/pos/retur', area: 'operations', roles: POS_ROLES },
  { path: '/pos/meja', area: 'operations', roles: POS_ROLES },
  { path: '/pos/kds', area: 'operations', roles: POS_ROLES },
  { path: '/pos/menu-qr', area: 'operations', roles: POS_ROLES },
  { path: '/pos/kiosk', area: 'operations', roles: POS_ROLES },
  { path: '/pos/customer', area: 'operations', roles: POS_ROLES },
  { path: '/pos/produk', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/kategori', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/stok', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/bahan-baku', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/resep', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/gudang', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/transfer-stok', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/supplier', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/pembelian', area: 'inventory', roles: POS_ROLES },
  { path: '/pos/hutang', area: 'finance', roles: FINANCE_ROLES },
  { path: '/pos/hutang-piutang', area: 'finance', roles: FINANCE_ROLES },
  { path: '/pos/kas', area: 'finance', roles: FINANCE_ROLES },
  { path: '/pos/akuntansi', area: 'finance', roles: FINANCE_ROLES },
  { path: '/pos/laporan', area: 'reports', roles: FINANCE_ROLES },
  { path: '/pos/laporan/laba-rugi', area: 'reports', roles: FINANCE_ROLES },
  { path: '/pos/laporan/kasir', area: 'reports', roles: FINANCE_ROLES },
  { path: '/pos/laporan/stok', area: 'reports', roles: POS_ROLES },
  { path: '/pos/laporan/cashflow', area: 'reports', roles: FINANCE_ROLES },
  { path: '/pos/laporan/outlet', area: 'reports', roles: FINANCE_ROLES },
  { path: '/pos/analitik', area: 'reports', roles: FINANCE_ROLES },
  { path: '/pos/analitik-produk', area: 'reports', roles: FINANCE_ROLES },
  { path: '/pos/audit', area: 'administration', roles: ['admin', 'merchant'] },
  { path: '/pos/akses', area: 'administration', roles: ['admin', 'merchant'] },
  { path: '/pos/promosi', area: 'administration', roles: POS_ROLES },
  { path: '/pos/loyalty', area: 'administration', roles: POS_ROLES },
  { path: '/pos/integrasi', area: 'administration', roles: POS_ROLES },
  { path: '/pos/jadwal', area: 'workforce', roles: POS_ROLES },
  { path: '/pos/absensi', area: 'workforce', roles: POS_ROLES },
  { path: '/pos/penggajian', area: 'workforce', roles: FINANCE_ROLES },
  { path: '/pos/target-omzet', area: 'reports', roles: FINANCE_ROLES },
  { path: '/pos/pengguna', area: 'administration', roles: ['admin', 'merchant'] },
  { path: '/pos/pengaturan', area: 'administration', roles: ['admin', 'merchant'] },
  { path: '/pos/harga', area: 'inventory', roles: ['admin', 'merchant'] },
];

export function getPOSPermission(path: string): POSMenuPermission | undefined {
  return POS_MENU_PERMISSIONS.find((permission) => path === permission.path);
}

export function canAccessPOSPath(roles: AppRole[], path: string): boolean {
  const permission = getPOSPermission(path);
  if (!permission) return path === '/pos/setup';
  return permission.roles.some((role) => roles.includes(role));
}

export function POSAccessRoute({ children }: { children: React.ReactNode }) {
  const { user, roles, rolesLoading } = useAuth();
  const location = useLocation();

  if (rolesLoading) {
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
  if (!canAccessPOSPath(roles, location.pathname)) return <Navigate to="/unauthorized" replace />;
  return <>{children}</>;
}
