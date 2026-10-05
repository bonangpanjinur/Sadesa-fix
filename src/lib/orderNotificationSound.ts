import { enableAudio, getAudioContext, isAudioEnabled, requestAudioPermission } from '@/lib/audioManager';

export type OrderSoundAudience = 'merchant' | 'courier';
export type OrderSoundPreset = 'urgent' | 'bell' | 'chime' | 'custom';
export interface OrderSoundProfile {
  enabled: boolean;
  preset: OrderSoundPreset;
  custom_audio_url: string;
  volume: number;
}

export interface OrderNotificationSoundSettings {
  enabled: boolean;
  merchant_enabled: boolean;
  courier_enabled: boolean;
  preset: OrderSoundPreset;
  custom_audio_url: string;
  volume: number;
  merchant_preset: OrderSoundPreset;
  merchant_custom_audio_url: string;
  merchant_volume: number;
  courier_preset: OrderSoundPreset;
  courier_custom_audio_url: string;
  courier_volume: number;
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
  merchant_preset: 'urgent',
  merchant_custom_audio_url: '',
  merchant_volume: 1,
  courier_preset: 'urgent',
  courier_custom_audio_url: '',
  courier_volume: 1,
  repeat_count: 3,
  repeat_gap_ms: 700,
};

const SETTINGS_KEY = 'order_notification_sound_settings';
const LOCAL_OVERRIDE_KEY = 'order_notification_sound_override';
let settingsCache: { value: OrderNotificationSoundSettings; expiresAt: number } | null = null;
let activePlayback: { audience: OrderSoundAudience; stop: () => void } | null = null;
let activeCustomAudio: { audience: OrderSoundAudience; stop: () => void } | null = null;
let backgroundAudio: HTMLAudioElement | null = null;
let backgroundAudioUnlocked = false;
let backgroundAudioTimer: number | null = null;
let activeBackgroundAudio: { audience: OrderSoundAudience; stop: () => void } | null = null;
const soundRequestGenerations: Record<OrderSoundAudience, number> = { merchant: 0, courier: 0 };
const pendingSoundAudiences = new Set<OrderSoundAudience>();

/** Stop the current short alert without changing saved settings. */
export function stopOrderNotificationSound(audience?: OrderSoundAudience) {
  const targets = audience ? [audience] : ['merchant', 'courier'] as const;
  targets.forEach((target) => {
    soundRequestGenerations[target] += 1;
    pendingSoundAudiences.delete(target);
  });
  if (activePlayback && (!audience || activePlayback.audience === audience)) {
    activePlayback.stop();
    activePlayback = null;
  }
  if (activeCustomAudio && (!audience || activeCustomAudio.audience === audience)) {
    activeCustomAudio.stop();
    activeCustomAudio = null;
  }
  if (activeBackgroundAudio && (!audience || activeBackgroundAudio.audience === audience)) {
    activeBackgroundAudio.stop();
    activeBackgroundAudio = null;
  }
}

function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  const number = typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  return Math.min(max, Math.max(min, number));
}

export function normalizeOrderNotificationSoundSettings(value: unknown): OrderNotificationSoundSettings {
  const input = value && typeof value === 'object' ? value as Partial<OrderNotificationSoundSettings> : {};
  const isPreset = (candidate: unknown): candidate is OrderSoundPreset =>
    ['urgent', 'bell', 'chime', 'custom'].includes(candidate as string);
  const legacyPreset = isPreset(input.preset) ? input.preset : DEFAULT_ORDER_SOUND_SETTINGS.preset;
  const legacyVolume = clampNumber(input.volume, 0, 1, DEFAULT_ORDER_SOUND_SETTINGS.volume);
  return {
    ...DEFAULT_ORDER_SOUND_SETTINGS,
    ...input,
    // Order audio is required for both operational audiences. The browser
    // permission remains user-controlled, while audience enabled flags are not.
    enabled: true,
    merchant_enabled: true,
    courier_enabled: true,
    preset: legacyPreset,
    custom_audio_url: typeof input.custom_audio_url === 'string' ? input.custom_audio_url : '',
    volume: legacyVolume,
    merchant_preset: isPreset(input.merchant_preset) ? input.merchant_preset : legacyPreset,
    merchant_custom_audio_url: typeof input.merchant_custom_audio_url === 'string'
      ? input.merchant_custom_audio_url : (typeof input.custom_audio_url === 'string' ? input.custom_audio_url : ''),
    merchant_volume: clampNumber(input.merchant_volume, 0, 1, legacyVolume),
    courier_preset: isPreset(input.courier_preset) ? input.courier_preset : legacyPreset,
    courier_custom_audio_url: typeof input.courier_custom_audio_url === 'string'
      ? input.courier_custom_audio_url : (typeof input.custom_audio_url === 'string' ? input.custom_audio_url : ''),
    courier_volume: clampNumber(input.courier_volume, 0.1, 1, legacyVolume),
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

export function getAudienceProfile(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience): OrderSoundProfile {
  return audience === 'merchant'
    ? { enabled: settings.merchant_enabled, preset: settings.merchant_preset, custom_audio_url: settings.merchant_custom_audio_url, volume: settings.merchant_volume }
    : { enabled: true, preset: settings.courier_preset, custom_audio_url: settings.courier_custom_audio_url, volume: settings.courier_volume };
}

function localOverrideKey(audience: OrderSoundAudience) {
  return `${LOCAL_OVERRIDE_KEY}:${audience}`;
}

export function getOrderSoundLocalOverride(audience: OrderSoundAudience): Partial<OrderSoundProfile> | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = window.localStorage.getItem(localOverrideKey(audience));
    return raw ? JSON.parse(raw) as Partial<OrderSoundProfile> : null;
  } catch {
    return null;
  }
}

