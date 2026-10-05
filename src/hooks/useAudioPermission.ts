import { useCallback, useEffect, useState } from 'react';
import {
  enableAudio,
  isAudioEnabled,
  isWebAudioSupported,
  subscribeAudioManager,
} from '@/lib/audioManager';

export function useAudioPermission() {
  const [isSupported] = useState(() => isWebAudioSupported());
  const [isEnabled, setIsEnabled] = useState(() => isAudioEnabled());
  // The saved preference survives reloads; the browser's unlocked AudioContext
  // does not. Operational users must make a fresh gesture in every app session.
  const [needsPermission, setNeedsPermission] = useState(() => isSupported && !isAudioEnabled());
  const [isActivating, setIsActivating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(() => {
    const enabled = isAudioEnabled();
    setIsEnabled(enabled);
    if (enabled) {
      setNeedsPermission(false);
      setError(null);
    } else {
      setNeedsPermission(true);
    }
  }, []);

  useEffect(() => {
    const unsubscribeState = subscribeAudioManager('statechange', refresh);
    const unsubscribePermission = subscribeAudioManager('permission-required', () => {
      setNeedsPermission(true);
      setError(null);
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
  }, [refresh]);

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
