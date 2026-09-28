export type OrderSoundAudience = 'merchant' | 'courier';
export type OrderSoundPreset = 'urgent' | 'bell' | 'chime' | 'custom';

export interface OrderNotificationSoundSettings {
  enabled: boolean;
  merchant_enabled: boolean;
  courier_enabled: boolean;
  preset: OrderSoundPreset;
  custom_audio_url: string;
  volume: number;
  repeat_count: number;
  repeat_gap_ms: number;
}

export const DEFAULT_ORDER_SOUND_SETTINGS: OrderNotificationSoundSettings = {
  enabled: true,
  merchant_enabled: true,
  courier_enabled: true,
  preset: 'urgent',
  custom_audio_url: '',
  volume: 1,
  repeat_count: 3,
  repeat_gap_ms: 700,
};

const SETTINGS_KEY = 'order_notification_sound_settings';
let settingsCache: { value: OrderNotificationSoundSettings; expiresAt: number } | null = null;
let activePlayback: { stop: () => void } | null = null;
let sharedAudioContext: AudioContext | null = null;

function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  const number = typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  return Math.min(max, Math.max(min, number));
}

export function normalizeOrderNotificationSoundSettings(value: unknown): OrderNotificationSoundSettings {
  const input = value && typeof value === 'object' ? value as Partial<OrderNotificationSoundSettings> : {};
  return {
    ...DEFAULT_ORDER_SOUND_SETTINGS,
    ...input,
    enabled: input.enabled !== false,
    merchant_enabled: input.merchant_enabled !== false,
    courier_enabled: input.courier_enabled !== false,
    preset: ['urgent', 'bell', 'chime', 'custom'].includes(input.preset || '')
      ? input.preset as OrderSoundPreset
      : DEFAULT_ORDER_SOUND_SETTINGS.preset,
    custom_audio_url: typeof input.custom_audio_url === 'string' ? input.custom_audio_url : '',
    volume: clampNumber(input.volume, 0, 1, DEFAULT_ORDER_SOUND_SETTINGS.volume),
    repeat_count: Math.round(clampNumber(input.repeat_count, 1, 6, DEFAULT_ORDER_SOUND_SETTINGS.repeat_count)),
    repeat_gap_ms: Math.round(clampNumber(input.repeat_gap_ms, 250, 3000, DEFAULT_ORDER_SOUND_SETTINGS.repeat_gap_ms)),
  };
}

export async function fetchOrderNotificationSoundSettings(force = false): Promise<OrderNotificationSoundSettings> {
  if (!force && settingsCache && settingsCache.expiresAt > Date.now()) return settingsCache.value;

  try {
    const { supabase } = await import('@/integrations/supabase/client');
    const { data } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', SETTINGS_KEY)
      .maybeSingle();
    const value = normalizeOrderNotificationSoundSettings(data?.value);
    settingsCache = { value, expiresAt: Date.now() + 60_000 };
    return value;
  } catch {
    return DEFAULT_ORDER_SOUND_SETTINGS;
  }
}

export function clearOrderNotificationSoundSettingsCache() {
  settingsCache = null;
}

function isAudienceEnabled(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience) {
  return settings.enabled && (audience === 'merchant' ? settings.merchant_enabled : settings.courier_enabled);
}

function getAudioContext() {
  if (sharedAudioContext && sharedAudioContext.state !== 'closed') return sharedAudioContext;
  const AudioContextConstructor = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  sharedAudioContext = AudioContextConstructor ? new AudioContextConstructor() : null;
  return sharedAudioContext;
}

/** Call from a user gesture before a realtime callback needs to play audio. */
export function unlockOrderNotificationAudio() {
  if (typeof window === 'undefined') return;
  const context = getAudioContext();
  if (context?.state === 'suspended') void context.resume().catch(() => undefined);
}

async function playPreset(preset: Exclude<OrderSoundPreset, 'custom'>, volume: number) {
  const context = getAudioContext();
  if (!context) return;
  if (context.state === 'suspended') await context.resume();

  const notes = preset === 'urgent'
    ? [{ frequency: 880, at: 0 }, { frequency: 1175, at: 0.18 }, { frequency: 880, at: 0.36 }]
    : preset === 'bell'
      ? [{ frequency: 784, at: 0 }, { frequency: 1047, at: 0.06 }, { frequency: 1319, at: 0.12 }]
      : [{ frequency: 659, at: 0 }, { frequency: 784, at: 0.16 }, { frequency: 988, at: 0.32 }];
  const duration = preset === 'bell' ? 0.85 : 0.62;
  const master = context.createGain();
  master.gain.setValueAtTime(Math.max(0.01, volume * 0.72), context.currentTime);
  master.gain.exponentialRampToValueAtTime(0.01, context.currentTime + duration);
  master.connect(context.destination);

  notes.forEach(({ frequency, at }) => {
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = preset === 'urgent' ? 'square' : 'sine';
    oscillator.frequency.setValueAtTime(frequency, context.currentTime + at);
    gain.gain.setValueAtTime(0.001, context.currentTime + at);
    gain.gain.exponentialRampToValueAtTime(1, context.currentTime + at + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + Math.min(duration, at + 0.28));
    oscillator.connect(gain);
    gain.connect(master);
    oscillator.start(context.currentTime + at);
    oscillator.stop(context.currentTime + Math.min(duration, at + 0.3));
  });

}

async function playCustomAudio(url: string, volume: number) {
  const audio = new Audio(url);
  audio.preload = 'auto';
  audio.volume = volume;
  audio.currentTime = 0;
  await audio.play();
  await new Promise<void>((resolve) => {
    audio.addEventListener('ended', () => resolve(), { once: true });
    audio.addEventListener('error', () => resolve(), { once: true });
  });
}

export async function playOrderNotificationSound(audience: OrderSoundAudience) {
  if (typeof window === 'undefined') return;
  const settings = await fetchOrderNotificationSoundSettings();
  if (!isAudienceEnabled(settings, audience)) return;

  activePlayback?.stop();
  let stopped = false;
  let timeoutId: number | undefined;
  activePlayback = { stop: () => { stopped = true; if (timeoutId) window.clearTimeout(timeoutId); } };

  try {
    for (let index = 0; index < settings.repeat_count && !stopped; index += 1) {
      if (settings.preset === 'custom' && settings.custom_audio_url) {
        await playCustomAudio(settings.custom_audio_url, settings.volume);
      } else {
        await playPreset(settings.preset === 'custom' ? 'urgent' : settings.preset, settings.volume);
      }
      if (index < settings.repeat_count - 1 && !stopped) {
        await new Promise<void>((resolve) => { timeoutId = window.setTimeout(resolve, settings.repeat_gap_ms); });
      }
    }
  } catch {
    // Browser autoplay policy or an unavailable custom file should not break order updates.
  } finally {
    if (activePlayback?.stop && !stopped) activePlayback = null;
  }
}

export function previewOrderNotificationSound(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience = 'merchant') {
  settingsCache = { value: normalizeOrderNotificationSoundSettings(settings), expiresAt: Date.now() + 60_000 };
  return playOrderNotificationSound(audience);
}

export const ORDER_SOUND_SETTINGS_KEY = SETTINGS_KEY;
export const ORDER_SOUND_PRESET_LABELS: Record<OrderSoundPreset, string> = {
  urgent: 'Urgent — tiga nada tegas',
  bell: 'Bell — nada lonceng',
  chime: 'Chime — nada ramah',
  custom: 'Audio custom yang diunggah',
};
