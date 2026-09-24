import { useEffect, useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useUserRoles } from '@/hooks/useUserRoles';
import type { AppRole } from '@/types/auth';
import { Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

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
  const isPOSRoute = location.pathname === '/pos' || location.pathname.startsWith('/pos/');
  const isMerchantWorkspaceRoute = location.pathname === '/merchant'
    || location.pathname.startsWith('/merchant/');
  const isCourierWorkspaceRoute = location.pathname === '/courier'
    || location.pathname.startsWith('/courier/');
  const requiresApprovedMerchant = isMerchantWorkspaceRoute && location.pathname !== '/merchant';
  const requiredRoles = allowedRoles
    ?? (isPOSRoute ? posRouteRoles : isMerchantWorkspaceRoute ? ['merchant'] : undefined);
  const routeRequiredRoles = requiredRoles
    ?? (isCourierWorkspaceRoute ? ['courier'] : undefined);
  const [merchantAccessLoading, setMerchantAccessLoading] = useState(false);
  const [merchantAccessAllowed, setMerchantAccessAllowed] = useState(true);

  useEffect(() => {
    if (!requiresApprovedMerchant || !user || rolesLoading || !roles.includes('merchant')) {
      setMerchantAccessLoading(false);
      setMerchantAccessAllowed(true);
      return;
    }

    let cancelled = false;
    setMerchantAccessLoading(true);

    void supabase
      .from('merchants')
      .select('registration_status, status')
      .eq('user_id', user.id)
      .maybeSingle()
      .then(({ data, error }) => {
        if (cancelled) return;
        const allowed = !error
          && data?.registration_status === 'APPROVED'
          && data.status === 'ACTIVE';
        setMerchantAccessAllowed(allowed);
        setMerchantAccessLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [location.pathname, requiresApprovedMerchant, roles, rolesLoading, user]);

  // Show loading while checking auth state
  const waitingForRequiredRoles = (Boolean(routeRequiredRoles?.length) && rolesLoading)
    || merchantAccessLoading;

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
  if (routeRequiredRoles && routeRequiredRoles.length > 0) {
    if (!hasAnyRole(routeRequiredRoles)) {
      // User doesn't have required role - redirect to appropriate dashboard
      return <Navigate to="/unauthorized" replace />;
    }
  }

  if (requiresApprovedMerchant && !merchantAccessAllowed) {
    return <Navigate to="/merchant" state={{ from: location, reason: 'merchant_not_active' }} replace />;
  }

  return <>{children}</>;
}
