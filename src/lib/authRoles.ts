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

export function ensureBuyerFallback(roles: AppRole[]): AppRole[] {
  return roles.length > 0 ? roles : ['buyer'];
}
