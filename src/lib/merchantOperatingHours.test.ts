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

  it('uses legacy hours only when no weekly schedule exists', () => {
    const missingScheduleDay = getMerchantOperatingStatus(
      true,
      '08:00',
      '17:00',
      [{ day_of_week: 4, open_time: '10:00', close_time: '12:00', is_closed: false }],
      new Date('2026-09-25T04:00:00.000Z'), // Friday, 11:00 WIB.
    );
    expect(missingScheduleDay.isCurrentlyOpen).toBe(false);
    expect(missingScheduleDay.reason).toBe('Jadwal toko belum tersedia hari ini');

    const legacyRecord = getMerchantOperatingStatus(
      true,
      '08:00',
      '17:00',
      [],
      new Date('2026-09-25T04:00:00.000Z'),
    );
    expect(legacyRecord.isCurrentlyOpen).toBe(true);
    expect(legacyRecord.openTime).toBe('08:00');
  });

  it('keeps an overnight schedule open after midnight even if the new day is closed', () => {
    const overnightSchedule = [
      { day_of_week: 2, open_time: '22:00', close_time: '02:00', is_closed: false },
      { day_of_week: 3, open_time: null, close_time: null, is_closed: true },
    ];
    const afterMidnight = getMerchantOperatingStatus(
      true,
      '08:00',
      '17:00',
      overnightSchedule,
      new Date('2026-09-22T17:00:00.000Z'), // Wednesday, 00:00 WIB.
    );

    expect(afterMidnight.isCurrentlyOpen).toBe(true);
    expect(afterMidnight.openTime).toBe('22:00');

    const afterClosing = getMerchantOperatingStatus(
      true,
      '08:00',
      '17:00',
      overnightSchedule,
      new Date('2026-09-22T19:00:00.000Z'), // Wednesday, 02:00 WIB.
    );
    expect(afterClosing.isCurrentlyOpen).toBe(false);
  });
});
