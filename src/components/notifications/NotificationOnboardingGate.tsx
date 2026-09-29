import { useCallback, useEffect, useRef, useState } from 'react';
import { Bell, RotateCcw, ShieldAlert, Loader2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  getPushPermission,
  getSubscriptionStatus,
  hasActiveBrowserPushSubscription,
  isPushSupported,
  subscribeToPush,
  getLastPushError,
} from '@/lib/pushNotification';

type OnboardingStatus = 'checking' | 'ready' | 'unsupported' | 'default' | 'denied' | 'subscribe-failed' | 'sync-failed';

/**
 * Mandatory push onboarding for couriers only. Mount it inside CourierLayout,
 * and never show the modal when this browser already has an active subscription.
 * The browser permission prompt is only reached from an explicit button click.
 */
export function NotificationOnboardingGate() {
  const { user, loading: authLoading } = useAuth();
  const [status, setStatus] = useState<OnboardingStatus>('checking');
  const [busy, setBusy] = useState(false);
  const operationRef = useRef(0);

  const checkStatus = useCallback(async () => {
    const operationId = ++operationRef.current;
    if (!user) {
      setStatus('ready');
      return;
    }

    setStatus('checking');
    const supported = await isPushSupported();
    if (operationId !== operationRef.current) return;
    if (!supported) {
      setStatus('unsupported');
      return;
    }

    const permission = await getPushPermission();
    if (operationId !== operationRef.current) return;
    if (permission === 'denied') {
      setStatus('denied');
      return;
    }
    if (permission !== 'granted') {
      setStatus('default');
      return;
    }

    const browserSubscribed = await hasActiveBrowserPushSubscription();
    if (operationId !== operationRef.current) return;
    if (!browserSubscribed) {
      setStatus('default');
      return;
    }

    const registered = await getSubscriptionStatus(user.id);
    if (operationId !== operationRef.current) return;
    if (registered) {
      setStatus('ready');
      return;
    }

    // A local subscription means the user already enabled push. Re-register it
    // quietly so a stale/missing server row does not bring back the blocking modal.
    const repaired = await subscribeToPush(user.id);
    if (operationId !== operationRef.current) return;
    if (!repaired) {
      console.warn('Push is enabled in this browser but could not be re-synced to the server.');
      setStatus('sync-failed');
      return;
    }
    setStatus('ready');
  }, [user]);

  useEffect(() => {
    if (authLoading) return;
    void checkStatus();
  }, [authLoading, checkStatus]);

  const handleEnable = async () => {
    if (!user || busy) return;
    const operationId = ++operationRef.current;
    setBusy(true);
    try {
      const subscribed = await subscribeToPush(user.id);
      if (operationId !== operationRef.current) return;
      if (subscribed) {
        setStatus('ready');
      } else {
        const permission = await getPushPermission();
        if (operationId !== operationRef.current) return;
        if (permission === 'denied') {
          setStatus('denied');
        } else {
          setStatus('subscribe-failed');
        }
      }
    } finally {
      if (operationId === operationRef.current) setBusy(false);
    }
  };

  if (authLoading || !user || status === 'checking' || status === 'ready') {
    return null;
  }

  const isDenied = status === 'denied';
  const isUnsupported = status === 'unsupported';
  const isSyncFailed = status === 'sync-failed';

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
            {isDenied ? 'Notifikasi diblokir' : isUnsupported ? 'Notifikasi tidak tersedia' : isSyncFailed ? 'Izin sudah ada, sinkronisasi belum selesai' : 'Aktifkan notifikasi'}
          </CardTitle>
          <CardDescription className="max-w-md text-center">
            {isDenied
              ? 'Izin notifikasi untuk Sadesa sedang diblokir oleh browser. Browser tidak mengizinkan aplikasi mengubahnya secara otomatis.'
              : isUnsupported
                ? 'Browser ini tidak mendukung push notification. Gunakan browser modern seperti Chrome, Edge, atau Firefox untuk menerima update pesanan.'
              : isSyncFailed
                ? 'Browser sudah memiliki izin dan subscription, tetapi server belum menerima pendaftarannya. Coba ulangi saat koneksi stabil.'
                : 'Notifikasi push wajib aktif untuk ojek agar pesanan tetap masuk saat aplikasi tidak terbuka. Aktifkan bunyi dan getar untuk alarm pesanan.'}
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
              Notifikasi push wajib untuk ojek, tetapi browser ini tidak mendukung Notification API, Service Worker, dan Push API. Silakan gunakan browser yang mendukung fitur tersebut.
            </div>
          ) : (
            <div className="rounded-lg border bg-muted/40 p-4 text-sm text-muted-foreground">
              {isSyncFailed ? (
                <>
                  <p className="font-medium text-foreground">Langkah berikutnya</p>
                  <p className="mt-1">Pastikan koneksi internet aktif, lalu tekan <strong>Coba sinkronkan lagi</strong>. Izin browser tidak perlu diberikan ulang.</p>
                  {getLastPushError() && <p className="mt-2 text-xs text-destructive">Detail: {getLastPushError()}</p>}
                </>
              ) : 'Push wajib aktif untuk menerima pesanan saat aplikasi tidak terbuka. Permintaan izin browser hanya muncul setelah Anda menekan tombol di bawah.'}
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
                {busy ? 'Menyinkronkan...' : isSyncFailed ? 'Coba sinkronkan lagi' : 'Aktifkan Notifikasi'}
              </Button>
            )}
          </div>

          {(status === 'subscribe-failed' || status === 'sync-failed') && (
            <p className="flex items-center justify-center gap-2 text-center text-sm text-destructive" role="alert">
              <ShieldAlert className="h-4 w-4" />
              {status === 'sync-failed' ? 'Izin sudah diberikan, tetapi pendaftaran ke server belum berhasil.' : 'Aktivasi belum berhasil. Pastikan izin sudah diberikan, lalu coba lagi.'}
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
export default NotificationOnboardingGate;
