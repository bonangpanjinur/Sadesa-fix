import { useCallback, useEffect, useState } from 'react';
import {
  enableAudio,
  hasAudioPermissionPreference,
  isAudioEnabled,
  isWebAudioSupported,
  shouldPromptForAudioActivation,
  subscribeAudioManager,
} from '@/lib/audioManager';

export function useAudioPermission() {
  const [isSupported] = useState(() => isWebAudioSupported());
  const [isEnabled, setIsEnabled] = useState(() => isAudioEnabled());
  // Prompt once. A previous opt-in is remembered across reloads; if the
  // browser suspends audio later, silently resume it on the next user gesture.
  const [needsPermission, setNeedsPermission] = useState(() => shouldPromptForAudioActivation(isSupported));
  const [isActivating, setIsActivating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(() => {
    const enabled = isAudioEnabled();
    setIsEnabled(enabled);
    if (enabled) {
      setNeedsPermission(false);
      setError(null);
    } else if (shouldPromptForAudioActivation(isSupported)) {
      setNeedsPermission(true);
    } else {
      setNeedsPermission(false);
    }
  }, [isSupported]);

  useEffect(() => {
    const unsubscribeState = subscribeAudioManager('statechange', refresh);
    const unsubscribePermission = subscribeAudioManager('permission-required', () => {
      if (shouldPromptForAudioActivation(isSupported)) {
        setNeedsPermission(true);
        setError(null);
      }
    });
    const handleVisibility = () => refresh();
    window.addEventListener('pageshow', handleVisibility);
    document.addEventListener('visibilitychange', handleVisibility);
    return () => {
      unsubscribeState();
      unsubscribePermission();
      window.removeEventListener('pageshow', handleVisibility);
      document.removeEventListener('visibilitychange', handleVisibility);
    };
  }, [isSupported, refresh]);

  useEffect(() => {
    if (!isSupported || !hasAudioPermissionPreference() || isEnabled) return;

    let disposed = false;
    const resumeOnUserGesture = () => {
      if (!hasAudioPermissionPreference() || isAudioEnabled()) return;
      void enableAudio({ playConfirmationTone: false }).then(() => {
        if (disposed) return;
        setIsEnabled(true);
        setNeedsPermission(false);
        setError(null);
      }).catch(() => {
        // Keep listening for the next real user gesture; do not reopen the
        // blocking first-time activation dialog after a previous opt-in.
      });
    };

    window.addEventListener('pointerdown', resumeOnUserGesture, true);
    window.addEventListener('keydown', resumeOnUserGesture, true);
    window.addEventListener('touchstart', resumeOnUserGesture, true);
    return () => {
      disposed = true;
      window.removeEventListener('pointerdown', resumeOnUserGesture, true);
      window.removeEventListener('keydown', resumeOnUserGesture, true);
      window.removeEventListener('touchstart', resumeOnUserGesture, true);
    };
  }, [isEnabled, isSupported]);

  const activate = useCallback(async () => {
    setIsActivating(true);
    setError(null);
    try {
      await enableAudio();
      setIsEnabled(true);
      setNeedsPermission(false);
    } catch (activationError) {
      setIsEnabled(false);
      setError(activationError instanceof Error ? activationError.message : 'Audio belum dapat diaktifkan.');
    } finally {
      setIsActivating(false);
    }
  }, []);

  return {
    isSupported,
    isEnabled,
    needsPermission: isSupported && needsPermission,
    isActivating,
    error,
    activate,
  };
}
