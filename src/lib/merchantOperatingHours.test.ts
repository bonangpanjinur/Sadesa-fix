import { describe, expect, it } from 'vitest';
import { getMerchantOperatingStatus, isWithinOperatingHours } from './merchantOperatingHours';

describe('merchant operating hours', () => {
  it('supports schedules that cross midnight', () => {
    expect(isWithinOperatingHours('22:00', '02:00', 23 * 60)).toBe(true);
    expect(isWithinOperatingHours('22:00', '02:00', 60)).toBe(true);
    expect(isWithinOperatingHours('22:00', '02:00', 12 * 60)).toBe(false);
  });

  it('uses the weekly schedule and Jakarta day instead of the legacy hours', () => {
    const status = getMerchantOperatingStatus(
      true,
      '08:00',
      '17:00',
      [
        { day_of_week: 4, open_time: '10:00', close_time: '12:00', is_closed: false },
        { day_of_week: 5, open_time: null, close_time: null, is_closed: true },
      ],
      new Date('2026-09-24T04:00:00.000Z'), // Thursday, 11:00 WIB.
    );

    expect(status.isCurrentlyOpen).toBe(true);
    expect(status.openTime).toBe('10:00');
    expect(status.closeTime).toBe('12:00');
  });

  it('marks a scheduled day off as closed', () => {
    const status = getMerchantOperatingStatus(
      true,
      '08:00',
      '17:00',
      [{ day_of_week: 5, open_time: null, close_time: null, is_closed: true }],
      new Date('2026-09-25T04:00:00.000Z'), // Friday, 11:00 WIB.
    );

    expect(status.isCurrentlyOpen).toBe(false);
    expect(status.reason).toBe('Toko tutup hari ini');
  });
});
