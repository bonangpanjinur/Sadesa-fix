export const MAX_OJEK_DELIVERY_DISTANCE_KM = 20;

export interface DeliveryRestrictionResult {
  exceedsMaxDistance: boolean;
  reasons: string[];
}

export function getDeliveryRestriction(distanceKm: number | null | undefined): DeliveryRestrictionResult {
  const exceedsMaxDistance = distanceKm !== null
    && distanceKm !== undefined
    && distanceKm > MAX_OJEK_DELIVERY_DISTANCE_KM;

  return {
    exceedsMaxDistance,
    reasons: exceedsMaxDistance
      ? [`jarak rute lebih dari ${MAX_OJEK_DELIVERY_DISTANCE_KM} km`]
      : [],
  };
}
