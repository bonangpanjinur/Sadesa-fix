import { useCallback, useState, useEffect } from 'react';
import { Bell, BellOff, Loader2 } from 'lucide-react';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/contexts/AuthContext';
import {
  getLastPushError,
  isPushSupported,
  getPushPermission,
  subscribeToPush,
  unsubscribeFromPush,
  getSubscriptionStatus,
} from '@/lib/pushNotification';
import { useTranslation } from '@/lib/i18n';
import { toast } from 'sonner';

export function PushNotificationSettings({ required = false }: { required?: boolean }) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const [supported, setSupported] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission>('default');
  const [subscribed, setSubscribed] = useState(false);
  const [loading, setLoading] = useState(true);
  const [toggling, setToggling] = useState(false);
  const [statusError, setStatusError] = useState(false);

  const checkStatus = useCallback(async () => {
    setLoading(true);
    setStatusError(false);
    try {
      const isSupported = await isPushSupported();
      setSupported(isSupported);
      if (!isSupported) {
        setSubscribed(false);
        return;
      }

      const currentPermission = await getPushPermission();
      setPermission(currentPermission);
      if (user && currentPermission === 'granted') {
        setSubscribed(await getSubscriptionStatus(user.id));
      } else {
        setSubscribed(false);
      }
    } catch (error) {
      console.error('Error checking push notification status:', error);
      setStatusError(true);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    void checkStatus();
  }, [checkStatus]);

  const handleToggle = async (enabled: boolean) => {
    if (required && !enabled && subscribed) return;
    if (!user) {
      toast.error(t('settings.push.login_required'));
      return;
    }

    setToggling(true);
    try {
      if (enabled) {
        const success = await subscribeToPush(user.id);
        if (success) {
          setSubscribed(true);
          setPermission('granted');
          toast.success(t('settings.push.enabled'));
        } else {
          toast.error(getLastPushError() || t('settings.push.enable_failed'));
        }
      } else {
        const success = await unsubscribeFromPush(user.id);
        if (success) {
          setSubscribed(false);
          toast.success(t('settings.push.disabled'));
        } else {
          toast.error(t('settings.push.disable_failed'));
        }
      }
    } catch (error) {
      console.error('Error updating push notification settings:', error);
      toast.error(t('settings.push.error'));
    } finally {
      setToggling(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 rounded-lg bg-muted/50 p-4" role="status" aria-live="polite">
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
        <span className="text-sm text-muted-foreground">{t('settings.push.loading')}</span>
      </div>
    );
  }

  if (statusError) {
    return (
      <div className="flex items-center justify-between gap-3 rounded-lg border border-destructive/20 bg-destructive/5 p-4" role="alert">
        <span className="text-sm text-destructive">{t('settings.push.status_failed')}</span>
        <Button type="button" variant="outline" size="sm" onClick={() => void checkStatus()}>
          {t('common.retry')}
        </Button>
      </div>
    );
  }

  if (!supported) {
    return (
      <div className="rounded-lg bg-muted/50 p-4">
        <div className="flex items-center gap-2 text-muted-foreground">
          <BellOff className="h-4 w-4" aria-hidden="true" />
          <span className="text-sm">{t('settings.push.unsupported')}</span>
        </div>
      </div>
    );
  }

  if (permission === 'denied') {
    return (
      <div className="rounded-lg bg-destructive/10 p-4">
        <div className="flex items-center gap-2 text-destructive">
          <BellOff className="h-4 w-4" aria-hidden="true" />
          <span className="text-sm">{t('settings.push.permission_denied')}</span>
        </div>
        <p className="mt-2 text-xs text-muted-foreground">{t('settings.push.permission_help')}</p>
      </div>
    );
  }

  return (
    <div className="rounded-lg border border-border bg-card p-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className={`rounded-full p-2 ${subscribed ? 'bg-primary/10' : 'bg-muted'}`}>
            <Bell className={`h-4 w-4 ${subscribed ? 'text-primary' : 'text-muted-foreground'}`} aria-hidden="true" />
          </div>
          <div>
            <Label htmlFor="push-toggle" className="cursor-pointer font-medium">
              {t('settings.push.title')}
            </Label>
            <p className="text-xs text-muted-foreground">
              {required ? t('settings.push.required') : t('settings.push.description_inline')}
            </p>
          </div>
        </div>
        <Switch
          id="push-toggle"
          checked={subscribed}
          onCheckedChange={handleToggle}
          disabled={toggling || (required && subscribed)}
        />
      </div>

      {subscribed && (
        <div className="mt-3 border-t border-border pt-3">
          <p className="flex items-center gap-1 text-xs text-muted-foreground">
            <span className="h-2 w-2 animate-pulse rounded-full bg-primary" aria-hidden="true" />
            {t('settings.push.active')}
          </p>
        </div>
      )}
    </div>
  );
}
