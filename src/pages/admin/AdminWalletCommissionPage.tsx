import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowDownToLine, ArrowRight, CheckCircle2, ClipboardCheck, Download, Eye, Percent, RefreshCw, Save, WalletCards, XCircle } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Link } from 'react-router-dom';
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
import { COMMISSION_WALLET_LEDGER_PAGE_SIZE, commissionWalletLedgerCursorFilter, hasNextCommissionWalletLedgerPage, type CommissionWalletLedgerCursor } from '@/lib/commissionWalletLedger';
import { toast } from 'sonner';

type OwnerType = 'MERCHANT' | 'COURIER';
type FeeSetting = { owner_type: OwnerType; fee_percent: number; is_enabled: boolean; charge_courier_delivery: boolean; updated_at: string };
type TopupRequest = { id: string; owner_type: OwnerType; merchant_id: string | null; courier_id: string | null; amount_rupiah: number; proof_path: string | null; note: string | null; status: string; admin_notes: string | null; created_at: string; payment_provider: string; payment_status: string; payment_invoice_url: string | null };
type PolicySetting = { refund_window_days: number; low_balance_threshold_rupiah: number };
type WalletAccount = { id: string; owner_type: OwnerType; merchant_id: string | null; courier_id: string | null; balance_rupiah: number; debt_rupiah: number; is_active: boolean; updated_at: string };
type LedgerRow = { id: string; wallet_id: string; entry_type: string; source_type: string; source_id: string | null; amount_delta_rupiah: number; debt_delta_rupiah: number; base_amount_rupiah: number | null; fee_percent: number | null; note: string | null; created_at: string };

const defaultPolicy: PolicySetting = { refund_window_days: 7, low_balance_threshold_rupiah: 10_000 };

