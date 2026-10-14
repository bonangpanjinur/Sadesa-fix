import { useCallback, useEffect, useState } from 'react';
import { Clock3, Copy, Landmark, Plus, Store, Wallet } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

type OwnerRole = 'VERIFIKATOR' | 'ADMIN_DESA';
type Summary = { commission_percent: number; is_enabled: boolean; pending_rupiah: number; available_rupiah: number; reserved_rupiah: number; net_rupiah: number };
type ReferralCode = { id: string; code: string; description: string | null; is_active: boolean; usage_count: number; max_usage: number | null; created_at: string };
type Entry = { id: string; entry_type: string; amount_rupiah: number; fee_collected_base_rupiah: number; commission_percent: number; release_at: string; note: string | null; created_at: string };
type Payout = { id: string; amount_rupiah: number; bank_name: string; account_number: string; account_holder: string; status: string; admin_notes: string | null; payout_reference: string | null; created_at: string };
type ReferredMerchant = { merchant_id: string; merchant_name: string; registration_status: string; fee_collected_rupiah: number; referral_earned_rupiah: number; recorded_fee_transactions: number };
const money = (value: number) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Math.round(value || 0));
const statusLabel: Record<string, string> = { PENDING: 'Menunggu', APPROVED: 'Disetujui', PAID: 'Dibayar', REJECTED: 'Ditolak' };

