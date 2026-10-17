import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, Bell, BellRing, Clock3, Sparkles, Utensils, X } from 'lucide-react';
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
      className="relative mx-4 flex items-start gap-3 overflow-hidden rounded-2xl border border-emerald-200/80 bg-gradient-to-br from-emerald-50 via-white to-amber-50 px-3 py-3.5 shadow-[0_8px_24px_-14px_rgba(6,95,70,0.45)]"
      aria-label={`Pengingat makan ${period}`}
      data-testid="meal-time-reminder"
    >
      <div className="pointer-events-none absolute -right-8 -top-10 h-28 w-28 rounded-full bg-amber-200/30 blur-2xl" aria-hidden="true" />
      <div className="pointer-events-none absolute -bottom-12 left-1/3 h-24 w-24 rounded-full bg-emerald-200/25 blur-2xl" aria-hidden="true" />
      <div className="relative flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-700 to-emerald-500 text-white shadow-[0_6px_14px_-6px_rgba(4,120,87,0.9)]">
        <Utensils className="h-5 w-5" strokeWidth={2.25} aria-hidden="true" />
        <Sparkles className="absolute -right-1 -top-1 h-3.5 w-3.5 fill-amber-300 text-amber-300" aria-hidden="true" />
      </div>
      <div className="relative min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-1.5 text-[10px] font-bold uppercase tracking-[0.08em] text-emerald-800">
          <span className="inline-flex items-center gap-1 rounded-full bg-white/80 px-2 py-0.5 shadow-sm">
            <Clock3 className="h-3 w-3" aria-hidden="true" />
            {greetings[period]}
          </span>
          <span className="text-emerald-700/60">•</span>
          <span>{period}</span>
        </div>
        <p className="mt-1 text-[13px] font-extrabold leading-snug tracking-[-0.01em] text-slate-950">{copy.title}</p>
        <p className="mt-0.5 max-w-2xl text-[10px] leading-snug text-slate-700">{copy.body}</p>
        <Link to="/products?type=makanan" className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-emerald-800 px-3 py-1.5 text-[10px] font-bold text-white shadow-sm transition hover:bg-emerald-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700 focus-visible:ring-offset-2">
          Lihat rekomendasi <ArrowRight className="h-3 w-3" aria-hidden="true" />
        </Link>
        <p className="mt-1.5 text-[9px] leading-tight text-slate-600">Pengingat harian · 07.00 · 12.00 · 16.00 · 19.00</p>
      </div>
      {user && isSupported && !isSubscribed && (
        <Button type="button" size="sm" variant="outline" className="relative h-auto shrink-0 gap-1 rounded-full border-emerald-200 bg-white/90 px-2.5 py-1.5 text-[10px] font-bold text-emerald-900 shadow-sm" onClick={() => void handleEnablePush()} disabled={loading} aria-label="Aktifkan pengingat makan SaDesa">
          {loading ? <BellRing className="h-3.5 w-3.5 animate-pulse" aria-hidden="true" /> : <Bell className="h-3.5 w-3.5" aria-hidden="true" />}
          <span className="hidden sm:inline">Aktifkan pengingat</span>
          <span className="sm:hidden">Aktifkan</span>
        </Button>
      )}
      {user && isSupported && isSubscribed && (
        <span className="relative hidden shrink-0 items-center gap-1 rounded-full border border-emerald-100 bg-white/85 px-2.5 py-1.5 text-[10px] font-bold text-emerald-800 shadow-sm sm:inline-flex" aria-label="Pengingat makan aktif">
          <BellRing className="h-3.5 w-3.5" aria-hidden="true" /> Aktif
        </span>
      )}
      {!user && (
        <Button asChild type="button" size="sm" variant="outline" className="h-auto shrink-0 rounded-full border-emerald-200 bg-white px-2.5 py-1.5 text-[10px] text-emerald-800">
          <Link to="/auth">Masuk</Link>
        </Button>
      )}
      <button type="button" className="relative shrink-0 rounded-full p-1 text-slate-500 transition hover:bg-white/80 hover:text-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700" onClick={() => setIsDismissed(true)} aria-label="Tutup rekomendasi makanan">
        <X className="h-4 w-4" aria-hidden="true" />
      </button>
    </aside>
  );
}
