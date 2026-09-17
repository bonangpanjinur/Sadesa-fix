import { describe, expect, it } from 'vitest';
import { canBuyerContactCourier, canBuyerTrackCourier } from './deliveryVisibility';

describe('buyer courier visibility', () => {
  it('keeps chat and live tracking hidden while an offer is waiting', () => {
    expect(canBuyerContactCourier('ASSIGNED', 'courier-1')).toBe(false);
    expect(canBuyerTrackCourier('ASSIGNED', 'courier-1')).toBe(false);
  });

  it('starts both surfaces only after the courier accepts', () => {
    expect(canBuyerContactCourier('COURIER_ACCEPTED', 'courier-1')).toBe(true);
    expect(canBuyerTrackCourier('COURIER_ACCEPTED', 'courier-1')).toBe(true);
  });

  it('does not expose either surface without a courier identity', () => {
    expect(canBuyerContactCourier('COURIER_ACCEPTED', null)).toBe(false);
    expect(canBuyerTrackCourier('COURIER_ACCEPTED', undefined)).toBe(false);
  });

  it('keeps live tracking closed after delivery completes', () => {
    expect(canBuyerContactCourier('DELIVERED', 'courier-1')).toBe(true);
    expect(canBuyerTrackCourier('DELIVERED', 'courier-1')).toBe(false);
  });
});