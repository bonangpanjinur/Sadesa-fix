import { describe, expect, it } from 'vitest';
import { rankPOSCustomerAreas } from './posCustomerAreas';

describe('rankPOSCustomerAreas', () => {
  it('ranks areas by unique customers and aggregates transactions and revenue', () => {
    const result = rankPOSCustomerAreas(
      [
        { customer_id: 'a', total: 100 },
        { customer_id: 'a', total: 50 },
        { customer_id: 'b', total: 75 },
        { customer_id: 'c', total: 80 },
      ],
      [
        { id: 'a', district_name: 'Kec. Satu', city_name: 'Kabupaten A' },
        { id: 'b', district_name: ' KEC. SATU ', city_name: 'KABUPATEN A' },
        { id: 'c', district_name: 'Kec. Dua', city_name: 'Kabupaten A' },
      ],
    );

    expect(result).toHaveLength(2);
    expect(result[0]).toMatchObject({ label: 'Kec. Satu', detail: 'Kabupaten A', customerCount: 2, transactionCount: 3, revenue: 225 });
    expect(result[1]).toMatchObject({ label: 'Kec. Dua', detail: 'Kabupaten A', customerCount: 1, transactionCount: 1, revenue: 80 });
  });

  it('omits anonymous sales, unknown customer ids, and profiles without an area', () => {
    const result = rankPOSCustomerAreas(
      [
        { customer_id: null, total: 500 },
        { customer_id: 'missing', total: 100 },
        { customer_id: 'no-area', total: 50 },
      ],
      [{ id: 'no-area', district_name: ' ', city_name: null }],
    );

    expect(result).toEqual([]);
  });

  it('does not expose customer identifiers or names in the aggregate output', () => {
    const result = rankPOSCustomerAreas(
      [{ customer_id: 'private-id', total: 25 }],
      [{ id: 'private-id', district_name: 'Kecamatan Aman', city_name: 'Kabupaten Aman' }],
    );

    expect(result).toEqual([{
      key: 'kecamatan aman|kabupaten aman', label: 'Kecamatan Aman', detail: 'Kabupaten Aman', customerCount: 1, transactionCount: 1, revenue: 25,
    }]);
    expect(JSON.stringify(result)).not.toContain('private-id');
  });
});
