export interface UserGeographyRecord {
  user_id: string;
  province_name: string | null;
  city_name: string | null;
  district_name: string | null;
}

export type GeographyLevel = 'province' | 'city' | 'district';

export interface GeographyBucket {
  key: string;
  name: string;
  count: number;
}

export const UNKNOWN_LOCATION_KEY = '__unknown_location__';

export function normalizeLocationName(value: string | null | undefined): string {
  return value?.trim().replace(/\s+/g, ' ').toLocaleLowerCase('id-ID') ?? '';
}

function cleanName(value: string | null | undefined): string {
  return value?.trim().replace(/\s+/g, ' ') ?? '';
}

function uniqueUsers(records: UserGeographyRecord[]): UserGeographyRecord[] {
  const users = new Map<string, UserGeographyRecord>();
  records.forEach((record) => {
    if (!users.has(record.user_id)) users.set(record.user_id, record);
  });
  return [...users.values()];
}

export function aggregateGeography(
  records: UserGeographyRecord[],
  level: GeographyLevel,
  provinceName?: string,
  cityName?: string,
): GeographyBucket[] {
  const users = uniqueUsers(records);
  const selectedProvince = normalizeLocationName(provinceName);
  const selectedCity = normalizeLocationName(cityName);
  const buckets = new Map<string, GeographyBucket>();

  users.forEach((user) => {
    if (level !== 'province' && normalizeLocationName(user.province_name) !== selectedProvince) return;
    if (level === 'district' && normalizeLocationName(user.city_name) !== selectedCity) return;

    const rawName = level === 'province'
      ? user.province_name
      : level === 'city'
        ? user.city_name
        : user.district_name;
    const name = cleanName(rawName) || 'Belum diisi';
    const key = normalizeLocationName(rawName) || UNKNOWN_LOCATION_KEY;
    const bucket = buckets.get(key);
    if (bucket) bucket.count += 1;
    else buckets.set(key, { key, name, count: 1 });
  });

  return [...buckets.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name, 'id'));
}

export function getGeographyMetrics(records: UserGeographyRecord[]) {
  const users = uniqueUsers(records);
  const provinceKeys = new Set<string>();
  const cityKeys = new Set<string>();
  const districtKeys = new Set<string>();
  let completeUsers = 0;

  users.forEach((user) => {
    const province = normalizeLocationName(user.province_name);
    const city = normalizeLocationName(user.city_name);
    const district = normalizeLocationName(user.district_name);
    if (province) provinceKeys.add(province);
    if (province && city) cityKeys.add(`${province}::${city}`);
    if (province && city && district) {
      districtKeys.add(`${province}::${city}::${district}`);
      completeUsers += 1;
    }
  });

  return {
    totalUsers: users.length,
    completeUsers,
    incompleteUsers: users.length - completeUsers,
    provinceCount: provinceKeys.size,
    cityCount: cityKeys.size,
    districtCount: districtKeys.size,
  };
}