export function saveOrderSoundLocalOverride(audience: OrderSoundAudience, profile: OrderSoundProfile) {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(localOverrideKey(audience), JSON.stringify(profile));
}

export function clearOrderSoundLocalOverride(audience: OrderSoundAudience) {
  if (typeof window === 'undefined') return;
  window.localStorage.removeItem(localOverrideKey(audience));
}

export function resolveOrderSoundProfile(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience, override = getOrderSoundLocalOverride(audience)): OrderSoundProfile {
  const profile = { ...getAudienceProfile(settings, audience), ...(override || {}) };
  return {
    ...profile,
    enabled: true,
    volume: clampNumber(profile.volume, 0.1, 1, audience === 'courier' ? DEFAULT_ORDER_SOUND_SETTINGS.courier_volume : DEFAULT_ORDER_SOUND_SETTINGS.merchant_volume),
  };
}

export function shouldPlayOrderNotificationSound(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience, profile: OrderSoundProfile): boolean {
  return (audience === 'merchant' || audience === 'courier') && settings.enabled && profile.enabled;
}

/** Call from a user gesture before a realtime callback needs to play audio. */
export async function unlockOrderNotificationAudio(options: { playConfirmationTone?: boolean } = {}): Promise<boolean> {
  if (typeof window === 'undefined') return false;
  // WebAudio can be suspended when a mobile browser backgrounds the page.
  // Keep a user-gesture-unlocked media element as a best-effort background
  // fallback. A service worker cannot play audio itself; it uses Web Push.
  if (!backgroundAudio) {
    backgroundAudio = new Audio('/notification.wav');
    backgroundAudio.preload = 'auto';
    backgroundAudio.setAttribute('aria-hidden', 'true');
  }
  const backgroundUnlock = backgroundAudio.play().then(() => {
    backgroundAudio?.pause();
    if (backgroundAudio) backgroundAudio.currentTime = 0;
    backgroundAudioUnlocked = true;
  }).catch(() => undefined);
  const webAudioUnlock = enableAudio(options).then(flushPendingSoundAudiences).catch(() => undefined);
  await Promise.all([backgroundUnlock, webAudioUnlock]);
  return isAudioEnabled() || backgroundAudioUnlocked;
}

function stopBackgroundAudioPlayback() {
  if (backgroundAudioTimer !== null) {
    window.clearTimeout(backgroundAudioTimer);
    backgroundAudioTimer = null;
  }
  backgroundAudio?.pause();
  if (backgroundAudio) backgroundAudio.currentTime = 0;
}

async function playBackgroundAudio(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience, volume: number, customAudioUrl?: string) {
  if (!backgroundAudioUnlocked || !backgroundAudio) return false;
  stopBackgroundAudioPlayback();
  backgroundAudio.src = customAudioUrl || '/notification.wav';
  let stopped = false;
  let resolveStop: (() => void) | null = null;
  const playback = {
    audience,
    stop: () => {
      stopped = true;
      stopBackgroundAudioPlayback();
      resolveStop?.();
    },
  };
  activeBackgroundAudio = playback;
  try {
    for (let index = 0; index < settings.repeat_count && !stopped; index += 1) {
      const audio = backgroundAudio;
      audio.volume = Math.max(0.1, Math.min(1, volume));
      audio.currentTime = 0;
      await new Promise<void>((resolve) => {
        resolveStop = resolve;
        const onEnded = () => {
          audio.removeEventListener('ended', onEnded);
          resolveStop = null;
          resolve();
        };
        audio.addEventListener('ended', onEnded, { once: true });
        void audio.play().catch(() => resolve());
      });
      if (index < settings.repeat_count - 1 && !stopped) {
        await new Promise<void>((resolve) => {
          backgroundAudioTimer = window.setTimeout(() => {
            backgroundAudioTimer = null;
            resolve();
          }, settings.repeat_gap_ms);
          resolveStop = resolve;
        });
      }
    }
    return true;
  } finally {
    stopBackgroundAudioPlayback();
    if (activeBackgroundAudio === playback) activeBackgroundAudio = null;
  }
}

