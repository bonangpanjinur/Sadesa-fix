import { Navigate, useLocation } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { getRedirectPathForRoles } from '@/types/auth';

/**
 * Canonical entrypoint for users who want to open their dashboard without
 * knowing which role-specific workspace they belong to.
 */
export function DashboardRoute() {
  const { user, roles, loading, rolesLoading, merchantRoleRecoveryLoading } = useAuth();
  const location = useLocation();

  if (loading || (user && (rolesLoading || merchantRoleRecoveryLoading))) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background" role="status" aria-live="polite">
        <div className="flex flex-col items-center gap-3">
          <Loader2 className="h-8 w-8 animate-spin text-primary" aria-hidden="true" />
          <p className="text-sm text-muted-foreground">Memuat dashboard…</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return <Navigate to="/auth" state={{ from: location }} replace />;
  }

  return <Navigate to={getRedirectPathForRoles(roles)} replace />;
}
