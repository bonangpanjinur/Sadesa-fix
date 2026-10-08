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
  exclusiveRegistration?: boolean;
}

export function ProtectedRoute({ 
  children, 
  allowedRoles,
  redirectTo = '/auth',
  exclusiveRegistration = false,
}: ProtectedRouteProps) {
  const { user, loading: authLoading } = useAuth();
  const { roles, loading: rolesLoading, merchantRoleRecoveryLoading, hasAnyRole } = useUserRoles();
  const location = useLocation();
  const posRouteRoles: AppRole[] = ['admin', 'merchant'];
  const isPOSRoute = location.pathname === '/pos' || location.pathname.startsWith('/pos/');
  const isMerchantWorkspaceRoute = location.pathname === '/merchant'
    || location.pathname.startsWith('/merchant/');
  const isCourierWorkspaceRoute = location.pathname === '/courier'
    || location.pathname.startsWith('/courier/');
  const requiresApprovedMerchant = isMerchantWorkspaceRoute && location.pathname !== '/merchant';
  const addressUserId = user?.id;
  const requiredRoles = allowedRoles
    ?? (isPOSRoute ? posRouteRoles : isMerchantWorkspaceRoute ? ['merchant'] : undefined);
  const routeRequiredRoles = requiredRoles
    ?? (isCourierWorkspaceRoute ? ['courier'] : undefined);
  const registeredBusinessRole = roles.find((role) => ['merchant', 'courier', 'service_provider'].includes(role));
  const [merchantAccessLoading, setMerchantAccessLoading] = useState(false);
  const [merchantAccessAllowed, setMerchantAccessAllowed] = useState(true);
  const [addressStatus, setAddressStatus] = useState<'checking' | 'complete' | 'incomplete' | 'error'>('checking');
  const requiresAddressCompletion = Boolean(addressUserId)
    && location.pathname !== '/account'
    && location.pathname !== '/profile';

  useEffect(() => {
    if (!addressUserId || !requiresAddressCompletion) {
      setAddressStatus('complete');
      return;
    }

    let cancelled = false;
    setAddressStatus('checking');
    void supabase
      .from('profiles')
      .select('province_id, city_id, district_id, village_id')
      .eq('user_id', addressUserId)
      .maybeSingle()
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error) {
          console.warn('Unable to verify required profile address:', error);
          setAddressStatus('error');
          return;
        }
        setAddressStatus(data?.province_id && data?.city_id && data?.district_id && data?.village_id
          ? 'complete'
          : 'incomplete');
      });

    return () => { cancelled = true; };
  }, [addressUserId, requiresAddressCompletion]);

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
    || (isMerchantWorkspaceRoute && !roles.includes('merchant') && merchantRoleRecoveryLoading)
    || merchantAccessLoading;

  if (authLoading || waitingForRequiredRoles || (requiresAddressCompletion && addressStatus === 'checking')) {
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

  if (requiresAddressCompletion && addressStatus === 'incomplete') {
    return <Navigate to="/account?completeAddress=1" state={{ from: location, reason: 'profile_address_required' }} replace />;
  }

  if (exclusiveRegistration && registeredBusinessRole) {
    const destination = registeredBusinessRole === 'merchant'
      ? '/merchant'
      : registeredBusinessRole === 'courier'
        ? '/courier'
        : '/services/provider-history';
    return <Navigate to={destination} replace state={{ from: location, reason: 'business_role_already_registered' }} />;
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