export default function AdminWalletCommissionPage() {
  const [settings, setSettings] = useState<FeeSetting[]>([]);
  const [requests, setRequests] = useState<TopupRequest[]>([]);
  const [wallets, setWallets] = useState<WalletAccount[]>([]);
  const [ledger, setLedger] = useState<LedgerRow[]>([]);
  const [ledgerCount, setLedgerCount] = useState(0);
  const [ledgerPage, setLedgerPage] = useState(0);
  const [ledgerCursors, setLedgerCursors] = useState<Array<CommissionWalletLedgerCursor | null>>([null]);
  const ledgerCursor = ledgerCursors[ledgerPage] ?? null;
  const [policy, setPolicy] = useState<PolicySetting>(defaultPolicy);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<OwnerType | 'POLICY' | null>(null);
  const [processing, setProcessing] = useState<string | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});

  const loadData = useCallback(async () => {
    setLoading(true);
    const [feeResult, requestResult, walletResult, ledgerResult, policyResult] = await Promise.all([
      supabase.from('commission_fee_settings' as never).select('*'),
      supabase.from('commission_wallet_topup_requests' as never).select('*').order('created_at' as never, { ascending: false } as never).limit(100),
      supabase.from('commission_wallets' as never).select('id,owner_type,merchant_id,courier_id,balance_rupiah,debt_rupiah,is_active,updated_at').order('updated_at' as never, { ascending: false } as never).limit(1000),
      (() => {
        let query = supabase.from('commission_wallet_ledger' as never)
          .select('id,wallet_id,entry_type,source_type,source_id,amount_delta_rupiah,debt_delta_rupiah,base_amount_rupiah,fee_percent,note,created_at', { count: 'exact' });
        if (ledgerCursor) query = query.or(commissionWalletLedgerCursorFilter(ledgerCursor) as never);
        return query.order('created_at' as never, { ascending: false } as never)
          .order('id' as never, { ascending: false } as never)
          .limit(COMMISSION_WALLET_LEDGER_PAGE_SIZE);
      })(),
      supabase.from('commission_wallet_policy_settings' as never).select('refund_window_days,low_balance_threshold_rupiah').eq('id' as never, true as never).maybeSingle(),
    ]);
    if (feeResult.error) {
      console.error('Gagal memuat tarif komisi wallet:', feeResult.error);
      toast.error('Pengaturan komisi belum tersedia. Terapkan migration wallet lebih dahulu.');
    } else setSettings((feeResult.data ?? []) as unknown as FeeSetting[]);
    if (requestResult.error) {
      console.error('Gagal memuat permintaan top-up:', requestResult.error);
      toast.error('Gagal memuat antrean top-up. Pastikan migration top-up diterapkan.');
    } else setRequests((requestResult.data ?? []) as unknown as TopupRequest[]);
    if (walletResult.error) console.error('Gagal memuat wallet:', walletResult.error);
    else setWallets((walletResult.data ?? []) as unknown as WalletAccount[]);
    if (ledgerResult.error) console.error('Gagal memuat ledger:', ledgerResult.error);
    else {
      setLedger((ledgerResult.data ?? []) as unknown as LedgerRow[]);
      setLedgerCount(ledgerResult.count ?? 0);
    }
    if (policyResult.error) console.error('Gagal memuat kebijakan wallet:', policyResult.error);
    else {
      const policyData = (policyResult as unknown as { data: PolicySetting | null }).data;
      if (policyData) setPolicy(policyData);
    }
    setLoading(false);
  }, [ledgerCursor]);

  useEffect(() => { void loadData(); }, [loadData]);

  const summary = useMemo(() => ({
    balance: wallets.reduce((sum, wallet) => sum + Number(wallet.balance_rupiah || 0), 0),
    debt: wallets.reduce((sum, wallet) => sum + Number(wallet.debt_rupiah || 0), 0),
    low: wallets.filter((wallet) => wallet.is_active && Number(wallet.balance_rupiah || 0) <= Number(policy.low_balance_threshold_rupiah || 0)).length,
    ready: wallets.filter((wallet) => wallet.is_active && Number(wallet.balance_rupiah || 0) > 0 && Number(wallet.debt_rupiah || 0) === 0).length,
    pending: requests.filter((request) => request.status === 'PENDING').length,
  }), [wallets, policy.low_balance_threshold_rupiah, requests]);

  const scrollToSection = (id: string) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });

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
      .update({ fee_percent: percent, is_enabled: setting.is_enabled, charge_courier_delivery: setting.charge_courier_delivery, updated_by: (await supabase.auth.getUser()).data.user?.id ?? null, updated_at: new Date().toISOString() } as never)
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

  const savePolicy = async () => {
    const days = Number(policy.refund_window_days);
    const threshold = Number(policy.low_balance_threshold_rupiah);
    if (!Number.isInteger(days) || days < 1 || days > 365 || !Number.isSafeInteger(threshold) || threshold < 0) {
      toast.error('Jendela refund harus 1–365 hari dan ambang saldo harus Rp0 atau lebih');
      return;
    }
    setSaving('POLICY');
    const { error } = await supabase.from('commission_wallet_policy_settings' as never)
      .update({ refund_window_days: days, low_balance_threshold_rupiah: threshold, updated_by: (await supabase.auth.getUser()).data.user?.id ?? null, updated_at: new Date().toISOString() } as never)
      .eq('id' as never, true as never);
    if (error) toast.error(error.message || 'Gagal menyimpan kebijakan wallet');
    else { toast.success('Kebijakan wallet berhasil disimpan'); await loadData(); }
    setSaving(null);
  };

  const reviewTopup = async (request: TopupRequest, approve: boolean) => {
    if (request.payment_provider !== 'MANUAL' || !request.proof_path) {
      toast.error('Invoice Xendit diproses otomatis dari webhook dan tidak dapat disetujui manual.');
      return;
    }
    const action = approve ? 'menyetujui dan mengkredit saldo' : 'menolak';
    if (!window.confirm(`Yakin ${action} top-up ${formatPrice(request.amount_rupiah)}? Periksa bukti transfer sebelum menyetujui.`)) return;
    setProcessing(request.id);
    const { error } = await supabase.rpc('process_commission_wallet_topup' as never, {
      p_request_id: request.id, p_approve: approve, p_admin_notes: notes[request.id]?.trim() || null,
    } as never);
    if (error) {
      console.error('Gagal memproses top-up:', error);
      toast.error(error.message || 'Gagal memproses top-up');
    } else {
      toast.success(approve ? 'Top-up disetujui; tagihan lama dilunasi lebih dahulu bila ada' : 'Top-up ditolak');
      await loadData();
    }
    setProcessing(null);
  };

  const openProof = async (proofPath: string | null) => {
    if (!proofPath) return;
    const { data, error } = await supabase.storage.from('commission-topup-proofs').createSignedUrl(proofPath, 300);
    if (error || !data?.signedUrl) { toast.error('Bukti tidak dapat dibuka'); return; }
    window.open(data.signedUrl, '_blank', 'noopener,noreferrer');
  };

  const exportLedger = () => {
    const rows = [['created_at', 'wallet_id', 'entry_type', 'source_type', 'source_id', 'balance_delta_rupiah', 'debt_delta_rupiah', 'base_amount_rupiah', 'fee_percent', 'note'], ...ledger.map((entry) => [entry.created_at, entry.wallet_id, entry.entry_type, entry.source_type, entry.source_id ?? '', entry.amount_delta_rupiah, entry.debt_delta_rupiah, entry.base_amount_rupiah ?? '', entry.fee_percent ?? '', entry.note ?? ''])];
    const csv = rows.map((row) => row.map((cell) => `"${String(cell).replaceAll('"', '""')}"`).join(',')).join('\r\n');
    const url = URL.createObjectURL(new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a'); link.href = url; link.download = `commission-wallet-ledger-${new Date().toISOString().slice(0, 10)}-page-${ledgerPage + 1}.csv`; link.click(); URL.revokeObjectURL(url);
  };

  const goToNextLedgerPage = () => {
    const lastEntry = ledger[ledger.length - 1];
    if (!lastEntry || !hasNextCommissionWalletLedgerPage(ledgerCount, ledger.length)) return;
    setLedgerCursors((current) => [...current.slice(0, ledgerPage + 1), { created_at: lastEntry.created_at, id: lastEntry.id }]);
    setLedgerPage((current) => current + 1);
  };

  const configCard = (ownerType: OwnerType) => {
    const setting = settings.find((item) => item.owner_type === ownerType);
    const label = ownerType === 'MERCHANT' ? 'Pedagang' : 'Ojek';
    return (
      <Card key={ownerType}>
        <CardHeader><CardTitle>{label}</CardTitle><CardDescription>{ownerType === 'MERCHANT' ? 'Basis: subtotal produk pada order, tidak termasuk ongkir.' : 'Basis: tarif final perjalanan. Pengiriman barang memakai estimasi penghasilan courier (fallback ongkir) bila diaktifkan.'}</CardDescription></CardHeader>
        <CardContent className="space-y-5">
          {!setting ? <p className="text-sm text-muted-foreground">Konfigurasi belum dibuat di database.</p> : <>
            <div className="space-y-2"><Label htmlFor={`fee-${ownerType}`}>Persentase komisi</Label><div className="flex max-w-xs items-center gap-2"><Input id={`fee-${ownerType}`} type="number" min="0" max="100" step="0.01" value={setting.fee_percent} onChange={(event) => updateSetting(ownerType, { fee_percent: Number(event.target.value) })} /><span className="text-sm">%</span></div></div>
            <div className="flex items-center justify-between gap-3 rounded-md border p-3"><div><Label htmlFor={`enabled-${ownerType}`}>Aktifkan pemotongan</Label><p className="text-xs text-muted-foreground">Transaksi selesai tetap tercatat jika saldo kurang; kekurangan menjadi tagihan dan aktivitas baru ditahan sampai lunas.</p></div><Switch id={`enabled-${ownerType}`} checked={setting.is_enabled} onCheckedChange={(checked) => updateSetting(ownerType, { is_enabled: checked })} /></div>
            {ownerType === 'COURIER' && <div className="flex items-center justify-between gap-3 rounded-md border p-3"><div><Label htmlFor="courier-delivery-fee">Kenakan juga pada pengiriman barang</Label><p className="text-xs text-muted-foreground">Tarif ojek yang sama dikenakan atas penghasilan courier dari pengiriman marketplace/paket.</p></div><Switch id="courier-delivery-fee" checked={setting.charge_courier_delivery} onCheckedChange={(checked) => updateSetting(ownerType, { charge_courier_delivery: checked })} /></div>}
            <p className="text-sm text-muted-foreground">Contoh: transaksi Rp20.000 pada tarif 5% memotong Rp1.000.</p>
            <Button onClick={() => void saveSetting(setting)} disabled={saving !== null}><Save className="mr-2 h-4 w-4" />{saving === ownerType ? 'Menyimpan…' : 'Simpan tarif'}</Button>
          </>}
        </CardContent>
      </Card>
    );
  };

  return (
    <AdminLayout title="Komisi Saldo" subtitle="Tarif, saldo, tunggakan, refund, dan top-up wallet">
      <div className="mx-auto max-w-6xl space-y-6 p-4 md:p-6">
        <Alert className="border-primary/20 bg-primary/5"><Percent className="h-4 w-4" /><AlertTitle>Peralihan dari paket kuota</AlertTitle><AlertDescription className="flex flex-col items-start gap-2 sm:flex-row sm:items-center sm:justify-between"><span>Saldo kuota lama tidak dikonversi. Rekonsiliasi permintaan legacy sebelum cutover; wallet baru hanya bertambah lewat top-up atau kredit yang terverifikasi.</span><Button asChild variant="link" size="sm" className="h-auto shrink-0 p-0"><Link to="/admin/transaction-quota">Buka histori legacy <ArrowRight className="h-4 w-4" /></Link></Button></AlertDescription></Alert>
        <Card className="border-primary/20">
          <CardHeader className="pb-3"><CardTitle className="text-lg">Alur aman sebelum komisi diaktifkan</CardTitle><CardDescription>Top-up dianjurkan lebih dulu agar akun tetap memenuhi syarat dan tidak menimbulkan tagihan.</CardDescription></CardHeader>
          <CardContent className="grid gap-4 md:grid-cols-3">
            <div className="rounded-lg border p-4"><div className="mb-2 flex items-center gap-2 font-semibold"><ClipboardCheck className="h-4 w-4 text-primary" />1. Rekonsiliasi legacy</div><p className="mb-3 text-sm text-muted-foreground">Selesaikan pemeriksaan pembayaran paket lama sebelum cutover. Saldo kuota tidak dipindahkan.</p><Button asChild variant="outline" size="sm"><Link to="/admin/transaction-quota">Tinjau permintaan lama</Link></Button></div>
            <div className="rounded-lg border p-4"><div className="mb-2 flex items-center gap-2 font-semibold"><WalletCards className="h-4 w-4 text-primary" />2. Danai wallet</div><p className="mb-3 text-sm text-muted-foreground">Pedagang dan ojek mengajukan top-up di halaman wallet mereka. Admin verifikasi bukti transfer manual di bawah.</p><Button variant="outline" size="sm" onClick={() => scrollToSection('wallet-topups')}>Lihat antrean top-up <ArrowDownToLine className="h-4 w-4" /></Button></div>
            <div className="rounded-lg border p-4"><div className="mb-2 flex items-center gap-2 font-semibold"><Percent className="h-4 w-4 text-primary" />3. Atur komisi</div><p className="mb-3 text-sm text-muted-foreground">Pastikan tarif dan kebijakan sesuai persetujuan bisnis. Tarif awal 0% dan nonaktif.</p><Button variant="outline" size="sm" onClick={() => scrollToSection('commission-fee-settings')}>Atur tarif <ArrowRight className="h-4 w-4" /></Button></div>
          </CardContent>
          <div className="border-t px-6 py-3 text-sm text-muted-foreground">Jika saldo tidak cukup saat transaksi selesai, sistem mencatat kekurangan sebagai tagihan. Akun yang berutang tidak dapat memulai aktivitas baru sampai tagihan dilunasi lewat top-up.</div>
        </Card>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <Card><CardHeader className="pb-2"><CardDescription>Total saldo tersedia</CardDescription><CardTitle>{formatPrice(summary.balance)}</CardTitle></CardHeader></Card>
          <Card><CardHeader className="pb-2"><CardDescription>Total tagihan komisi</CardDescription><CardTitle className="text-destructive">{formatPrice(summary.debt)}</CardTitle></CardHeader></Card>
          <Card><CardHeader className="pb-2"><CardDescription>Wallet aktif siap digunakan</CardDescription><CardTitle>{summary.ready}</CardTitle><CardDescription className="text-xs">Saldo positif dan tidak ada tagihan</CardDescription></CardHeader></Card>
          <Card><CardHeader className="pb-2"><CardDescription>Saldo rendah atau nol</CardDescription><CardTitle>{summary.low}</CardTitle><CardDescription className="text-xs">Wallet aktif pada/di bawah ambang {formatPrice(policy.low_balance_threshold_rupiah)}</CardDescription></CardHeader></Card>
        </div>
        <div id="commission-fee-settings" className="scroll-mt-24">
          <div className="mb-3"><h2 className="text-xl font-semibold">Tarif komisi</h2><p className="text-sm text-muted-foreground">Perubahan tarif berlaku pada transaksi baru setelah disimpan.</p></div>
          {loading ? <div className="py-12 text-center text-muted-foreground">Memuat data…</div> : <div className="grid gap-4 md:grid-cols-2">{configCard('MERCHANT')}{configCard('COURIER')}</div>}
        </div>
        <Card>
          <CardHeader><CardTitle>Kebijakan wallet</CardTitle><CardDescription>Jendela pengajuan refund dan ambang notifikasi saldo dapat diubah tanpa migration.</CardDescription></CardHeader>
          <CardContent className="grid gap-4 md:grid-cols-3 md:items-end">
            <div className="space-y-2"><Label htmlFor="refund-window">Batas pengajuan refund (hari)</Label><Input id="refund-window" type="number" min="1" max="365" value={policy.refund_window_days} onChange={(event) => setPolicy((current) => ({ ...current, refund_window_days: Number(event.target.value) }))} /></div>
            <div className="space-y-2"><Label htmlFor="low-balance-threshold">Ambang saldo rendah (Rp)</Label><Input id="low-balance-threshold" type="number" min="0" step="1000" value={policy.low_balance_threshold_rupiah} onChange={(event) => setPolicy((current) => ({ ...current, low_balance_threshold_rupiah: Number(event.target.value) }))} /></div>
            <Button onClick={() => void savePolicy()} disabled={saving !== null}><Save className="mr-2 h-4 w-4" />{saving === 'POLICY' ? 'Menyimpan…' : 'Simpan kebijakan'}</Button>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between"><div><CardTitle>Wallet dan tunggakan</CardTitle><CardDescription>Owner dengan utang tidak dapat menerima transaksi/penugasan baru; top-up melunasi tunggakan lebih dahulu.</CardDescription></div></CardHeader>
          <CardContent>
            {!wallets.length ? <p className="py-6 text-center text-sm text-muted-foreground">Belum ada wallet terdaftar.</p> : <div className="space-y-2">{wallets.map((wallet) => <div key={wallet.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3 text-sm"><div><p className="font-medium">{wallet.owner_type === 'MERCHANT' ? 'Pedagang' : 'Ojek'} · {wallet.merchant_id ?? wallet.courier_id}</p><p className="text-xs text-muted-foreground">Wallet {wallet.is_active ? 'aktif' : 'nonaktif'} · diperbarui {new Date(wallet.updated_at).toLocaleString('id-ID')}</p></div><div className="flex flex-wrap gap-2"><Badge variant="outline">Saldo {formatPrice(wallet.balance_rupiah)}</Badge><Badge variant={Number(wallet.debt_rupiah) > 0 ? 'destructive' : 'secondary'}>Tagihan {formatPrice(wallet.debt_rupiah)}</Badge>{Number(wallet.balance_rupiah) <= policy.low_balance_threshold_rupiah && <Badge variant="outline">Saldo rendah</Badge>}</div></div>)}</div>}
          </CardContent>
        </Card>
        <Card id="wallet-topups">
          <CardHeader className="flex flex-row items-center justify-between"><div><CardTitle>Permintaan top-up ({summary.pending} menunggu)</CardTitle><CardDescription>Transfer manual perlu diverifikasi; invoice Xendit hanya dikreditkan dari callback provider yang valid.</CardDescription></div><Button variant="outline" size="icon" onClick={() => void loadData()} aria-label="Muat ulang"><RefreshCw className="h-4 w-4" /></Button></CardHeader>
          <CardContent>
            {!requests.length ? <p className="py-8 text-center text-sm text-muted-foreground">Belum ada permintaan top-up.</p> : <div className="space-y-3">{requests.map((request) => (
              <div key={request.id} className="space-y-3 rounded-md border p-4">
                <div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex flex-wrap items-center gap-2"><p className="font-semibold">{formatPrice(request.amount_rupiah)}</p><Badge variant={request.status === 'APPROVED' ? 'default' : request.status === 'REJECTED' ? 'destructive' : 'secondary'}>{request.status}</Badge><Badge variant="outline">{request.owner_type === 'MERCHANT' ? 'Pedagang' : 'Ojek'}</Badge><Badge variant="outline">{request.payment_provider} · {request.payment_status}</Badge></div><p className="mt-1 text-xs text-muted-foreground">ID pemilik: {request.merchant_id ?? request.courier_id} · {new Date(request.created_at).toLocaleString('id-ID')}</p>{request.note && <p className="mt-1 text-sm">Referensi: {request.note}</p>}{request.payment_invoice_url && <a className="text-sm text-primary underline" href={request.payment_invoice_url} target="_blank" rel="noreferrer">Buka invoice Xendit</a>}</div>{request.proof_path && <Button variant="outline" size="sm" onClick={() => void openProof(request.proof_path)}><Eye className="mr-2 h-4 w-4" />Buka bukti</Button>}</div>
                {request.status === 'PENDING' && request.payment_provider === 'MANUAL' ? <><Textarea placeholder="Catatan verifikasi/penolakan (opsional)" value={notes[request.id] ?? ''} maxLength={500} onChange={(event) => setNotes((current) => ({ ...current, [request.id]: event.target.value }))} /><div className="flex flex-wrap gap-2"><Button onClick={() => void reviewTopup(request, true)} disabled={processing !== null}><CheckCircle2 className="mr-2 h-4 w-4" />{processing === request.id ? 'Memproses…' : 'Setujui & kreditkan saldo'}</Button><Button variant="destructive" onClick={() => void reviewTopup(request, false)} disabled={processing !== null}><XCircle className="mr-2 h-4 w-4" />Tolak</Button></div></> : request.status === 'PENDING' ? <p className="text-sm text-muted-foreground">Menunggu pembayaran Xendit; saldo belum dikreditkan.</p> : request.admin_notes && <p className="text-sm text-muted-foreground">Catatan: {request.admin_notes}</p>}
              </div>
            ))}</div>}
          </CardContent>
        </Card>
        <Card><CardHeader className="flex flex-row items-start justify-between gap-3"><div><CardTitle>Ledger terbaru</CardTitle><CardDescription>Halaman {ledgerPage + 1}; memuat {ledger.length} dari {ledgerCount} mutasi pada halaman ini dan sesudahnya. CSV mengekspor halaman aktif.</CardDescription></div><Button variant="outline" onClick={exportLedger} disabled={!ledger.length}><Download className="mr-2 h-4 w-4" />Ekspor halaman CSV</Button></CardHeader><CardContent>{ledger.length ? <><div className="space-y-2">{ledger.map((entry) => <div key={entry.id} className="flex flex-wrap items-center justify-between gap-2 border-b py-2 text-sm last:border-0"><div><p className="font-medium">{entry.entry_type} · {entry.source_type}</p><p className="text-xs text-muted-foreground">{entry.wallet_id} · {new Date(entry.created_at).toLocaleString('id-ID')}</p></div><div className="text-right"><p>Saldo: {formatPrice(entry.amount_delta_rupiah)}</p><p className={entry.debt_delta_rupiah > 0 ? 'text-xs text-destructive' : 'text-xs text-muted-foreground'}>Tagihan: {formatPrice(entry.debt_delta_rupiah)}</p></div></div>)}</div><div className="mt-4 flex items-center justify-between border-t pt-3"><Button variant="outline" onClick={() => setLedgerPage((current) => Math.max(0, current - 1))} disabled={loading || ledgerPage === 0}>Sebelumnya</Button><span className="text-xs text-muted-foreground">{COMMISSION_WALLET_LEDGER_PAGE_SIZE} mutasi per halaman</span><Button variant="outline" onClick={goToNextLedgerPage} disabled={loading || !hasNextCommissionWalletLedgerPage(ledgerCount, ledger.length)}>Berikutnya</Button></div></> : <p className="py-6 text-center text-sm text-muted-foreground">Belum ada mutasi.</p>}</CardContent></Card>
      </div>
    </AdminLayout>
  );
}
