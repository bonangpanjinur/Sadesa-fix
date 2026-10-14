/**
 * P2-05: Admin Push Notification Settings
 * Inspect server-side VAPID readiness, test push, and broadcast to subscribers.
 */
import { useState, useEffect, useCallback } from 'react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import {
  Bell, Save, Send, TestTube, AlertCircle, Volume2, Upload,
  Loader2, Key, Users, RefreshCw, History,
} from 'lucide-react';
import { supabase, SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { buildAdminPushTestPayload } from '@/lib/adminPushTest';
import {
  DEFAULT_ORDER_SOUND_SETTINGS,
  normalizeOrderNotificationSoundSettings,
  ORDER_SOUND_PRESET_LABELS,
  ORDER_SOUND_SETTINGS_KEY,
  previewOrderNotificationSound,
  clearOrderNotificationSoundSettingsCache,
  type OrderNotificationSoundSettings,
} from '@/lib/orderNotificationSound';


interface VapidRuntimeStatus {
  publicKeyConfigured: boolean;
  privateKeyConfigured: boolean;
  vapidConfigured: boolean;
  missingVariables: string[];
}

interface PushDeliveryLog {
  id: string;
  created_at: string;
  source: 'admin_test' | 'admin_broadcast' | 'queue';
  recipient_user_id: string | null;
  title: string;
  status: 'sent' | 'failed' | 'expired';
  provider_status_code: number | null;
  error_message: string | null;
}

export default function AdminPushNotificationPage() {
  const { user } = useAuth();
  const [vapidStatus, setVapidStatus] = useState<VapidRuntimeStatus | null>(null);
  const [vapidStatusLoading, setVapidStatusLoading] = useState(true);
  const [vapidStatusError, setVapidStatusError] = useState<string | null>(null);
  const [soundSettings, setSoundSettings] = useState<OrderNotificationSoundSettings>(DEFAULT_ORDER_SOUND_SETTINGS);
  const [soundSaving, setSoundSaving] = useState(false);
  const [soundUploading, setSoundUploading] = useState<'merchant' | 'courier' | null>(null);

  // Test push state
  const [testUserId, setTestUserId] = useState('');
  const [testTitle, setTestTitle] = useState('Test Push Notification');
  const [testBody, setTestBody] = useState('Halo! Ini adalah test push notification dari SaDesa.');
  const [testing, setTesting] = useState(false);
  const [selfTesting, setSelfTesting] = useState(false);

  // Broadcast state
  const [broadcastTitle, setBroadcastTitle] = useState('');
  const [broadcastBody, setBroadcastBody] = useState('');
  const [broadcastUrl, setBroadcastUrl] = useState('/');
  const [broadcasting, setBroadcasting] = useState(false);

  // Subscriber count
  const [subscriberCount, setSubscriberCount] = useState<number | null>(null);
  const [pushDeliveryLogs, setPushDeliveryLogs] = useState<PushDeliveryLog[]>([]);
  const [pushDeliveryLogsLoading, setPushDeliveryLogsLoading] = useState(true);
  const [pushDeliveryLogsError, setPushDeliveryLogsError] = useState<string | null>(null);
  const [pushDeliveryRealtimeStatus, setPushDeliveryRealtimeStatus] = useState<'connecting' | 'connected' | 'disconnected'>('connecting');

  const refreshVapidStatus = useCallback(async () => {
    setVapidStatusLoading(true);
    setVapidStatusError(null);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.access_token) throw new Error('Sesi admin tidak ditemukan.');

      const response = await fetch(`${SUPABASE_URL}/functions/v1/push-subscription`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: SUPABASE_PUBLISHABLE_KEY,
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ action: 'get_vapid_config' }),
      });
      const payload = await response.json().catch(() => null) as Partial<VapidRuntimeStatus> | null;
      if (!response.ok) throw new Error(`Pemeriksaan server gagal (${response.status}).`);
      if (
        !payload
        || typeof payload.vapidConfigured !== 'boolean'
        || typeof payload.publicKeyConfigured !== 'boolean'
        || typeof payload.privateKeyConfigured !== 'boolean'
        || !Array.isArray(payload.missingVariables)
      ) {
        throw new Error('Edge Function push-subscription belum menyediakan status konfigurasi terbaru.');
      }

      setVapidStatus(payload as VapidRuntimeStatus);
    } catch (error) {
      setVapidStatus(null);
      setVapidStatusError(error instanceof Error ? error.message : 'Status server belum dapat diperiksa.');
    } finally {
      setVapidStatusLoading(false);
    }
  }, []);

  const fetchSoundSettings = useCallback(async () => {
    const { data } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', ORDER_SOUND_SETTINGS_KEY)
      .maybeSingle();
    setSoundSettings(normalizeOrderNotificationSoundSettings(data?.value));
  }, []);

  const fetchSubscriberCount = useCallback(async () => {
    try {
      const { count } = await supabase
        .from('push_subscriptions')
        .select('*', { count: 'exact', head: true });
      setSubscriberCount(count ?? 0);
    } catch {
      setSubscriberCount(null);
    }
  }, []);

  const fetchPushDeliveryLogs = useCallback(async () => {
    setPushDeliveryLogsLoading(true);
    setPushDeliveryLogsError(null);
    try {
      const { data, error } = await supabase
        .from('push_delivery_logs')
        .select('id, created_at, source, recipient_user_id, title, status, provider_status_code, error_message')
        .order('created_at', { ascending: false })
        .limit(100);
      if (error) throw error;
      const rows = (data ?? []) as PushDeliveryLog[];
      setPushDeliveryLogs((current) => {
        const merged = new Map(current.map((row) => [row.id, row]));
        rows.forEach((row) => merged.set(row.id, row));
        return [...merged.values()]
          .sort((left, right) => Date.parse(right.created_at) - Date.parse(left.created_at))
          .slice(0, 100);
      });
    } catch (error) {
      setPushDeliveryLogsError(error instanceof Error ? error.message : 'Riwayat push belum dapat dimuat.');
    } finally {
      setPushDeliveryLogsLoading(false);
    }
  }, []);

  useEffect(() => {
    void refreshVapidStatus();
    void fetchSubscriberCount();
    void fetchSoundSettings();
    void fetchPushDeliveryLogs();
  }, [fetchPushDeliveryLogs, fetchSubscriberCount, fetchSoundSettings, refreshVapidStatus]);

  useEffect(() => {
    const channel = supabase
      .channel('admin-push-delivery-logs')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'push_delivery_logs',
      }, (payload) => {
        const incoming = payload.new as PushDeliveryLog;
        setPushDeliveryLogs((current) => [incoming, ...current.filter((row) => row.id !== incoming.id)]
          .sort((left, right) => Date.parse(right.created_at) - Date.parse(left.created_at))
          .slice(0, 100));
      })
      .subscribe((status) => {
        const connected = status === 'SUBSCRIBED';
        const disconnected = status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED';
        setPushDeliveryRealtimeStatus(connected ? 'connected' : disconnected ? 'disconnected' : 'connecting');
        if (connected) void fetchPushDeliveryLogs();
      });

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [fetchPushDeliveryLogs]);

  const handleSaveSoundSettings = async () => {
    setSoundSaving(true);
    try {
      const normalized = normalizeOrderNotificationSoundSettings(soundSettings);
      const { error } = await supabase.from('app_settings').upsert({
        key: ORDER_SOUND_SETTINGS_KEY,
        value: normalized,
        category: 'notification',
        description: 'Pengaturan suara alarm pesanan masuk untuk merchant dan kurir',
      }, { onConflict: 'key' });
      if (error) throw error;
      setSoundSettings(normalized);
      clearOrderNotificationSoundSettingsCache();
      toast.success('Pengaturan suara pesanan berhasil disimpan');
    } catch {
      toast.error('Gagal menyimpan pengaturan suara pesanan');
    } finally {
      setSoundSaving(false);
    }
  };

  const handleSoundUpload = async (file: File, audience: 'merchant' | 'courier') => {
    const allowedTypes = ['audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/mp4'];
    if (!allowedTypes.includes(file.type)) {
      toast.error('Format audio harus MP3, WAV, OGG, atau M4A');
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      toast.error('Ukuran audio maksimal 5 MB');
      return;
    }
    setSoundUploading(audience);
    try {
      const extension = file.name.split('.').pop()?.toLowerCase() || 'mp3';
      const path = `order-alarm-${audience}-${Date.now()}.${extension}`;
      const { error } = await supabase.storage.from('notification-sounds').upload(path, file, {
        upsert: true,
        contentType: file.type,
        cacheControl: '3600',
      });
      if (error) throw error;
      const { data } = supabase.storage.from('notification-sounds').getPublicUrl(path);
      setSoundSettings((current) => audience === 'merchant'
        ? { ...current, merchant_preset: 'custom', merchant_custom_audio_url: data.publicUrl }
        : { ...current, courier_preset: 'custom', courier_custom_audio_url: data.publicUrl });
      toast.success(`Audio custom ${audience === 'merchant' ? 'merchant' : 'ojek'} berhasil diunggah. Klik simpan untuk mengaktifkannya.`);
    } catch {
      toast.error('Gagal mengunggah audio custom');
    } finally {
      setSoundUploading(null);
    }
  };

  const handleTestPush = async () => {
    if (!testUserId.trim()) {
      toast.error('User ID wajib diisi');
      return;
    }
    setTesting(true);
    try {
      const { data, error } = await supabase.functions.invoke('send-push-notification', {
        body: buildAdminPushTestPayload(testUserId, testTitle, testBody),
      });
      if (error) throw error;
      const json = data as { sent?: number; total?: number; message?: string; success?: boolean };
      if (json?.success === false) throw new Error(json.message || 'Gagal mengirim');
      toast.success(`Push dikirim ke ${json?.sent ?? 0}/${json?.total ?? 0} subscription`);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Gagal mengirim test push');
    } finally {
      setTesting(false);
    }
  };

  const handleSelfTestPush = async () => {
    if (!user) {
      toast.error('Sesi admin tidak ditemukan. Silakan masuk kembali.');
      return;
    }
    if (!testTitle.trim() || !testBody.trim()) {
      toast.error('Judul dan isi notifikasi wajib diisi');
      return;
    }

    setSelfTesting(true);
    try {
      const { data, error } = await supabase.functions.invoke('send-push-notification', {
        body: buildAdminPushTestPayload(user.id, testTitle, testBody),
      });
      if (error) throw error;
      const result = data as { sent?: number; total?: number; message?: string; success?: boolean };
      if (result?.success === false) throw new Error(result.message || 'Gagal mengirim push uji');

      const sent = result?.sent ?? 0;
      const total = result?.total ?? 0;
      if (total === 0) {
        toast.error('Akun admin ini belum memiliki subscription push aktif. Aktifkan Notifikasi Push pada perangkat yang ingin diuji.');
      } else if (sent === 0) {
        toast.error(`Push uji gagal dikirim ke ${total} perangkat akun admin.`);
      } else if (sent < total) {
        toast.warning(`Push uji terkirim ke ${sent}/${total} perangkat akun admin.`);
      } else {
        toast.success(`Push uji terkirim ke ${sent}/${total} perangkat akun admin.`);
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Gagal mengirim push uji ke akun admin');
    } finally {
      setSelfTesting(false);
    }
  };

  const handleBroadcast = async () => {
    if (!broadcastTitle.trim() || !broadcastBody.trim()) {
      toast.error('Judul dan pesan wajib diisi');
      return;
    }
    setBroadcasting(true);
    try {
      const { data, error } = await supabase.functions.invoke('send-push-notification', {
        body: {
          all: true,
          title: broadcastTitle,
          body: broadcastBody,
          url: broadcastUrl || '/',
        },
      });
      if (error) throw error;
      const json = data as { sent?: number; total?: number; message?: string; success?: boolean };
      const sent = json?.sent ?? 0;
      const total = json?.total ?? 0;
      if (json?.success === false && sent === 0) throw new Error(json.message || 'Gagal broadcast');
      if (total === 0) {
        toast.warning('Belum ada perangkat yang mengaktifkan push notification.');
        return;
      }
      if (json?.success === false || sent < total) {
        toast.warning(`Sebagian push terkirim: ${sent}/${total} perangkat. Periksa riwayat log untuk rincian.`);
      } else {
        toast.success(`Broadcast terkirim ke ${sent}/${total} perangkat`);
      }
      setBroadcastTitle('');
      setBroadcastBody('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Gagal broadcast');
    } finally {
      setBroadcasting(false);
    }
  };


  const vapidConfigured = vapidStatus?.vapidConfigured === true;
  return (
    <AdminLayout title="Push Notification" subtitle="Konfigurasi web push notification ke pengguna">
      <div className="max-w-3xl mx-auto space-y-6">

        {/* Stats Bar */}
        <div className="grid grid-cols-2 gap-4">
          <Card>
            <CardContent className="flex items-center gap-3 py-4">
              <div className="w-10 h-10 rounded-full bg-blue-500/10 flex items-center justify-center">
                <Users className="h-5 w-5 text-blue-500" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Total Subscriber</p>
                <p className="text-xl font-bold">
                  {subscriberCount !== null ? subscriberCount.toLocaleString('id-ID') : '—'}
                </p>
              </div>
              <Button variant="ghost" size="icon" className="ml-auto" onClick={fetchSubscriberCount}>
                <RefreshCw className="h-4 w-4" />
              </Button>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="flex items-center gap-3 py-4">
              <div className={`w-10 h-10 rounded-full flex items-center justify-center ${vapidConfigured ? 'bg-green-500/10' : 'bg-muted'}`}>
                <Bell className={`h-5 w-5 ${vapidConfigured ? 'text-green-500' : 'text-muted-foreground'}`} />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Status konfigurasi VAPID</p>
                <Badge variant={vapidConfigured ? 'default' : 'secondary'}>
                  {vapidStatusLoading
                    ? 'Memeriksa...'
                    : vapidStatusError
                      ? 'Tidak dapat diverifikasi'
                      : vapidConfigured
                        ? 'Variabel VAPID tersedia'
                        : 'Konfigurasi belum lengkap'}
                </Badge>
              </div>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="ml-auto"
                aria-label="Periksa konfigurasi VAPID"
                title="Periksa konfigurasi VAPID"
                onClick={() => void refreshVapidStatus()}
                disabled={vapidStatusLoading}
              >
                {vapidStatusLoading
                  ? <Loader2 className="h-4 w-4 animate-spin" />
                  : <RefreshCw className="h-4 w-4" />
                }
              </Button>
            </CardContent>
          </Card>
        </div>

        <Card className="border-primary/20 bg-primary/[0.03]">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Volume2 className="h-5 w-5 text-primary" />
              Alarm Pesanan Masuk
            </CardTitle>
            <CardDescription>
              Atur nada merchant dan ojek secara terpisah. Alarm keduanya wajib aktif; browser tetap memerlukan satu interaksi pengguna sebelum audio dapat diputar otomatis.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-5">
            <div className="rounded-lg border bg-background p-3">
              <label className="flex cursor-pointer items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked
                  disabled
                  className="h-4 w-4 accent-primary"
                />
                Alarm pesanan aktif (wajib)
              </label>
              <div className="mt-3 grid gap-2 pl-6 text-sm sm:grid-cols-2">
                <label className="flex cursor-pointer items-center gap-2">
                  <input type="checkbox" checked disabled aria-label="Alarm merchant wajib aktif" className="h-4 w-4 accent-primary" />
                  Alarm merchant wajib aktif
                </label>
                <div className="flex items-center gap-2 font-medium text-primary" role="status">
                  <input type="checkbox" checked disabled aria-label="Alarm ojek wajib aktif" className="h-4 w-4 accent-primary" />
                  Alarm ojek wajib aktif (bunyi &amp; getar)
                </div>
              </div>
              <p className="mt-2 pl-6 text-xs text-muted-foreground">
                Alarm merchant dan ojek tidak dapat dimatikan dari konfigurasi audio. Perangkat tetap perlu menekan tombol aktivasi audio satu kali untuk membuka izin audio browser.
              </p>
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
              {(['merchant', 'courier'] as const).map((audience) => {
                const isMerchant = audience === 'merchant';
                const presetKey = isMerchant ? 'merchant_preset' : 'courier_preset';
                const volumeKey = isMerchant ? 'merchant_volume' : 'courier_volume';
                const customKey = isMerchant ? 'merchant_custom_audio_url' : 'courier_custom_audio_url';
                const label = isMerchant ? 'Merchant' : 'Ojek';
                return (
                  <div key={audience} className="space-y-4 rounded-lg border bg-background p-4">
                    <div>
                      <p className="font-semibold">Alarm {label}</p>
                      <p className="text-xs text-muted-foreground">Nada dan volume khusus untuk {label.toLowerCase()}.</p>
                    </div>
                    <div>
                      <Label htmlFor={`${audience}-sound-preset`}>Preset suara</Label>
                      <select
                        id={`${audience}-sound-preset`}
                        value={soundSettings[presetKey]}
                        onChange={(event) => setSoundSettings((current) => ({ ...current, [presetKey]: event.target.value as OrderNotificationSoundSettings['preset'] }))}
                        className="mt-1 h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
                      >
                        {Object.entries(ORDER_SOUND_PRESET_LABELS).map(([value, optionLabel]) => (
                          <option key={value} value={value}>{optionLabel}</option>
                        ))}
                      </select>
                    </div>
                    <div>
                      <Label htmlFor={`${audience}-sound-volume`}>Volume: {Math.round(soundSettings[volumeKey] * 100)}%</Label>
                      <input id={`${audience}-sound-volume`} type="range" min="0.1" max="1" step="0.05" value={soundSettings[volumeKey]} onChange={(event) => setSoundSettings((current) => ({ ...current, [volumeKey]: Number(event.target.value) }))} className="mt-4 w-full accent-primary" />
                    </div>
                    <div className="rounded-lg border border-dashed p-3">
                      <div className="flex items-center justify-between gap-2">
                        <div>
                          <p className="text-sm font-medium">Audio custom {label}</p>
                          <p className="text-xs text-muted-foreground">Maksimal 5 MB.</p>
                        </div>
                        <label className="inline-flex cursor-pointer items-center justify-center rounded-md border px-3 py-2 text-sm font-medium transition hover:bg-muted">
                          <Upload className="mr-2 h-4 w-4" />
                          {soundUploading === audience ? 'Mengunggah...' : 'Upload'}
                          <input type="file" accept="audio/mpeg,audio/wav,audio/ogg,audio/mp4" className="hidden" disabled={soundUploading !== null} onChange={(event) => { const file = event.target.files?.[0]; if (file) void handleSoundUpload(file, audience); event.currentTarget.value = ''; }} />
                        </label>
                      </div>
                      {soundSettings[customKey] && <p className="mt-2 truncate text-xs text-muted-foreground">Audio aktif: {soundSettings[customKey]}</p>}
                    </div>
                    <Button variant="outline" onClick={() => void previewOrderNotificationSound(soundSettings, audience)}>
                      <Volume2 className="mr-2 h-4 w-4" /> Preview alarm {label}
                    </Button>
                  </div>
                );
              })}
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <Label htmlFor="order-sound-repeat">Jumlah pengulangan: {soundSettings.repeat_count}x</Label>
                <input
                  id="order-sound-repeat"
                  type="range"
                  min="1"
                  max="6"
                  step="1"
                  value={soundSettings.repeat_count}
                  onChange={(event) => setSoundSettings((current) => ({ ...current, repeat_count: Number(event.target.value) }))}
                  className="mt-4 w-full accent-primary"
                />
              </div>
              <div>
                <Label htmlFor="order-sound-gap">Jeda antar bunyi: {soundSettings.repeat_gap_ms} ms</Label>
                <input
                  id="order-sound-gap"
                  type="range"
                  min="250"
                  max="3000"
                  step="50"
                  value={soundSettings.repeat_gap_ms}
                  onChange={(event) => setSoundSettings((current) => ({ ...current, repeat_gap_ms: Number(event.target.value) }))}
                  className="mt-4 w-full accent-primary"
                />
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button onClick={() => void handleSaveSoundSettings()} disabled={soundSaving || Boolean(soundUploading)}>
                {soundSaving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
                Simpan alarm
              </Button>
            </div>
          </CardContent>
        </Card>

        <Tabs defaultValue="config">
          <TabsList className="grid w-full grid-cols-4">
            <TabsTrigger value="config">
              <Key className="h-4 w-4 mr-1.5" />
              Konfigurasi
            </TabsTrigger>
            <TabsTrigger value="test">
              <TestTube className="h-4 w-4 mr-1.5" />
              Test Kirim
            </TabsTrigger>
            <TabsTrigger value="broadcast">
              <Users className="h-4 w-4 mr-1.5" />
              Broadcast
            </TabsTrigger>
            <TabsTrigger value="logs">
              <History className="h-4 w-4 mr-1.5" />
              Riwayat Log
            </TabsTrigger>
          </TabsList>

          {/* ── Tab Konfigurasi ── */}
          <TabsContent value="config">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Key className="h-5 w-5" />
                  Konfigurasi Server VAPID
                </CardTitle>
                <CardDescription>
                  Kunci push dibaca Edge Functions dari secrets server. Halaman ini hanya memeriksa keberadaan variabel; nilainya tidak pernah dimuat atau disimpan di browser.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="rounded-lg border bg-muted/30 p-4 text-sm">
                  <p className="font-medium">Simpan hanya di konfigurasi server Supabase</p>
                  <p className="mt-1 text-muted-foreground">
                    Push subscription dan pengiriman membaca <code>VAPID_PUBLIC_KEY</code> serta <code>VAPID_PRIVATE_KEY</code> dari Edge Function secrets. Jangan simpan private key di <code>app_settings</code> atau variabel frontend <code>VITE_*</code>.
                  </p>
                </div>

                <div className="space-y-2 rounded-lg border p-4 text-sm">
                  <p className="font-medium">Pemeriksaan keberadaan variabel</p>
                  {vapidStatusLoading && <p className="text-muted-foreground">Memeriksa konfigurasi server...</p>}
                  {vapidStatusError && <p className="text-destructive">{vapidStatusError}</p>}
                  {vapidStatus && (
                    <>
                      <p>VAPID pair: {vapidStatus.vapidConfigured ? 'tersedia' : 'belum lengkap'}</p>
                      {!vapidStatus.vapidConfigured && vapidStatus.missingVariables.length > 0 && (
                        <p className="text-destructive">
                          Variabel yang belum tersedia: {vapidStatus.missingVariables.join(', ')}
                        </p>
                      )}
                    </>
                  )}
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => void refreshVapidStatus()}
                    disabled={vapidStatusLoading}
                  >
                    {vapidStatusLoading
                      ? <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      : <RefreshCw className="mr-2 h-4 w-4" />
                    }
                    Periksa ulang konfigurasi server
                  </Button>
                </div>

                <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-4 text-xs text-muted-foreground">
                  Pemeriksaan ini tidak dapat memastikan jadwal cron atau secret di Supabase Vault. Pastikan Vault berisi nama <code>sadesa_project_url</code>, <code>sadesa_publishable_key</code>, dan <code>sadesa_notification_worker_secret</code>; nilainya tidak dibaca halaman ini.
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          {/* ── Tab Test Kirim ── */}
          <TabsContent value="test">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <TestTube className="h-5 w-5" />
                  Test Push ke User
                </CardTitle>
                <CardDescription>
                  Kirim uji coba ke akun admin yang sedang login atau ke satu user berdasarkan User ID.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <Label htmlFor="test-user-id">User ID</Label>
                  <Input
                    id="test-user-id"
                    value={testUserId}
                    onChange={e => setTestUserId(e.target.value)}
                    placeholder="UUID user (dari tabel profiles)"
                    className="mt-1 font-mono text-xs"
                  />
                </div>
                <div>
                  <Label htmlFor="test-title">Judul Notifikasi</Label>
                  <Input
                    id="test-title"
                    value={testTitle}
                    onChange={e => setTestTitle(e.target.value)}
                    className="mt-1"
                  />
                </div>
                <div>
                  <Label htmlFor="test-body">Isi Notifikasi</Label>
                  <Textarea
                    id="test-body"
                    value={testBody}
                    onChange={e => setTestBody(e.target.value)}
                    rows={3}
                    className="mt-1"
                  />
                </div>
                <p className="text-xs text-muted-foreground">
                  Uji mandiri hanya dikirim ke subscription milik akun admin yang sedang login; pengguna lain tidak menerima notifikasi.
                </p>
                <div className="flex flex-wrap gap-2">
                  <Button type="button" variant="outline" onClick={() => void handleSelfTestPush()} disabled={selfTesting || testing || !user || !vapidConfigured}>
                    {selfTesting
                      ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Mengirim...</>
                      : <><Send className="h-4 w-4 mr-2" />Kirim Uji ke Akun Admin Saya</>
                    }
                  </Button>
                  <Button onClick={handleTestPush} disabled={testing || selfTesting || !vapidConfigured}>
                    {testing
                      ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Mengirim...</>
                      : <><TestTube className="h-4 w-4 mr-2" />Kirim Test ke User</>
                    }
                  </Button>
                </div>
                {!vapidConfigured && (
                  <p className="text-xs text-destructive flex items-center gap-1">
                    <AlertCircle className="h-3 w-3" />
                    {vapidStatusError || 'Konfigurasi Edge Function belum lengkap. Periksa tab Konfigurasi.'}
                  </p>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          {/* ── Tab Broadcast ── */}
          <TabsContent value="broadcast">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Users className="h-5 w-5" />
                  Broadcast ke Semua Subscriber
                </CardTitle>
                <CardDescription>
                  Kirim push notification ke semua pengguna yang sudah subscribe.
                  {subscriberCount !== null && (
                    <span className="font-medium text-foreground"> ({subscriberCount} subscriber aktif)</span>
                  )}
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <Label htmlFor="bc-title">Judul Broadcast</Label>
                  <Input
                    id="bc-title"
                    value={broadcastTitle}
                    onChange={e => setBroadcastTitle(e.target.value)}
                    placeholder="Promo Hari Ini! 🎉"
                    className="mt-1"
                  />
                </div>
                <div>
                  <Label htmlFor="bc-body">Isi Pesan</Label>
                  <Textarea
                    id="bc-body"
                    value={broadcastBody}
                    onChange={e => setBroadcastBody(e.target.value)}
                    placeholder="Dapatkan diskon 30% untuk semua produk UMKM hari ini saja!"
                    rows={4}
                    className="mt-1"
                  />
                </div>
                <div>
                  <Label htmlFor="bc-url">URL Tujuan (opsional)</Label>
                  <Input
                    id="bc-url"
                    value={broadcastUrl}
                    onChange={e => setBroadcastUrl(e.target.value)}
                    placeholder="/products"
                    className="mt-1"
                  />
                </div>

                <div className="p-3 bg-amber-50 dark:bg-amber-950/30 rounded-lg flex gap-2">
                  <AlertCircle className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
                  <p className="text-xs text-amber-700 dark:text-amber-300">
                    Broadcast akan dikirim ke <strong>semua subscriber aktif</strong>.
                    Pastikan konten sudah benar sebelum mengirim.
                  </p>
                </div>

                <Button
                  onClick={handleBroadcast}
                  disabled={broadcasting || !vapidConfigured}
                  className="w-full"
                >
                  {broadcasting
                    ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Mengirim Broadcast...</>
                    : <><Send className="h-4 w-4 mr-2" />Kirim Broadcast</>
                  }
                </Button>
                {!vapidConfigured && (
                  <p className="text-xs text-destructive">
                    {vapidStatusError || 'Pastikan konfigurasi VAPID Edge Function sudah lengkap.'}
                  </p>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="logs">
            <Card>
              <CardHeader className="flex flex-row items-start justify-between gap-4">
                <div>
                  <CardTitle className="flex items-center gap-2">
                    <History className="h-5 w-5" />
                    Riwayat Pengiriman Push
                  </CardTitle>
                  <CardDescription>
                    100 percobaan terbaru dari test/broadcast admin dan antrean notifikasi aplikasi. Status diterima berarti layanan push menerima permintaan, bukan konfirmasi bahwa perangkat menampilkan notifikasi.
                  </CardDescription>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <Badge variant={pushDeliveryRealtimeStatus === 'connected' ? 'default' : 'secondary'}>
                    {pushDeliveryRealtimeStatus === 'connected'
                      ? 'Realtime aktif'
                      : pushDeliveryRealtimeStatus === 'connecting'
                        ? 'Menghubungkan Realtime'
                        : 'Realtime terputus'
                    }
                  </Badge>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => void fetchPushDeliveryLogs()}
                    disabled={pushDeliveryLogsLoading}
                    aria-label="Segarkan riwayat push"
                  >
                    {pushDeliveryLogsLoading
                      ? <Loader2 className="h-4 w-4 animate-spin" />
                      : <RefreshCw className="h-4 w-4" />
                    }
                  </Button>
                </div>
              </CardHeader>
              <CardContent>
                {pushDeliveryLogsError && (
                  <p role="alert" className="mb-3 rounded-md border border-destructive/30 p-3 text-sm text-destructive">
                    Gagal memuat riwayat: {pushDeliveryLogsError}
                  </p>
                )}
                {pushDeliveryLogsLoading && pushDeliveryLogs.length === 0 && (
                  <p role="status" className="py-8 text-center text-sm text-muted-foreground">Memuat riwayat pengiriman...</p>
                )}
                {!pushDeliveryLogsLoading && !pushDeliveryLogsError && pushDeliveryLogs.length === 0 && (
                  <p className="py-8 text-center text-sm text-muted-foreground">Belum ada percobaan pengiriman push.</p>
                )}
                <div role="log" aria-live="polite" aria-label="Riwayat percobaan pengiriman push" className="space-y-3">
                  {pushDeliveryLogs.map((log) => {
                    const statusLabel = log.status === 'sent'
                      ? 'Diterima layanan push'
                      : log.status === 'expired'
                        ? 'Subscription kedaluwarsa'
                        : 'Gagal';
                    const sourceLabel = log.source === 'admin_test'
                      ? 'Test admin'
                      : log.source === 'admin_broadcast'
                        ? 'Broadcast admin'
                        : 'Antrean aplikasi';
                    return (
                      <div key={log.id} className="flex items-start justify-between gap-4 rounded-lg border p-3">
                        <div className="min-w-0 space-y-1">
                          <div className="flex flex-wrap items-center gap-2">
                            <p className="break-words text-sm font-medium">{log.title}</p>
                            <Badge variant={log.status === 'sent' ? 'default' : 'destructive'}>{statusLabel}</Badge>
                          </div>
                          <p className="text-xs text-muted-foreground">
                            {sourceLabel} · {log.recipient_user_id ? `User ${log.recipient_user_id.slice(0, 8)}` : 'Penerima tidak tersedia'} · {new Date(log.created_at).toLocaleString('id-ID')}
                            {log.provider_status_code ? ` · HTTP ${log.provider_status_code}` : ''}
                          </p>
                          {log.error_message && <p className="break-words text-xs text-destructive">{log.error_message}</p>}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </AdminLayout>
  );
}
