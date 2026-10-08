export interface UserGeographyRecord {
  user_id: string;
  province_name: string | null;
  city_name: string | null;
  district_name: string | null;
  address?: string | null;
}

export type GeographyLevel = 'province' | 'city' | 'district';

export interface GeographyBucket {
  key: string;
  name: string;
  count: number;
}

export interface UserMapPoint {
  key: string;
  lat: number;
  lng: number;
  count: number;
  areas: string[];
}

export interface RegistrationDateBounds {
  from?: string;
  toExclusive?: string;
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

function parseLocalCalendarDate(value: string): Date | null {
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(0);
  date.setFullYear(year, month - 1, day);
  date.setHours(0, 0, 0, 0);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return null;
  return date;
}

export function getRegistrationDateBounds(startDate?: string, endDate?: string): RegistrationDateBounds {
  const start = startDate ? parseLocalCalendarDate(startDate) : null;
  const end = endDate ? parseLocalCalendarDate(endDate) : null;
  if ((startDate && !start) || (endDate && !end)) throw new Error('Tanggal pendaftaran tidak valid.');

  if (end) end.setDate(end.getDate() + 1);
  return {
    ...(start ? { from: start.toISOString() } : {}),
    ...(end ? { toExclusive: end.toISOString() } : {}),
  };
}

export function parseProfileMapCoordinates(address: string | null | undefined): { lat: number; lng: number } | null {
  if (!address) return null;

  const patterns = [
    /[?&](?:q|query)=(-?\d{1,2}(?:\.\d+)?)(?:,|%2c)(-?\d{1,3}(?:\.\d+)?)/i,
    /@(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)/,
    /!3d(-?\d{1,2}(?:\.\d+)?).*?!4d(-?\d{1,3}(?:\.\d+)?)/,
  ];

  for (const pattern of patterns) {
    const match = address.match(pattern);
    if (!match) continue;
    const lat = Number(match[1]);
    const lng = Number(match[2]);
    if (Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
      return { lat, lng };
    }
  }

  return null;
}

export function aggregateUserMapPoints(
  records: UserGeographyRecord[],
  provinceName?: string,
  cityName?: string,
): UserMapPoint[] {
  const selectedProvince = normalizeLocationName(provinceName);
  const selectedCity = normalizeLocationName(cityName);
  const points = new Map<string, UserMapPoint>();

  uniqueUsers(records).forEach((user) => {
    if (selectedProvince && normalizeLocationName(user.province_name) !== selectedProvince) return;
    if (selectedCity && normalizeLocationName(user.city_name) !== selectedCity) return;
    const coordinates = parseProfileMapCoordinates(user.address);
    if (!coordinates) return;

    // Round before displaying: one cell is roughly 10–11 km at Indonesian latitudes.
    const lat = Math.round(coordinates.lat * 10) / 10;
    const lng = Math.round(coordinates.lng * 10) / 10;
    const key = `${lat.toFixed(1)},${lng.toFixed(1)}`;
    const area = [user.province_name, user.city_name, user.district_name]
      .map(cleanName)
      .filter(Boolean)
      .join(' · ');
    const point = points.get(key);
    if (point) {
      point.count += 1;
      if (area && !point.areas.includes(area)) point.areas.push(area);
    } else {
      points.set(key, { key, lat, lng, count: 1, areas: area ? [area] : [] });
    }
  });

  return [...points.values()].sort((a, b) => b.count - a.count || a.key.localeCompare(b.key));
}
