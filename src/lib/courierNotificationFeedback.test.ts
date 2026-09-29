import { beforeEach, describe, expect, it, vi } from 'vitest';
import { COURIER_ALARM_VIBRATION_PATTERN, vibrateCourierAlarm } from './courierNotificationFeedback';

describe('courier alarm vibration', () => {
  beforeEach(() => {
    Object.defineProperty(navigator, 'vibrate', {
      configurable: true,
      value: vi.fn().mockReturnValue(true),
    });
  });

  it('uses the required multi-pulse pattern for courier alerts', () => {
    expect(vibrateCourierAlarm()).toBe(true);
    expect(navigator.vibrate).toHaveBeenCalledWith(COURIER_ALARM_VIBRATION_PATTERN);
  });

  it('does not throw when the browser does not expose vibration', () => {
    Object.defineProperty(navigator, 'vibrate', { configurable: true, value: undefined });
    expect(vibrateCourierAlarm()).toBe(false);
  });
});
