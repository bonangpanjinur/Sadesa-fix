import { useAuth } from '@/contexts/AuthContext';
import type { AppRole } from '@/types/auth';

/**
 * Hook to access user roles from AuthContext
 * This is a convenience wrapper around useAuth for role-specific functionality
 */
export function useUserRoles() {
  const { 
    roles, 
    rolesLoading: loading, 
    merchantRoleRecoveryLoading,
    hasRole, 
    hasAnyRole,
    isAdmin,
    isVerifikator,
    isMerchant,
    isCourier,
    isAdminDesa,
    isServiceProvider,
    refetchRoles,
  } = useAuth();

  return {
    roles,
    loading,
    merchantRoleRecoveryLoading,
    error: null, // For backwards compatibility
    hasRole,
    hasAnyRole,
    isAdmin,
    isVerifikator,
    isMerchant,
    isCourier,
    isAdminDesa,
    isServiceProvider,
    refetch: refetchRoles,
  };
}
