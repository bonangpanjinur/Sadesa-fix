import { useMemo, useState } from 'react';
import { CheckCircle2, Clock3, CircleDollarSign, FileClock, RefreshCw, ShieldCheck, Wallet, XCircle } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { AdminStatePanel } from '@/components/admin/AdminPagePrimitives';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { formatPrice } from '@/lib/utils';

const db = supabase as unknown as { from: typeof supabase.from; rpc: typeof supabase.rpc };

type ServiceRequest = {
  id: string;
  title: string;
  description: string;
  location: string;
  agreed_price: number | null;
  platform_fee: number;
  transfer_fee: number;
  provider_payout: number | null;
  requester_approved: boolean;
  status: string;
  created_at: string;
};
type Payout = { id: string; request_id: string; gross_amount: number; platform_fee: number; transfer_fee: number; net_amount: number; status: string; released_at: string | null; created_at: string; note: string | null };
type Proof = { request_id: string; status: string; amount: number; created_at: string };

const money = (value: number | null | undefined) => formatPrice(Number(value || 0));
const statusMeta: Record<string, { label: string; tone: 'default' | 'secondary' | 'destructive' | 'outline'; icon: typeof Clock3 }> = {
  NEGOTIATING: { label: 'Negosiasi', tone: 'secondary', icon: FileClock },
  WAITING_PAYMENT: { label: 'Menunggu pembayaran', tone: 'secondary', icon: Clock3 },
  PAID_TO_ADMIN: { label: 'Dana masuk admin', tone: 'default', icon: ShieldCheck },
  APPROVED_TO_START: { label: 'Disetujui mulai', tone: 'default', icon: CheckCircle2 },
  IN_PROGRESS: { label: 'Sedang dikerjakan', tone: 'outline', icon: Clock3 },
  WAITING_CONFIRMATION: { label: 'Menunggu konfirmasi', tone: 'outline', icon: FileClock },
  COMPLETED: { label: 'Selesai', tone: 'default', icon: CheckCircle2 },
  DISPUTED: { label: 'Dalam sengketa', tone: 'destructive', icon: XCircle },
  CANCELLED: { label: 'Dibatalkan', tone: 'destructive', icon: XCircle },
  REFUNDED: { label: 'Direfund', tone: 'secondary', icon: XCircle },
};

