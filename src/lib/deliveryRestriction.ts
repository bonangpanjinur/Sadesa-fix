export const MAX_LOCAL_DELIVERY_DISTANCE_KM = 10;

export interface DeliveryRegion {
  cityId?: string | null;
  cityName?: string | null;
  districtId?: string | null;
  districtName?: string | null;
}

export interface DeliveryRestrictionResult {
  requiresExpedition: boolean;
  reasons: string[];
}

function normalizeRegionName(value: string | null | undefined): string {
  return (value ?? '')
    .toLocaleLowerCase('id-ID')
    .replace(/\b(kabupaten|kab\.?|kota|kecamatan|kec\.?)\b/g, '')
    .replace(/[^a-z0-9]+/g, '');
}

function regionsDiffer(
  destinationId: string | null | undefined,
  destinationName: string | null | undefined,
  merchantName: string | null | undefined,
): boolean {
  if (destinationId && merchantName && destinationId === merchantName) return false;

  const destination = normalizeRegionName(destinationName);
  const merchant = normalizeRegionName(merchantName);
  return Boolean(destination && merchant && destination !== merchant);
}

export function getDeliveryRestriction(
  distanceKm: number | null | undefined,
  destination: DeliveryRegion,
  merchant: DeliveryRegion,
): DeliveryRestrictionResult {
  const reasons: string[] = [];

  if (distanceKm !== null && distanceKm !== undefined && distanceKm > MAX_LOCAL_DELIVERY_DISTANCE_KM) {
    reasons.push(`jarak lebih dari ${MAX_LOCAL_DELIVERY_DISTANCE_KM} km`);
  }

  if (regionsDiffer(destination.districtId, destination.districtName, merchant.districtName)) {
    reasons.push('berbeda kecamatan');
  }

  if (regionsDiffer(destination.cityId, destination.cityName, merchant.cityName)) {
    reasons.push('berbeda kabupaten/kota');
  }

  return {
    requiresExpedition: reasons.length > 0,
    reasons,
  };
}
