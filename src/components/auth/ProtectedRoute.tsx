import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useUserRoles } from '@/hooks/useUserRoles';
import type { AppRole } from '@/types/auth';
import { Loader2 } from 'lucide-react';

interface ProtectedRouteProps {
  children: React.ReactNode;
  allowedRoles?: AppRole[];
  redirectTo?: string;
}

export function ProtectedRoute({ 
  children, 
  allowedRoles,
  redirectTo = '/auth' 
}: ProtectedRouteProps) {
  const { user, loading: authLoading } = useAuth();
  const { roles, loading: rolesLoading, hasAnyRole } = useUserRoles();
  const location = useLocation();
  const posRouteRoles: AppRole[] = ['admin', 'merchant'];
  const requiredRoles = allowedRoles ?? (location.pathname === '/pos' || location.pathname.startsWith('/pos/') ? posRouteRoles : undefined);

  // Show loading while checking auth state
  const waitingForRequiredRoles = Boolean(requiredRoles?.length) && rolesLoading;

  if (authLoading || waitingForRequiredRoles) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-3">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
          <p className="text-sm text-muted-foreground">Memuat...</p>
        </div>
      </div>
    );
  }

  // Redirect to auth if not logged in
  if (!user) {
    return <Navigate to={redirectTo} state={{ from: location }} replace />;
  }

  // If specific roles are required, check them
  if (requiredRoles && requiredRoles.length > 0) {
    if (!hasAnyRole(requiredRoles)) {
      // User doesn't have required role - redirect to appropriate dashboard
      return <Navigate to="/unauthorized" replace />;
    }
  }

  return <>{children}</>;
}
