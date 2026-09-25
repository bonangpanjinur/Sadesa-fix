import { useEffect, useState } from 'react';
import { CheckCircle2, FileClock, Loader2, MessageCircle, Receipt, ShieldCheck, Upload, Wallet } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { AdminStatePanel } from '@/components/admin/AdminPagePrimitives';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { compressImage, uploadFile, validateFile, deleteFile } from '@/lib/storage';
import { formatPrice } from '@/lib/utils';
import { toast } from 'sonner';

const db = supabase as unknown as { from: typeof supabase.from; rpc: typeof supabase.rpc };

type ServiceRequest = {
  id: string;
  title: string;
  description: string;
  location: string;
  agreed_price: number | null;
  requester_budget: number | null;
  platform_fee: number;
  transfer_fee: number;
  provider_payout: number | null;
  status: string;
  requester_completed: boolean;
  provider_completed: boolean;
  requester_approved: boolean;
  provider_approved: boolean;
  service_type: 'JOB' | 'RENTAL';
  rental_start_at: string | null;
  rental_end_at: string | null;
  rental_deposit: number;
  rental_late_fee_per_day: number;
  handover_condition: string | null;
  payment_due_at: string | null;
  completion_due_at: string | null;
  created_at: string;
  provider?: { provider_name: string } | null;
};

type Proof = { request_id: string; amount: number; status: string; proof_url: string | null; admin_note: string | null; created_at: string };
type ServiceMessage = { id: string; request_id: string; sender_id: string; body: string; created_at: string };
const money = (value: number | null | undefined) => formatPrice(Number(value || 0));
const statusMeta: Record<string, { label: string; tone: 'default' | 'secondary' | 'destructive' | 'outline' }> = {
  NEGOTIATING: { label: 'Negosiasi', tone: 'secondary' },
  WAITING_PAYMENT: { label: 'Siap dibayar', tone: 'secondary' },
  APPROVED_TO_START: { label: 'Dana diverifikasi', tone: 'default' },
  IN_PROGRESS: { label: 'Sedang dikerjakan', tone: 'outline' },
  WAITING_CONFIRMATION: { label: 'Menunggu konfirmasi', tone: 'outline' },
  COMPLETED: { label: 'Selesai', tone: 'default' },
  DISPUTED: { label: 'Dalam sengketa', tone: 'destructive' },
  CANCELLED: { label: 'Dibatalkan', tone: 'destructive' },
  REFUNDED: { label: 'Direfund', tone: 'secondary' },
};

