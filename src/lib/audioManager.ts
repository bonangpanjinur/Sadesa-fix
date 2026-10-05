const AUDIO_PERMISSION_KEY = 'sadesa-audio-enabled';
const AUDIO_PERMISSION_EVENT = 'sadesa-audio-permission-changed';
const AUDIO_PERMISSION_REQUIRED_EVENT = 'sadesa-audio-permission-required';

type AudioContextConstructor = new () => AudioContext;

type AudioManagerEvent = 'statechange' | 'permission-required';
const listeners: Record<AudioManagerEvent, Set<() => void>> = {
  statechange: new Set(),
  'permission-required': new Set(),
};

let sharedAudioContext: AudioContext | null = null;
let contextStateListener: (() => void) | null = null;

function getAudioContextConstructor(): AudioContextConstructor | null {
  if (typeof window === 'undefined') return null;
  const browserWindow = window as Window & { webkitAudioContext?: AudioContextConstructor };
  return window.AudioContext || browserWindow.webkitAudioContext || null;
}

function emit(event: AudioManagerEvent) {
  listeners[event].forEach((listener) => listener());
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent(event === 'statechange' ? AUDIO_PERMISSION_EVENT : AUDIO_PERMISSION_REQUIRED_EVENT));
  }
}

function readPermissionPreference() {
  if (typeof window === 'undefined') return false;
  try {
    return window.localStorage.getItem(AUDIO_PERMISSION_KEY) === 'true';
  } catch {
    return false;
  }
}

function writePermissionPreference(enabled: boolean) {
  if (typeof window === 'undefined') return;
  try {
    if (enabled) window.localStorage.setItem(AUDIO_PERMISSION_KEY, 'true');
    else window.localStorage.removeItem(AUDIO_PERMISSION_KEY);
  } catch {
    // Private browsing/storage restrictions must not break audio activation.
  }
}

function attachStateListener(context: AudioContext) {
  if (contextStateListener) return;
  contextStateListener = () => {
    emit('statechange');
    if (context.state === 'suspended' && readPermissionPreference()) emit('permission-required');
  };
  context.addEventListener('statechange', contextStateListener);
}

function ensureAudioContext() {
  if (sharedAudioContext && sharedAudioContext.state !== 'closed') return sharedAudioContext;
  const Constructor = getAudioContextConstructor();
  if (!Constructor) return null;
  sharedAudioContext = new Constructor();
  contextStateListener = null;
  attachStateListener(sharedAudioContext);
  return sharedAudioContext;
}

/** Returns the singleton context without creating one during initial page load. */
export function getAudioContext(): AudioContext | null {
  return sharedAudioContext && sharedAudioContext.state !== 'closed' ? sharedAudioContext : null;
}

export function isWebAudioSupported() {
  return getAudioContextConstructor() !== null;
}

/** True only when the saved preference exists and the shared context is running. */
export function isAudioEnabled() {
  return isWebAudioSupported() && readPermissionPreference() && getAudioContext()?.state === 'running';
}

/** Used by the permission hook to avoid showing the prompt on every reload. */
export function hasAudioPermissionPreference() {
  return readPermissionPreference();
}

export function subscribeAudioManager(event: AudioManagerEvent, listener: () => void) {
  listeners[event].add(listener);
  return () => listeners[event].delete(listener);
}

/** Must be called from a user gesture; confirmation tone is optional for silent autoplay unlocks. */
export async function enableAudio(options: { playConfirmationTone?: boolean } = {}) {
  if (!isWebAudioSupported()) throw new Error('Web Audio API tidak didukung oleh browser ini.');
  const context = ensureAudioContext();
  if (!context) throw new Error('Web Audio API tidak tersedia.');
  if (context.state === 'suspended') await context.resume();
  if (context.state !== 'running') throw new Error(`AudioContext tidak dapat diaktifkan (status: ${context.state}).`);
  if (options.playConfirmationTone !== false) await playTestSound();
  writePermissionPreference(true);
  emit('statechange');
  return true;
}

export async function disableAudio() {
  writePermissionPreference(false);
  const context = getAudioContext();
  if (context?.state === 'running') await context.suspend();
  emit('statechange');
}

/** A short, user-initiated verification beep. It never creates a context. */
export async function playTestSound() {
  const context = getAudioContext();
  if (!context || context.state !== 'running') return false;
  await playToneSequence([{ frequency: 880, at: 0, duration: 0.14 }], 0.22);
  return true;
}

export async function playToneSequence(
  notes: Array<{ frequency: number; at: number; duration: number }>,
  volume = 0.3,
) {
  const context = getAudioContext();
  if (!context || context.state !== 'running') return false;
  const master = context.createGain();
  master.gain.setValueAtTime(Math.max(0.01, Math.min(1, volume)), context.currentTime);
  master.connect(context.destination);
  notes.forEach(({ frequency, at, duration }) => {
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    const startAt = context.currentTime + at;
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(frequency, startAt);
    gain.gain.setValueAtTime(0.001, startAt);
    gain.gain.linearRampToValueAtTime(1, startAt + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.001, startAt + duration);
    oscillator.connect(gain);
    gain.connect(master);
    oscillator.start(startAt);
    oscillator.stop(startAt + duration + 0.04);
  });
  return true;
}

/** Lets background notification handlers ask the visible modal to re-enable audio. */
export function requestAudioPermission() {
  emit('permission-required');
}

export const AUDIO_PERMISSION_STORAGE_KEY = AUDIO_PERMISSION_KEY;
