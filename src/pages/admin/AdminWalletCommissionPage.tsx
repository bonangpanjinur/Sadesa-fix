import { useCallback, useEffect, useState } from 'react';
import { Percent, Save } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

type OwnerType = 'MERCHANT' | 'COURIER';
type FeeSetting = { owner_type: OwnerType; fee_percent: number; is_enabled: boolean; updated_at: string };

export default function AdminWalletCommissionPage() {
  const [settings, setSettings] = useState<FeeSetting[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<OwnerType | null>(null);

  const loadSettings = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('commission_fee_settings' as never)
      .select('*');
    if (error) {
      console.error('Gagal memuat tarif komisi wallet:', error);
      toast.error('Pengaturan komisi belum tersedia. Terapkan migration wallet lebih dahulu.');
    } else {
      setSettings((data ?? []) as unknown as FeeSetting[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => { void loadSettings(); }, [loadSettings]);

  const updateSetting = (ownerType: OwnerType, changes: Partial<FeeSetting>) => {
    setSettings((current) => current.map((item) => item.owner_type === ownerType ? { ...item, ...changes } : item));
  };

  const saveSetting = async (setting: FeeSetting) => {
    const percent = Number(setting.fee_percent);
    if (!Number.isFinite(percent) || percent < 0 || percent > 100) {
      toast.error('Tarif komisi harus berada di antara 0% sampai 100%');
      return;
    }
    setSaving(setting.owner_type);
    const { error } = await supabase
      .from('commission_fee_settings' as never)
      .update({ fee_percent: percent, is_enabled: setting.is_enabled, updated_by: (await supabase.auth.getUser()).data.user?.id ?? null, updated_at: new Date().toISOString() } as never)
      .eq('owner_type' as never, setting.owner_type as never);
    if (error) {
      console.error('Gagal menyimpan tarif komisi:', error);
      toast.error('Gagal menyimpan tarif komisi');
    } else {
      toast.success(`Tarif ${setting.owner_type === 'MERCHANT' ? 'pedagang' : 'ojek'} berhasil disimpan`);
      await loadSettings();
    }
    setSaving(null);
  };

  const configCard = (ownerType: OwnerType) => {
    const setting = settings.find((item) => item.owner_type === ownerType);
    const label = ownerType === 'MERCHANT' ? 'Pedagang' : 'Ojek';
    return (
      <Card key={ownerType}>
        <CardHeader>
          <CardTitle>{label}</CardTitle>
          <CardDescription>
            {ownerType === 'MERCHANT'
              ? 'Basis perhitungan: subtotal order (tidak termasuk ongkir).'
              : 'Basis perhitungan: tarif final perjalanan ojek.'}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-5">
          {!setting ? <p className="text-sm text-muted-foreground">Konfigurasi belum dibuat di database.</p> : <>
            <div className="space-y-2">
              <Label htmlFor={`fee-${ownerType}`}>Persentase komisi</Label>
              <div className="flex max-w-xs items-center gap-2">
                <Input id={`fee-${ownerType}`} type="number" min="0" max="100" step="0.01" value={setting.fee_percent}
                  onChange={(event) => updateSetting(ownerType, { fee_percent: Number(event.target.value) })} />
                <span className="text-sm">%</span>
              </div>
            </div>
            <div className="flex items-center justify-between gap-3 rounded-md border p-3">
              <div><Label htmlFor={`enabled-${ownerType}`}>Aktifkan pemotongan</Label><p className="text-xs text-muted-foreground">Tarif nonaktif tidak memotong saldo dan tidak memblokir transaksi selesai.</p></div>
              <Switch id={`enabled-${ownerType}`} checked={setting.is_enabled} onCheckedChange={(checked) => updateSetting(ownerType, { is_enabled: checked })} />
            </div>
            <p className="text-sm text-muted-foreground">Contoh: transaksi Rp20.000 pada tarif 5% memotong Rp1.000.</p>
            <Button onClick={() => void saveSetting(setting)} disabled={saving !== null}>
              <Save className="mr-2 h-4 w-4" />{saving === ownerType ? 'Menyimpan…' : 'Simpan tarif'}
            </Button>
          </>}
        </CardContent>
      </Card>
    );
  };

  return (
    <AdminLayout title="Komisi Saldo" subtitle="Atur persentase komisi wallet pedagang dan ojek secara terpisah">
      <div className="mx-auto max-w-5xl space-y-6 p-4 md:p-6">
        <Alert>
          <Percent className="h-4 w-4" />
          <AlertTitle>Berbeda dari komisi verifikator</AlertTitle>
          <AlertDescription>Pengaturan ini menentukan potongan saldo rupiah setiap transaksi selesai. Komisi referral/verifikator tetap dikelola di menu terpisah. Pastikan wallet pelaku sudah memiliki saldo sebelum tarif diaktifkan.</AlertDescription>
        </Alert>
        {loading ? <div className="py-12 text-center text-muted-foreground">Memuat pengaturan…</div> : (
          <div className="grid gap-4 md:grid-cols-2">{configCard('MERCHANT')}{configCard('COURIER')}</div>
        )}
      </div>
    </AdminLayout>
  );
}
