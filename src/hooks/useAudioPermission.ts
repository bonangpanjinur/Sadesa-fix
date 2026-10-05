import { useCallback, useEffect, useState } from 'react';
import {
  enableAudio,
  hasAudioPermissionPreference,
  isAudioEnabled,
  isWebAudioSupported,
  subscribeAudioManager,
} from '@/lib/audioManager';

export function useAudioPermission() {
  const [isSupported] = useState(() => isWebAudioSupported());
  const [isEnabled, setIsEnabled] = useState(() => isAudioEnabled());
  const [needsPermission, setNeedsPermission] = useState(() => isSupported && !hasAudioPermissionPreference());
  const [isActivating, setIsActivating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(() => {
    const enabled = isAudioEnabled();
    const hasPreference = hasAudioPermissionPreference();
    setIsEnabled(enabled);
    // A stored preference is enough to keep the modal quiet after a reload.
    // If a context exists and is suspended, the manager explicitly asks again.
    if (enabled) {
      setNeedsPermission(false);
      setError(null);
    } else if (!hasPreference) {
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
