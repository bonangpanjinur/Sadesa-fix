import { useCallback, useEffect, useMemo, useState } from 'react';
import { Check, CircleDollarSign, Download, Eye, FileCheck2, RefreshCw, ShieldCheck, Wallet, Wrench, X } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { AdminStatePanel } from '@/components/admin/AdminPagePrimitives';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';
import { logAdminAction } from '@/lib/auditLog';
import { getPaymentProofSignedUrl } from '@/lib/paymentProof';

const db = supabase as unknown as { from: typeof supabase.from; rpc: typeof supabase.rpc };
type Proof = {
  id: string;
  request_id: string;
  amount: number;
  transfer_reference: string | null;
  proof_url: string | null;
  proof_path?: string | null;
  status: 'PENDING' | 'VERIFIED' | 'REJECTED';
  admin_note: string | null;
  created_at: string;
  request?: { id: string; title: string; description: string; location: string; agreed_price: number | null; platform_fee: number; transfer_fee: number; provider_payout: number | null; status: string; provider_id: string; requester_id: string };
};

type Payout = {
  id: string;
  request_id: string;
  gross_amount: number;
  platform_fee: number;
  transfer_fee: number;
  net_amount: number;
  status: 'RELEASED' | 'PENDING' | 'FAILED';
  note: string | null;
  external_transfer_reference?: string | null;
  created_at: string;
  released_at: string | null;
  request?: { title: string; location: string; status: string; provider_id: string; provider_payout: number | null };
};
type ProviderProfile = { id: string; provider_id: string; provider_name: string; headline: string; bio: string | null; village: string | null; min_price: number; created_at: string; verification_status: string; service_skills?: { subcategory_id: string; service_subcategories?: { name: string }[] | null }[] };

const money = (value: number | null | undefined) => formatPrice(Number(value || 0));
const shortId = (id: string) => id.slice(0, 8).toUpperCase();

