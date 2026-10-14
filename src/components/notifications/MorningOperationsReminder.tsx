import { useEffect, useState } from 'react';
import { BellRing, X } from 'lucide-react';

type Audience = 'merchant' | 'courier';

interface MorningOperationsReminderProps {
  audience: Audience;
  userId?: string;
}

const reminderCopy: Record<Audience, { title: string; description: string; backgroundPush: string }> = {
  merchant: {
    title: 'Jangan tutup dashboard selama toko beroperasi',
    description: 'Biarkan SaDesa tetap terbuka saat menerima pesanan supaya pembaruan realtime dan alarm di halaman tetap aktif.',
    backgroundPush: 'Web Push mungkin tetap masuk jika PWA ditutup, tetapi izin browser/OS dan konfigurasi push harus aktif. Audio halaman tidak berjalan setelah aplikasi ditutup.',
  },
  courier: {
    title: 'Tetap buka dashboard saat Anda online',
    description: 'Jangan tutup aplikasi atau keluar dari akun selama siap menerima tugas. Halaman terbuka membantu tawaran realtime dan pembaruan lokasi.',
    backgroundPush: 'PWA tidak menjamin lokasi terus terkirim jika ditutup atau disuspensi. Web Push dapat memberi notifikasi saat aplikasi tertutup hanya jika izin dan pengaturan perangkat aktif.',
  },
};

function getLocalDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function MorningOperationsReminder({ audience, userId }: MorningOperationsReminderProps) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    setVisible(false);
    if (!userId) return;

    const now = new Date();
    const hour = now.getHours();
    if (hour < 5 || hour >= 12) return;

    const storageKey = `sadesa:morning-operations-reminder:${audience}:${userId}:${getLocalDateKey(now)}`;
    try {
      if (window.localStorage.getItem(storageKey)) return;
      // Mark it as shown before displaying so remounts do not repeat it today.
      window.localStorage.setItem(storageKey, 'shown');
    } catch {
      // Storage may be unavailable in private browsing; still show the reminder this visit.
    }
    setVisible(true);
  }, [audience, userId]);

  if (!visible) return null;

  const copy = reminderCopy[audience];
  return (
    <aside
      role="status"
      aria-live="polite"
      data-testid={`morning-operations-reminder-${audience}`}
      className="relative rounded-xl border border-amber-300/70 bg-amber-50 p-4 pr-12 text-amber-950 shadow-sm dark:border-amber-800 dark:bg-amber-950/30 dark:text-amber-100"
    >
      <BellRing className="absolute left-4 top-4 h-5 w-5 text-amber-700 dark:text-amber-300" aria-hidden="true" />
      <button
        type="button"
        onClick={() => setVisible(false)}
        className="absolute right-2 top-2 inline-flex h-8 w-8 items-center justify-center rounded-md text-amber-900/70 hover:bg-amber-900/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-700 dark:text-amber-100"
        aria-label="Tutup pengingat operasional pagi"
      >
        <X className="h-4 w-4" aria-hidden="true" />
      </button>
      <div className="pl-8">
        <h2 className="text-sm font-semibold">{copy.title}</h2>
        <p className="mt-1 text-sm leading-5">{copy.description}</p>
        <p className="mt-2 text-xs leading-5 text-amber-900/80 dark:text-amber-100/80">{copy.backgroundPush}</p>
      </div>
    </aside>
  );
}
