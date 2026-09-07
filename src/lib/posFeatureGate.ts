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

export function isPOSModuleEnabled(enabledModules: string[] | null | undefined, moduleId?: string) {
  // An empty module list is the legacy configuration. Keep all existing POS
  // tenants usable until they explicitly choose a module set in onboarding.
  return !moduleId || !enabledModules?.length || enabledModules.includes(moduleId);
}