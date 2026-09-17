const BUYER_COURIER_CONTACT_STATUSES = [
  'COURIER_ACCEPTED',
  'PICKED_UP',
  'SENT',
  'DELIVERING',
  'DELIVERED',
  'DONE',
] as const;

const BUYER_COURIER_TRACKING_STATUSES = [
  'COURIER_ACCEPTED',
  'PICKED_UP',
  'SENT',
  'DELIVERING',
] as const;

export function canBuyerContactCourier(status: string, courierId: string | null | undefined): boolean {
  return Boolean(courierId && BUYER_COURIER_CONTACT_STATUSES.includes(status as typeof BUYER_COURIER_CONTACT_STATUSES[number]));
}

export function canBuyerTrackCourier(status: string, courierId: string | null | undefined): boolean {
  return Boolean(courierId && BUYER_COURIER_TRACKING_STATUSES.includes(status as typeof BUYER_COURIER_TRACKING_STATUSES[number]));
}