function ServiceProviderHistoryContent() {
  const { user } = useAuth();
  const [refreshKey, setRefreshKey] = useState(0);
  const [finishingId, setFinishingId] = useState<string | null>(null);
  const [priceDrafts, setPriceDrafts] = useState<Record<string, string>>({});
  const [pricingId, setPricingId] = useState<string | null>(null);
  const { data, isLoading, isError } = useQuery<{ requests: ServiceRequest[]; payouts: Payout[]; proofs: Proof[] }>({
    queryKey: ['service-provider-history', user?.id, refreshKey],
    enabled: Boolean(user),
    queryFn: async () => {
      const { data: requests, error: requestError } = await db.from('service_requests').select('id,title,description,location,agreed_price,platform_fee,transfer_fee,provider_payout,status,created_at').eq('provider_id', user!.id).order('created_at', { ascending: false });
      if (requestError) throw requestError;
      const requestIds = (requests || []).map((request: ServiceRequest) => request.id);
      if (requestIds.length === 0) return { requests: [], payouts: [], proofs: [] };
      const [{ data: payouts, error: payoutError }, { data: proofs, error: proofError }] = await Promise.all([
        db.from('service_payouts').select('id,request_id,gross_amount,platform_fee,transfer_fee,net_amount,status,released_at,created_at,note').in('request_id', requestIds).order('created_at', { ascending: false }),
        db.from('service_payment_proofs').select('request_id,status,amount,created_at').in('request_id', requestIds).order('created_at', { ascending: false }),
      ]);
      if (payoutError || proofError) throw payoutError || proofError;
      return { requests: requests || [], payouts: payouts || [], proofs: proofs || [] };
    },
    staleTime: 30000,
  });

  const payoutsByRequest = useMemo(() => new Map((data?.payouts || []).map((payout) => [payout.request_id, payout])), [data?.payouts]);
  const latestProofByRequest = useMemo(() => new Map((data?.proofs || []).map((proof) => [proof.request_id, proof])), [data?.proofs]);
  const completedPayouts = (data?.payouts || []).filter((payout) => payout.status === 'RELEASED');
  const totalGross = completedPayouts.reduce((sum, payout) => sum + Number(payout.gross_amount || 0), 0);
  const totalFees = completedPayouts.reduce((sum, payout) => sum + Number(payout.platform_fee || 0) + Number(payout.transfer_fee || 0), 0);
  const totalNet = completedPayouts.reduce((sum, payout) => sum + Number(payout.net_amount || 0), 0);

  async function markCompleted(requestId: string) {
    setFinishingId(requestId);
    const { error } = await db.rpc('service_mark_completed', { p_request_id: requestId });
    if (error) toast.error(error.message || 'Gagal mengirim konfirmasi selesai.');
    else { toast.success('Konfirmasi pekerjaan selesai tersimpan.'); setRefreshKey((key) => key + 1); }
    setFinishingId(null);
  }

  async function proposePrice(requestId: string) {
    const price = Number(priceDrafts[requestId]);
    if (!Number.isFinite(price) || price <= 0) return toast.error('Masukkan harga lebih dari nol.');
    setPricingId(requestId);
    const { error } = await db.rpc('service_provider_propose_price', { p_request_id: requestId, p_agreed_price: price });
    if (error) toast.error(error.message || 'Gagal mengirim penawaran harga.');
    else { toast.success('Harga penawaran tersimpan. Menunggu persetujuan requester.'); setPriceDrafts((drafts) => ({ ...drafts, [requestId]: '' })); setRefreshKey((key) => key + 1); }
    setPricingId(null);
  }

  if (isLoading) return <div className="flex min-h-screen items-center justify-center"><div className="flex flex-col items-center gap-3 text-muted-foreground"><RefreshCw className="h-8 w-8 animate-spin text-primary" /><p className="text-sm">Memuat riwayat transaksi...</p></div></div>;
  if (isError) return <div className="mx-auto max-w-2xl p-6"><AdminStatePanel type="error" title="Riwayat gagal dimuat" description="Periksa koneksi atau pastikan migrasi marketplace jasa sudah diterapkan." actionLabel="Coba lagi" onAction={() => setRefreshKey((key) => key + 1)} /></div>;

  return <div className="mobile-shell min-h-screen bg-background pb-28"><Header /><main className="mx-auto max-w-5xl px-4 py-6 sm:px-6"><div className="mb-6 flex flex-col justify-between gap-3 sm:flex-row sm:items-end"><div><p className="text-xs font-bold uppercase tracking-[0.16em] text-emerald-700">Ruang penyedia jasa</p><h1 className="mt-1 font-heading text-3xl font-black">Riwayat transaksi saya</h1><p className="mt-1 text-sm text-muted-foreground">Pantau pekerjaan, dana yang ditahan admin, fee, dan status pencairan.</p></div><Button variant="outline" onClick={() => setRefreshKey((key) => key + 1)} className="gap-2 rounded-full"><RefreshCw className="h-4 w-4" />Segarkan</Button></div>
    <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4"><Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">Total pekerjaan</p><p className="mt-1 text-2xl font-bold">{data?.requests.length || 0}</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">Sudah dicairkan</p><p className="mt-1 text-2xl font-bold text-emerald-700">{money(totalNet)}</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">Gross transaksi</p><p className="mt-1 text-2xl font-bold">{money(totalGross)}</p></CardContent></Card><Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">Fee & transfer</p><p className="mt-1 text-2xl font-bold">{money(totalFees)}</p></CardContent></Card></div>
    {(data?.requests.length || 0) === 0 ? <Card className="rounded-3xl border-dashed"><CardContent className="p-12 text-center"><Wallet className="mx-auto h-10 w-10 text-emerald-600" /><h2 className="mt-3 font-heading text-lg font-bold">Belum ada transaksi jasa</h2><p className="mt-1 text-sm text-muted-foreground">Saat ada pengguna memesan keahlian Anda, statusnya akan muncul di sini.</p></CardContent></Card> : <div className="space-y-4">{data!.requests.map((request) => { const payout = payoutsByRequest.get(request.id); const proof = latestProofByRequest.get(request.id); const meta = statusMeta[request.status] || statusMeta.NEGOTIATING; const StatusIcon = meta.icon; const payoutLabel = payout?.status === 'RELEASED' ? 'Dana sudah dicairkan' : payout?.status === 'PENDING' ? 'Menunggu pencairan admin' : proof?.status === 'VERIFIED' ? 'Dana ditahan admin' : 'Belum ada pembayaran terverifikasi'; return <Card key={request.id} className="rounded-3xl"><CardContent className="p-5"><div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between"><div className="flex gap-3"><div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-emerald-100 text-emerald-700"><StatusIcon className="h-5 w-5" /></div><div><div className="flex flex-wrap items-center gap-2"><h2 className="font-heading text-lg font-extrabold">{request.title}</h2><Badge variant={meta.tone}>{meta.label}</Badge></div><p className="mt-1 text-xs text-muted-foreground">#{request.id.slice(0, 8).toUpperCase()} · {new Date(request.created_at).toLocaleDateString('id-ID')} · {request.location}</p><p className="mt-3 max-w-2xl text-sm text-muted-foreground">{request.description}</p></div></div><div className="rounded-2xl bg-emerald-50 px-4 py-3 lg:min-w-48 lg:text-right"><p className="text-[10px] font-bold uppercase tracking-wide text-emerald-700">Status dana</p><p className="mt-1 text-sm font-bold text-emerald-950">{payoutLabel}</p><p className="mt-1 text-xs text-emerald-800">{payout ? money(payout.net_amount) : money(request.provider_payout || request.agreed_price)}</p></div></div><div className="mt-5 grid gap-3 border-t pt-4 text-sm sm:grid-cols-4"><div><p className="text-xs text-muted-foreground">Harga deal</p><p className="font-semibold">{money(request.agreed_price)}</p></div><div><p className="text-xs text-muted-foreground">Fee admin</p><p className="font-semibold">{money(payout?.platform_fee || request.platform_fee)}</p></div><div><p className="text-xs text-muted-foreground">Biaya transfer</p><p className="font-semibold">{money(payout?.transfer_fee || request.transfer_fee)}</p></div><div><p className="text-xs text-muted-foreground">Diterima bersih</p><p className="font-semibold text-emerald-700">{money(payout?.net_amount || request.provider_payout)}</p></div></div>{request.status === 'NEGOTIATING' && !request.agreed_price && <div className="mt-4 flex gap-2"><Input type="number" min="1" value={priceDrafts[request.id] || ''} onChange={(event) => setPriceDrafts((drafts) => ({ ...drafts, [request.id]: event.target.value }))} placeholder="Harga penawaran (Rp)" /><Button onClick={() => void proposePrice(request.id)} disabled={pricingId === request.id}>{pricingId === request.id ? 'Mengirim...' : 'Kirim harga'}</Button></div>}{['APPROVED_TO_START','IN_PROGRESS','WAITING_CONFIRMATION'].includes(request.status) && !request.provider_completed && <Button onClick={() => void markCompleted(request.id)} disabled={finishingId === request.id} className="mt-4 gap-2 rounded-full bg-emerald-700 hover:bg-emerald-800"><CheckCircle2 className="h-4 w-4" />{finishingId === request.id ? 'Menyimpan...' : 'Konfirmasi pekerjaan selesai'}</Button>}{request.provider_completed && <div className="mt-4 flex items-center gap-2 rounded-xl bg-emerald-50 px-3 py-2 text-xs text-emerald-800"><CheckCircle2 className="h-4 w-4" />Konfirmasi penyedia sudah tersimpan.</div>}{payout?.status === 'RELEASED' && <div className="mt-4 flex items-center gap-2 rounded-xl bg-emerald-50 px-3 py-2 text-xs text-emerald-800"><CheckCircle2 className="h-4 w-4" />Dicairkan pada {new Date(payout.released_at || payout.created_at).toLocaleString('id-ID')}{payout.note ? ` · ${payout.note}` : ''}</div>}</CardContent></Card>; })}</div>}
  </main><BottomNav /></div>;
}

export default function ServiceProviderHistoryPage() { return <ProtectedRoute><ServiceProviderHistoryContent /></ProtectedRoute>; }
