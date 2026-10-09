import { useMemo, useState } from 'react';
import { AlertCircle, ArrowDownToLine, Clock3, FileUp, RefreshCw, Wallet } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { CourierLayout } from '@/components/courier/CourierLayout';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { useCourierGuard } from '@/hooks/useCourierGuard';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';
import { formatPrice } from '@/lib/utils';
import { toast } from 'sonner';

type OwnerType = 'MERCHANT' | 'COURIER';
type WalletRow = { id: string; balance_rupiah: number; is_active: boolean };
type LedgerRow = { id: string; entry_type: string; amount_delta_rupiah: number; base_amount_rupiah: number | null; fee_percent: number | null; note: string | null; created_at: string };
type TopupRow = { id: string; amount_rupiah: number; status: string; admin_notes: string | null; created_at: string };
type FeeRow = { fee_percent: number; is_enabled: boolean };
type BankInfo = { bank_name?: string; bank_account_number?: string; bank_account_name?: string; qris_image_url?: string };
type WalletData = { wallet: WalletRow | null; ledger: LedgerRow[]; requests: TopupRow[]; fee: FeeRow | null; bank: BankInfo | null };

function WalletPanel({ ownerType, ownerId, ownerName, loading: guardLoading }: { ownerType: OwnerType; ownerId: string | null; ownerName: string; loading: boolean }) {
  const { user } = useAuth();
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [proof, setProof] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const title = ownerType === 'MERCHANT' ? 'Saldo Komisi Pedagang' : 'Saldo Komisi Ojek';
  const queryKey = ['commission-wallet-account', ownerType, ownerId];
  const { data, isLoading, error, refetch } = useQuery<WalletData>({
    queryKey,
    enabled: !!ownerId,
    queryFn: async () => {
      const ownerColumn = ownerType === 'MERCHANT' ? 'merchant_id' : 'courier_id';
      const { data: walletData, error: walletError } = await supabase.from('commission_wallets' as never)
        .select('id,balance_rupiah,is_active').eq('owner_type' as never, ownerType as never)
        .eq(ownerColumn as never, ownerId as never).maybeSingle();
      if (walletError) throw walletError;
      const wallet = walletData as unknown as WalletRow | null;
      const [{ data: feeData, error: feeError }, { data: requestData, error: requestError }, { data: bankData }] = await Promise.all([
        supabase.from('commission_fee_settings' as never).select('fee_percent,is_enabled').eq('owner_type' as never, ownerType as never).maybeSingle(),
        supabase.from('commission_wallet_topup_requests' as never).select('id,amount_rupiah,status,admin_notes,created_at').eq('owner_type' as never, ownerType as never).eq(ownerColumn as never, ownerId as never).order('created_at' as never, { ascending: false } as never).limit(10),
        supabase.from('app_settings').select('value').eq('key', 'admin_payment_info').maybeSingle(),
      ]);
      if (feeError) throw feeError;
      if (requestError) throw requestError;
      let ledger: LedgerRow[] = [];
      if (wallet?.id) {
        const { data: ledgerData, error: ledgerError } = await supabase.from('commission_wallet_ledger' as never)
          .select('id,entry_type,amount_delta_rupiah,base_amount_rupiah,fee_percent,note,created_at')
          .eq('wallet_id' as never, wallet.id as never).order('created_at' as never, { ascending: false } as never).limit(25);
        if (ledgerError) throw ledgerError;
        ledger = (ledgerData ?? []) as unknown as LedgerRow[];
      }
      const bankValue = bankData?.value && typeof bankData.value === 'object' ? bankData.value as BankInfo : null;
      return {
        wallet,
        ledger,
        requests: (requestData ?? []) as unknown as TopupRow[],
        fee: (feeData ?? null) as unknown as FeeRow | null,
        bank: bankValue,
      };
    },
    staleTime: 15_000,
  });

  const bankDetails = useMemo(() => {
    const bank = data?.bank;
    if (!bank) return null;
    return [bank.bank_name, bank.bank_account_number, bank.bank_account_name].filter(Boolean);
  }, [data?.bank]);
  const hasPaymentDetails = Boolean(bankDetails?.length || data?.bank?.qris_image_url);

  const submitTopup = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const numericAmount = Number(amount);
    if (!Number.isInteger(numericAmount) || numericAmount < 10_000 || numericAmount > 1_000_000_000) {
      toast.error('Nominal top-up harus Rp10.000–Rp1.000.000.000');
      return;
    }
    if (!proof || !user || !ownerId) {
      toast.error('Pilih bukti transfer terlebih dahulu');
      return;
    }
    const allowed = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
    if (!allowed.includes(proof.type) || proof.size > 8 * 1024 * 1024) {
      toast.error('Bukti harus berupa JPG, PNG, WebP, atau PDF maksimal 8 MB');
      return;
    }

    setSubmitting(true);
    let uploadedPath: string | null = null;
    try {
      const extension = proof.name.split('.').pop()?.toLowerCase() || (proof.type === 'application/pdf' ? 'pdf' : 'jpg');
      uploadedPath = `${user.id}/${ownerType.toLowerCase()}/${crypto.randomUUID()}.${extension}`;
      const { error: uploadError } = await supabase.storage.from('commission-topup-proofs').upload(uploadedPath, proof, { contentType: proof.type, upsert: false });
      if (uploadError) throw uploadError;
      const { error: requestError } = await supabase.rpc('create_commission_wallet_topup_request' as never, {
        p_owner_type: ownerType,
        p_amount_rupiah: numericAmount,
        p_proof_path: uploadedPath,
        p_note: note.trim() || null,
      } as never);
      if (requestError) throw requestError;
      toast.success('Permintaan top-up dikirim untuk verifikasi admin');
      setAmount('');
      setNote('');
      setProof(null);
      const fileInput = document.getElementById('topup-proof') as HTMLInputElement | null;
      if (fileInput) fileInput.value = '';
      await refetch();
    } catch (caught) {
      if (uploadedPath) {
        const { data: attachedRequest, error: checkError } = await supabase.from('commission_wallet_topup_requests' as never)
          .select('id').eq('proof_path' as never, uploadedPath as never).maybeSingle();
        if (!checkError && !attachedRequest) {
          try { await supabase.storage.from('commission-topup-proofs').remove([uploadedPath]); } catch { /* Keep failure non-fatal. */ }
        }
      }
      console.error('Gagal mengajukan top-up wallet:', caught);
      toast.error(caught instanceof Error ? caught.message : 'Gagal mengajukan top-up');
    } finally {
      setSubmitting(false);
    }
  };

  const content = (
    <div className="mx-auto max-w-5xl space-y-5 p-4 md:p-6">
      {error && <Alert variant="destructive"><AlertCircle className="h-4 w-4" /><AlertTitle>Saldo belum dapat dimuat</AlertTitle><AlertDescription>{error instanceof Error ? error.message : 'Periksa apakah migration wallet sudah diterapkan.'}</AlertDescription></Alert>}
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader className="pb-2"><CardDescription>Saldo komisi Anda</CardDescription><CardTitle className="flex items-center gap-2 text-3xl"><Wallet className="h-7 w-7 text-primary" />{isLoading || guardLoading ? 'Memuat…' : formatPrice(data?.wallet?.balance_rupiah ?? 0)}</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>{ownerName ? `Akun: ${ownerName}` : title}</p>
            <p>Tarif saat ini: {data?.fee?.is_enabled ? `${data.fee.fee_percent}%` : 'belum aktif'}</p>
            <p>Wallet {data?.wallet?.is_active === false ? 'dinonaktifkan' : 'aktif'}. Saldo hanya dipotong saat transaksi selesai.</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Ajukan top-up</CardTitle><CardDescription>Transfer dan lampirkan bukti. Saldo bertambah setelah admin memverifikasi pembayaran.</CardDescription></CardHeader>
          <CardContent className="space-y-3">
            {bankDetails?.length ? <div className="rounded-md border bg-muted/30 p-3 text-sm"><p className="font-medium">Informasi pembayaran</p>{bankDetails.map((item, i) => <p key={`${i}-${item}`}>{item}</p>)}{data?.bank?.qris_image_url && <a className="text-primary underline" href={data.bank.qris_image_url} target="_blank" rel="noreferrer">Lihat QRIS</a>}</div> : <Alert><AlertDescription>Informasi rekening belum diatur admin. Hubungi admin sebelum transfer.</AlertDescription></Alert>}
            <form className="space-y-3" onSubmit={(event) => void submitTopup(event)}>
              <div className="space-y-1"><Label htmlFor="topup-amount">Nominal (Rp)</Label><Input id="topup-amount" inputMode="numeric" type="number" min="10000" max="1000000000" step="1000" value={amount} onChange={(event) => setAmount(event.target.value)} required /></div>
              <div className="space-y-1"><Label htmlFor="topup-proof">Bukti transfer (JPG/PNG/WebP/PDF, maks. 8 MB)</Label><Input id="topup-proof" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" onChange={(event) => setProof(event.target.files?.[0] ?? null)} required /></div>
              <div className="space-y-1"><Label htmlFor="topup-note">Catatan / referensi transfer (opsional)</Label><Textarea id="topup-note" value={note} onChange={(event) => setNote(event.target.value)} maxLength={500} rows={2} /></div>
              <Button type="submit" disabled={submitting || !data?.wallet || !hasPaymentDetails}><FileUp className="mr-2 h-4 w-4" />{submitting ? 'Mengirim…' : 'Kirim pengajuan'}</Button>
              {!data?.wallet && !isLoading && <p className="text-xs text-destructive">Wallet belum tersedia. Hubungi admin.</p>}
            </form>
          </CardContent>
        </Card>
      </div>
      <Card>
        <CardHeader className="flex flex-row items-center justify-between"><div><CardTitle>Permintaan top-up</CardTitle><CardDescription>Top-up hanya masuk setelah persetujuan admin.</CardDescription></div><Button variant="outline" size="icon" onClick={() => void refetch()} aria-label="Muat ulang"><RefreshCw className="h-4 w-4" /></Button></CardHeader>
        <CardContent>
          {!data?.requests.length ? <p className="py-6 text-center text-sm text-muted-foreground">Belum ada permintaan top-up.</p> : <div className="space-y-2">{data.requests.map((request) => <div key={request.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3"><div><p className="font-medium">{formatPrice(request.amount_rupiah)}</p><p className="text-xs text-muted-foreground">{new Date(request.created_at).toLocaleString('id-ID')}</p>{request.admin_notes && <p className="mt-1 text-sm">Catatan admin: {request.admin_notes}</p>}</div><Badge variant={request.status === 'APPROVED' ? 'default' : request.status === 'REJECTED' ? 'destructive' : 'secondary'}><Clock3 className="mr-1 h-3 w-3" />{request.status}</Badge></div>)}</div>}
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle>Riwayat saldo</CardTitle><CardDescription>Mutasi wallet, termasuk potongan komisi dan top-up terverifikasi.</CardDescription></CardHeader>
        <CardContent>
          {!data?.ledger.length ? <p className="py-6 text-center text-sm text-muted-foreground">Belum ada mutasi.</p> : <div className="space-y-2">{data.ledger.map((entry) => <div key={entry.id} className="flex flex-wrap items-center justify-between gap-3 border-b py-3 last:border-0"><div><p className="font-medium">{entry.entry_type === 'COMMISSION' ? 'Komisi transaksi' : entry.entry_type === 'TOPUP' ? 'Top-up' : entry.entry_type}</p><p className="text-xs text-muted-foreground">{new Date(entry.created_at).toLocaleString('id-ID')}{entry.fee_percent !== null ? ` · tarif ${entry.fee_percent}% dari ${formatPrice(entry.base_amount_rupiah ?? 0)}` : ''}</p>{entry.note && <p className="text-xs text-muted-foreground">{entry.note}</p>}</div><span className={entry.amount_delta_rupiah < 0 ? 'font-semibold text-destructive' : 'font-semibold text-primary'}>{entry.amount_delta_rupiah < 0 ? '−' : '+'}{formatPrice(Math.abs(entry.amount_delta_rupiah))}</span></div>)}</div>}
        </CardContent>
      </Card>
      <p className="flex items-start gap-2 text-xs text-muted-foreground"><ArrowDownToLine className="mt-0.5 h-3.5 w-3.5 shrink-0" />Bukti disimpan privat dan hanya dapat dibaca pemilik akun serta admin. Pembayaran belum otomatis menambah saldo; admin perlu memeriksa bukti terlebih dahulu.</p>
    </div>
  );

  if (ownerType === 'MERCHANT') return <MerchantLayout title={title} subtitle="Top-up saldo dan lihat potongan komisi marketplace">{content}</MerchantLayout>;
  return <CourierLayout title={title} subtitle="Top-up saldo dan lihat potongan komisi perjalanan">{content}</CourierLayout>;
}

export function MerchantCommissionWalletPage() {
  const guard = useMerchantGuard();
  return <WalletPanel ownerType="MERCHANT" ownerId={guard.merchantId} ownerName={guard.merchantName} loading={guard.loading} />;
}

export function CourierCommissionWalletPage() {
  const guard = useCourierGuard();
  return <WalletPanel ownerType="COURIER" ownerId={guard.courierId} ownerName={guard.courierName} loading={guard.loading} />;
}
