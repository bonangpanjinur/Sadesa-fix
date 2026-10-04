import { Navigate, useLocation } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { usePOS, type POSRole } from '@/contexts/POSContext';
import type { AppRole } from '@/types/auth';
import { isPOSModuleEnabled, isPOSOperational, isPOSSetupStatus } from '@/lib/posFeatureGate';
import { getPOSNavigationItem } from './posNavigation';

import { canAccessPOSPath, getPOSPermission } from './posPermissionConfig';

export function POSAccessRoute({ children }: { children: React.ReactNode }) {
  const { user, roles, rolesLoading, merchantRoleRecoveryLoading } = useAuth();
  const { tenant, posEnabled, posRole, posRoleLoading } = usePOS();
  const location = useLocation();
  const isSetupRoute = location.pathname === '/merchant/pos/setup' || location.pathname === '/pos/setup';

  if (rolesLoading || (Boolean(user) && posRoleLoading)
    || (Boolean(user) && !roles.includes('merchant') && merchantRoleRecoveryLoading)) {
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
  if (isSetupRoute) return <>{children}</>;
  if (!tenant || isPOSSetupStatus(tenant.status)) {
    return <Navigate to="/merchant/pos/setup" state={{ from: location }} replace />;
  }
  const permissionPath = location.pathname.replace(/^\/pos(?=\/|$)/, '/merchant/pos');
  const permission = getPOSPermission(permissionPath);
  const navigationItem = getPOSNavigationItem(permissionPath);
  if (!posEnabled || !isPOSOperational(tenant.status)
    || !isPOSModuleEnabled(tenant.enabled_modules, navigationItem?.moduleId ?? permission?.moduleId)) {
    return <Navigate to="/merchant/pos/subscribe" state={{ from: location }} replace />;
  }
  return <>{children}</>;
}
