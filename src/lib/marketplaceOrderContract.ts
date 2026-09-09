export type MarketplacePaymentMethod = 'COD' | 'TRANSFER' | 'ONLINE';
export type MarketplaceDeliveryType = 'PICKUP' | 'INTERNAL' | 'EXPEDITION';
export type MarketplaceOrderStatus = 'PENDING_CONFIRMATION' | 'PENDING_PAYMENT' | 'NEW';
export type MarketplacePaymentStatus = 'COD' | 'PENDING_TRANSFER' | 'UNPAID';

export interface MarketplaceOrderPayloadInput {
  buyerId: string;
  merchantId: string;
  status: MarketplaceOrderStatus;
  deliveryType: MarketplaceDeliveryType;
  deliveryName: string;
  deliveryPhone: string;
  deliveryAddress: string;
  deliveryLat: number | null;
  deliveryLng: number | null;
  deliveryProvinceId: string | null;
  deliveryProvinceName: string | null;
  deliveryCityId: string | null;
  deliveryCityName: string | null;
  deliveryDistrictId: string | null;
  deliveryDistrictName: string | null;
  shippingCost: number;
  subtotal: number;
  total: number;
  notes: string | null;
  flashSaleDiscount: number;
  paymentMethod: MarketplacePaymentMethod;
  paymentStatus: MarketplacePaymentStatus;
  confirmationDeadline: string | null;
  codServiceFee: number;
  buyerDistanceKm: number | null;
}

/**
 * Marketplace orders are buyer-owned orders and do not require a POS tenant.
 * POS stock allocation, when configured, is handled by the reservation RPC.
 */
export function buildMarketplaceOrderPayload(input: MarketplaceOrderPayloadInput) {
  return {
    buyer_id: input.buyerId,
    merchant_id: input.merchantId,
    status: input.status,
    handled_by: 'ADMIN',
    delivery_type: input.deliveryType,
    delivery_name: input.deliveryName,
    delivery_phone: input.deliveryPhone,
    delivery_address: input.deliveryAddress,
    delivery_lat: input.deliveryLat,
    delivery_lng: input.deliveryLng,
    delivery_province_id: input.deliveryProvinceId,
    delivery_province_name: input.deliveryProvinceName,
    delivery_city_id: input.deliveryCityId,
    delivery_city_name: input.deliveryCityName,
    delivery_district_id: input.deliveryDistrictId,
    delivery_district_name: input.deliveryDistrictName,
    shipping_cost: input.shippingCost,
    subtotal: input.subtotal,
    total: input.total,
    notes: input.notes,
    flash_sale_discount: input.flashSaleDiscount,
    payment_method: input.paymentMethod,
    payment_status: input.paymentStatus,
    confirmation_deadline: input.confirmationDeadline,
    cod_service_fee: input.codServiceFee,
    buyer_distance_km: input.buyerDistanceKm,
  };
}