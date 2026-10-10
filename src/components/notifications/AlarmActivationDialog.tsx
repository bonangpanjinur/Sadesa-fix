import { useState } from 'react';
import { Bell, Check, Loader2, Volume2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/contexts/AuthContext';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { getLastPushError, requestPushPermission, subscribeToPush } from '@/lib/pushNotification';
import { unlockOrderNotificationAudio } from '@/lib/orderNotificationSound';
import { vibrateCourierAlarm } from '@/lib/courierNotificationFeedback';

type AlarmAudience = 'merchant' | 'courier';

interface AlarmActivationDialogProps {
  audience: AlarmAudience;
}

const copy = {
  merchant: {
    trigger: 'Aktifkan Alarm & Notifikasi',
    title: 'Aktifkan alarm pesanan',
    description: 'Aktifkan suara dan daftarkan notifikasi push agar pesanan tetap diberitahukan saat aplikasi tertutup.',
    notificationLabel: 'Notifikasi pesanan',
    success: 'Alarm pesanan pedagang aktif',
    successDescription: 'Suara aktif dan push background sudah terdaftar untuk pesanan baru.',
    fallback: 'Alarm audio aktif',
    fallbackDescription: 'Push background belum aktif. Izinkan notifikasi agar pesanan tetap diberitahukan saat aplikasi tertutup.',
    error: 'Alarm audio belum aktif',
    errorDescription: 'Izinkan audio browser lalu tekan tombol ini kembali.',
  },
  courier: {
    trigger: 'Aktifkan Alarm Ojek',
    title: 'Aktifkan alarm tawaran',
    description: 'Aktifkan suara dan daftarkan notifikasi push agar tawaran tetap diberitahukan saat aplikasi tertutup.',
    notificationLabel: 'Notifikasi tawaran order',
    success: 'Alarm Ojek aktif',
    successDescription: 'Suara, vibrasi, dan push background sudah terdaftar untuk tawaran baru.',
    fallback: 'Alarm audio Ojek aktif',
    fallbackDescription: 'Push background belum aktif. Izinkan notifikasi agar tawaran tetap diberitahukan saat aplikasi tertutup.',
    error: 'Alarm audio Ojek belum aktif',
    errorDescription: 'Izinkan audio browser lalu tekan tombol ini kembali.',
  },
} as const;

export function AlarmActivationDialog({ audience }: AlarmActivationDialogProps) {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [activating, setActivating] = useState(false);
  const text = copy[audience];

  const activate = async () => {
    setActivating(true);
    if (audience === 'courier') vibrateCourierAlarm();
    // Request permission directly from the button gesture before any async work.
    const permissionRequest = requestPushPermission();
    try {
      const [audioActivated, notificationsAllowed] = await Promise.all([
        unlockOrderNotificationAudio({ playConfirmationTone: false }),
        permissionRequest,
      ]);
      if (!notificationsAllowed) {
        if (audioActivated) toast.warning(text.fallback, { description: text.fallbackDescription });
        else toast.error(text.error, { description: text.errorDescription });
        return;
      }
      if (!user) {
        toast.error('Sesi login tidak ditemukan. Masuk kembali untuk mendaftarkan push notification.');
        return;
      }
      const pushSubscribed = await subscribeToPush(user.id);
      if (audioActivated && pushSubscribed) {
        toast.success(text.success, { description: text.successDescription });
        setOpen(false);
      } else if (!pushSubscribed) {
        toast.error('Push background belum berhasil didaftarkan.', {
          description: getLastPushError() || (audioActivated ? text.fallbackDescription : text.errorDescription),
        });
      } else {
        toast.error(text.error, { description: text.errorDescription });
      }
    } catch (error) {
      toast.error('Aktivasi alarm atau notifikasi gagal.', {
        description: error instanceof Error ? error.message : text.errorDescription,
      });
    } finally {
      setActivating(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(nextOpen) => !activating && setOpen(nextOpen)}>
      <Button
        variant="outline"
        size="sm"
        className="min-h-9 gap-1.5 text-xs font-semibold"
        onClick={() => setOpen(true)}
        aria-label={text.trigger}
        title={text.trigger}
      >
        <Bell className="h-3.5 w-3.5" />
        <span>{text.trigger}</span>
      </Button>
      <DialogContent className="max-w-md rounded-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-left">
            <Bell className="h-5 w-5 text-primary" />
            {text.title}
          </DialogTitle>
          <DialogDescription className="text-left">{text.description}</DialogDescription>
        </DialogHeader>
        <div className="space-y-3 rounded-xl border bg-muted/30 p-4 text-sm">
          <div className="flex items-start gap-3">
            <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">1</span>
            <div>
              <p className="font-medium">Aktifkan suara alarm</p>
              <p className="text-muted-foreground">Suara akan berbunyi ketika tawaran atau pesanan baru masuk.</p>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">2</span>
            <div>
              <p className="font-medium">Izinkan {text.notificationLabel.toLowerCase()}</p>
              <p className="text-muted-foreground">Notifikasi membantu Anda melihat pesanan meskipun tab sedang tidak aktif.</p>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">3</span>
            <div>
              <p className="font-medium">Daftarkan push background</p>
              <p className="text-muted-foreground">Subscription push tersimpan agar pemberitahuan tetap dapat dikirim saat aplikasi tertutup.</p>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-900 dark:bg-amber-950/30 dark:text-amber-200">
          <Volume2 className="h-4 w-4 shrink-0" />
          <span>Pastikan volume perangkat dan izin notifikasi tidak dibisukan.</span>
        </div>
        <DialogFooter className="gap-2 sm:flex-row">
          <Button variant="outline" onClick={() => setOpen(false)} disabled={activating} className="sm:flex-1">Nanti</Button>
          <Button onClick={() => void activate()} disabled={activating} className="sm:flex-1">
            {activating ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Check className="mr-2 h-4 w-4" />}
            {activating ? 'Mengaktifkan...' : 'Aktifkan Sekarang'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
