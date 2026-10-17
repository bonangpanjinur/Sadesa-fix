import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { AlarmClock, ArrowRight, Bell, BellRing, Clock3, Settings2, Sparkles, Utensils, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { usePushNotification } from '@/hooks/usePushNotification';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { DEFAULT_MEAL_RECOMMENDATIONS, getMealPeriod, MEAL_PERIODS, normalizeMealRecommendations, type MealPeriod, type MealRecommendations } from '@/lib/mealRecommendations';
import { toast } from 'sonner';

export { getMealPeriod } from '@/lib/mealRecommendations';
const greetings = { pagi: 'Selamat pagi', siang: 'Selamat siang', sore: 'Selamat sore', malam: 'Selamat malam' };
const DEFAULT_SCHEDULE: Record<MealPeriod, string> = { pagi: '07:00', siang: '12:00', sore: '16:00', malam: '19:00' };
const SCHEDULE_STORAGE_KEY = 'sadesa-meal-reminder-schedule';
const SNOOZE_STORAGE_KEY = 'sadesa-meal-reminder-snoozed-until';
const PREFERENCE_COLUMNS: Record<MealPeriod, string> = { pagi: 'pagi_time', siang: 'siang_time', sore: 'sore_time', malam: 'malam_time' };

function readSchedule(): Record<MealPeriod, string> {
  try {
    const saved = JSON.parse(localStorage.getItem(SCHEDULE_STORAGE_KEY) || '{}') as Partial<Record<MealPeriod, string>>;
    return MEAL_PERIODS.reduce((result, mealPeriod) => ({ ...result, [mealPeriod]: saved[mealPeriod] || DEFAULT_SCHEDULE[mealPeriod] }), {} as Record<MealPeriod, string>);
  } catch {
    return DEFAULT_SCHEDULE;
  }
}

export function MealTimeReminder() {
  const [now, setNow] = useState(() => new Date());
  const [recommendations, setRecommendations] = useState<MealRecommendations>(DEFAULT_MEAL_RECOMMENDATIONS);
  const [isDismissed, setIsDismissed] = useState(false);
  const [isScheduleOpen, setIsScheduleOpen] = useState(false);
  const [schedule, setSchedule] = useState<Record<MealPeriod, string>>(DEFAULT_SCHEDULE);
  const [snoozedUntil, setSnoozedUntil] = useState<number | null>(null);
  const { user } = useAuth();
  const { isSupported, isSubscribed, loading, subscribe } = usePushNotification();

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    let mounted = true;
    void (async () => {
      const localSchedule = readSchedule();
      const localSnooze = Number(localStorage.getItem(SNOOZE_STORAGE_KEY));
      if (mounted) {
        setSchedule(localSchedule);
        if (localSnooze > Date.now()) setSnoozedUntil(localSnooze);
      }
      if (!user) return;
      const { data, error } = await supabase
        .from('meal_reminder_preferences' as never)
        .select('pagi_time, siang_time, sore_time, malam_time, snoozed_until')
        .eq('user_id', user.id)
        .maybeSingle();
      if (!mounted || error || !data) return;
      const preferences = data as unknown as Record<string, unknown>;
      const accountSchedule = MEAL_PERIODS.reduce((result, mealPeriod) => ({
        ...result,
        [mealPeriod]: typeof preferences[PREFERENCE_COLUMNS[mealPeriod]] === 'string'
          ? String(preferences[PREFERENCE_COLUMNS[mealPeriod]]).slice(0, 5)
          : DEFAULT_SCHEDULE[mealPeriod],
      }), {} as Record<MealPeriod, string>);
      setSchedule(accountSchedule);
      const accountSnooze = typeof preferences.snoozed_until === 'string' ? Date.parse(preferences.snoozed_until) : NaN;
      if (Number.isFinite(accountSnooze) && accountSnooze > Date.now()) setSnoozedUntil(accountSnooze);
    })();
    return () => { mounted = false; };
  }, [user]);

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

  const handleSnooze = async () => {
    const until = Date.now() + 60 * 60 * 1000;
    if (user) {
      const { error } = await supabase.from('meal_reminder_preferences' as never).upsert({
        user_id: user.id,
        ...Object.fromEntries(MEAL_PERIODS.map((mealPeriod) => [PREFERENCE_COLUMNS[mealPeriod], schedule[mealPeriod]])),
        snoozed_until: new Date(until).toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });
      if (error) {
        toast.error('Snooze belum tersimpan. Coba lagi.');
        return;
      }
    } else {
      localStorage.setItem(SNOOZE_STORAGE_KEY, String(until));
    }
    setSnoozedUntil(until);
    toast.success(user ? 'Pengingat disnooze di akun selama 1 jam.' : 'Pengingat disnooze selama 1 jam.');
  };

  const handleScheduleChange = (mealPeriod: MealPeriod, value: string) => {
    setSchedule((current) => ({ ...current, [mealPeriod]: value }));
  };

  const handleSaveSchedule = async () => {
    if (user) {
      const { error } = await supabase.from('meal_reminder_preferences' as never).upsert({
        user_id: user.id,
        ...Object.fromEntries(MEAL_PERIODS.map((mealPeriod) => [PREFERENCE_COLUMNS[mealPeriod], schedule[mealPeriod]])),
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });
      if (error) {
        toast.error('Jadwal belum tersimpan. Coba lagi.');
        return;
      }
    } else {
      localStorage.setItem(SCHEDULE_STORAGE_KEY, JSON.stringify(schedule));
    }
    setIsScheduleOpen(false);
    toast.success(user ? 'Jadwal pengingat tersinkron ke akun.' : 'Jadwal pengingat disimpan di perangkat ini.');
  };

  if (isDismissed || (snoozedUntil !== null && snoozedUntil > now.getTime())) return null;

  return (
    <aside
      className="relative mx-3 flex items-start gap-2.5 overflow-hidden rounded-2xl border border-emerald-200/80 bg-gradient-to-br from-emerald-50 via-white to-amber-50 px-2.5 py-3 shadow-[0_8px_24px_-14px_rgba(6,95,70,0.45)] sm:mx-4 sm:gap-3 sm:px-3 sm:py-3.5"
      aria-label={`Pengingat makan ${period}`}
      data-testid="meal-time-reminder"
    >
      <div className="pointer-events-none absolute -right-8 -top-10 h-28 w-28 rounded-full bg-amber-200/30 blur-2xl" aria-hidden="true" />
      <div className="pointer-events-none absolute -bottom-12 left-1/3 h-24 w-24 rounded-full bg-emerald-200/25 blur-2xl" aria-hidden="true" />
      <div className="relative flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-emerald-700 to-emerald-500 text-white shadow-[0_6px_14px_-6px_rgba(4,120,87,0.9)] sm:h-11 sm:w-11 sm:rounded-2xl">
        <Utensils className="h-4 w-4 sm:h-5 sm:w-5" strokeWidth={2.25} aria-hidden="true" />
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
        <p className="mt-1 text-[12px] font-extrabold leading-snug tracking-[-0.01em] text-slate-950 sm:text-[13px]">{copy.title}</p>
        <p className="mt-0.5 max-w-2xl truncate text-[9px] leading-snug text-slate-700 sm:text-[10px]">{copy.body}</p>
        <div className="mt-1.5 flex flex-wrap items-center gap-1 sm:mt-2 sm:gap-1.5">
          <Link to="/products?type=makanan" className="inline-flex items-center gap-1 rounded-full bg-emerald-800 px-2.5 py-1.5 text-[9px] font-bold text-white shadow-sm transition hover:bg-emerald-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700 focus-visible:ring-offset-2 sm:gap-1.5 sm:px-3 sm:text-[10px]">
            Lihat rekomendasi <ArrowRight className="h-3 w-3" aria-hidden="true" />
          </Link>
          <button type="button" onClick={() => void handleSnooze()} className="inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-white/80 px-2 py-1.5 text-[9px] font-semibold text-emerald-900 transition hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700 focus-visible:ring-offset-1 sm:px-2.5 sm:text-[10px]" aria-label="Snooze pengingat selama satu jam">
            <AlarmClock className="h-3 w-3" aria-hidden="true" /><span className="hidden sm:inline">Snooze 1 jam</span><span className="sm:hidden">Snooze</span>
          </button>
          <button type="button" onClick={() => setIsScheduleOpen((open) => !open)} className={`inline-flex items-center gap-1 rounded-full px-2 py-1.5 text-[9px] font-semibold text-emerald-800 transition-all duration-200 active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700 focus-visible:ring-offset-1 sm:text-[10px] ${isScheduleOpen ? 'bg-white shadow-sm ring-1 ring-emerald-200' : 'hover:bg-white/70'}`} aria-expanded={isScheduleOpen} aria-controls="meal-reminder-schedule">
            <Settings2 className={`h-3 w-3 transition-transform duration-300 ease-out ${isScheduleOpen ? 'rotate-90' : 'rotate-0'}`} aria-hidden="true" /><span className="hidden sm:inline">Ubah jadwal</span><span className="sm:hidden">Jadwal</span>
          </button>
        </div>
        <p className="mt-1.5 hidden text-[9px] leading-tight text-slate-600 sm:block">Pengingat harian · {MEAL_PERIODS.map((mealPeriod) => schedule[mealPeriod].replace(':', '.')).join(' · ')}</p>
        <div id="meal-reminder-schedule" aria-hidden={!isScheduleOpen} className={`grid transition-[grid-template-rows] duration-300 ease-out ${isScheduleOpen ? 'mt-2 grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
          <div className="min-h-0 overflow-hidden">
            <div className={`rounded-xl border border-emerald-100 bg-white/75 p-2.5 shadow-sm transition-all duration-300 ease-out ${isScheduleOpen ? 'translate-y-0 opacity-100' : '-translate-y-2 opacity-0'}`}>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {MEAL_PERIODS.map((mealPeriod) => (
                  <label key={mealPeriod} className="flex flex-col gap-1 text-[9px] font-semibold capitalize text-slate-700">
                    {mealPeriod}
                    <input tabIndex={isScheduleOpen ? 0 : -1} type="time" value={schedule[mealPeriod]} onChange={(event) => handleScheduleChange(mealPeriod, event.target.value)} className="h-8 rounded-lg border border-emerald-100 bg-white px-2 text-[11px] font-bold text-slate-900 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100" />
                  </label>
                ))}
              </div>
              <div className="mt-2 flex justify-end gap-1.5">
                <button type="button" tabIndex={isScheduleOpen ? 0 : -1} onClick={() => setIsScheduleOpen(false)} className="rounded-full px-2.5 py-1.5 text-[10px] font-semibold text-slate-600 transition-colors hover:bg-slate-100">Batal</button>
                <button type="button" tabIndex={isScheduleOpen ? 0 : -1} onClick={() => void handleSaveSchedule()} className="rounded-full bg-emerald-800 px-3 py-1.5 text-[10px] font-bold text-white transition-colors hover:bg-emerald-900">Simpan jadwal</button>
              </div>
            </div>
          </div>
        </div>
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
