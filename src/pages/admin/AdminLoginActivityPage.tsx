import { useCallback, useEffect, useMemo, useState } from 'react';
import { CheckCircle2, Clock3, Laptop, RefreshCw, Smartphone } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';

interface LoginActivity {
  id: string;
  user_id: string;
  device_id: string;
  device_name: string;
  device_type: 'browser' | 'pwa';
  platform: string | null;
  user_agent: string | null;
  first_seen_at: string;
  last_seen_at: string;
  login_count: number;
}

interface Profile {
  user_id: string;
  full_name: string | null;
}

const ACTIVE_WINDOW_MS = 15 * 60 * 1000;

function formatDate(value: string) {
  return new Date(value).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' });
}

export default function AdminLoginActivityPage() {
  const [activities, setActivities] = useState<LoginActivity[]>([]);
  const [profiles, setProfiles] = useState<Map<string, string>>(new Map());
  const [loading, setLoading] = useState(true);
  const [lastRefresh, setLastRefresh] = useState(new Date());

  const loadActivities = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('admin_login_activity' as never)
      .select('id,user_id,device_id,device_name,device_type,platform,user_agent,first_seen_at,last_seen_at,login_count')
      .order('last_seen_at', { ascending: false })
      .limit(100);
    if (error) {
      console.error('Unable to load admin login activity:', error);
      setActivities([]);
      setLoading(false);
      return;
    }
    const rows = (data || []) as unknown as LoginActivity[];
    setActivities(rows);
    const userIds = [...new Set(rows.map((row) => row.user_id))];
    if (userIds.length > 0) {
      const { data: profileRows } = await supabase
        .from('profiles')
        .select('user_id, full_name')
        .in('user_id', userIds);
      setProfiles(new Map(((profileRows || []) as Profile[]).map((profile) => [profile.user_id, profile.full_name || 'Admin'])));
    }
    setLastRefresh(new Date());
    setLoading(false);
  }, []);

  useEffect(() => { void loadActivities(); }, [loadActivities]);

  const activeCount = useMemo(
    () => activities.filter((activity) => Date.now() - Date.parse(activity.last_seen_at) <= ACTIVE_WINDOW_MS).length,
    [activities],
  );

  return (
    <AdminLayout title="Aktivitas Login" subtitle="Daftar perangkat yang digunakan admin untuk masuk">
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm text-muted-foreground">{activeCount} perangkat aktif dalam 15 menit terakhir</p>
          <p className="text-xs text-muted-foreground">Diperbarui {lastRefresh.toLocaleTimeString('id-ID')}</p>
        </div>
        <Button variant="outline" onClick={() => void loadActivities()} disabled={loading}>
          <RefreshCw className={`mr-2 h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>
      <Card>
        <CardHeader><CardTitle className="text-base">Perangkat admin</CardTitle></CardHeader>
        <CardContent>
          {activities.length === 0 && !loading ? (
            <p className="py-8 text-center text-sm text-muted-foreground">Belum ada aktivitas login admin yang tercatat.</p>
          ) : (
            <div className="space-y-3">
              {activities.map((activity) => {
                const isActive = Date.now() - Date.parse(activity.last_seen_at) <= ACTIVE_WINDOW_MS;
                const DeviceIcon = activity.device_type === 'pwa' ? Smartphone : Laptop;
                return (
                  <div key={activity.id} className="flex items-start gap-3 rounded-xl border p-3">
                    <div className="rounded-lg bg-muted p-2"><DeviceIcon className="h-5 w-5" /></div>
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-semibold">{activity.device_name}</p>
                        <Badge variant={isActive ? 'success' : 'outline'}>
                          {isActive ? <><CheckCircle2 className="mr-1 h-3 w-3" /> Aktif</> : 'Tidak aktif'}
                        </Badge>
                      </div>
                      <p className="mt-1 text-xs text-muted-foreground">{profiles.get(activity.user_id) || 'Admin'} · {activity.platform || 'Platform tidak diketahui'}</p>
                      <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground"><Clock3 className="h-3 w-3" /> Login terakhir {formatDate(activity.last_seen_at)} · {activity.login_count} kali</p>
                      <p className="mt-1 break-all text-[10px] text-muted-foreground">ID perangkat: {activity.device_id}</p>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>
    </AdminLayout>
  );
}
