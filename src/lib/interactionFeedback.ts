/** Lightweight feedback for an explicit user interaction. */
export function playSnoozeFeedback(): void {
  if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') {
    try {
      navigator.vibrate([18, 24, 18]);
      return;
    } catch {
      // Fall back to a short Web Audio tick when haptics are unavailable.
    }
  }

  if (typeof window === 'undefined') return;
  const AudioContextConstructor = window.AudioContext
    || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!AudioContextConstructor) return;

  try {
    const context = new AudioContextConstructor();
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    const startAt = context.currentTime;
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(620, startAt);
    oscillator.frequency.exponentialRampToValueAtTime(420, startAt + 0.045);
    gain.gain.setValueAtTime(0.0001, startAt);
    gain.gain.exponentialRampToValueAtTime(0.035, startAt + 0.006);
    gain.gain.exponentialRampToValueAtTime(0.0001, startAt + 0.06);
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start(startAt);
    oscillator.stop(startAt + 0.065);
    void oscillator.addEventListener('ended', () => { void context.close(); }, { once: true });
  } catch {
    // Feedback is optional and must never block snooze behavior.
  }
}
