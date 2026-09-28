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
      courier_volume: 0.45,
    });

    expect(result.preset).toBe('custom');
    expect(result.custom_audio_url).toContain('alarm.mp3');
    expect(result.merchant_enabled).toBe(false);
    expect(result.courier_enabled).toBe(true);
    expect(result.merchant_preset).toBe('custom');
    expect(result.courier_preset).toBe('custom');
    expect(result.courier_volume).toBe(0.45);
  });

  it('keeps separate audience profiles when configured', () => {
    const result = normalizeOrderNotificationSoundSettings({
      merchant_preset: 'bell',
      merchant_volume: 0.3,
      courier_preset: 'chime',
      courier_volume: 0.8,
    });

    expect(result.merchant_preset).toBe('bell');
    expect(result.merchant_volume).toBe(0.3);
    expect(result.courier_preset).toBe('chime');
    expect(result.courier_volume).toBe(0.8);
  });
});