function MonthlyReport({ proofs, payouts }: { proofs: Proof[]; payouts: Payout[] }) {
  const [month, setMonth] = useState(() => new Date().toISOString().slice(0, 7));
  const report = useMemo(() => {
    const paid = proofs.filter((proof) => proof.status === 'VERIFIED' && proof.created_at.slice(0, 7) === month);
    const monthPayouts = payouts.filter((payout) => (payout.released_at || payout.created_at).slice(0, 7) === month);
    const totalTransactions = paid.reduce((sum, proof) => sum + Number(proof.amount || 0), 0);
    const gross = monthPayouts.reduce((sum, payout) => sum + Number(payout.gross_amount || 0), 0);
    const platformFee = monthPayouts.reduce((sum, payout) => sum + Number(payout.platform_fee || 0), 0);
    const transferFee = monthPayouts.reduce((sum, payout) => sum + Number(payout.transfer_fee || 0), 0);
    const providerNet = monthPayouts.reduce((sum, payout) => sum + Number(payout.net_amount || 0), 0);
    return { paid, monthPayouts, totalTransactions, gross, platformFee, transferFee, providerNet };
  }, [month, proofs, payouts]);

  const exportCsv = () => {
    const rows = report.paid.map((proof) => {
      const payout = report.monthPayouts.find((item) => item.request_id === proof.request_id);
      return [proof.created_at, proof.request_id, proof.request?.title || '', proof.amount, payout?.platform_fee || 0, payout?.transfer_fee || 0, payout?.net_amount || 0, payout?.status || 'HELD'];
    });
    const csv = [['Tanggal', 'Request ID', 'Pekerjaan', 'Total Transaksi', 'Fee Admin', 'Biaya Transfer', 'Bersih Penyedia', 'Status'], ...rows]
      .map((row) => row.map((value) => `"${String(value).replaceAll('"', '""')}"`).join(',')).join('\n');
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    link.download = `laporan-jasa-${month}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
  };

  return <div className="space-y-5">
    <div className="flex flex-col justify-between gap-3 rounded-xl border bg-muted/20 p-4 sm:flex-row sm:items-center"><div><p className="font-semibold">Periode laporan</p><p className="text-xs text-muted-foreground">Rekap berdasarkan bukti transfer terverifikasi dan payout jasa.</p></div><div className="flex gap-2"><input type="month" value={month} onChange={(event) => setMonth(event.target.value)} className="h-9 rounded-md border border-input bg-background px-3 text-sm" /><Button variant="outline" size="sm" onClick={exportCsv} className="gap-2"><Download className="h-4 w-4" />CSV</Button></div></div>
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4"><Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">Total transaksi jasa</p><p className="mt-1 text-xl font-bold">{money(report.totalTransactions)}</p><p className="text-xs text-muted-foreground">{report.paid.length} transaksi dibayar</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">Potongan fee admin</p><p className="mt-1 text-xl font-bold text-emerald-700">{money(report.platformFee)}</p><p className="text-xs text-muted-foreground">Fee platform bulan ini</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">Biaya transfer</p><p className="mt-1 text-xl font-bold">{money(report.transferFee)}</p><p className="text-xs text-muted-foreground">Dibebankan pada payout</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">Diteruskan ke penyedia</p><p className="mt-1 text-xl font-bold">{money(report.providerNet)}</p><p className="text-xs text-muted-foreground">Gross payout {money(report.gross)}</p></CardContent></Card></div>
    {report.paid.length === 0 ? <AdminStatePanel type="empty" title="Belum ada transaksi pada bulan ini" description="Pilih bulan lain atau tunggu bukti transfer terverifikasi." /> : <div className="overflow-x-auto rounded-xl border"><table className="w-full min-w-[720px] text-sm"><thead className="bg-muted/40 text-left"><tr><th className="p-3 font-semibold">Tanggal</th><th className="p-3 font-semibold">Pekerjaan</th><th className="p-3 text-right font-semibold">Transaksi</th><th className="p-3 text-right font-semibold">Fee admin</th><th className="p-3 text-right font-semibold">Bersih penyedia</th><th className="p-3 font-semibold">Status</th></tr></thead><tbody>{report.paid.map((proof) => { const payout = report.monthPayouts.find((item) => item.request_id === proof.request_id); return <tr key={proof.id} className="border-t"><td className="p-3 text-muted-foreground">{new Date(proof.created_at).toLocaleDateString('id-ID')}</td><td className="p-3"><p className="font-medium">{proof.request?.title || `Request #${shortId(proof.request_id)}`}</p><p className="text-xs text-muted-foreground">#{shortId(proof.request_id)}</p></td><td className="p-3 text-right font-medium">{money(proof.amount)}</td><td className="p-3 text-right">{money(payout?.platform_fee)}</td><td className="p-3 text-right">{money(payout?.net_amount)}</td><td className="p-3"><Badge variant={payout?.status === 'RELEASED' ? 'default' : 'secondary'}>{payout?.status || 'DANA DITAHAN'}</Badge></td></tr>; })}</tbody></table></div>}
  </div>;
}

function ServiceFinanceSettings() {
  const [feePercent, setFeePercent] = useState('5');
  const [bankName, setBankName] = useState('');
  const [accountNumber, setAccountNumber] = useState('');
  const [accountName, setAccountName] = useState('');
  const [qrisUrl, setQrisUrl] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    void (async () => {
      const { data } = await supabase.from('app_settings').select('key,value').in('key', ['service_platform_fee', 'admin_payment_info']);
      for (const item of data || []) {
        const value = item.value as Record<string, unknown>;
        if (item.key === 'service_platform_fee' && typeof value.percent === 'number') setFeePercent(String(value.percent));
        if (item.key === 'admin_payment_info') {
          setBankName(String(value.bank_name || ''));
          setAccountNumber(String(value.bank_account_number || ''));
          setAccountName(String(value.bank_account_name || ''));
          setQrisUrl(String(value.qris_image_url || ''));
        }
      }
    })();
  }, []);

  async function save() {
    const fee = Number(feePercent);
    if (!Number.isFinite(fee) || fee < 0 || fee > 100) return toast.error('Fee jasa harus di antara 0–100%.');
    if (!bankName.trim() || !accountNumber.trim() || !accountName.trim()) return toast.error('Lengkapi bank, nomor rekening, dan nama pemilik rekening.');
    setSaving(true);
    const { error } = await supabase.from('app_settings').upsert([
      { key: 'service_platform_fee', value: { percent: fee }, category: 'payment', description: 'Fee platform transaksi jasa' },
      { key: 'admin_payment_info', value: { bank_name: bankName.trim(), bank_account_number: accountNumber.trim(), bank_account_name: accountName.trim(), qris_image_url: qrisUrl.trim() }, category: 'payment', description: 'Rekening admin untuk pembayaran jasa manual' },
    ], { onConflict: 'key' });
    setSaving(false);
    if (error) toast.error(error.message || 'Pengaturan jasa gagal disimpan.');
    else toast.success('Fee dan rekening pembayaran jasa tersimpan.');
  }

  return <Card className="mb-6"><CardHeader><CardTitle>Pengaturan keuangan jasa</CardTitle><p className="text-sm text-muted-foreground">Fee ini dipakai server saat provider mengirim penawaran baru. Rekening ditampilkan kepada buyer saat pembayaran manual.</p></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 sm:grid-cols-4"><div><label className="text-sm font-medium">Fee platform (%)</label><Input type="number" min="0" max="100" step="0.01" value={feePercent} onChange={(event) => setFeePercent(event.target.value)} /></div><div><label className="text-sm font-medium">Nama bank</label><Input value={bankName} onChange={(event) => setBankName(event.target.value)} placeholder="BCA / BRI / ..." /></div><div><label className="text-sm font-medium">Nomor rekening</label><Input value={accountNumber} onChange={(event) => setAccountNumber(event.target.value)} /></div><div><label className="text-sm font-medium">Nama pemilik</label><Input value={accountName} onChange={(event) => setAccountName(event.target.value)} /></div></div><div className="flex flex-col gap-3 sm:flex-row sm:items-end"><div className="flex-1"><label className="text-sm font-medium">URL QRIS (opsional)</label><Input value={qrisUrl} onChange={(event) => setQrisUrl(event.target.value)} placeholder="https://..." /></div><Button onClick={() => void save()} disabled={saving}>{saving ? 'Menyimpan...' : 'Simpan pengaturan'}</Button></div></CardContent></Card>;
}

