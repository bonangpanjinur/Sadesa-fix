import { useCallback, useEffect, useState } from 'react';
import { Bell, Check, Clock3, Loader2, RotateCcw, Save, Utensils } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import type { Json } from '@/integrations/supabase/types';
import { DEFAULT_MEAL_RECOMMENDATIONS, MEAL_PERIODS, MEAL_PERIOD_LABELS, normalizeMealRecommendations, type MealPeriod, type MealRecommendations } from '@/lib/mealRecommendations';
import { toast } from 'sonner';

const SETTINGS_KEY = 'meal_time_recommendations';

export default function AdminMealRecommendationsPage() {
  const { user } = useAuth();
  const [recommendations, setRecommendations] = useState<MealRecommendations>(DEFAULT_MEAL_RECOMMENDATIONS);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [lastSaved, setLastSaved] = useState(false);

  const loadSettings = useCallback(async () => {
    setLoading(true);
    setLoadError(null);
    try {
      const { data, error } = await supabase.from('app_settings').select('value').eq('key', SETTINGS_KEY).maybeSingle();
      if (error) throw error;
      setRecommendations(normalizeMealRecommendations(data?.value));
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : 'Pengaturan belum dapat dimuat.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void loadSettings(); }, [loadSettings]);

  const update = (period: MealPeriod, field: 'title' | 'body' | 'suggestion' | 'enabled', value: string | boolean) => {
    setLastSaved(false);
    setRecommendations((current) => ({
      ...current,
      [period]: { ...current[period], [field]: value },
    }));
  };

  const saveSettings = async () => {
    if (!user) {
      toast.error('Sesi admin tidak ditemukan. Silakan masuk kembali.');
      return;
    }
    const invalid = MEAL_PERIODS.find((period) =>
      !recommendations[period].title.trim() || !recommendations[period].body.trim() || !recommendations[period].suggestion.trim());
    if (invalid) {
      toast.error(`Judul, pesan push, dan saran ${invalid} wajib diisi.`);
      return;
    }

    setSaving(true);
    setLastSaved(false);
    try {
      const normalized = normalizeMealRecommendations(recommendations);
      const { error } = await supabase.from('app_settings').upsert({
        key: SETTINGS_KEY,
        value: normalized as unknown as Json,
        category: 'notification',
        description: 'Template pesan push dan saran makanan untuk tiap waktu makan',
        updated_by: user.id,
      }, { onConflict: 'key' });
      if (error) throw error;
      setRecommendations(normalized);
      setLastSaved(true);
      toast.success('Template rekomendasi makanan berhasil disimpan.');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Gagal menyimpan template rekomendasi.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <AdminLayout title="Rekomendasi Makanan" subtitle="Atur pesan push dan saran makanan untuk setiap waktu makan">
      <div className="mx-auto max-w-5xl space-y-6">
        <Alert>
          <Clock3 className="h-4 w-4" />
          <AlertDescription>
            Push dijadwalkan pukul <strong>07.00, 12.00, 16.00, dan 19.00</strong> menurut zona waktu perangkat pelanggan. Anda dapat mengubah pesan per periode dan menonaktifkan periode tertentu; perubahan diterapkan setelah migration template tersedia di database.
          </AlertDescription>
        </Alert>

        {loadError && <Alert variant="destructive"><AlertDescription>Pengaturan belum dapat dimuat: {loadError}. Form memakai nilai default; jangan simpan sebelum masalah akses database diperbaiki.</AlertDescription></Alert>}
        {lastSaved && <Alert><Check className="h-4 w-4" /><AlertDescription>Template berhasil disimpan dan akan digunakan oleh halaman beranda serta scheduler push.</AlertDescription></Alert>}

        {loading ? (
          <div role="status" className="flex items-center justify-center gap-2 py-16 text-muted-foreground"><Loader2 className="h-5 w-5 animate-spin" />Memuat template…</div>
        ) : (
          <div className="space-y-4">
            {MEAL_PERIODS.map((period) => (
              <MealPeriodCard
                key={period}
                period={period}
                enabled={recommendations[period].enabled}
                title={recommendations[period].title}
                body={recommendations[period].body}
                suggestion={recommendations[period].suggestion}
                onChange={update}
              />
            ))}
            <div className="flex flex-col-reverse justify-between gap-3 sm:flex-row">
              <Button type="button" variant="outline" onClick={() => { setRecommendations(DEFAULT_MEAL_RECOMMENDATIONS); setLastSaved(false); }} disabled={saving}>
                <RotateCcw className="mr-2 h-4 w-4" />Pulihkan default
              </Button>
              <Button type="button" onClick={() => void saveSettings()} disabled={saving || Boolean(loadError)}>
                {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
                Simpan semua template
              </Button>
            </div>
          </div>
        )}
      </div>
    </AdminLayout>
  );
}

function MealPeriodCard({
  period, enabled, title, body, suggestion, onChange,
}: {
  period: MealPeriod;
  enabled: boolean;
  title: string;
  body: string;
  suggestion: string;
  onChange: (period: MealPeriod, field: 'title' | 'body' | 'suggestion' | 'enabled', value: string | boolean) => void;
}) {
  const id = `meal-${period}`;
  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0">
        <div>
          <CardTitle className="flex items-center gap-2 text-lg"><Utensils className="h-5 w-5 text-primary" />{MEAL_PERIOD_LABELS[period]}</CardTitle>
          <CardDescription className="mt-1">Template khusus pengingat {period}.</CardDescription>
        </div>
        <label htmlFor={`${id}-enabled`} className="flex cursor-pointer items-center gap-2 rounded-full border px-3 py-2 text-sm">
          <input id={`${id}-enabled`} type="checkbox" checked={enabled} onChange={(event) => onChange(period, 'enabled', event.target.checked)} className="h-4 w-4 accent-primary" />
          <Bell className="h-4 w-4" />Push aktif
        </label>
      </CardHeader>
      <CardContent className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2 md:col-span-2">
          <Label htmlFor={`${id}-title`}>Judul push <span className="font-normal text-muted-foreground">({title.length}/80)</span></Label>
          <Input id={`${id}-title`} value={title} maxLength={80} onChange={(event) => onChange(period, 'title', event.target.value)} />
        </div>
        <div className="space-y-2">
          <Label htmlFor={`${id}-body`}>Pesan push <span className="font-normal text-muted-foreground">({body.length}/180)</span></Label>
          <Textarea id={`${id}-body`} value={body} maxLength={180} rows={3} onChange={(event) => onChange(period, 'body', event.target.value)} />
        </div>
        <div className="space-y-2">
          <Label htmlFor={`${id}-suggestion`}>Saran di banner beranda <span className="font-normal text-muted-foreground">({suggestion.length}/240)</span></Label>
          <Textarea id={`${id}-suggestion`} value={suggestion} maxLength={240} rows={3} onChange={(event) => onChange(period, 'suggestion', event.target.value)} />
        </div>
      </CardContent>
    </Card>
  );
}
