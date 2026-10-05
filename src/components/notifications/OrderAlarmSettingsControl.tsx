import { useState } from 'react';
import { Settings2, Volume2, RotateCcw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import {
  fetchOrderNotificationSoundSettings,
  getAudienceProfile,
  getOrderSoundLocalOverride,
  previewOrderNotificationSound,
  resolveOrderSoundProfile,
  saveOrderSoundLocalOverride,
  clearOrderSoundLocalOverride,
  ORDER_SOUND_PRESET_LABELS,
  type OrderNotificationSoundSettings,
  type OrderSoundAudience,
  type OrderSoundProfile,
} from '@/lib/orderNotificationSound';
import { toast } from 'sonner';

interface OrderAlarmSettingsControlProps {
  audience: OrderSoundAudience;
}

function profileLabel(audience: OrderSoundAudience) {
  return audience === 'merchant' ? 'Merchant' : 'Ojek';
}

function applyProfile(settings: OrderNotificationSoundSettings, audience: OrderSoundAudience, profile: OrderSoundProfile) {
  return audience === 'merchant'
    ? { ...settings, merchant_enabled: profile.enabled, merchant_preset: profile.preset, merchant_custom_audio_url: profile.custom_audio_url, merchant_volume: profile.volume }
    : { ...settings, courier_enabled: profile.enabled, courier_preset: profile.preset, courier_custom_audio_url: profile.custom_audio_url, courier_volume: profile.volume };
}

export function OrderAlarmSettingsControl({ audience }: OrderAlarmSettingsControlProps) {
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [hasOverride, setHasOverride] = useState(false);
  const [globalSettings, setGlobalSettings] = useState<OrderNotificationSoundSettings | null>(null);
  const [profile, setProfile] = useState<OrderSoundProfile | null>(null);
  const label = profileLabel(audience);

  const loadSettings = async () => {
    setLoading(true);
    try {
      const global = await fetchOrderNotificationSoundSettings(true);
      const override = getOrderSoundLocalOverride(audience);
      setGlobalSettings(global);
      setHasOverride(Boolean(override));
      setProfile(resolveOrderSoundProfile(global, audience, override));
    } finally {
      setLoading(false);
    }
  };

  const handleOpenChange = (nextOpen: boolean) => {
    setOpen(nextOpen);
    if (nextOpen) void loadSettings();
  };

  const handleSave = () => {
    if (!profile) return;
    setSaving(true);
    try {
      saveOrderSoundLocalOverride(audience, profile);
      setHasOverride(true);
      toast.success(`Pengaturan alarm ${label} disimpan di perangkat ini`);
      setOpen(false);
    } finally {
      setSaving(false);
    }
  };

  const handleReset = async () => {
    clearOrderSoundLocalOverride(audience);
    setHasOverride(false);
    const global = await fetchOrderNotificationSoundSettings(true);
    setGlobalSettings(global);
    setProfile(getAudienceProfile(global, audience));
    toast.success(`Alarm ${label} kembali mengikuti pengaturan global`);
  };

  const handlePreview = () => {
    if (!profile || !globalSettings) return;
    void previewOrderNotificationSound(applyProfile(globalSettings, audience, profile), audience);
  };

  return (
    <>
      <Button variant="outline" size="sm" className="min-h-9 gap-1.5 text-xs" onClick={() => handleOpenChange(true)} aria-label={`Pengaturan alarm ${label}`}>
        <Settings2 className="h-3.5 w-3.5" />
        <span className="hidden sm:inline">Alarm {label}</span>
      </Button>
      <Dialog open={open} onOpenChange={handleOpenChange}>
        <DialogContent className="flex max-h-[calc(100dvh-1rem)] w-[calc(100vw-1rem)] max-w-md flex-col gap-0 overflow-hidden p-0 sm:max-h-[calc(100dvh-2rem)] sm:w-full">
          <DialogHeader className="shrink-0 px-4 pb-3 pt-5 pr-12 text-left sm:px-6 sm:pb-4 sm:pt-6 sm:pr-12">
            <DialogTitle>Pengaturan Alarm {label}</DialogTitle>
            <DialogDescription>
              Pengaturan awal mengikuti default global admin. Perubahan di sini hanya berlaku pada perangkat {label.toLowerCase()} ini.
            </DialogDescription>
          </DialogHeader>
          <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-4 sm:px-6">
            {loading || !profile ? (
              <div className="py-8 text-center text-sm text-muted-foreground">Memuat pengaturan alarm...</div>
            ) : (
              <div className="space-y-5">
                <div className="rounded-md border bg-muted/30 p-3 text-sm" role="status">
                  <p className="font-medium">Alarm {label} wajib aktif.</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    Alarm {label.toLowerCase()} tidak dapat dimatikan. Nada dering dan volume dapat diatur terpisah untuk perangkat ini.
                  </p>
                </div>
                <div>
                  <label htmlFor={`${audience}-local-preset`} className="text-sm font-medium">Jenis suara alarm</label>
                  <select id={`${audience}-local-preset`} value={profile.preset} onChange={(event) => setProfile({ ...profile, preset: event.target.value as OrderSoundProfile['preset'] })} className="mt-1 h-10 w-full rounded-md border border-input bg-background px-3 text-sm">
                    {Object.entries(ORDER_SOUND_PRESET_LABELS).map(([value, optionLabel]) => <option key={value} value={value}>{optionLabel}</option>)}
                  </select>
                </div>
                <div>
                  <label htmlFor={`${audience}-local-volume`} className="text-sm font-medium">Volume alarm: {Math.round(profile.volume * 100)}%</label>
                  <input id={`${audience}-local-volume`} type="range" min="0.1" max="1" step="0.05" value={profile.volume} onChange={(event) => setProfile({ ...profile, volume: Number(event.target.value) })} className="mt-3 w-full accent-primary" />
                </div>
                {profile.custom_audio_url && <p className="truncate text-xs text-muted-foreground">Audio custom global: {profile.custom_audio_url}</p>}
                <p className="text-xs text-muted-foreground">{hasOverride ? 'Override lokal aktif. Perubahan global admin tidak mengganti pengaturan perangkat ini.' : 'Belum ada override lokal. Nilai ini masih mengikuti pengaturan global admin.'}</p>
                {audience === 'merchant' && (
                  <p className="text-xs text-muted-foreground">
                    Saat aplikasi ditutup, suara mengikuti notifikasi sistem perangkat. Nada pilihan di sini berlaku saat aplikasi masih berjalan.
                  </p>
                )}
              </div>
            )}
          </div>
          <DialogFooter className="shrink-0 gap-2 border-t px-4 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-6 sm:py-4">
            <Button className="w-full sm:w-auto" variant="ghost" onClick={() => void handleReset()} disabled={loading || !hasOverride}>
              <RotateCcw className="mr-2 h-4 w-4" /> Ikuti Global
            </Button>
            <div className="flex w-full gap-2 sm:w-auto">
              <Button className="min-w-0 flex-1 whitespace-nowrap sm:flex-none" variant="outline" onClick={handlePreview} disabled={loading || !profile || !globalSettings}>
                <Volume2 className="mr-2 h-4 w-4" /> Uji Suara
              </Button>
              <Button className="min-w-0 flex-1 whitespace-nowrap sm:flex-none" onClick={handleSave} disabled={loading || saving || !profile}>{saving ? 'Menyimpan...' : 'Simpan'}</Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