export default function AdminServicesPage() {
  const [proofs, setProofs] = useState<Proof[]>([]);
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [providerProfiles, setProviderProfiles] = useState<ProviderProfile[]>([]);
  const [providerNotes, setProviderNotes] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [selectedProof, setSelectedProof] = useState<Proof | null>(null);
  const [selectedProofUrl, setSelectedProofUrl] = useState<string | null>(null);
  const [loadingProofUrl, setLoadingProofUrl] = useState(false);
  const [selectedPayout, setSelectedPayout] = useState<Payout | null>(null);
  const [note, setNote] = useState('');
  const [actionLoading, setActionLoading] = useState(false);

  const loadData = useCallback(async (refresh = false) => {
    if (refresh) setRefreshing(true); else setLoading(true);
    const [proofResult, payoutResult, providerResult] = await Promise.all([
      db.from('service_payment_proofs').select('*,request:service_requests(id,title,description,location,agreed_price,platform_fee,transfer_fee,provider_payout,status,provider_id,requester_id)').order('created_at', { ascending: false }),
      db.from('service_payouts').select('*,request:service_requests(title,location,status,provider_id,provider_payout)').order('status', { ascending: true }).order('created_at', { ascending: false }),
      db.from('service_profiles').select('id,provider_id,provider_name,headline,bio,village,min_price,created_at,verification_status,service_skills(subcategory_id,service_subcategories(name))').eq('verification_status', 'PENDING').order('created_at', { ascending: true }),
    ]);
    if (proofResult.error || payoutResult.error || providerResult.error) {
      toast.error('Gagal memuat escrow jasa. Pastikan migrasi database sudah diterapkan.');
    } else {
      setProofs(proofResult.data || []);
      setProviderProfiles(providerResult.data || []);
      setPayouts(payoutResult.data || []);
    }
    setLoading(false); setRefreshing(false);
  }, []);

  useEffect(() => { void loadData(); }, [loadData]);

  const pendingProofs = useMemo(() => proofs.filter((proof) => proof.status === 'PENDING'), [proofs]);
  const readyPayouts = useMemo(() => payouts.filter((payout) => payout.status === 'PENDING' && ['WAITING_CONFIRMATION', 'COMPLETED'].includes(payout.request?.status || '')), [payouts]);
  const heldFunds = proofs.filter((proof) => proof.status === 'VERIFIED').reduce((sum, proof) => sum + Number(proof.amount || 0), 0);
  const totalFees = payouts.reduce((sum, payout) => sum + Number(payout.platform_fee || 0), 0);

  async function openProof(proof: Proof) {
    setSelectedProof(proof);
    setSelectedProofUrl(null);
    setLoadingProofUrl(true);
    setNote('');
    const signedUrl = await getPaymentProofSignedUrl(proof.proof_path || proof.proof_url);
    setSelectedProofUrl(signedUrl);
    setLoadingProofUrl(false);
    if (!signedUrl) toast.error('Bukti tidak dapat dibuka. Path mungkin sudah tidak tersedia atau akses ditolak.');
  }

  async function verifyProof(approved: boolean) {
    if (!selectedProof) return;
    setActionLoading(true);
    const status = approved ? 'VERIFIED' : 'REJECTED';
    const { error } = await db.rpc('service_admin_review_payment', { p_proof_id: selectedProof.id, p_approved: approved, p_note: note.trim() || null });
    if (error) toast.error(error.message || 'Gagal memproses bukti transfer');
    else {
      await logAdminAction(approved ? 'VERIFY_SERVICE_PAYMENT' : 'REJECT_SERVICE_PAYMENT', 'service_payment_proof', selectedProof.id, { status: selectedProof.status }, { status, note: note.trim() || null });
      toast.success(approved ? 'Bukti transfer diverifikasi. Penyedia boleh mulai bekerja.' : 'Bukti transfer ditolak.');
      setSelectedProof(null); setNote(''); await loadData(true);
    }
    setActionLoading(false);
  }

  async function releasePayout() {
    if (!selectedPayout || !selectedPayout.request) return;
    const transferReference = note.trim();
    if (transferReference.length < 3) return toast.error('Transfer harus sudah dilakukan; masukkan nomor referensi transfer aktual.');
    setActionLoading(true);
    const gross = Number(selectedPayout.gross_amount || selectedPayout.request.provider_payout || 0);
    const { error } = await db.rpc('service_admin_release_payout', { p_request_id: selectedPayout.request_id, p_external_transfer_reference: transferReference, p_note: null });
    if (error) toast.error(error.message || 'Gagal mencairkan dana');
    else {
      await logAdminAction('RELEASE_SERVICE_PAYOUT', 'service_payout', selectedPayout.id, { status: 'PENDING' }, { status: 'RELEASED', request_id: selectedPayout.request_id });
      toast.success(`Transfer ${money(gross)} dicatat dengan referensi ${transferReference}.`); setSelectedPayout(null); setNote(''); await loadData(true);
    }
    setActionLoading(false);
  }

  async function reviewProvider(profile: ProviderProfile, decision: 'VERIFIED' | 'REJECTED') {
    const reviewNote = providerNotes[profile.id]?.trim() || '';
    if (decision === 'REJECTED' && reviewNote.length < 3) return toast.error('Isi alasan penolakan minimal 3 karakter.');
    setActionLoading(true);
    const { error } = await db.rpc('service_admin_review_provider', { p_profile_id: profile.id, p_decision: decision, p_note: reviewNote || null });
    if (error) toast.error(error.message || 'Gagal menyimpan keputusan verifikasi provider.');
    else {
      await logAdminAction('REVIEW_SERVICE_PROVIDER', 'service_profile', profile.id, { status: 'PENDING' }, { status: decision, note: reviewNote || null });
      toast.success(decision === 'VERIFIED' ? 'Provider diverifikasi dan dapat tampil di katalog.' : 'Provider ditolak; profil dapat diajukan ulang setelah diperbaiki.');
      setProviderNotes((notes) => ({ ...notes, [profile.id]: '' }));
      await loadData(true);
    }
    setActionLoading(false);
  }

  return <AdminLayout title="Escrow Jasa" subtitle="Verifikasi pembayaran pengguna dan cairkan dana penyedia jasa secara terkontrol">
    <div className="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
      <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Bukti menunggu</p><p className="mt-1 text-2xl font-bold text-warning">{pendingProofs.length}</p><p className="text-xs text-muted-foreground">Perlu diverifikasi</p></CardContent></Card>
      <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Dana ditahan</p><p className="mt-1 text-2xl font-bold text-emerald-700">{money(heldFunds)}</p><p className="text-xs text-muted-foreground">Bukti terverifikasi</p></CardContent></Card>
      <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Siap dicairkan</p><p className="mt-1 text-2xl font-bold">{readyPayouts.length}</p><p className="text-xs text-muted-foreground">Pekerjaan selesai</p></CardContent></Card>
      <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Fee platform</p><p className="mt-1 text-2xl font-bold">{money(totalFees)}</p><p className="text-xs text-muted-foreground">Akumulasi payout</p></CardContent></Card>
    </div>

    <ServiceFinanceSettings />

    <Card><CardHeader className="flex-row items-center justify-between space-y-0"><CardTitle className="flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-emerald-700" />Kontrol escrow jasa</CardTitle><Button variant="outline" size="sm" onClick={() => void loadData(true)} disabled={refreshing} className="gap-2"><RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />Segarkan</Button></CardHeader><CardContent>
      {loading ? <AdminStatePanel type="loading" title="Memuat escrow jasa" description="Mengambil bukti transfer dan antrean pencairan." /> : <Tabs defaultValue="proofs"><TabsList className="mb-4"><TabsTrigger value="proofs">Bukti transfer <Badge variant="secondary" className="ml-2">{pendingProofs.length}</Badge></TabsTrigger><TabsTrigger value="payouts">Pencairan <Badge variant="secondary" className="ml-2">{readyPayouts.length}</Badge></TabsTrigger><TabsTrigger value="providers">Provider <Badge variant="secondary" className="ml-2">{providerProfiles.length}</Badge></TabsTrigger><TabsTrigger value="all">Riwayat</TabsTrigger><TabsTrigger value="report">Laporan bulanan</TabsTrigger></TabsList>
        <TabsContent value="proofs"><div className="space-y-3">{pendingProofs.length === 0 ? <AdminStatePanel type="empty" title="Tidak ada bukti transfer tertunda" description="Semua bukti transfer sudah ditangani." /> : pendingProofs.map((proof) => <div key={proof.id} className="flex flex-col gap-4 rounded-xl border p-4 lg:flex-row lg:items-center"><div className="flex-1"><div className="flex flex-wrap items-center gap-2"><Badge variant="warning">PENDING</Badge><span className="font-semibold">{proof.request?.title || `Request #${shortId(proof.request_id)}`}</span></div><p className="mt-1 text-sm text-muted-foreground">{proof.request?.location || '-'} · Transfer {money(proof.amount)}</p><p className="mt-1 text-xs text-muted-foreground">Ref: {proof.transfer_reference || '-'} · {new Date(proof.created_at).toLocaleString('id-ID')}</p></div><Button onClick={() => void openProof(proof)} className="gap-2"><Eye className="h-4 w-4" />Review bukti</Button></div>)}</div></TabsContent>
        <TabsContent value="payouts"><div className="space-y-3">{readyPayouts.length === 0 ? <AdminStatePanel type="empty" title="Belum ada pencairan siap diproses" description="Pencairan tersedia setelah pekerjaan mencapai tahap konfirmasi selesai." /> : readyPayouts.map((payout) => <div key={payout.id} className="flex flex-col gap-4 rounded-xl border p-4 lg:flex-row lg:items-center"><div className="flex-1"><div className="flex flex-wrap items-center gap-2"><Badge variant="outline">SIAP CAIR</Badge><span className="font-semibold">{payout.request?.title || `Request #${shortId(payout.request_id)}`}</span></div><p className="mt-1 text-sm text-muted-foreground">{payout.request?.location || '-'} · Gross {money(payout.gross_amount)}</p><p className="mt-1 text-xs text-muted-foreground">Fee {money(payout.platform_fee)} · Transfer {money(payout.transfer_fee)} · Bersih <b className="text-foreground">{money(payout.net_amount)}</b></p></div><Button onClick={() => { setSelectedPayout(payout); setNote(''); }} className="gap-2 bg-emerald-700 hover:bg-emerald-800"><Wallet className="h-4 w-4" />Cairkan dana</Button></div>)}</div></TabsContent>
        <TabsContent value="providers"><div className="space-y-3">{providerProfiles.length === 0 ? <AdminStatePanel type="empty" title="Tidak ada provider menunggu verifikasi" description="Profil baru akan muncul di sini sebelum ditampilkan ke publik." /> : providerProfiles.map((profile) => <div key={profile.id} className="rounded-xl border p-4"><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div className="flex-1"><div className="flex items-center gap-2"><Wrench className="h-4 w-4 text-emerald-700" /><p className="font-semibold">{profile.provider_name} · {profile.headline}</p></div><p className="mt-1 text-sm text-muted-foreground">{profile.village || 'Area layanan belum diisi'} · Mulai {money(profile.min_price)}</p><p className="mt-2 text-sm">{profile.bio || 'Tidak ada deskripsi.'}</p><p className="mt-2 text-xs text-muted-foreground">Keahlian: {profile.service_skills?.map((skill) => skill.service_subcategories?.[0]?.name).filter(Boolean).join(', ') || 'Belum terhubung'}</p></div><Badge variant="secondary">MENUNGGU REVIEW</Badge></div><div className="mt-3 flex flex-col gap-2 sm:flex-row"><Textarea value={providerNotes[profile.id] || ''} onChange={(event) => setProviderNotes((notes) => ({ ...notes, [profile.id]: event.target.value }))} placeholder="Catatan review / alasan jika ditolak" maxLength={1000} className="min-h-10 sm:flex-1" /><Button onClick={() => void reviewProvider(profile, 'VERIFIED')} disabled={actionLoading} className="gap-2"><Check className="h-4 w-4" />Verifikasi</Button><Button variant="destructive" onClick={() => void reviewProvider(profile, 'REJECTED')} disabled={actionLoading || (providerNotes[profile.id] || '').trim().length < 3} className="gap-2"><X className="h-4 w-4" />Tolak</Button></div></div>)}</div></TabsContent>
        <TabsContent value="all"><div className="space-y-3">{payouts.length === 0 ? <AdminStatePanel type="empty" title="Belum ada riwayat payout" description="Riwayat akan muncul setelah transaksi jasa memiliki payout." /> : payouts.map((payout) => <div key={payout.id} className="flex items-center justify-between rounded-xl border p-4"><div><p className="font-semibold">{payout.request?.title || `Request #${shortId(payout.request_id)}`}</p><p className="text-xs text-muted-foreground">{money(payout.net_amount)} ke penyedia · {payout.request?.status || '-'}</p>{payout.external_transfer_reference && <p className="text-xs text-muted-foreground">Referensi transfer: {payout.external_transfer_reference}</p>}</div><Badge variant={payout.status === 'RELEASED' ? 'default' : 'secondary'}>{payout.status}</Badge></div>)}</div></TabsContent>
        <TabsContent value="report"><MonthlyReport proofs={proofs} payouts={payouts} /></TabsContent>
      </Tabs>}</CardContent></Card>

    {selectedProof && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true"><Card className="w-full max-w-xl"><CardHeader><CardTitle className="flex items-center gap-2"><FileCheck2 className="h-5 w-5 text-emerald-700" />Review bukti transfer</CardTitle></CardHeader><CardContent className="space-y-4"><div className="rounded-xl bg-muted/50 p-4"><p className="font-semibold">{selectedProof.request?.title || `Request #${shortId(selectedProof.request_id)}`}</p><p className="mt-1 text-sm text-muted-foreground">Nominal transfer: <b className="text-foreground">{money(selectedProof.amount)}</b></p><p className="text-sm text-muted-foreground">Referensi: {selectedProof.transfer_reference || '-'}</p>{loadingProofUrl ? <p className="mt-3 text-sm text-muted-foreground">Menyiapkan tautan bukti aman...</p> : selectedProofUrl ? <a href={selectedProofUrl} target="_blank" rel="noreferrer" className="mt-3 inline-flex items-center gap-2 text-sm font-bold text-primary underline">Buka bukti transfer <Eye className="h-4 w-4" /></a> : <p className="mt-3 text-sm text-destructive">Bukti privat tidak tersedia untuk dibuka.</p>}</div><Textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="Catatan admin, wajib diisi jika menolak" maxLength={1000} /><div className="flex justify-end gap-2"><Button variant="outline" onClick={() => { setSelectedProof(null); setSelectedProofUrl(null); }} disabled={actionLoading}>Batal</Button><Button variant="destructive" onClick={() => void verifyProof(false)} disabled={actionLoading || !note.trim()}><X className="mr-2 h-4 w-4" />Tolak</Button><Button onClick={() => void verifyProof(true)} disabled={actionLoading}><Check className="mr-2 h-4 w-4" />Verifikasi</Button></div></CardContent></Card></div>}
    {selectedPayout && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true"><Card className="w-full max-w-xl"><CardHeader><CardTitle className="flex items-center gap-2"><CircleDollarSign className="h-5 w-5 text-emerald-700" />Catat transfer payout manual</CardTitle></CardHeader><CardContent className="space-y-4"><div className="rounded-xl bg-emerald-50 p-4"><p className="font-semibold">{selectedPayout.request?.title || `Request #${shortId(selectedPayout.request_id)}`}</p><p className="mt-1 text-xs text-emerald-900">Lakukan transfer di kanal bank/gateway terlebih dahulu. Formulir ini hanya mencatat transfer yang sudah berhasil.</p><div className="mt-3 grid grid-cols-3 gap-2 text-sm"><div><p className="text-muted-foreground">Gross</p><b>{money(selectedPayout.gross_amount)}</b></div><div><p className="text-muted-foreground">Fee platform</p><b>{money(selectedPayout.platform_fee)}</b></div><div><p className="text-muted-foreground">Diteruskan</p><b className="text-emerald-700">{money(selectedPayout.net_amount)}</b></div></div></div><Textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="Nomor referensi transfer aktual (wajib)" maxLength={200} /><div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setSelectedPayout(null)} disabled={actionLoading}>Batal</Button><Button onClick={() => void releasePayout()} disabled={actionLoading || note.trim().length < 3} className="bg-emerald-700 hover:bg-emerald-800"><Wallet className="mr-2 h-4 w-4" />Catat transfer selesai</Button></div></CardContent></Card></div>}
  </AdminLayout>;
}
