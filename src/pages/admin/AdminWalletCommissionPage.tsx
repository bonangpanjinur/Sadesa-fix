import { useCallback, useEffect, useState } from 'react';
import { CheckCircle2, Eye, Percent, RefreshCw, Save, XCircle } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice } from '@/lib/utils';
import { toast } from 'sonner';

type OwnerType = 'MERCHANT' | 'COURIER';
type FeeSetting = { owner_type: OwnerType; fee_percent: number; is_enabled: boolean; updated_at: string };
type TopupRequest = { id: string; owner_type: OwnerType; merchant_id: string | null; courier_id: string | null; amount_rupiah: number; proof_path: string; note: string | null; status: string; admin_notes: string | null; created_at: string };

export default function AdminWalletCommissionPage() {
  const [settings, setSettings] = useState<FeeSetting[]>([]);
  const [requests, setRequests] = useState<TopupRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<OwnerType | null>(null);
  const [processing, setProcessing] = useState<string | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});

  const loadData = useCallback(async () => {
    setLoading(true);
    const [{ data, error }, { data: requestData, error: requestError }] = await Promise.all([
      supabase.from('commission_fee_settings' as never).select('*'),
      supabase.from('commission_wallet_topup_requests' as never).select('*').order('created_at' as never, { ascending: false } as never).limit(50),
    ]);
    if (error) {
      console.error('Gagal memuat tarif komisi wallet:', error);
      toast.error('Pengaturan komisi belum tersedia. Terapkan migration wallet lebih dahulu.');
    } else setSettings((data ?? []) as unknown as FeeSetting[]);
    if (requestError) {
      console.error('Gagal memuat permintaan top-up:', requestError);
      toast.error('Gagal memuat permintaan top-up. Pastikan migration top-up diterapkan.');
    } else setRequests((requestData ?? []) as unknown as TopupRequest[]);
    setLoading(false);
  }, []);

  useEffect(() => { void loadData(); }, [loadData]);

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
    const { error } = await supabase.from('commission_fee_settings' as never)
      .update({ fee_percent: percent, is_enabled: setting.is_enabled, updated_by: (await supabase.auth.getUser()).data.user?.id ?? null, updated_at: new Date().toISOString() } as never)
      .eq('owner_type' as never, setting.owner_type as never);
    if (error) {
      console.error('Gagal menyimpan tarif komisi:', error);
      toast.error(error.message || 'Gagal menyimpan tarif komisi');
    } else {
      toast.success(`Tarif ${setting.owner_type === 'MERCHANT' ? 'pedagang' : 'ojek'} berhasil disimpan`);
      await loadData();
    }
    setSaving(null);
  };

  const reviewTopup = async (request: TopupRequest, approve: boolean) => {
    const action = approve ? 'menyetujui dan mengkredit saldo' : 'menolak';
    if (!window.confirm(`Yakin ${action} top-up ${formatPrice(request.amount_rupiah)}? Periksa bukti transfer sebelum menyetujui.`)) return;
    setProcessing(request.id);
    const { error } = await supabase.rpc('process_commission_wallet_topup' as never, {
      p_request_id: request.id,
      p_approve: approve,
      p_admin_notes: notes[request.id]?.trim() || null,
    } as never);
    if (error) {
      console.error('Gagal memproses top-up:', error);
      toast.error(error.message || 'Gagal memproses top-up');
    } else {
      toast.success(approve ? 'Top-up disetujui dan saldo telah dikreditkan' : 'Top-up ditolak');
      await loadData();
    }
    setProcessing(null);
  };

  const openProof = async (proofPath: string) => {
    const { data, error } = await supabase.storage.from('commission-topup-proofs').createSignedUrl(proofPath, 300);
    if (error || !data?.signedUrl) {
      toast.error('Bukti tidak dapat dibuka');
      return;
    }
    window.open(data.signedUrl, '_blank', 'noopener,noreferrer');
  };

  const configCard = (ownerType: OwnerType) => {
    const setting = settings.find((item) => item.owner_type === ownerType);
    const label = ownerType === 'MERCHANT' ? 'Pedagang' : 'Ojek';
    return (
      <Card key={ownerType}>
        <CardHeader><CardTitle>{label}</CardTitle><CardDescription>{ownerType === 'MERCHANT' ? 'Basis: subtotal order, di luar ongkir.' : 'Basis: tarif final perjalanan ojek.'}</CardDescription></CardHeader>
        <CardContent className="space-y-5">
          {!setting ? <p className="text-sm text-muted-foreground">Konfigurasi belum dibuat di database.</p> : <>
            <div className="space-y-2"><Label htmlFor={`fee-${ownerType}`}>Persentase komisi</Label><div className="flex max-w-xs items-center gap-2"><Input id={`fee-${ownerType}`} type="number" min="0" max="100" step="0.01" value={setting.fee_percent} onChange={(event) => updateSetting(ownerType, { fee_percent: Number(event.target.value) })} /><span className="text-sm">%</span></div></div>
            <div className="flex items-center justify-between gap-3 rounded-md border p-3"><div><Label htmlFor={`enabled-${ownerType}`}>Aktifkan pemotongan</Label><p className="text-xs text-muted-foreground">Tarif nonaktif tidak memotong saldo dan tidak memblokir transaksi.</p></div><Switch id={`enabled-${ownerType}`} checked={setting.is_enabled} onCheckedChange={(checked) => updateSetting(ownerType, { is_enabled: checked })} /></div>
            <p className="text-sm text-muted-foreground">Contoh: transaksi Rp20.000 pada tarif 5% memotong Rp1.000.</p>
            <Button onClick={() => void saveSetting(setting)} disabled={saving !== null}><Save className="mr-2 h-4 w-4" />{saving === ownerType ? 'Menyimpan…' : 'Simpan tarif'}</Button>
          </>}
        </CardContent>
      </Card>
    );
  };

  return (
    <AdminLayout title="Komisi Saldo" subtitle="Atur persentase komisi dan verifikasi top-up wallet">
      <div className="mx-auto max-w-6xl space-y-6 p-4 md:p-6">
        <Alert><Percent className="h-4 w-4" /><AlertTitle>Berbeda dari komisi verifikator</AlertTitle><AlertDescription>Komisi ini memotong saldo wallet saat transaksi selesai. Sebelum mengaktifkan tarif, pastikan merchant/ojek sudah mengetahui kebijakan, saldo awal/top-up siap, dan pembayaran tier lama yang masih pending sudah direkonsiliasi. Saldo kuota lama tidak dikonversi; aktivasi tarif pedagang mengalihkan ketersediaan katalog ke wallet dan menghentikan pembelian tier baru. Persetujuan top-up akan langsung mengkredit saldo dan mencatat ledger.</AlertDescription></Alert>
        {loading ? <div className="py-12 text-center text-muted-foreground">Memuat data…</div> : <div className="grid gap-4 md:grid-cols-2">{configCard('MERCHANT')}{configCard('COURIER')}</div>}
        <Card>
          <CardHeader className="flex flex-row items-center justify-between"><div><CardTitle>Permintaan top-up</CardTitle><CardDescription>Verifikasi bukti pembayaran sebelum menyetujui. Saldo dikreditkan sekali secara atomik.</CardDescription></div><Button variant="outline" size="icon" onClick={() => void loadData()} aria-label="Muat ulang"><RefreshCw className="h-4 w-4" /></Button></CardHeader>
          <CardContent>
            {!requests.length ? <p className="py-8 text-center text-sm text-muted-foreground">Belum ada permintaan top-up.</p> : <div className="space-y-3">{requests.map((request) => (
              <div key={request.id} className="space-y-3 rounded-md border p-4">
                <div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex flex-wrap items-center gap-2"><p className="font-semibold">{formatPrice(request.amount_rupiah)}</p><Badge variant={request.status === 'APPROVED' ? 'default' : request.status === 'REJECTED' ? 'destructive' : 'secondary'}>{request.status}</Badge><Badge variant="outline">{request.owner_type === 'MERCHANT' ? 'Pedagang' : 'Ojek'}</Badge></div><p className="mt-1 text-xs text-muted-foreground">ID pemilik: {request.merchant_id ?? request.courier_id} · {new Date(request.created_at).toLocaleString('id-ID')}</p>{request.note && <p className="mt-1 text-sm">Referensi: {request.note}</p>}</div><Button variant="outline" size="sm" onClick={() => void openProof(request.proof_path)}><Eye className="mr-2 h-4 w-4" />Buka bukti</Button></div>
                {request.status === 'PENDING' ? <><Textarea placeholder="Catatan verifikasi/penolakan (opsional)" value={notes[request.id] ?? ''} maxLength={500} onChange={(event) => setNotes((current) => ({ ...current, [request.id]: event.target.value }))} /><div className="flex flex-wrap gap-2"><Button onClick={() => void reviewTopup(request, true)} disabled={processing !== null}><CheckCircle2 className="mr-2 h-4 w-4" />{processing === request.id ? 'Memproses…' : 'Setujui & kreditkan saldo'}</Button><Button variant="destructive" onClick={() => void reviewTopup(request, false)} disabled={processing !== null}><XCircle className="mr-2 h-4 w-4" />Tolak</Button></div></> : request.admin_notes && <p className="text-sm text-muted-foreground">Catatan admin: {request.admin_notes}</p>}
              </div>
            ))}</div>}
          </CardContent>
        </Card>
      </div>
    </AdminLayout>
  );
}
