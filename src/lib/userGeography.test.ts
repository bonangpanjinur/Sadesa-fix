import { describe, expect, it } from 'vitest';
import {
  aggregateGeography,
  aggregateUserMapPoints,
  getGeographyMetrics,
  parseProfileMapCoordinates,
  type UserGeographyRecord,
} from './userGeography';

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
      { key: '__unknown_location__', name: 'Belum diisi', count: 1 },
      { key: 'jawa barat', name: 'Jawa Barat', count: 1 },
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

  it('parses supported Google Maps coordinate URL formats only when coordinates are valid', () => {
    expect(parseProfileMapCoordinates('Rumah\nGoogle Maps: https://maps.google.com/?q=-7.2,108.1')).toEqual({ lat: -7.2, lng: 108.1 });
    expect(parseProfileMapCoordinates('https://www.google.com/maps/@-6.9,107.6,15z')).toEqual({ lat: -6.9, lng: 107.6 });
    expect(parseProfileMapCoordinates('https://maps.google.com/?q=120,108')).toBeNull();
    expect(parseProfileMapCoordinates('Alamat tanpa koordinat')).toBeNull();
  });

  it('groups map pins in generalized cells and filters them by the selected region', () => {
    const withCoordinates: UserGeographyRecord[] = [
      { user_id: '1', province_name: 'Banten', city_name: 'Kota Serang', district_name: 'Serang', address: 'https://maps.google.com/?q=-6.12,106.12' },
      { user_id: '2', province_name: 'Banten', city_name: 'Kota Serang', district_name: 'Serang', address: 'https://maps.google.com/?q=-6.14,106.14' },
      { user_id: '3', province_name: 'Jawa Barat', city_name: 'Kota Tasikmalaya', district_name: 'Cihideung', address: 'https://maps.google.com/?q=-7.32,108.22' },
      { user_id: '4', province_name: 'Banten', city_name: 'Kota Serang', district_name: 'Serang', address: null },
    ];

    expect(aggregateUserMapPoints(withCoordinates)).toEqual([
      { key: '-6.1,106.1', lat: -6.1, lng: 106.1, count: 2, areas: ['Banten · Kota Serang · Serang'] },
      { key: '-7.3,108.2', lat: -7.3, lng: 108.2, count: 1, areas: ['Jawa Barat · Kota Tasikmalaya · Cihideung'] },
    ]);
    expect(aggregateUserMapPoints(withCoordinates, 'Banten', 'Kota Serang')).toHaveLength(1);
  });
});
