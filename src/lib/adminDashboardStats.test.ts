import { describe, expect, it } from 'vitest';
import { getLocalDayBounds, isCompletedToday } from './adminDashboardStats';

describe('admin dashboard completion metrics', () => {
  it('uses the local calendar day rather than the UTC date', () => {
    const now = new Date('2026-10-10T22:30:00.000Z');
    const { start, end } = getLocalDayBounds(now);

    expect(start.getHours()).toBe(0);
    expect(end.getTime() - start.getTime()).toBe(24 * 60 * 60 * 1000);
  });

  it('counts a legacy order completed today even when it was created earlier', () => {
    const now = new Date('2026-10-11T05:24:00.000+07:00');
    const { start } = getLocalDayBounds(now);

    expect(isCompletedToday({
      status: 'DONE',
      created_at: '2026-10-08T10:00:00.000Z',
      delivered_at: new Date(start.getTime() + 60 * 60 * 1000).toISOString(),
    }, now)).toBe(true);
  });

  it('does not count a historical DONE order as completed today', () => {
    const now = new Date('2026-10-11T05:24:00.000+07:00');
    const { start } = getLocalDayBounds(now);

    expect(isCompletedToday({
      status: 'DONE',
      created_at: '2026-10-08T10:00:00.000Z',
      delivered_at: new Date(start.getTime() - 60 * 60 * 1000).toISOString(),
    }, now)).toBe(false);
  });

  it('ignores orders created today that are not DONE', () => {
    const now = new Date('2026-10-11T05:24:00.000+07:00');

    expect(isCompletedToday({
      status: 'PROCESSED',
      created_at: '2026-10-10T23:00:00.000Z',
      updated_at: '2026-10-10T23:10:00.000Z',
    }, now)).toBe(false);
  });
});
