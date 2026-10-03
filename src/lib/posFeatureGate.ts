export const POS_STATUSES = [
  'inactive',
  'setup_required',
  'trial',
  'active',
  'grace',
  'suspended',
  'cancelled',
] as const;

export type POSStatus = (typeof POS_STATUSES)[number];

export function isPOSStatus(value: unknown): value is POSStatus {
  return typeof value === 'string' && POS_STATUSES.includes(value as POSStatus);
}

export function isPOSOperational(status: POSStatus | null | undefined) {
  return status === 'trial' || status === 'active' || status === 'grace';
}

export function isPOSSetupStatus(status: POSStatus | null | undefined) {
  return status === 'inactive' || status === 'setup_required';
}

/**
 * A provisioned POS tenant must remain discoverable during onboarding. The
 * route gate still redirects setup-status tenants to the setup page, but
 * hiding the whole navigation makes an admin-granted account look unentitled.
 */
export function shouldShowPOSNavigation(status: POSStatus | null | undefined) {
  return isPOSOperational(status) || isPOSSetupStatus(status);
}

export function isPOSModuleEnabled(enabledModules: string[] | null | undefined, moduleId?: string) {
  // An empty module list is the legacy configuration. Keep all existing POS
  // tenants usable until they explicitly choose a module set in onboarding.
  return !moduleId || !enabledModules?.length || enabledModules.includes(moduleId);
}
