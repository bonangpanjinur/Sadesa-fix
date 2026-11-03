import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Activity, CheckCircle2, Loader2, QrCode, RefreshCw, Search, Store, TriangleAlert } from 'lucide-react';
import { toast } from 'sonner';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { AdminStatePanel } from '@/components/admin/AdminPagePrimitives';
import { cn } from '@/lib/utils';

type GdcProfileStatus = 'PENDING_VALIDATION' | 'ACTIVE' | 'SUSPENDED';

type Merchant = {
  id: string;
  name: string;
  phone: string | null;
  city: string | null;
  status: string | null;
  registration_status: string | null;
};

type GdcProfile = {
  id: string;
  merchant_id: string;
  provider: 'GDC';
  status: GdcProfileStatus;
  provider_merchant_id: string;
  provider_account_number: string;
  nmid: string | null;
  store_id: string | null;
  terminal_id: string | null;
  service_code: string | null;
  verified_at: string | null;
  verified_by: string | null;
  updated_at: string;
};

type GdcActivity = {
  id: string;
  profile_id: string;
  actor_user_id: string;
  action: string;
  metadata: Record<string, unknown>;
  occurred_at: string;
};

type FormValues = {
  providerMerchantId: string;
  providerAccountNumber: string;
  nmid: string;
  storeId: string;
  terminalId: string;
  serviceCode: string;
  status: GdcProfileStatus;
};

const EMPTY_FORM: FormValues = {
  providerMerchantId: '',
  providerAccountNumber: '',
  nmid: '',
  storeId: '',
  terminalId: '',
  serviceCode: '',
  status: 'PENDING_VALIDATION',
};

// GDC profile tables are introduced by a database migration that is not yet
// reflected in the generated Supabase types.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const db = supabase as any;

const statusLabels: Record<GdcProfileStatus, string> = {
  PENDING_VALIDATION: 'Menunggu validasi',
  ACTIVE: 'Aktif',
  SUSPENDED: 'Ditangguhkan',
};

const statusVariants: Record<GdcProfileStatus, 'default' | 'secondary' | 'destructive'> = {
  PENDING_VALIDATION: 'secondary',
  ACTIVE: 'default',
  SUSPENDED: 'destructive',
};

const toFormValues = (profile: GdcProfile | null): FormValues => profile ? {
  providerMerchantId: profile.provider_merchant_id || '',
  providerAccountNumber: profile.provider_account_number || '',
  nmid: profile.nmid || '',
  storeId: profile.store_id || '',
  terminalId: profile.terminal_id || '',
  serviceCode: profile.service_code || '',
  status: profile.status || 'PENDING_VALIDATION',
} : { ...EMPTY_FORM };

const errorMessage = (error: unknown, fallback: string) => error instanceof Error ? error.message : fallback;

