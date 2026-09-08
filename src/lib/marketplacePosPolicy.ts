import { isPOSOperational, type POSStatus } from '@/lib/posFeatureGate';

/**
 * The product boundary shared by pricing, routing, and support copy.
 * Marketplace access must never be inferred from POS entitlement.
 */
export const MARKETPLACE_POS_POLICY = {
  marketplace: {
    name: 'Marketplace',
    access: 'free',
    requiresPOS: false,
    remainsAvailableWhenPOSIsSuspended: true,
  },
  pos: {
    name: 'POS',
    access: 'paid',
    requiresEntitlement: true,
    operationalStatuses: ['trial', 'active', 'grace'] as POSStatus[],
  },
  tableQr: {
    requiresPOS: true,
    requiresActiveTableContext: true,
    source: 'table_qr',
  },
  offline: {
    supportedOperations: ['cash_sale', 'cached_catalogue', 'local_receipt'] as const,
    onlineOnlyOperations: ['online_payment', 'marketplace_order', 'final_report'] as const,
  },
} as const;

export function isMarketplaceAvailable(): true {
  return MARKETPLACE_POS_POLICY.marketplace.remainsAvailableWhenPOSIsSuspended;
}

export function canOperatePOS(status: POSStatus | null | undefined): boolean {
  return isPOSOperational(status);
}

export function canUseTableQr(status: POSStatus | null | undefined, hasActiveTableContext: boolean): boolean {
  return canOperatePOS(status) && hasActiveTableContext;
}