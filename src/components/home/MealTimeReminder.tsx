import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Bell, BellRing, Clock3, Utensils, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { usePushNotification } from '@/hooks/usePushNotification';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { DEFAULT_MEAL_RECOMMENDATIONS, getMealPeriod, normalizeMealRecommendations, type MealRecommendations } from '@/lib/mealRecommendations';
import { toast } from 'sonner';

export { getMealPeriod } from '@/lib/mealRecommendations';
const greetings = { pagi: 'Selamat pagi', siang: 'Selamat siang', sore: 'Selamat sore', malam: 'Selamat malam' };

export function MealTimeReminder() {
  const [now, setNow] = useState(() => new Date());
  const [recommendations, setRecommendations] = useState<MealRecommendations>(DEFAULT_MEAL_RECOMMENDATIONS);
  const [isDismissed, setIsDismissed] = useState(false);
  const { user } = useAuth();
  const { isSupported, isSubscribed, loading, subscribe } = usePushNotification();

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    let mounted = true;
    void (async () => {
      try {
        const { data, error } = await supabase.from('app_settings').select('value').eq('key', 'meal_time_recommendations').maybeSingle();
        if (mounted && !error && data?.value) setRecommendations(normalizeMealRecommendations(data.value));
      } catch {
        // Keep built-in copy when settings are temporarily unavailable.
      }
    })();
    return () => { mounted = false; };
  }, []);

  const period = getMealPeriod(now.getHours());
  const copy = recommendations[period];

  const handleEnablePush = async () => {
    const success = await subscribe();
    if (success) toast.success('Pengingat SaDesa diaktifkan pada perangkat ini.');
    else toast.error('Notifikasi belum aktif. Periksa izin browser dan coba lagi.');
  };

  if (isDismissed) return null;

  return (
    <aside
      className="mx-4 flex items-start gap-3 rounded-2xl border border-emerald-100 bg-gradient-to-r from-emerald-50 to-amber-50 px-3 py-3 shadow-sm"
      aria-label={`Pengingat makan ${period}`}
      data-testid="meal-time-reminder"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white text-emerald-700 shadow-sm">
        <Utensils className="h-5 w-5" aria-hidden="true" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1 text-[11px] font-extrabold text-emerald-950">
          <Clock3 className="h-3 w-3" aria-hidden="true" />
          {greetings[period]}
        </div>
        <p className="mt-0.5 text-[12px] font-bold leading-snug text-slate-900">{copy.title}</p>
        <p className="mt-0.5 text-[10px] leading-snug text-slate-700">{copy.body}</p>
        <Link to="/products?type=makanan" className="mt-1.5 inline-flex items-center gap-1 text-[10px] font-bold text-emerald-900 underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700 focus-visible:ring-offset-1">
          Lihat rekomendasi <span aria-hidden="true">→</span>
        </Link>
        <p className="mt-1 text-[9px] leading-tight text-slate-600">Pengingat harian: 07.00, 12.00, 16.00, dan 19.00</p>
      </div>
      {user && isSupported && !isSubscribed && (
        <Button type="button" size="sm" variant="outline" className="h-auto shrink-0 gap-1 rounded-full border-emerald-200 bg-white px-2.5 py-1.5 text-[10px] text-emerald-900 shadow-sm" onClick={() => void handleEnablePush()} disabled={loading} aria-label="Aktifkan pengingat makan SaDesa">
          {loading ? <BellRing className="h-3.5 w-3.5 animate-pulse" aria-hidden="true" /> : <Bell className="h-3.5 w-3.5" aria-hidden="true" />}
          <span className="hidden sm:inline">Aktifkan pengingat</span>
          <span className="sm:hidden">Aktifkan</span>
        </Button>
      )}
      {user && isSupported && isSubscribed && (
        <span className="hidden shrink-0 items-center gap-1 rounded-full bg-white/80 px-2.5 py-1.5 text-[10px] font-semibold text-emerald-800 sm:inline-flex" aria-label="Pengingat makan aktif">
          <BellRing className="h-3.5 w-3.5" aria-hidden="true" /> Aktif
        </span>
      )}
      {!user && (
        <Button asChild type="button" size="sm" variant="outline" className="h-auto shrink-0 rounded-full border-emerald-200 bg-white px-2.5 py-1.5 text-[10px] text-emerald-800">
          <Link to="/auth">Masuk</Link>
        </Button>
      )}
      <button type="button" className="shrink-0 rounded-full p-1 text-slate-500 transition hover:bg-white/70 hover:text-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700" onClick={() => setIsDismissed(true)} aria-label="Tutup rekomendasi makanan">
        <X className="h-4 w-4" aria-hidden="true" />
      </button>
    </aside>
  );
}
