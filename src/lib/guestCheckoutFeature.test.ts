import { describe, expect, it } from 'vitest';
import { isGuestCheckoutEnabled } from './guestCheckoutFeature';

describe('guest checkout rollout flag', () => {
  it('fails closed for missing, malformed, or disabled values', () => {
    expect(isGuestCheckoutEnabled(undefined)).toBe(false);
    expect(isGuestCheckoutEnabled(null)).toBe(false);
    expect(isGuestCheckoutEnabled({ enabled: false })).toBe(false);
    expect(isGuestCheckoutEnabled('not-a-boolean')).toBe(false);
  });

  it('accepts the supported enabled settings shapes', () => {
    expect(isGuestCheckoutEnabled(true)).toBe(true);
    expect(isGuestCheckoutEnabled({ enabled: true })).toBe(true);
    expect(isGuestCheckoutEnabled('true')).toBe(true);
    expect(isGuestCheckoutEnabled(' ON ')).toBe(true);
    expect(isGuestCheckoutEnabled('1')).toBe(true);
  });

  it('supports deterministic pilot and percentage rollout decisions', () => {
    expect(isGuestCheckoutEnabled({ enabled: true, rollout_percent: 0 }, 'session-a')).toBe(false);
    expect(isGuestCheckoutEnabled({ enabled: true, pilot_user_ids: ['session-a'], rollout_percent: 0 }, 'session-a')).toBe(true);
    expect(isGuestCheckoutEnabled({ enabled: true, rollout_percent: 100 }, 'session-a')).toBe(true);
    expect(isGuestCheckoutEnabled({ enabled: true, rollout_percent: 50 }, 'session-a'))
      .toBe(isGuestCheckoutEnabled({ enabled: true, rollout_percent: 50 }, 'session-a'));
  });
});
