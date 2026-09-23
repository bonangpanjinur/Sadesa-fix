import { useCallback, useEffect, useState } from 'react';
import { Bell, RotateCcw, ShieldAlert, Loader2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  getPushPermission,
  getSubscriptionStatus,
  isPushSupported,
  subscribeToPush,
} from '@/lib/pushNotification';

type OnboardingStatus = 'checking' | 'ready' | 'unsupported' | 'default' | 'denied' | 'subscribe-failed';

/**
 * Blocks authenticated application content until this browser has an active
 * Sadesa push subscription. The browser permission prompt is only reached from
 * the explicit button click in this component.
 */
export function NotificationOnboardingGate() {
  const { user, loading: authLoading } = useAuth();
  const [status, setStatus] = useState<OnboardingStatus>('checking');
  const [busy, setBusy] = useState(false);

  const checkStatus = useCallback(async () => {
    if (!user) {
      setStatus('ready');
      return;
    }

    setStatus('checking');
    const supported = await isPushSupported();
    if (!supported) {
      setStatus('unsupported');
      return;
    }

    const permission = await getPushPermission();
    if (permission === 'denied') {
      setStatus('denied');
      return;
    }
    if (permission !== 'granted') {
      setStatus('default');
      return;
    }

    const subscribed = await getSubscriptionStatus(user.id);
    setStatus(subscribed ? 'ready' : 'subscribe-failed');
  }, [user]);

  useEffect(() => {
    if (authLoading) return;
    void checkStatus();
  }, [authLoading, checkStatus]);

  const handleEnable = async () => {
    if (!user || busy) return;
    setBusy(true);
    try {
      const subscribed = await subscribeToPush(user.id);
      if (subscribed) {
        setStatus('ready');
      } else {
        const permission = await getPushPermission();
        setStatus(permission === 'denied' ? 'denied' : 'subscribe-failed');
      }
    } finally {
      setBusy(false);
    }
  };

  if (authLoading || !user || status === 'checking' || status === 'ready') {
    return null;
  }

  const isDenied = status === 'denied';
  const isUnsupported = status === 'unsupported';

  return (
    <div
      className="fixed inset-0 z-[100] flex min-h-screen items-center justify-center overflow-y-auto bg-background/95 px-4 py-8 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="notification-onboarding-title"
    >
      <Card className="w-full max-w-lg shadow-xl">
        <CardHeader className="items-center text-center">
          <div className={`mb-2 flex h-16 w-16 items-center justify-center rounded-full ${isDenied ? 'bg-destructive/10' : 'bg-primary/10'}`}>
            {isDenied ? <ShieldAlert className="h-8 w-8 text-destructive" /> : <Bell className="h-8 w-8 text-primary" />}
          </div>
          <CardTitle id="notification-onboarding-title">
            {isDenied ? 'Notifikasi diblokir' : isUnsupported ? 'Notifikasi tidak tersedia' : 'Aktifkan notifikasi'}
          </CardTitle>
          <CardDescription className="max-w-md text-center">
            {isDenied
              ? 'Izin notifikasi untuk Sadesa sedang diblokir oleh browser. Browser tidak mengizinkan aplikasi mengubahnya secara otomatis.'
              : isUnsupported
                ? 'Browser ini tidak mendukung push notification. Gunakan browser modern seperti Chrome, Edge, atau Firefox untuk menerima update pesanan.'
                : 'Aktifkan notifikasi untuk menerima update pesanan dan informasi penting dari Sadesa.'}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {isDenied ? (
            <div className="rounded-lg border border-destructive/20 bg-destructive/5 p-4 text-sm text-muted-foreground">
              <p className="font-medium text-foreground">Cara mengaktifkan:</p>
              <ol className="mt-2 list-inside list-decimal space-y-1">
                <li>Buka pengaturan browser untuk situs ini.</li>
                <li>Pilih <strong>Notifications</strong> atau <strong>Notifikasi</strong>.</li>
                <li>Ubah izin Sadesa menjadi <strong>Allow</strong>.</li>
                <li>Kembali ke sini, lalu tekan tombol cek ulang.</li>
              </ol>
            </div>
          ) : isUnsupported ? (
            <div className="rounded-lg border bg-muted/40 p-4 text-sm text-muted-foreground">
              Push notification membutuhkan Notification API, Service Worker, dan Push API. Silakan buka Sadesa memakai browser yang mendukung fitur tersebut.
            </div>
          ) : (
            <div className="rounded-lg border bg-muted/40 p-4 text-sm text-muted-foreground">
              Permintaan izin hanya akan muncul setelah Anda menekan tombol di bawah. Sadesa tidak meminta izin secara otomatis saat halaman dibuka.
            </div>
          )}

          <div className="flex flex-col gap-2 sm:flex-row sm:justify-end">
            {isDenied ? (
              <Button variant="outline" onClick={() => void checkStatus()} disabled={busy}>
                <RotateCcw className="h-4 w-4" />
                Cek ulang izin
              </Button>
            ) : isUnsupported ? null : (
              <Button onClick={() => void handleEnable()} disabled={busy}>
                {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Bell className="h-4 w-4" />}
                {busy ? 'Mengaktifkan...' : 'Aktifkan Notifikasi'}
              </Button>
            )}
          </div>

          {status === 'subscribe-failed' && (
            <p className="flex items-center justify-center gap-2 text-center text-sm text-destructive" role="alert">
              <ShieldAlert className="h-4 w-4" />
              Aktivasi belum berhasil. Pastikan izin sudah diberikan, lalu coba lagi.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
export default NotificationOnboardingGate;