function ServiceRequestsContent() {
  const { user } = useAuth();
  const [refreshKey, setRefreshKey] = useState(0);
  const [amount, setAmount] = useState('');
  const [reference, setReference] = useState('');
  const [uploading, setUploading] = useState(false);
  const [finishing, setFinishing] = useState(false);
  const [acceptingId, setAcceptingId] = useState<string | null>(null);
  const [messageDrafts, setMessageDrafts] = useState<Record<string, string>>({});
  const [disputeDrafts, setDisputeDrafts] = useState<Record<string, string>>({});
  const [sendingId, setSendingId] = useState<string | null>(null);

  const { data, isLoading, isError } = useQuery<{ requests: ServiceRequest[]; proofs: Proof[]; messages: ServiceMessage[] }>({
    queryKey: ['service-requester-history', user?.id, refreshKey],
    enabled: Boolean(user),
    queryFn: async () => {
      const { data: requests, error } = await db.from('service_requests').select('*,provider:service_profiles!service_requests_profile_id_fkey(provider_name)').eq('requester_id', user!.id).order('created_at', { ascending: false });
      if (error) throw error;
      const ids = (requests || []).map((item: ServiceRequest) => item.id);
      if (!ids.length) return { requests: [], proofs: [], messages: [] };
      const [{ data: proofs, error: proofError }, { data: messages, error: messageError }] = await Promise.all([
        db.from('service_payment_proofs').select('request_id,amount,status,proof_url,admin_note,created_at').in('request_id', ids).order('created_at', { ascending: false }),
        db.from('service_messages').select('id,request_id,sender_id,body,created_at').in('request_id', ids).order('created_at', { ascending: true }),
      ]);
      if (proofError || messageError) throw proofError || messageError;
      return { requests: requests || [], proofs: proofs || [], messages: messages || [] };
    },
    staleTime: 15000,
  });

  const latestProof = (requestId: string) => data?.proofs.find((proof) => proof.request_id === requestId);
  const messagesFor = (requestId: string) => data?.messages.filter((message) => message.request_id === requestId) || [];

  async function acceptPrice(requestId: string) {
    setAcceptingId(requestId);
    const { error } = await db.rpc('service_requester_accept_price', { p_request_id: requestId });
    if (error) toast.error(error.message || 'Gagal menyetujui penawaran harga.');
    else { toast.success('Harga disetujui. Silakan ikuti instruksi pembayaran di request ini.'); setRefreshKey((key) => key + 1); }
    setAcceptingId(null);
  }

  async function sendMessage(requestId: string) {
    const body = (messageDrafts[requestId] || '').trim();
    if (!user || body.length < 1 || body.length > 2000) return toast.error('Pesan harus berisi 1–2000 karakter.');
    setSendingId(requestId);
    const { error } = await db.from('service_messages').insert({ request_id: requestId, sender_id: user.id, body });
    if (error) toast.error(error.message || 'Pesan gagal dikirim.');
    else { setMessageDrafts((drafts) => ({ ...drafts, [requestId]: '' })); setRefreshKey((key) => key + 1); }
    setSendingId(null);
  }

  async function openDispute(requestId: string) {
    const reason = (disputeDrafts[requestId] || '').trim();
    if (reason.length < 10) return toast.error('Jelaskan sengketa minimal 10 karakter.');
    const { error } = await db.rpc('service_open_dispute', { p_request_id: requestId, p_reason: reason, p_amount: null });
    if (error) toast.error(error.message || 'Sengketa gagal dibuka.');
    else { toast.success('Sengketa tercatat dan dana tetap ditahan selama peninjauan.'); setDisputeDrafts((drafts) => ({ ...drafts, [requestId]: '' })); setRefreshKey((key) => key + 1); }
  }

  async function submitProof(request: ServiceRequest, file: File) {
    if (!request.agreed_price) return toast.error('Harga belum disepakati oleh kedua pihak.');
    const validationError = validateFile(file, 5);
    if (validationError) return toast.error(validationError);
    setUploading(true);
    let uploadedUrl: string | null = null;
    try {
      const result = await uploadFile({ bucket: 'payment-proofs', path: `services/${request.id}`, file: await compressImage(file) });
      if (result.error || !result.url) throw new Error(result.error || 'Upload bukti gagal');
      uploadedUrl = result.url;
      const { error } = await db.rpc('service_submit_payment_proof', { p_request_id: request.id, p_amount: Number(amount || request.agreed_price), p_transfer_reference: reference, p_proof_url: uploadedUrl });
      if (error) throw error;
      toast.success('Bukti pembayaran terkirim untuk verifikasi admin.');
      setAmount(''); setReference(''); setRefreshKey((key) => key + 1);
    } catch (error) {
      if (uploadedUrl) await deleteFile('payment-proofs', uploadedUrl);
      toast.error(error instanceof Error ? error.message : 'Bukti pembayaran gagal disimpan.');
    } finally { setUploading(false); }
  }

  async function markCompleted(requestId: string) {
    setFinishing(true);
    const { error } = await db.rpc('service_mark_completed', { p_request_id: requestId });
    if (error) toast.error(error.message || 'Gagal mengirim konfirmasi selesai.');
    else { toast.success('Konfirmasi selesai tersimpan.'); setRefreshKey((key) => key + 1); }
    setFinishing(false);
  }

  if (isLoading) return <div className="flex min-h-screen items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-primary" /></div>;
  if (isError) return <div className="mx-auto max-w-2xl p-6"><AdminStatePanel type="error" title="Request gagal dimuat" description="Periksa koneksi lalu coba lagi." actionLabel="Coba lagi" onAction={() => setRefreshKey((key) => key + 1)} /></div>;

  return <div className="mobile-shell min-h-screen bg-background pb-28"><Header /><main className="mx-auto max-w-4xl px-4 py-6 sm:px-6"><div className="mb-6"><p className="text-xs font-bold uppercase tracking-[0.16em] text-emerald-700">Aktivitas jasa</p><h1 className="mt-1 font-heading text-3xl font-black">Request jasa saya</h1><p className="mt-1 text-sm text-muted-foreground">Pantau negosiasi, pembayaran escrow, dan penyelesaian pekerjaan dari satu tempat.</p></div>
    {(data?.requests.length || 0) === 0 ? <Card className="rounded-3xl border-dashed"><CardContent className="p-12 text-center"><FileClock className="mx-auto h-10 w-10 text-emerald-600" /><h2 className="mt-3 font-heading text-lg font-bold">Belum ada request jasa</h2><p className="mt-1 text-sm text-muted-foreground">Pilih penyedia dari katalog jasa untuk memulai.</p><Button className="mt-5 rounded-full" onClick={() => window.location.assign('/services')}>Cari penyedia jasa</Button></CardContent></Card> : <div className="space-y-4">{data!.requests.map((request) => { const meta = statusMeta[request.status] || statusMeta.NEGOTIATING; const proof = latestProof(request.id); const messages = messagesFor(request.id); return <Card key={request.id} className="rounded-3xl"><CardHeader><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><div className="flex flex-wrap items-center gap-2"><CardTitle>{request.title}</CardTitle><Badge variant={meta.tone}>{meta.label}</Badge>{request.service_type === 'RENTAL' && <Badge variant="outline">Sewa</Badge>}</div><p className="mt-1 text-xs text-muted-foreground">#{request.id.slice(0, 8).toUpperCase()} · {request.provider?.provider_name || 'Penyedia jasa'} · {request.location}</p></div><p className="text-lg font-black text-emerald-700">{request.agreed_price ? money(request.agreed_price) : 'Harga belum final'}</p></div></CardHeader><CardContent className="space-y-4"><p className="text-sm text-muted-foreground">{request.description}</p>{request.service_type === 'RENTAL' && <div className="grid gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm sm:grid-cols-2"><div><p className="text-xs text-amber-800">Periode sewa</p><b>{request.rental_start_at ? new Date(request.rental_start_at).toLocaleString('id-ID') : '-'} – {request.rental_end_at ? new Date(request.rental_end_at).toLocaleString('id-ID') : '-'}</b></div><div><p className="text-xs text-amber-800">Deposit / denda per hari</p><b>{money(request.rental_deposit)} / {money(request.rental_late_fee_per_day)}</b></div><div className="sm:col-span-2"><p className="text-xs text-amber-800">Kondisi saat serah-terima</p><b>{request.handover_condition || 'Akan dicatat saat serah-terima'}</b></div></div>}<div className="grid gap-3 rounded-2xl bg-muted/40 p-4 text-sm sm:grid-cols-3"><div><p className="text-xs text-muted-foreground">Budget awal · bukan harga final</p><b>{request.requester_budget ? money(request.requester_budget) : 'Tidak ditentukan'}</b></div><div><p className="text-xs text-muted-foreground">Harga kesepakatan</p><b>{money(request.agreed_price)}</b></div><div><p className="text-xs text-muted-foreground">Fee platform</p><b>{money(request.platform_fee)}</b></div></div>{request.status === 'NEGOTIATING' && request.agreed_price !== null && request.provider_approved && <div className="rounded-2xl border border-blue-200 bg-blue-50 p-4"><p className="font-semibold text-blue-950">Penawaran penyedia: {money(request.agreed_price)}</p><p className="mt-1 text-sm text-blue-900/80">Tinjau nilai ini. Setelah disetujui, harga menjadi terkunci dan Anda dapat melanjutkan pembayaran.</p><Button className="mt-3" onClick={() => void acceptPrice(request.id)} disabled={acceptingId === request.id}>{acceptingId === request.id ? 'Menyimpan...' : 'Setujui harga & lanjut bayar'}</Button></div>}{request.status === 'WAITING_PAYMENT' && <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4"><div className="flex gap-3"><Wallet className="mt-0.5 h-5 w-5 text-amber-700" /><div><b className="text-amber-950">Bayar ke rekening admin</b><p className="mt-1 text-sm text-amber-900/80">Transfer tepat sebesar {money(request.agreed_price)}, lalu unggah bukti. Admin akan memverifikasi sebelum pekerjaan dimulai.</p></div></div>{proof?.status === 'PENDING' ? <p className="mt-3 text-sm font-semibold text-amber-900">Bukti sedang menunggu verifikasi admin.</p> : <><div className="mt-4 grid gap-3 sm:grid-cols-2"><Input type="number" min="1" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder={`Nominal ${money(request.agreed_price)}`} /><Input value={reference} onChange={(event) => setReference(event.target.value)} placeholder="Nomor referensi transfer" /></div><label className="mt-3 flex cursor-pointer items-center justify-center gap-2 rounded-xl border-2 border-dashed border-amber-300 bg-white p-4 text-sm font-bold text-amber-900 hover:bg-amber-100"><Upload className="h-4 w-4" />{uploading ? 'Mengunggah...' : 'Pilih bukti transfer'}<input type="file" accept="image/jpeg,image/png,image/webp" className="hidden" disabled={uploading} onChange={(event) => { const file = event.target.files?.[0]; if (file) void submitProof(request, file); event.target.value = ''; }} /></label></>}</div>}{proof?.status === 'REJECTED' && <div className="rounded-xl bg-red-50 p-3 text-sm text-red-800">Bukti ditolak: {proof.admin_note || 'Silakan upload ulang bukti yang sesuai.'}</div>}{(request.status === 'NEGOTIATING' || ['APPROVED_TO_START','IN_PROGRESS','WAITING_CONFIRMATION'].includes(request.status)) && <div className="space-y-3 rounded-2xl border p-4"><div className="flex items-center gap-2 font-semibold"><MessageCircle className="h-4 w-4" />Pesan negosiasi dan pekerjaan</div><div className="max-h-48 space-y-2 overflow-y-auto">{messages.length ? messages.map((message) => <div key={message.id} className={`rounded-xl p-3 text-sm ${message.sender_id === user?.id ? 'ml-6 bg-emerald-50' : 'mr-6 bg-muted/50'}`}><p>{message.body}</p><p className="mt-1 text-[10px] text-muted-foreground">{message.sender_id === user?.id ? 'Anda' : 'Penyedia'} · {new Date(message.created_at).toLocaleString('id-ID')}</p></div>) : <p className="text-xs text-muted-foreground">Belum ada pesan.</p>}</div><div className="flex gap-2"><Input maxLength={2000} value={messageDrafts[request.id] || ''} onChange={(event) => setMessageDrafts((drafts) => ({ ...drafts, [request.id]: event.target.value }))} placeholder="Tulis pesan ke penyedia..." /><Button onClick={() => void sendMessage(request.id)} disabled={sendingId === request.id || !(messageDrafts[request.id] || '').trim()}>{sendingId === request.id ? 'Mengirim...' : 'Kirim'}</Button></div></div>}{['APPROVED_TO_START','IN_PROGRESS','WAITING_CONFIRMATION'].includes(request.status) && !request.requester_completed && <Button onClick={() => void markCompleted(request.id)} disabled={finishing} className="gap-2 rounded-full bg-emerald-700 hover:bg-emerald-800"><CheckCircle2 className="h-4 w-4" />{finishing ? 'Menyimpan...' : 'Konfirmasi pekerjaan selesai'}</Button>}{request.requester_completed && <p className="flex items-center gap-2 text-sm font-semibold text-emerald-700"><ShieldCheck className="h-4 w-4" />Konfirmasi Anda sudah tersimpan.</p>}{request.payment_due_at && request.status === 'WAITING_PAYMENT' && <p className="text-xs text-amber-700">Batas pembayaran: {new Date(request.payment_due_at).toLocaleString('id-ID')}</p>}{['APPROVED_TO_START','IN_PROGRESS','WAITING_CONFIRMATION'].includes(request.status) && <div className="space-y-2 border-t pt-3"><p className="text-xs text-muted-foreground">Jika ada masalah, dana tetap ditahan saat sengketa diperiksa admin.</p><Textarea maxLength={2000} value={disputeDrafts[request.id] || ''} onChange={(event) => setDisputeDrafts((drafts) => ({ ...drafts, [request.id]: event.target.value }))} placeholder="Jelaskan masalah yang ingin disengketakan (min. 10 karakter)" /><Button variant="outline" onClick={() => void openDispute(request.id)} disabled={(disputeDrafts[request.id] || '').trim().length < 10}>Buka sengketa</Button></div>}<div className="flex items-center gap-2 border-t pt-3 text-xs text-muted-foreground"><Receipt className="h-4 w-4" />Dana ditahan admin dan status transaksi hanya berubah setelah bukti transfer diverifikasi atau pencairan/refund direkonsiliasi.</div></CardContent></Card>; })}</div>}
  </main><BottomNav /></div>;
}

export default function ServiceRequestsPage() { return <ProtectedRoute><ServiceRequestsContent /></ProtectedRoute>; }
