import { useCallback, useEffect, useState } from 'react';
import { toast } from 'sonner';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';

type Role = 'VERIFIKATOR' | 'ADMIN_DESA';
type Setting = { owner_role: Role; commission_percent: number; is_enabled: boolean };
type Payout = { id: string; owner_user_id: string; owner_role: Role; amount_rupiah: number; bank_name: string; account_number: string; account_holder: string; status: string; payout_reference: string | null; admin_notes: string | null; created_at: string };
type LedgerRow = { id: string; owner_user_id: string; owner_role: Role; merchant_id: string | null; entry_type: string; amount_rupiah: number; fee_collected_base_rupiah: number; commission_percent: number; release_at: string; created_at: string; note: string | null };
const money = (value: number) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Math.round(value || 0));

export default function AdminReferralCommissionsPage() {
  const [settings, setSettings] = useState<Setting[]>([]);
  const [percentages, setPercentages] = useState<Record<Role, string>>({ VERIFIKATOR: '0', ADMIN_DESA: '0' });
  const [enabled, setEnabled] = useState<Record<Role, boolean>>({ VERIFIKATOR: false, ADMIN_DESA: false });
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [ledger, setLedger] = useState<LedgerRow[]>([]);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [references, setReferences] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [settingsReady, setSettingsReady] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    const [settingsResult, payoutsResult, ledgerResult] = await Promise.all([
      (supabase as any).from('merchant_referral_commission_settings').select('*').order('owner_role'),
      (supabase as any).from('merchant_referral_payout_requests').select('*').order('created_at', { ascending: false }).limit(200),
      (supabase as any).from('merchant_referral_commission_ledger').select('*').order('created_at', { ascending: false }).limit(100),
    ]);
    const nextSettings = (settingsResult.data || []) as Setting[];
    const hasBothSettings = (['VERIFIKATOR', 'ADMIN_DESA'] as Role[]).every(role => nextSettings.some(item => item.owner_role === role));
    setSettingsReady(!settingsResult.error && hasBothSettings);
    if (settingsResult.error) toast.error(settingsResult.error.message);
    else if (!hasBothSettings) toast.error('Pengaturan referral belum lengkap. Pastikan bundle SQL 92 sudah diterapkan.');
    setSettings(nextSettings);
    setPercentages({
      VERIFIKATOR: String(nextSettings.find(item => item.owner_role === 'VERIFIKATOR')?.commission_percent ?? 0),
      ADMIN_DESA: String(nextSettings.find(item => item.owner_role === 'ADMIN_DESA')?.commission_percent ?? 0),
    });
    setEnabled({
      VERIFIKATOR: nextSettings.find(item => item.owner_role === 'VERIFIKATOR')?.is_enabled ?? false,
      ADMIN_DESA: nextSettings.find(item => item.owner_role === 'ADMIN_DESA')?.is_enabled ?? false,
    });
    if (payoutsResult.error) toast.error(payoutsResult.error.message); else setPayouts((payoutsResult.data || []) as Payout[]);
    if (ledgerResult.error) toast.error(ledgerResult.error.message); else setLedger((ledgerResult.data || []) as LedgerRow[]);
    setLoading(false);
  }, []);
  useEffect(() => { void loadData(); }, [loadData]);

  const saveSettings = async (role: Role) => {
    if (!settingsReady) return toast.error('Pengaturan belum berhasil dimuat; coba muat ulang sebelum menyimpan.');
    const rate = Number(percentages[role]);
    if (!Number.isFinite(rate) || rate < 0 || rate > 100) return toast.error('Tarif harus antara 0 sampai 100 persen');
    setBusy(`setting-${role}`);
    const { error } = await (supabase as any).from('merchant_referral_commission_settings').update({ commission_percent: rate, is_enabled: enabled[role], updated_by: (await supabase.auth.getUser()).data.user?.id ?? null, updated_at: new Date().toISOString() }).eq('owner_role', role);
    setBusy(null);
    if (error) return toast.error(error.message);
    toast.success(`Pengaturan ${role === 'VERIFIKATOR' ? 'verifikator' : 'admin desa'} disimpan`); await loadData();
  };
  const processPayout = async (item: Payout, status: 'APPROVED' | 'REJECTED' | 'PAID') => {
    if (status === 'PAID' && !references[item.id]?.trim()) return toast.error('Masukkan referensi transfer sebelum menandai dibayar');
    if (status === 'PAID' && !window.confirm(`Konfirmasi payout ${money(item.amount_rupiah)} ke ${item.bank_name} ${item.account_number} a.n. ${item.account_holder}, referensi ${references[item.id]?.trim()}?`)) return;
    setBusy(item.id);
    const { error } = await (supabase as any).rpc('process_merchant_referral_payout', {
      p_request_id: item.id,
      p_status: status,
      p_admin_notes: notes[item.id] || null,
      p_payout_reference: status === 'PAID' ? references[item.id]?.trim() : null,
    });
    setBusy(null);
    if (error) return toast.error(error.message);
    toast.success(status === 'PAID' ? 'Payout ditandai sudah dibayar' : status === 'APPROVED' ? 'Permintaan disetujui' : 'Permintaan ditolak'); await loadData();
  };

  return (
    <AdminLayout title="Komisi Referral Merchant" subtitle="Tarif referral dari fee merchant tertagih dan payout untuk verifikator/admin desa">
      <div className="space-y-6 p-4 lg:p-8">
        {!loading && !settingsReady && <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-destructive/40 bg-destructive/5 p-4 text-sm"><span>Pengaturan tarif referral tidak lengkap atau gagal dimuat. Penyimpanan dinonaktifkan agar nilai default tidak menimpa tarif tersimpan.</span><Button variant="outline" size="sm" onClick={() => void loadData()}>Coba muat ulang</Button></div>}
        <div className="rounded-lg border bg-muted/30 p-4 text-sm text-muted-foreground">
          Basis komisi adalah <strong>fee platform pedagang yang benar-benar berhasil dipotong/ditagih dari wallet</strong>. Tarif disimpan sebagai snapshot pada transaksi; mengubah tarif hanya berdampak pada fee berikutnya. Refund mengurangi komisi referral secara proporsional. Payout manual harus disertai nomor referensi transfer.
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          {(['VERIFIKATOR', 'ADMIN_DESA'] as Role[]).map(role => <Card key={role}>
            <CardHeader><CardTitle>{role === 'VERIFIKATOR' ? 'Verifikator' : 'Admin Desa'}</CardTitle><CardDescription>Tarif bagi hasil atas fee merchant yang tertagih.</CardDescription></CardHeader>
            <CardContent className="space-y-4">
              <div className="flex flex-wrap items-end gap-4">
                <div className="w-40 space-y-1"><Label htmlFor={`rate-${role}`}>Persentase referral</Label><div className="flex items-center gap-2"><Input id={`rate-${role}`} type="number" min="0" max="100" step="0.01" value={percentages[role]} disabled={loading || !settingsReady || busy === `setting-${role}`} onChange={e => setPercentages(current => ({ ...current, [role]: e.target.value }))} /><span>%</span></div></div>
                <label className="mb-2 flex items-center gap-2 text-sm"><input type="checkbox" checked={enabled[role]} disabled={loading || !settingsReady || busy === `setting-${role}`} onChange={e => setEnabled(current => ({ ...current, [role]: e.target.checked }))} />Aktifkan komisi referral</label>
                <Button onClick={() => void saveSettings(role)} disabled={loading || !settingsReady || busy === `setting-${role}`}>Simpan</Button>
              </div>
              <p className="text-xs text-muted-foreground">Tarif tersimpan: {settings.find(item => item.owner_role === role)?.commission_percent ?? 0}% · {(settings.find(item => item.owner_role === role)?.is_enabled ?? false) ? 'aktif' : 'nonaktif'}</p>
            </CardContent>
          </Card>)}
        </div>

        <Card><CardHeader><CardTitle>Permintaan payout</CardTitle><CardDescription>Urut terbaru dahulu. Status “Dibayar” hanya dapat dicatat setelah transaksi bank manual selesai.</CardDescription></CardHeader>
          <CardContent>{loading ? <p className="text-sm text-muted-foreground">Memuat...</p> : payouts.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada permintaan.</p> : <div className="space-y-4">{payouts.map(item => <div key={item.id} className="rounded-lg border p-4">
            <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-semibold">{money(item.amount_rupiah)} · {item.owner_role === 'VERIFIKATOR' ? 'Verifikator' : 'Admin Desa'}</p><p className="text-xs text-muted-foreground">User {item.owner_user_id} · {new Date(item.created_at).toLocaleString('id-ID')}</p><p className="mt-2">{item.bank_name} · {item.account_number} · a.n. {item.account_holder}</p></div><Badge variant={item.status === 'PAID' ? 'default' : item.status === 'REJECTED' ? 'destructive' : 'secondary'}>{item.status}</Badge></div>
            {item.payout_reference && <p className="mt-2 text-sm">Referensi: {item.payout_reference}</p>}
            {item.status !== 'PAID' && item.status !== 'REJECTED' && <div className="mt-4 grid gap-3 md:grid-cols-2"><div className="space-y-1"><Label>Catatan admin</Label><Textarea rows={2} value={notes[item.id] ?? item.admin_notes ?? ''} onChange={e => setNotes(current => ({ ...current, [item.id]: e.target.value }))} maxLength={1000} /></div>{item.status === 'APPROVED' && <div className="space-y-1"><Label>Referensi transfer (wajib untuk dibayar)</Label><Input value={references[item.id] || ''} onChange={e => setReferences(current => ({ ...current, [item.id]: e.target.value }))} maxLength={200} placeholder="No. transaksi bank" /></div>}
            <div className="flex flex-wrap gap-2 md:col-span-2">{item.status === 'PENDING' && <><Button size="sm" onClick={() => void processPayout(item, 'APPROVED')} disabled={busy === item.id}>Setujui</Button><Button size="sm" variant="destructive" onClick={() => void processPayout(item, 'REJECTED')} disabled={busy === item.id}>Tolak</Button></>}{item.status === 'APPROVED' && <><Button size="sm" onClick={() => void processPayout(item, 'PAID')} disabled={busy === item.id}>Catat sudah dibayar</Button><Button size="sm" variant="destructive" onClick={() => void processPayout(item, 'REJECTED')} disabled={busy === item.id}>Tolak / batalkan</Button></>}</div></div>}
          </div>)}</div>}</CardContent>
        </Card>

        <Card><CardHeader><CardTitle>Ledger referral terbaru</CardTitle><CardDescription>Riwayat accrual, reversal refund, dan payout yang tercatat.</CardDescription></CardHeader>
          <CardContent>{ledger.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada ledger komisi.</p> : <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Waktu</th><th className="p-2">Pemilik</th><th className="p-2">Tipe</th><th className="p-2">Fee tertagih</th><th className="p-2">Tarif</th><th className="p-2">Nilai</th><th className="p-2">Rilis</th></tr></thead><tbody>{ledger.map(item => <tr key={item.id} className="border-b"><td className="p-2 whitespace-nowrap">{new Date(item.created_at).toLocaleString('id-ID')}</td><td className="p-2">{item.owner_role}<br /><span className="text-xs text-muted-foreground">{item.owner_user_id}</span></td><td className="p-2">{item.entry_type}</td><td className="p-2">{money(item.fee_collected_base_rupiah)}</td><td className="p-2">{item.commission_percent}%</td><td className="p-2">{money(item.amount_rupiah)}</td><td className="p-2">{new Date(item.release_at).toLocaleDateString('id-ID')}</td></tr>)}</tbody></table></div>}</CardContent>
        </Card>
      </div>
    </AdminLayout>
  );
}
