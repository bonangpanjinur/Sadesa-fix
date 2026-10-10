export interface SignupAddressMetadata {
  full_name?: unknown;
  address?: unknown;
  province_id?: unknown;
  province_name?: unknown;
  city_id?: unknown;
  city_name?: unknown;
  district_id?: unknown;
  district_name?: unknown;
  village_id?: unknown;
  village_name?: unknown;
  address_detail?: unknown;
}

export interface SignupAddressProfileFields {
  full_name?: string | null;
  address?: string | null;
  province_id?: string | null;
  province_name?: string | null;
  city_id?: string | null;
  city_name?: string | null;
  district_id?: string | null;
  district_name?: string | null;
  village_id?: string | null;
  village_name?: string | null;
  address_detail?: string | null;
}

export interface RegistrationAddressPrefill {
  provinceCode: string;
  provinceName: string;
  cityCode: string;
  cityName: string;
  districtCode: string;
  districtName: string;
  villageCode: string;
  villageName: string;
  addressDetail: string;
}

function metadataText(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export function toRegistrationAddressPrefill(
  profile: SignupAddressProfileFields | null,
): RegistrationAddressPrefill | null {
  const provinceCode = metadataText(profile?.province_id);
  const cityCode = metadataText(profile?.city_id);
  const districtCode = metadataText(profile?.district_id);
  const villageCode = metadataText(profile?.village_id);
  if (!provinceCode || !cityCode || !districtCode || !villageCode) return null;
  return {
    provinceCode,
    provinceName: metadataText(profile?.province_name) || '',
    cityCode,
    cityName: metadataText(profile?.city_name) || '',
    districtCode,
    districtName: metadataText(profile?.district_name) || '',
    villageCode,
    villageName: metadataText(profile?.village_name) || '',
    addressDetail: metadataText(profile?.address_detail) || '',
  };
}

export function getSignupAddressBackfill(
  profile: SignupAddressProfileFields | null,
  metadata: SignupAddressMetadata | null | undefined,
): Partial<SignupAddressProfileFields> {
  const provinceId = metadataText(metadata?.province_id);
  const cityId = metadataText(metadata?.city_id);
  const districtId = metadataText(metadata?.district_id);
  const villageId = metadataText(metadata?.village_id);
  if (!provinceId || !cityId || !districtId || !villageId) return {};

  const backfill: Partial<SignupAddressProfileFields> = {};
  const fields: Array<keyof SignupAddressProfileFields> = [
    'address', 'province_id', 'province_name', 'city_id', 'city_name',
    'district_id', 'district_name', 'village_id', 'village_name', 'address_detail',
  ];
  for (const field of fields) {
    if (profile?.[field]?.trim()) continue;
    const value = metadataText(metadata?.[field]);
    if (value) backfill[field] = value;
  }
  return backfill;
}

/**
 * Auth signup metadata is the source submitted by the registration form. Keep
 * it as a backwards-compatible fallback for accounts created before the
 * profile provisioning trigger began copying the address columns.
 */
export function restoreSignupAddress<T extends SignupAddressProfileFields>(
  profile: T | null,
  metadata: SignupAddressMetadata | null | undefined,
  fallbackName = '',
): T | SignupAddressProfileFields | null {
  if (!metadata) return profile;

  const restored = {
    ...(profile ?? {}),
    full_name: profile?.full_name?.trim() || metadataText(metadata.full_name) || fallbackName || null,
    address: profile?.address || metadataText(metadata.address),
    province_id: profile?.province_id || metadataText(metadata.province_id),
    province_name: profile?.province_name || metadataText(metadata.province_name),
    city_id: profile?.city_id || metadataText(metadata.city_id),
    city_name: profile?.city_name || metadataText(metadata.city_name),
    district_id: profile?.district_id || metadataText(metadata.district_id),
    district_name: profile?.district_name || metadataText(metadata.district_name),
    village_id: profile?.village_id || metadataText(metadata.village_id),
    village_name: profile?.village_name || metadataText(metadata.village_name),
    address_detail: profile?.address_detail || metadataText(metadata.address_detail),
  };

  const hasAddress = Boolean(restored.province_id || restored.city_id || restored.district_id || restored.village_id || restored.address);
  return hasAddress ? restored : profile;
}
