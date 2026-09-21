import { describe, expect, it } from 'vitest';
import {
  DEFAULT_ORDER_SOUND_SETTINGS,
  normalizeOrderNotificationSoundSettings,
} from './orderNotificationSound';

describe('order notification sound settings', () => {
  it('uses safe defaults for missing values', () => {
    expect(normalizeOrderNotificationSoundSettings(null)).toEqual(DEFAULT_ORDER_SOUND_SETTINGS);
  });

  it('clamps loudness and repetition controls', () => {
    const result = normalizeOrderNotificationSoundSettings({
      volume: 4,
      repeat_count: 99,
      repeat_gap_ms: 1,
      preset: 'unknown',
    });

    expect(result.volume).toBe(1);
    expect(result.repeat_count).toBe(6);
    expect(result.repeat_gap_ms).toBe(250);
    expect(result.preset).toBe('urgent');
  });

  it('supports custom audio settings', () => {
    const result = normalizeOrderNotificationSoundSettings({
      preset: 'custom',
      custom_audio_url: 'https://example.com/alarm.mp3',
      merchant_enabled: false,
    });

    expect(result.preset).toBe('custom');
    expect(result.custom_audio_url).toContain('alarm.mp3');
    expect(result.merchant_enabled).toBe(false);
    expect(result.courier_enabled).toBe(true);
  });
});
