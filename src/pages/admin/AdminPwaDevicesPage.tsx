import { useCallback, useEffect, useState } from 'react';
import { RefreshCw, Smartphone, ShieldOff } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { reportObservability } from '@/lib/observability';
import type { PwaDeviceSession } from '@/lib/pwaDevice';

export default function AdminPwaDevicesPage() {
  const [devices, setDevices] = useState<PwaDeviceSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [revoking, setRevoking] = useState<string | null>(null);

  const loadDevices = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.from('pwa_device_sessions' as never)
      .select('id,user_id,tenant_id,device_id,device_name,device_type,platform,status,last_seen_at,last_sync_at,revoked_at,created_at,updated_at')
      .order('last_seen_at', { ascending: false });
    if (error) {
      reportObservability('device', 'admin_device_list_failed', 'error', {}, error);
      toast.error('Gagal memuat daftar perangkat');
    } else setDevices((data ?? []) as unknown as PwaDeviceSession[]);
    setLoading(false);
  }, []);

  useEffect(() => { void loadDevices(); }, [loadDevices]);

  const revoke = async (device: PwaDeviceSession) => {
    setRevoking(device.id);
    const { error } = await supabase.rpc('revoke_pwa_device' as never, { p_device_session_id: device.id } as never);
    if (error) {
      reportObservability('device', 'admin_device_revoke_failed', 'error', { deviceType: device.device_type }, error);
      toast.error(error.message);
    } else {
      reportObservability('device', 'admin_device_revoked', 'info', { deviceType: device.device_type });
      toast.success(`Session ${device.device_name} dicabut`);
      await loadDevices();
    }
    setRevoking(null);
  };

  return (
    <AdminLayout title="PWA Device Management" subtitle="Pantau perangkat kasir, last-seen, sinkronisasi, dan cabut session yang mencurigakan">
      <div className="flex justify-end mb-4"><Button variant="outline" onClick={() => void loadDevices()} disabled={loading}><RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />Refresh</Button></div>
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><Smartphone className="h-5 w-5 text-primary" />Perangkat terdaftar ({devices.length})</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          {loading ? <div className="py-12 text-center text-muted-foreground">Memuat perangkat...</div> : devices.length === 0 ? <div className="py-12 text-center text-muted-foreground">Belum ada perangkat PWA terdaftar.</div> : devices.map((device) => (
            <div key={device.id} className="flex flex-col gap-3 rounded-lg border p-4 md:flex-row md:items-center">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-muted"><Smartphone className="h-5 w-5 text-muted-foreground" /></div>
              <div className="min-w-0 flex-1"><div className="flex flex-wrap items-center gap-2"><p className="font-semibold">{device.device_name}</p><Badge variant={device.status === 'active' ? 'success' : device.status === 'revoked' ? 'destructive' : 'warning'}>{device.status}</Badge><Badge variant="outline">{device.device_type}</Badge></div><p className="mt-1 text-xs text-muted-foreground">User {device.user_id.slice(0, 8)} · {device.platform || 'platform tidak diketahui'}</p><p className="text-xs text-muted-foreground">Last seen {new Date(device.last_seen_at).toLocaleString('id-ID')} · Sync {device.last_sync_at ? new Date(device.last_sync_at).toLocaleString('id-ID') : 'belum ada'}</p></div>
              {device.status !== 'revoked' && <Button variant="destructive" size="sm" onClick={() => void revoke(device)} disabled={revoking === device.id}><ShieldOff className="mr-2 h-4 w-4" />{revoking === device.id ? 'Mencabut...' : 'Revoke session'}</Button>}
            </div>
          ))}
        </CardContent>
      </Card>
    </AdminLayout>
  );
}
