import type { AppRole } from '@/types/auth';

/**
 * Keeps the UI usable when an approved merchant exists but its historical
 * user_roles row was not created/read. Backend RLS remains authoritative for
 * every data mutation; this only repairs the frontend capability state.
 */
export function mergeMerchantRole(
  roles: AppRole[],
  hasMerchantProfile: boolean,
): AppRole[] {
  if (!hasMerchantProfile || roles.includes('merchant')) return roles;
  return [...roles, 'merchant'];
}

export function mergeCourierRole(
  roles: AppRole[],
  hasCourierProfile: boolean,
): AppRole[] {
  if (!hasCourierProfile || roles.includes('courier')) return roles;
  return [...roles, 'courier'];
}

/** Merchant, courier, and service provider accounts are also marketplace buyers. */
export function ensureBuyerFallback(roles: AppRole[]): AppRole[] {
  if (roles.length === 0) return ['buyer'];
  if ((roles.includes('merchant') || roles.includes('courier') || roles.includes('service_provider')) && !roles.includes('buyer')) {
    return [...roles, 'buyer'];
  }
  return roles;
}
