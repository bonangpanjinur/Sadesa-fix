import { describe, expect, it } from 'vitest';
import { aggregateGeography, getGeographyMetrics, type UserGeographyRecord } from './userGeography';

const users: UserGeographyRecord[] = [
  { user_id: '1', province_name: 'Banten', city_name: 'Kota Serang', district_name: 'Serang' },
  { user_id: '2', province_name: ' BANTEN ', city_name: 'Kota Serang', district_name: 'Serang' },
  { user_id: '3', province_name: 'Jawa Barat', city_name: 'Kota Tasikmalaya', district_name: 'Cihideung' },
  { user_id: '4', province_name: 'Banten', city_name: null, district_name: null },
  { user_id: '5', province_name: null, city_name: null, district_name: null },
];

describe('user geography aggregation', () => {
  it('counts each profile once and merges case/whitespace variations', () => {
    const provinces = aggregateGeography([...users, users[0]], 'province');
    expect(provinces).toEqual([
      { key: 'banten', name: 'Banten', count: 3 },
      { key: 'jawa barat', name: 'Jawa Barat', count: 1 },
      { key: '__unknown_location__', name: 'Belum diisi', count: 1 },
    ]);
  });

  it('drills from province to city to district while retaining missing-area counts', () => {
    expect(aggregateGeography(users, 'city', 'Banten')).toEqual([
      { key: 'kota serang', name: 'Kota Serang', count: 2 },
      { key: '__unknown_location__', name: 'Belum diisi', count: 1 },
    ]);
    expect(aggregateGeography(users, 'district', 'Banten', 'Kota Serang')).toEqual([
      { key: 'serang', name: 'Serang', count: 2 },
    ]);
  });

  it('summarizes complete and incomplete registered locations', () => {
    expect(getGeographyMetrics(users)).toEqual({
      totalUsers: 5,
      completeUsers: 3,
      incompleteUsers: 2,
      provinceCount: 2,
      cityCount: 2,
      districtCount: 2,
    });
  });
});