export default function AdminQrisMerchantSettingsPage() {
  const [merchants, setMerchants] = useState<Merchant[]>([]);
  const [profileStatusByMerchant, setProfileStatusByMerchant] = useState<Record<string, GdcProfileStatus>>({});
  const [selectedMerchantId, setSelectedMerchantId] = useState('');
  const [merchantSearch, setMerchantSearch] = useState('');
  const [form, setForm] = useState<FormValues>({ ...EMPTY_FORM });
  const [profile, setProfile] = useState<GdcProfile | null>(null);
  const [activities, setActivities] = useState<GdcActivity[]>([]);
  const [formOwnerMerchantId, setFormOwnerMerchantId] = useState<string | null>(null);
  const [draftDirty, setDraftDirty] = useState(false);
  const [loadingMerchants, setLoadingMerchants] = useState(true);
  const [loadingProfile, setLoadingProfile] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const profileRequestRef = useRef(0);

  const selectedMerchant = merchants.find((merchant) => merchant.id === selectedMerchantId) || null;
  const filteredMerchants = useMemo(() => {
    const query = merchantSearch.trim().toLowerCase();
    if (!query) return merchants;
    return merchants.filter((merchant) => [merchant.name, merchant.phone, merchant.city, merchant.id].filter(Boolean).join(' ').toLowerCase().includes(query));
  }, [merchantSearch, merchants]);

  const loadMerchants = useCallback(async () => {
    setLoadingMerchants(true);
    setLoadError(null);
    try {
      const [{ data, error }, { data: profiles }] = await Promise.all([
        db.from('merchants').select('id, name, phone, city, status, registration_status').order('name', { ascending: true }),
        db.from('gdc_payment_profiles').select('merchant_id, status').eq('provider', 'GDC'),
      ]);
      if (error) throw error;
      const merchantRows = (data || []) as Merchant[];
      setMerchants(merchantRows);
      setProfileStatusByMerchant(Object.fromEntries((profiles || []).map((item: { merchant_id: string; status: GdcProfileStatus }) => [item.merchant_id, item.status])));
      setSelectedMerchantId((current) => current && merchantRows.some((merchant) => merchant.id === current) ? current : merchantRows[0]?.id || '');
    } catch (error) {
      const message = errorMessage(error, 'Daftar toko gagal dimuat.');
      setLoadError(message);
      toast.error(message);
    } finally {
      setLoadingMerchants(false);
    }
  }, []);

  const loadProfile = useCallback(async (merchantId: string, preserveDraft: boolean) => {
    if (!merchantId) return;
    const requestId = ++profileRequestRef.current;
    setLoadingProfile(true);
    try {
      const { data, error } = await db.from('gdc_payment_profiles')
        .select('*')
        .eq('merchant_id', merchantId)
        .eq('provider', 'GDC')
        .maybeSingle();
      if (error) throw error;
      const nextProfile = (data || null) as GdcProfile | null;
      const { data: activityRows, error: activityError } = nextProfile ? await db.from('gdc_payment_profile_activity_logs')
        .select('id, profile_id, actor_user_id, action, metadata, occurred_at')
        .eq('profile_id', nextProfile.id)
        .order('occurred_at', { ascending: false })
        .limit(10) : { data: [], error: null };
      if (activityError) throw activityError;
      if (requestId !== profileRequestRef.current) return;
      setProfile(nextProfile);
      setActivities((activityRows || []) as GdcActivity[]);
      setProfileStatusByMerchant((current) => {
        const next = { ...current };
        if (nextProfile) next[merchantId] = nextProfile.status;
        else delete next[merchantId];
        return next;
      });
      // An automatic refresh must never erase values the admin is currently editing.
      // A merchant switch is the only time the draft is synchronized from the DB.
      if (!preserveDraft) {
        setForm(toFormValues(nextProfile));
        setFormOwnerMerchantId(merchantId);
        setDraftDirty(false);
      }
    } catch (error) {
      if (requestId !== profileRequestRef.current) return;
      toast.error(errorMessage(error, 'Profil pembayaran GDC gagal dimuat.'));
    } finally {
      if (requestId === profileRequestRef.current) setLoadingProfile(false);
    }
  }, []);

  useEffect(() => {
    void loadMerchants();
  }, [loadMerchants]);

  useEffect(() => {
    if (!selectedMerchantId) {
      setProfile(null);
      setActivities([]);
      setForm({ ...EMPTY_FORM });
      setFormOwnerMerchantId(null);
      setDraftDirty(false);
      return;
    }
    void loadProfile(selectedMerchantId, false);
  }, [loadProfile, selectedMerchantId]);

  const handleRefresh = async () => {
    setRefreshing(true);
    try {
      await loadMerchants();
      // Preserve the current draft while refreshing the selected merchant in the background.
      if (selectedMerchantId) await loadProfile(selectedMerchantId, true);
      toast.success('Daftar toko dan status profil diperbarui.');
    } finally {
      setRefreshing(false);
    }
  };

  const updateForm = <K extends keyof FormValues>(key: K, value: FormValues[K]) => {
    setForm((current) => ({ ...current, [key]: value }));
    setDraftDirty(true);
  };

  const saveProfile = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!selectedMerchantId) return;
    if (!form.providerMerchantId.trim() || !form.providerAccountNumber.trim()) {
      toast.error('Merchant ID dan account number GDC wajib diisi.');
      return;
    }
    setSaving(true);
    try {
      const { data, error } = await db.rpc('admin_upsert_gdc_payment_profile', {
        p_merchant_id: selectedMerchantId,
        p_provider_merchant_id: form.providerMerchantId.trim(),
        p_provider_account_number: form.providerAccountNumber.trim(),
        p_nmid: form.nmid.trim() || null,
        p_store_id: form.storeId.trim() || null,
        p_terminal_id: form.terminalId.trim() || null,
        p_service_code: form.serviceCode.trim() || null,
        p_status: form.status,
      });
      if (error) throw error;
      const savedProfile = data as GdcProfile;
      setProfile(savedProfile);
      setFormOwnerMerchantId(selectedMerchantId);
      setDraftDirty(false);
      await loadProfile(selectedMerchantId, true);
      toast.success('Profil QRIS Merchant tersimpan dan aktivitas admin tercatat.');
    } catch (error) {
      toast.error(errorMessage(error, 'Profil QRIS Merchant gagal disimpan.'));
    } finally {
      setSaving(false);
    }
  };

  const showDraftWarning = draftDirty && formOwnerMerchantId === selectedMerchantId;

  return (
    <AdminLayout
      title="Pengaturan QRIS Merchant"
      subtitle="Masukkan atau perbarui profil pembayaran GDC untuk toko yang sudah terdaftar."
      rightElement={(
        <Button variant="outline" size="sm" onClick={() => void handleRefresh()} disabled={refreshing || loadingMerchants} className="gap-2">
          <RefreshCw className={cn('h-4 w-4', (refreshing || loadingMerchants) && 'animate-spin')} />
          Segarkan
        </Button>
      )}
    >
      <div className="grid gap-4 xl:grid-cols-[minmax(280px,0.75fr)_minmax(0,1.5fr)]">
        <Card className="h-fit">
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Store className="h-5 w-5" />Toko terdaftar</CardTitle>
            <CardDescription>Pilih toko tanpa membuat pengajuan QRIS baru.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input value={merchantSearch} onChange={(event) => setMerchantSearch(event.target.value)} placeholder="Cari nama, telepon, atau ID toko" className="pl-9" aria-label="Cari toko terdaftar" />
            </div>
            {loadingMerchants ? <AdminStatePanel type="loading" className="min-h-40" title="Memuat daftar toko" /> : loadError ? <AdminStatePanel type="error" className="min-h-40" description={loadError} actionLabel="Coba lagi" onAction={() => void loadMerchants()} /> : filteredMerchants.length === 0 ? <AdminStatePanel type="empty" className="min-h-40" title="Toko tidak ditemukan" description="Coba ubah kata kunci pencarian." /> : (
              <div className="max-h-[calc(100vh-18rem)] space-y-2 overflow-y-auto pr-1">
                {filteredMerchants.map((merchant) => {
                  const status = profileStatusByMerchant[merchant.id];
                  const selected = merchant.id === selectedMerchantId;
                  return (
                    <button
                      key={merchant.id}
                      type="button"
                      onClick={() => setSelectedMerchantId(merchant.id)}
                      className={cn('w-full rounded-lg border p-3 text-left transition-colors', selected ? 'border-primary bg-primary/5' : 'hover:bg-muted/60')}
                    >
                      <div className="flex items-start justify-between gap-2">
                        <span className="min-w-0 truncate font-medium">{merchant.name}</span>
                        {status ? <Badge variant={statusVariants[status]} className="shrink-0 text-[10px]">{statusLabels[status]}</Badge> : <Badge variant="outline" className="shrink-0 text-[10px]">Belum diatur</Badge>}
                      </div>
                      <p className="mt-1 truncate text-xs text-muted-foreground">{merchant.city || 'Lokasi belum diisi'}{merchant.phone ? ` · ${merchant.phone}` : ''}</p>
                    </button>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>

        <div className="space-y-4">
          <Card>
            <CardHeader>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <CardTitle className="flex items-center gap-2"><QrCode className="h-5 w-5" />Profil pembayaran GDC</CardTitle>
                  <CardDescription>Credential API dan signature tetap berada di Edge Function Secrets.</CardDescription>
                </div>
                {loadingProfile && <Loader2 className="h-5 w-5 shrink-0 animate-spin text-primary" aria-label="Memuat profil" />}
              </div>
            </CardHeader>
            <CardContent>
              {!selectedMerchant ? <AdminStatePanel type="empty" title="Pilih toko terlebih dahulu" description="Pilih salah satu toko terdaftar di panel sebelah kiri untuk mengatur profil QRIS." /> : (
                <form onSubmit={(event) => void saveProfile(event)} className="space-y-5">
                  <div className="rounded-lg bg-muted/50 p-4 text-sm">
                    <div className="flex flex-wrap items-center gap-2"><strong>{selectedMerchant.name}</strong>{selectedMerchant.registration_status && <Badge variant="outline">{selectedMerchant.registration_status}</Badge>}{profile && <Badge variant={statusVariants[profile.status]}>{statusLabels[profile.status]}</Badge>}</div>
                    <p className="mt-1 break-all font-mono text-xs text-muted-foreground">Merchant ID internal: {selectedMerchant.id}</p>
                    <p className="mt-2 text-xs text-muted-foreground">Perubahan dilakukan langsung oleh admin untuk merchant ini; merchant tidak perlu mengajukan ulang.</p>
                  </div>

                  <div className="grid gap-4 sm:grid-cols-2">
                    <div className="space-y-2"><Label htmlFor="gdc-provider-merchant-id">GDC merchant ID <span className="text-destructive">*</span></Label><Input id="gdc-provider-merchant-id" value={form.providerMerchantId} onChange={(event) => updateForm('providerMerchantId', event.target.value)} placeholder="Nilai merchantId dari GDC" maxLength={160} /></div>
                    <div className="space-y-2"><Label htmlFor="gdc-account-number">GDC account number <span className="text-destructive">*</span></Label><Input id="gdc-account-number" value={form.providerAccountNumber} onChange={(event) => updateForm('providerAccountNumber', event.target.value)} placeholder="Nilai additionalInfo.accountNumber" maxLength={160} /></div>
                    <div className="space-y-2"><Label htmlFor="gdc-nmid">NMID</Label><Input id="gdc-nmid" value={form.nmid} onChange={(event) => updateForm('nmid', event.target.value)} placeholder="Identifier NMID (opsional)" maxLength={160} /></div>
                    <div className="space-y-2"><Label htmlFor="gdc-store-id">Store ID</Label><Input id="gdc-store-id" value={form.storeId} onChange={(event) => updateForm('storeId', event.target.value)} placeholder="Store identifier (opsional)" maxLength={160} /></div>
                    <div className="space-y-2"><Label htmlFor="gdc-terminal-id">Terminal ID</Label><Input id="gdc-terminal-id" value={form.terminalId} onChange={(event) => updateForm('terminalId', event.target.value)} placeholder="Terminal identifier (opsional)" maxLength={160} /></div>
                    <div className="space-y-2"><Label htmlFor="gdc-service-code">Service code</Label><Input id="gdc-service-code" value={form.serviceCode} onChange={(event) => updateForm('serviceCode', event.target.value)} placeholder="Sesuai kontrak GDC (opsional)" maxLength={160} /></div>
                    <div className="space-y-2 sm:col-span-2"><Label htmlFor="gdc-status">Status profil</Label><select id="gdc-status" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.status} onChange={(event) => updateForm('status', event.target.value as GdcProfileStatus)}><option value="PENDING_VALIDATION">Menunggu validasi</option><option value="ACTIVE">Aktif</option><option value="SUSPENDED">Ditangguhkan</option></select><p className="text-xs text-muted-foreground">Hanya profil berstatus Aktif yang boleh dipakai pada alur pembayaran GDC.</p></div>
                  </div>

                  <div className="flex flex-col gap-3 border-t pt-4 sm:flex-row sm:items-center sm:justify-between">
                    <div className="flex items-center gap-2 text-xs text-muted-foreground">{showDraftWarning ? <><TriangleAlert className="h-4 w-4 text-amber-600" />Ada perubahan yang belum disimpan.</> : profile ? <><CheckCircle2 className="h-4 w-4 text-emerald-600" />Profil tersimpan{profile.updated_at ? ` · ${new Date(profile.updated_at).toLocaleString('id-ID')}` : ''}</> : 'Belum ada profil GDC untuk toko ini.'}</div>
                    <Button type="submit" disabled={saving || loadingProfile}>{saving ? 'Menyimpan...' : 'Simpan profil QRIS'}</Button>
                  </div>
                </form>
              )}
            </CardContent>
          </Card>

          {selectedMerchant && <Card>
            <CardHeader><CardTitle className="flex items-center gap-2 text-base"><Activity className="h-4 w-4" />Riwayat aktivitas profil</CardTitle><CardDescription>Setiap penyimpanan melalui RPC admin_upsert_gdc_payment_profile dicatat di gdc_payment_profile_activity_logs.</CardDescription></CardHeader>
            <CardContent>
              {activities.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada aktivitas untuk profil toko ini.</p> : <div className="space-y-3">{activities.map((activity) => <div key={activity.id} className="flex flex-col gap-1 rounded-lg border p-3 text-sm sm:flex-row sm:items-start sm:justify-between"><div><p className="font-medium">{activity.action}</p><p className="text-xs text-muted-foreground">Admin {activity.actor_user_id}</p>{Object.keys(activity.metadata || {}).length > 0 && <p className="mt-1 text-xs text-muted-foreground">{Object.entries(activity.metadata).map(([key, value]) => `${key}: ${String(value)}`).join(' · ')}</p>}</div><time className="shrink-0 text-xs text-muted-foreground">{new Date(activity.occurred_at).toLocaleString('id-ID')}</time></div>)}</div>}
            </CardContent>
          </Card>}
        </div>
      </div>
    </AdminLayout>
  );
}