function flushPendingSoundAudiences() {
  if (!isAudioEnabled() || getAudioContext()?.state !== 'running') return;
  const audiences = [...pendingSoundAudiences];
  pendingSoundAudiences.clear();
  audiences.forEach((audience) => { void playOrderNotificationSound(audience); });
}

async function playPreset(preset: Exclude<OrderSoundPreset, 'custom'>, volume: number) {
  const context = getAudioContext();
  if (!context || context.state !== 'running') return;

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

async function playCustomAudio(url: string, volume: number, audience: OrderSoundAudience) {
  const context = getAudioContext();
  if (!context || context.state !== 'running') throw new Error('AudioContext is not running');
  const response = await fetch(url);
  if (!response.ok) throw new Error('Custom notification audio failed to load');
  const buffer = await context.decodeAudioData(await response.arrayBuffer());
  const source = context.createBufferSource();
  const gain = context.createGain();
  source.buffer = buffer;
  gain.gain.value = Math.max(0, Math.min(1, volume));
  source.connect(gain);
  gain.connect(context.destination);
  activeCustomAudio = { audience, stop: () => source.stop() };
  await new Promise<void>((resolve) => {
    source.addEventListener('ended', () => resolve(), { once: true });
    source.start();
  });
  if (activeCustomAudio?.audience === audience) activeCustomAudio = null;
}

async function playNotificationWithSettings(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience, ignoreLocalOverride = false) {
  const profile = ignoreLocalOverride ? getAudienceProfile(settings, audience) : resolveOrderSoundProfile(settings, audience);
  if (!shouldPlayOrderNotificationSound(settings, audience, profile)) return;

  activePlayback?.stop();
  let stopped = false;
  let wakeDelay: (() => void) | null = null;
  const playback = {
    audience,
    stop: () => {
      stopped = true;
      wakeDelay?.();
    },
  };
  activePlayback = playback;

  try {
    for (let index = 0; index < settings.repeat_count && !stopped; index += 1) {
      if (profile.preset === 'custom' && profile.custom_audio_url) {
        try {
          await playCustomAudio(profile.custom_audio_url, profile.volume, audience);
        } catch {
          // A remote custom file can be blocked by mobile autoplay/CORS. Keep
          // the alarm responsive by falling back to a local Web Audio preset.
          await playPreset('urgent', profile.volume);
        }
      } else {
        await playPreset(profile.preset === 'custom' ? 'urgent' : profile.preset, profile.volume);
      }
      if (index < settings.repeat_count - 1 && !stopped) {
        await new Promise<void>((resolve) => {
          const timer = window.setTimeout(() => {
            wakeDelay = null;
            resolve();
          }, settings.repeat_gap_ms);
          wakeDelay = () => {
            window.clearTimeout(timer);
            wakeDelay = null;
            resolve();
          };
        });
      }
    }
  } catch {
    // Browser autoplay policy or an unavailable custom file should not break order updates.
    if (!stopped && getAudioContext()?.state === 'suspended') pendingSoundAudiences.add(audience);
  } finally {
    if (activePlayback === playback) activePlayback = null;
  }
}

export async function playOrderNotificationSound(audience: OrderSoundAudience) {
  if (typeof window === 'undefined') return;
  const settings = await fetchOrderNotificationSoundSettings();
  const generation = soundRequestGenerations[audience];
  const profile = resolveOrderSoundProfile(settings, audience);
  if (soundRequestGenerations[audience] !== generation) return;
  // Prefer a media element while hidden: mobile browsers commonly suspend
  // WebAudio in background tabs, while an already-unlocked media element can
  // continue. If it cannot play, continue with the normal WebAudio path.
  if (document.hidden && await playBackgroundAudio(
    settings,
    audience,
    profile.volume,
    profile.preset === 'custom' ? profile.custom_audio_url : undefined,
  )) return;
  if (!isAudioEnabled()) {
    pendingSoundAudiences.add(audience);
    requestAudioPermission();
    return;
  }
  const context = getAudioContext();
  if (!context || context.state !== 'running') {
    pendingSoundAudiences.add(audience);
    requestAudioPermission();
    return;
  }
  return playNotificationWithSettings(settings, audience);
}

export async function previewOrderNotificationSound(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience = 'merchant') {
  await enableAudio();
  return playNotificationWithSettings(normalizeOrderNotificationSoundSettings(settings), audience, true);
}

export const ORDER_SOUND_SETTINGS_KEY = SETTINGS_KEY;
export const ORDER_SOUND_PRESET_LABELS: Record<OrderSoundPreset, string> = {
  urgent: 'Urgent — tiga nada tegas',
  bell: 'Bell — nada lonceng',
  chime: 'Chime — nada ramah',
  custom: 'Audio custom yang diunggah',
};
