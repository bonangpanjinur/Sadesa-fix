import type { BuyerTransactionKind } from './buyerTransaction';

/** The two customer-facing delivery intents supported by the platform. */
export const DELIVERY_SERVICE_TYPES = {
  MARKETPLACE: 'MARKETPLACE',
  COURIER_DELIVERY: 'COURIER_DELIVERY',
} as const;

export type DeliveryServiceType = typeof DELIVERY_SERVICE_TYPES[keyof typeof DELIVERY_SERVICE_TYPES];
export type DeliveryIntent = 'merchant_fulfillment' | 'direct_courier';

export interface DeliveryFlowDefinition {
  intent: DeliveryIntent;
  serviceType: DeliveryServiceType;
  label: string;
  description: string;
  buyerEntryPath: string;
  courierPath: string;
  pickupOwner: 'merchant' | 'buyer';
  requiresMerchant: boolean;
  allowsProductItems: boolean;
}

/**
 * Shared contract: pricing, payment, order history, notifications and tracking
 * remain common; dispatch ownership and lifecycle are intentionally separate.
 */
export const DELIVERY_FLOWS: Readonly<Record<DeliveryIntent, DeliveryFlowDefinition>> = {
  merchant_fulfillment: {
    intent: 'merchant_fulfillment',
    serviceType: DELIVERY_SERVICE_TYPES.MARKETPLACE,
    label: 'Belanja di Toko',
    description: 'Pesanan produk yang diambil dari toko dan dikirim kepada pembeli.',
    buyerEntryPath: '/checkout',
    courierPath: '/courier/deliveries',
    pickupOwner: 'merchant',
    requiresMerchant: true,
    allowsProductItems: true,
  },
  direct_courier: {
    intent: 'direct_courier',
    serviceType: DELIVERY_SERVICE_TYPES.COURIER_DELIVERY,
    label: 'Antar Barang',
    description: 'Pengiriman barang milik pemesan dari lokasi pickup ke penerima.',
    buyerEntryPath: '/transport/courier-booking',
    courierPath: '/courier/deliveries',
    pickupOwner: 'buyer',
    requiresMerchant: false,
    allowsProductItems: false,
  },
};

export function getDeliveryFlow(kind: BuyerTransactionKind): DeliveryFlowDefinition {
  return kind === 'courier_delivery'
    ? DELIVERY_FLOWS.direct_courier
    : DELIVERY_FLOWS.merchant_fulfillment;
}

export function isDirectCourierService(serviceType: string | null | undefined): boolean {
  return serviceType === DELIVERY_SERVICE_TYPES.COURIER_DELIVERY;
}

export function isMarketplaceService(serviceType: string | null | undefined): boolean {
  return !serviceType || serviceType === DELIVERY_SERVICE_TYPES.MARKETPLACE;
}
