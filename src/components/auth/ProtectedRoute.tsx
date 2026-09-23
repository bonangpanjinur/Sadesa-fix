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
  const requiresApprovedMerchant = isMerchantWorkspaceRoute && location.pathname !== '/merchant';
  const requiredRoles = allowedRoles
    ?? (isPOSRoute ? posRouteRoles : isMerchantWorkspaceRoute ? ['merchant'] : undefined);
  const [merchantAccessLoading, setMerchantAccessLoading] = useState(false);
  const [merchantAccessAllowed, setMerchantAccessAllowed] = useState(true);
  const [profileCompletionLoading, setProfileCompletionLoading] = useState(false);
  const [profileComplete, setProfileComplete] = useState(true);

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

  useEffect(() => {
    if (!user || location.pathname === '/account') {
      setProfileCompletionLoading(false);
      setProfileComplete(true);
      return;
    }
    let cancelled = false;
    setProfileCompletionLoading(true);
    void supabase
      .from('profiles')
      .select('address, avatar_url, province_id, city_id, district_id, village_id, address_detail')
      .eq('user_id', user.id)
      .maybeSingle()
      .then(({ data, error }) => {
        if (cancelled) return;
        const complete = !error && Boolean(
          data?.avatar_url && data.address && data.province_id && data.city_id
            && data.district_id && data.village_id && data.address_detail?.trim(),
        );
        setProfileComplete(complete);
        setProfileCompletionLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [location.pathname, user]);

  // Show loading while checking auth state
  const waitingForRequiredRoles = (Boolean(requiredRoles?.length) && rolesLoading)
    || merchantAccessLoading || profileCompletionLoading;

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

  if (location.pathname !== '/account' && !profileComplete) {
    return <Navigate to="/account" state={{ from: location, reason: 'profile_incomplete' }} replace />;
  }

  // If specific roles are required, check them
  if (requiredRoles && requiredRoles.length > 0) {
    if (!hasAnyRole(requiredRoles)) {
      // User doesn't have required role - redirect to appropriate dashboard
      return <Navigate to="/unauthorized" replace />;
    }
  }

  if (requiresApprovedMerchant && !merchantAccessAllowed) {
    return <Navigate to="/merchant" state={{ from: location, reason: 'merchant_not_active' }} replace />;
  }

  return <>{children}</>;
}
