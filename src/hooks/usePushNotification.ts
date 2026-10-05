/**
 * P2-05: Push Notification — frontend hook
 * Shares the authenticated subscription lifecycle with account settings.
 */
import { useState, useEffect, useCallback } from "react";
import { useAuth } from "@/contexts/AuthContext";
import {
  getPushPermission,
  hasActiveBrowserPushSubscription,
  isPushSupported,
  subscribeToPush,
  unsubscribeFromPush,
} from "@/lib/pushNotification";

export function usePushNotification() {
  const { user } = useAuth();
  const [isSupported, setIsSupported] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission>("default");
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const syncStatus = async () => {
      const supported = await isPushSupported();
      const currentPermission = await getPushPermission();
      const subscribed = supported && await hasActiveBrowserPushSubscription();
      if (cancelled) return;
      setIsSupported(supported);
      setPermission(currentPermission);
      setIsSubscribed(subscribed);
    };
    void syncStatus();

    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  const subscribe = useCallback(async (): Promise<boolean> => {
    if (!isSupported || !user) return false;
    setLoading(true);
    try {
      const success = await subscribeToPush(user.id);
      setPermission(await getPushPermission());
      if (success) setIsSubscribed(true);
      return success;
    } finally {
      setLoading(false);
    }
  }, [isSupported, user]);

  const unsubscribe = useCallback(async (): Promise<boolean> => {
    if (!isSupported || !user) return false;
    setLoading(true);
    try {
      const success = await unsubscribeFromPush(user.id);
      if (success) setIsSubscribed(false);
      return success;
    } finally {
      setLoading(false);
    }
  }, [isSupported, user]);

  return {
    isSupported,
    permission,
    isSubscribed,
    loading,
    subscribe,
    unsubscribe,
  };
}