export function ReferralCommissionPanel({ ownerRole }: { ownerRole: OwnerRole }) {
  const { user } = useAuth();
  const [summary, setSummary] = useState<Summary | null>(null);
  const [codes, setCodes] = useState<ReferralCode[]>([]);
  const [entries, setEntries] = useState<Entry[]>([]);
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [merchants, setMerchants] = useState<ReferredMerchant[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [code, setCode] = useState('');
  const [description, setDescription] = useState('');
  const [amount, setAmount] = useState('');
  const [bankName, setBankName] = useState('');
  const [accountNumber, setAccountNumber] = useState('');
  const [accountHolder, setAccountHolder] = useState('');

  const refresh = useCallback(async () => {
    if (!user?.id) return;
    setLoading(true);
    const [summaryResult, codeResult, ledgerResult, payoutResult, merchantsResult] = await Promise.all([
      supabase.rpc('get_merchant_referral_commission_summary' as never, { p_owner_role: ownerRole } as never),
      supabase.from('merchant_referral_codes' as never).select('id,code,description,is_active,usage_count,max_usage,created_at').eq('owner_user_id', user.id).eq('owner_role', ownerRole).order('created_at', { ascending: false }),
      supabase.from('merchant_referral_commission_ledger' as never).select('id,entry_type,amount_rupiah,fee_collected_base_rupiah,commission_percent,release_at,note,created_at').eq('owner_user_id', user.id).eq('owner_role', ownerRole).order('created_at', { ascending: false }).limit(50),
      supabase.from('merchant_referral_payout_requests' as never).select('id,amount_rupiah,bank_name,account_number,account_holder,status,admin_notes,payout_reference,created_at').eq('owner_user_id', user.id).eq('owner_role', ownerRole).order('created_at', { ascending: false }).limit(20),
      supabase.rpc('get_merchant_referral_merchants' as never, { p_owner_role: ownerRole } as never),
    ]);
    if (summaryResult.error) toast.error(summaryResult.error.message);
    setSummary((summaryResult.data || null) as Summary | null);
    if (codeResult.error) toast.error(codeResult.error.message); else setCodes((codeResult.data || []) as ReferralCode[]);
    if (ledgerResult.error) toast.error(ledgerResult.error.message); else setEntries((ledgerResult.data || []) as Entry[]);
    if (payoutResult.error) toast.error(payoutResult.error.message); else setPayouts((payoutResult.data || []) as Payout[]);
    if (merchantsResult.error) toast.error(merchantsResult.error.message); else setMerchants((merchantsResult.data || []) as ReferredMerchant[]);
    setLoading(false);
  }, [ownerRole, user?.id]);
  useEffect(() => { void refresh(); }, [refresh]);

  const createCode = async () => {
    if (!code.trim()) return toast.error('Isi kode referral terlebih dahulu');
    setSaving(true);
    const { error } = await supabase.rpc('create_admin_desa_referral_code' as never, { p_code: code.trim().toUpperCase(), p_description: description.trim() || null } as never);
    setSaving(false);
    if (error) return toast.error(error.message);
    toast.success('Kode referral admin desa berhasil dibuat'); setCode(''); setDescription(''); await refresh();
  };
  const toggleCode = async (item: ReferralCode) => {
    const { error } = await supabase.from('merchant_referral_codes' as never).update({ is_active: !item.is_active }).eq('id', item.id).eq('owner_user_id', user?.id);
    if (error) return toast.error(error.message);
    toast.success(item.is_active ? 'Kode dinonaktifkan' : 'Kode diaktifkan'); await refresh();
  };
  const requestPayout = async () => {
    const numericAmount = Math.floor(Number(amount));
    if (!numericAmount || numericAmount < 10000) return toast.error('Minimum penarikan Rp10.000');
    setSaving(true);
    const { error } = await supabase.rpc('create_merchant_referral_payout_request' as never, {
      p_owner_role: ownerRole, p_amount_rupiah: numericAmount, p_bank_name: bankName,
      p_account_number: accountNumber, p_account_holder: accountHolder,
    } as never);
    setSaving(false);
    if (error) return toast.error(error.message);
    toast.success('Permintaan payout dikirim untuk ditinjau admin');
    setAmount(''); setBankName(''); setAccountNumber(''); setAccountHolder(''); await refresh();
  };
  const copyCode = async (value: string) => {
    try { await navigator.clipboard.writeText(value); toast.success('Kode disalin'); }
    catch { toast.error('Tidak dapat menyalin kode'); }
  };

  return (
    <div className="space-y-6">
      <div className="rounded-lg border bg-muted/30 p-4 text-sm text-muted-foreground">
        Komisi referral dihitung dari <strong>fee platform merchant yang benar-benar tertagih</strong>, bukan omzet atau nilai penjualan. Fee yang belum dibayar karena saldo wallet tidak cukup belum menghasilkan komisi referral. Komisi menunggu masa refund yang berlaku sebelum tersedia untuk ditarik.
      </div>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card><CardHeader className="pb-2"><CardDescription>Tarif referral saat ini</CardDescription><CardTitle>{summary?.commission_percent ?? 0}%</CardTitle></CardHeader><CardContent><Badge variant={summary?.is_enabled ? 'default' : 'secondary'}>{summary?.is_enabled ? 'Aktif' : 'Nonaktif'}</Badge></CardContent></Card>
        <Card><CardHeader className="pb-2"><CardDescription>Menunggu masa refund</CardDescription><CardTitle className="text-xl">{money(summary?.pending_rupiah ?? 0)}</CardTitle></CardHeader><CardContent className="text-xs text-muted-foreground">Belum dapat ditarik</CardContent></Card>
        <Card><CardHeader className="pb-2"><CardDescription>Tersedia untuk payout</CardDescription><CardTitle className="text-xl">{money(summary?.available_rupiah ?? 0)}</CardTitle></CardHeader><CardContent className="text-xs text-muted-foreground">Setelah reservasi payout</CardContent></Card>
        <Card><CardHeader className="pb-2"><CardDescription>Payout sedang diproses</CardDescription><CardTitle className="text-xl">{money(summary?.reserved_rupiah ?? 0)}</CardTitle></CardHeader><CardContent className="text-xs text-muted-foreground">Permintaan menunggu/disetujui</CardContent></Card>
      </div>

      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><Wallet className="h-5 w-5" />Kode referral saya</CardTitle><CardDescription>Pedagang yang mendaftar dengan kode ini akan tercatat sebagai referral Anda.</CardDescription></CardHeader>
        <CardContent className="space-y-4">
          {ownerRole === 'ADMIN_DESA' && <div className="grid gap-3 rounded-md border p-3 md:grid-cols-[1fr_1fr_auto]">
            <div className="space-y-1"><Label htmlFor="ref-code">Kode baru</Label><Input id="ref-code" value={code} onChange={e => setCode(e.target.value.toUpperCase())} maxLength={32} placeholder="Contoh: DESA-MAJU" /></div>
            <div className="space-y-1"><Label htmlFor="ref-description">Keterangan (opsional)</Label><Input id="ref-description" value={description} onChange={e => setDescription(e.target.value)} maxLength={160} placeholder="Mis. promosi UMKM desa" /></div>
            <Button className="self-end" onClick={() => void createCode()} disabled={saving}><Plus className="mr-2 h-4 w-4" />Buat kode</Button>
          </div>}
          {loading ? <p className="text-sm text-muted-foreground">Memuat kode...</p> : codes.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada kode referral yang terhubung.</p> : <div className="divide-y rounded-md border">
            {codes.map(item => <div key={item.id} className="flex flex-wrap items-center justify-between gap-3 p-3">
              <div><div className="flex items-center gap-2 font-mono font-semibold">{item.code}<Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => void copyCode(item.code)} aria-label="Salin kode"><Copy className="h-3.5 w-3.5" /></Button></div><p className="text-xs text-muted-foreground">Terpakai {item.usage_count}{item.max_usage ? ` dari ${item.max_usage}` : ''}{item.description ? ` · ${item.description}` : ''}</p></div>
              <div className="flex items-center gap-2"><Badge variant={item.is_active ? 'default' : 'secondary'}>{item.is_active ? 'Aktif' : 'Nonaktif'}</Badge>{ownerRole === 'ADMIN_DESA' && <Button variant="outline" size="sm" onClick={() => void toggleCode(item)}>{item.is_active ? 'Nonaktifkan' : 'Aktifkan'}</Button>}</div>
            </div>)}
          </div>}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><Landmark className="h-5 w-5" />Ajukan payout</CardTitle><CardDescription>Minimum Rp10.000. Admin akan meninjau, melakukan transfer, lalu mencatat referensi pembayaran.</CardDescription></CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
            <div className="space-y-1"><Label htmlFor="payout-amount">Nominal (Rp)</Label><Input id="payout-amount" type="number" min={10000} step={1000} value={amount} onChange={e => setAmount(e.target.value)} /></div>
            <div className="space-y-1"><Label htmlFor="bank-name">Bank</Label><Input id="bank-name" value={bankName} onChange={e => setBankName(e.target.value)} maxLength={80} /></div>
            <div className="space-y-1"><Label htmlFor="account-number">Nomor rekening</Label><Input id="account-number" value={accountNumber} onChange={e => setAccountNumber(e.target.value)} maxLength={80} /></div>
            <div className="space-y-1"><Label htmlFor="account-holder">Nama pemilik rekening</Label><Input id="account-holder" value={accountHolder} onChange={e => setAccountHolder(e.target.value)} maxLength={120} /></div>
            <Button className="self-end" onClick={() => void requestPayout()} disabled={saving || loading || (summary?.available_rupiah ?? 0) < 10000}><Landmark className="mr-2 h-4 w-4" />Ajukan</Button>
          </div>
          <div className="rounded-md bg-muted/40 p-3 text-xs text-muted-foreground">Pastikan informasi rekening benar. Permintaan akan mengurangi saldo tersedia sementara hingga disetujui/dibayar atau ditolak.</div>
        </CardContent>
      </Card>

      <Card><CardHeader><CardTitle className="flex items-center gap-2"><Store className="h-5 w-5" />Pedagang referral</CardTitle><CardDescription>Hanya menampilkan pedagang yang secara eksplisit mendaftar dengan kode Anda.</CardDescription></CardHeader><CardContent>
        {merchants.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada pedagang yang terhubung dengan kode referral Anda.</p> : <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-2">Pedagang</th><th className="p-2">Status</th><th className="p-2 text-right">Fee tertagih</th><th className="p-2 text-right">Komisi referral</th><th className="p-2 text-right">Fee events</th></tr></thead><tbody>{merchants.map(item => <tr key={item.merchant_id} className="border-b"><td className="p-2">{item.merchant_name}</td><td className="p-2">{item.registration_status}</td><td className="p-2 text-right">{money(item.fee_collected_rupiah)}</td><td className="p-2 text-right">{money(item.referral_earned_rupiah)}</td><td className="p-2 text-right">{item.recorded_fee_transactions}</td></tr>)}</tbody></table></div>}
      </CardContent></Card>

      <div className="grid gap-6 xl:grid-cols-2">
        <Card><CardHeader><CardTitle>Riwayat komisi referral</CardTitle></CardHeader><CardContent>
          {entries.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada pencatatan komisi referral.</p> : <div className="space-y-3">{entries.map(item => <div key={item.id} className="flex items-start justify-between gap-3 border-b pb-3 last:border-0"><div><p className="font-medium">{item.entry_type === 'EARNING' ? 'Komisi fee tertagih' : item.entry_type === 'REFUND_REVERSAL' ? 'Pembalikan karena refund' : 'Payout'}{item.commission_percent > 0 ? ` · ${item.commission_percent}%` : ''}</p><p className="text-xs text-muted-foreground">{item.note || new Date(item.created_at).toLocaleString('id-ID')} · {item.entry_type === 'EARNING' && new Date(item.release_at) > new Date() ? 'Menunggu masa refund' : 'Dicatat'}</p></div><span className={item.amount_rupiah < 0 ? 'font-semibold text-destructive' : 'font-semibold'}>{money(item.amount_rupiah)}</span></div>)}</div>}
        </CardContent></Card>
        <Card><CardHeader><CardTitle className="flex items-center gap-2"><Clock3 className="h-5 w-5" />Riwayat payout</CardTitle></CardHeader><CardContent>
          {payouts.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada permintaan payout.</p> : <div className="space-y-3">{payouts.map(item => <div key={item.id} className="border-b pb-3 last:border-0"><div className="flex justify-between gap-3"><div><p className="font-medium">{money(item.amount_rupiah)} · {item.bank_name}</p><p className="text-xs text-muted-foreground">{item.account_number} a.n. {item.account_holder}</p></div><Badge variant={item.status === 'PAID' ? 'default' : item.status === 'REJECTED' ? 'destructive' : 'secondary'}>{statusLabel[item.status] || item.status}</Badge></div>{item.payout_reference && <p className="mt-1 text-xs">Referensi transfer: {item.payout_reference}</p>}{item.admin_notes && <p className="mt-1 text-xs text-muted-foreground">Catatan: {item.admin_notes}</p>}</div>)}</div>}
        </CardContent></Card>
      </div>
    </div>
  );
}
