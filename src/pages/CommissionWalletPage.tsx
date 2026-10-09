import { useMemo, useState, type FormEvent } from 'react';
import { AlertCircle, ArrowDownToLine, Clock3, Download, FileUp, RefreshCw, Wallet } from 'lucide-react';
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
import { createWalletTopupInvoice, isXenditEnabled } from '@/lib/paymentApi';
import { formatPrice } from '@/lib/utils';
import { downloadCsv } from '@/lib/csv';
import { toast } from 'sonner';

type OwnerType = 'MERCHANT' | 'COURIER';
type WalletRow = { id: string; balance_rupiah: number; debt_rupiah: number; is_active: boolean };
type LedgerRow = { id: string; entry_type: string; source_type: string; source_id: string | null; amount_delta_rupiah: number; debt_delta_rupiah: number; base_amount_rupiah: number | null; fee_percent: number | null; note: string | null; created_at: string };
type TopupRow = { id: string; amount_rupiah: number; status: string; admin_notes: string | null; created_at: string; payment_provider: string; payment_status: string; payment_invoice_url: string | null };
type FeeRow = { fee_percent: number; is_enabled: boolean; charge_courier_delivery?: boolean };
type PolicyRow = { low_balance_threshold_rupiah: number };
type BankInfo = { bank_name?: string; bank_account_number?: string; bank_account_name?: string; qris_image_url?: string };
type WalletData = { wallet: WalletRow | null; ledger: LedgerRow[]; requests: TopupRow[]; fee: FeeRow | null; policy: PolicyRow | null; bank: BankInfo | null; xenditEnabled: boolean };

const localDateValue = (date: Date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
const currentMonthStart = () => { const date = new Date(); date.setDate(1); return localDateValue(date); };
const todayValue = () => localDateValue(new Date());

function WalletPanel({ ownerType, ownerId, ownerName, loading: guardLoading }: { ownerType: OwnerType; ownerId: string | null; ownerName: string; loading: boolean }) {
  const { user } = useAuth();
  const [amount, setAmount] = useState('');
  const [estimateBase, setEstimateBase] = useState('');
  const [estimateActivity, setEstimateActivity] = useState<'RIDE' | 'DELIVERY'>('RIDE');
  const [ledgerFrom, setLedgerFrom] = useState(currentMonthStart);
  const [ledgerTo, setLedgerTo] = useState(todayValue);
  const [note, setNote] = useState('');
  const [proof, setProof] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [payingAutomatically, setPayingAutomatically] = useState(false);
  const title = ownerType === 'MERCHANT' ? 'Saldo Komisi Pedagang' : 'Saldo Komisi Ojek';
  const queryKey = ['commission-wallet-account', ownerType, ownerId, ledgerFrom, ledgerTo];
  const { data, isLoading, error, refetch } = useQuery<WalletData>({
    queryKey,
    enabled: !!ownerId,
    queryFn: async () => {
      const ownerColumn = ownerType === 'MERCHANT' ? 'merchant_id' : 'courier_id';
      const [{ data: walletData, error: walletError }, { data: feeData, error: feeError }, { data: requestData, error: requestError }, { data: bankData }, { data: policyData }, xenditEnabled] = await Promise.all([
        supabase.from('commission_wallets' as never).select('id,balance_rupiah,debt_rupiah,is_active').eq('owner_type' as never, ownerType as never).eq(ownerColumn as never, ownerId as never).maybeSingle(),
        supabase.from('commission_fee_settings' as never).select('fee_percent,is_enabled,charge_courier_delivery').eq('owner_type' as never, ownerType as never).maybeSingle(),
        supabase.from('commission_wallet_topup_requests' as never).select('id,amount_rupiah,status,admin_notes,created_at,payment_provider,payment_status,payment_invoice_url').eq('owner_type' as never, ownerType as never).eq(ownerColumn as never, ownerId as never).order('created_at' as never, { ascending: false } as never).limit(10),
        supabase.from('app_settings').select('value').eq('key', 'admin_payment_info').maybeSingle(),
        supabase.from('commission_wallet_policy_settings' as never).select('low_balance_threshold_rupiah').eq('id' as never, true as never).maybeSingle(),
        isXenditEnabled().catch(() => false),
      ]);
      if (walletError) throw walletError;
      if (feeError) throw feeError;
      if (requestError) throw requestError;
      const wallet = walletData as unknown as WalletRow | null;
      let ledger: LedgerRow[] = [];
      if (wallet?.id && ledgerFrom && ledgerTo && ledgerFrom <= ledgerTo) {
        const fromTimestamp = new Date(`${ledgerFrom}T00:00:00`).toISOString();
        const toExclusive = new Date(`${ledgerTo}T00:00:00`);
        toExclusive.setDate(toExclusive.getDate() + 1);
        const { data: ledgerData, error: ledgerError } = await supabase.from('commission_wallet_ledger' as never)
          .select('id,entry_type,source_type,source_id,amount_delta_rupiah,debt_delta_rupiah,base_amount_rupiah,fee_percent,note,created_at')
          .eq('wallet_id' as never, wallet.id as never)
          .gte('created_at' as never, fromTimestamp as never)
          .lt('created_at' as never, toExclusive.toISOString() as never)
          .order('created_at' as never, { ascending: false } as never).limit(1000);
        if (ledgerError) throw ledgerError;
        ledger = (ledgerData ?? []) as unknown as LedgerRow[];
      }
      const bankValue = bankData?.value && typeof bankData.value === 'object' ? bankData.value as BankInfo : null;
      return {
        wallet,
        ledger,
        requests: (requestData ?? []) as unknown as TopupRow[],
        fee: (feeData ?? null) as unknown as FeeRow | null,
        policy: (policyData ?? null) as unknown as PolicyRow | null,
        bank: bankValue,
        xenditEnabled,
      };
    },
    staleTime: 10_000,
    refetchInterval: 15_000,
  });

  const bankDetails = useMemo(() => {
    const bank = data?.bank;
    if (!bank) return null;
    return [bank.bank_name, bank.bank_account_number, bank.bank_account_name].filter(Boolean);
  }, [data?.bank]);
  const hasPaymentDetails = Boolean(bankDetails?.length || data?.bank?.qris_image_url);
  const pendingRequest = data?.requests.find((request) => request.status === 'PENDING');
  const pendingAutomatic = data?.requests.find((request) => request.status === 'PENDING' && request.payment_provider === 'XENDIT');
  const estimateValue = Number(estimateBase);
  const estimateRate = data?.fee?.is_enabled && (ownerType !== 'COURIER' || estimateActivity === 'RIDE' || data.fee.charge_courier_delivery)
    ? Number(data.fee.fee_percent)
    : 0;
  const estimateFee = Number.isSafeInteger(estimateValue) && estimateValue > 0 ? Math.round(estimateValue * estimateRate / 100) : null;
  const invalidLedgerRange = !ledgerFrom || !ledgerTo || ledgerFrom > ledgerTo;
  const ledgerSummary = useMemo(() => {
    const rows = data?.ledger ?? [];
    return {
      commission: rows.filter((row) => row.entry_type === 'COMMISSION').reduce((sum, row) => sum - Number(row.amount_delta_rupiah) + Number(row.debt_delta_rupiah), 0),
      topups: rows.filter((row) => row.entry_type === 'TOPUP').reduce((sum, row) => sum + Number(row.amount_delta_rupiah) - Number(row.debt_delta_rupiah), 0),
      refunds: rows.filter((row) => row.entry_type === 'REFUND').reduce((sum, row) => sum + Number(row.amount_delta_rupiah) - Number(row.debt_delta_rupiah), 0),
    };
  }, [data?.ledger]);

  const exportLedger = () => {
    const rows = [
      ['Waktu', 'Jenis mutasi', 'Jenis transaksi', 'ID transaksi', 'Nilai dasar (Rp)', 'Tarif (%)', 'Perubahan saldo (Rp)', 'Perubahan tagihan (Rp)', 'Catatan'],
      ...(data?.ledger ?? []).map((entry) => [entry.created_at, entry.entry_type, entry.source_type, entry.source_id ?? '', entry.base_amount_rupiah ?? '', entry.fee_percent ?? '', entry.amount_delta_rupiah, entry.debt_delta_rupiah, entry.note ?? '']),
    ];
    const account = ownerType === 'MERCHANT' ? 'pedagang' : 'ojek';
    downloadCsv(`laporan-komisi-${account}-${ledgerFrom}-${ledgerTo}.csv`, rows);
  };

  const submitTopup = async (event: FormEvent<HTMLFormElement>) => {
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
        p_owner_type: ownerType, p_amount_rupiah: numericAmount, p_proof_path: uploadedPath, p_note: note.trim() || null,
      } as never);
      if (requestError) throw requestError;
      toast.success('Permintaan top-up dikirim untuk verifikasi admin');
      setAmount(''); setNote(''); setProof(null);
      const fileInput = document.getElementById('topup-proof') as HTMLInputElement | null;
      if (fileInput) fileInput.value = '';
      await refetch();
    } catch (caught) {
      if (uploadedPath) {
        const { data: attachedRequest, error: checkError } = await supabase.from('commission_wallet_topup_requests' as never)
          .select('id').eq('proof_path' as never, uploadedPath as never).maybeSingle();
        if (!checkError && !attachedRequest) {
          try { await supabase.storage.from('commission-topup-proofs').remove([uploadedPath]); } catch { /* best-effort orphan cleanup */ }
        }
      }
      console.error('Gagal mengajukan top-up wallet:', caught);
      toast.error(caught instanceof Error ? caught.message : 'Gagal mengajukan top-up');
    } finally {
      setSubmitting(false);
    }
  };

  const startAutomaticTopup = async () => {
    if (!ownerId || !data?.xenditEnabled) return;
    const numericAmount = Number(amount);
    let requestId = pendingAutomatic?.id;
    if (!requestId && (!Number.isInteger(numericAmount) || numericAmount < 10_000 || numericAmount > 1_000_000_000)) {
      toast.error('Nominal top-up harus Rp10.000–Rp1.000.000.000');
      return;
    }
    if (pendingAutomatic && numericAmount && Number(pendingAutomatic.amount_rupiah) !== numericAmount) {
      toast.error(`Lanjutkan invoice yang tertunda sebesar ${formatPrice(pendingAutomatic.amount_rupiah)} atau tunggu sampai kedaluwarsa.`);
      return;
    }
    setPayingAutomatically(true);
    try {
      if (!requestId) {
        const { data: created, error: createError } = await supabase.rpc('create_commission_wallet_topup_invoice_request' as never, {
          p_owner_type: ownerType, p_amount_rupiah: numericAmount, p_note: note.trim() || null,
        } as never);
        if (createError) throw createError;
        requestId = String(created);
      }
      const invoice = await createWalletTopupInvoice({ topupRequestId: requestId });
      window.location.assign(invoice.invoice_url);
    } catch (caught) {
      console.error('Gagal membuat invoice top-up:', caught);
      toast.error(caught instanceof Error ? caught.message : 'Gagal membuat invoice. Request tersimpan; coba lanjutkan lagi.');
      await refetch();
    } finally {
      setPayingAutomatically(false);
    }
  };

  const content = (
    <div className="mx-auto max-w-5xl space-y-5 p-4 md:p-6">
      {error && <Alert variant="destructive"><AlertCircle className="h-4 w-4" /><AlertTitle>Saldo belum dapat dimuat</AlertTitle><AlertDescription>{error instanceof Error ? error.message : 'Periksa apakah migration wallet sudah diterapkan.'}</AlertDescription></Alert>}
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader className="pb-2"><CardDescription>Saldo tersedia</CardDescription><CardTitle className="flex items-center gap-2 text-3xl"><Wallet className="h-7 w-7 text-primary" />{isLoading || guardLoading ? 'Memuat…' : formatPrice(data?.wallet?.balance_rupiah ?? 0)}</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>{ownerName ? `Akun: ${ownerName}` : title}</p>
            <p>Tagihan komisi tertunggak: <strong className={Number(data?.wallet?.debt_rupiah ?? 0) > 0 ? 'text-destructive' : 'text-foreground'}>{formatPrice(data?.wallet?.debt_rupiah ?? 0)}</strong></p>
            <p>Tarif saat ini: {data?.fee?.is_enabled ? `${data.fee.fee_percent}%` : 'belum aktif'}</p>
            {ownerType === 'COURIER' && <p>Potongan pengiriman barang: {data?.fee?.charge_courier_delivery ? 'aktif' : 'nonaktif'}</p>}
            <p>Wallet {data?.wallet?.is_active === false ? 'dinonaktifkan' : 'aktif'}. Saldo dipotong saat transaksi selesai.</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Ajukan top-up</CardTitle><CardDescription>Top-up melunasi tagihan komisi tertunggak terlebih dahulu; sisanya masuk sebagai saldo tersedia.</CardDescription></CardHeader>
          <CardContent className="space-y-3">
            {data?.wallet && Number(data.wallet.debt_rupiah) > 0 && <Alert variant="destructive"><AlertCircle className="h-4 w-4" /><AlertTitle>Transaksi baru ditahan</AlertTitle><AlertDescription>Pesanan/penugasan baru tidak tersedia sampai tagihan {formatPrice(data.wallet.debt_rupiah)} lunas. Order yang sudah selesai tetap tercatat; kekurangan tidak membuat wallet negatif.</AlertDescription></Alert>}
            {data?.wallet && Number(data.wallet.debt_rupiah) === 0 && Number(data.wallet.balance_rupiah) <= Number(data.policy?.low_balance_threshold_rupiah ?? 10_000) && <Alert><AlertCircle className="h-4 w-4" /><AlertTitle>{ownerType === 'COURIER' && data.fee?.is_enabled && Number(data.wallet.balance_rupiah) <= 0 ? 'Isi saldo sebelum online' : 'Saldo komisi menipis'}</AlertTitle><AlertDescription>{ownerType === 'COURIER' && data.fee?.is_enabled && Number(data.wallet.balance_rupiah) <= 0 ? 'Saat tarif ojek aktif, courier perlu memiliki saldo positif dan tidak memiliki tagihan untuk online atau menerima pekerjaan.' : `Saldo tersedia sudah mencapai ambang ${formatPrice(data.policy?.low_balance_threshold_rupiah ?? 10_000)}. Lakukan top-up agar aktivitas tidak terhenti jika komisi melebihi saldo.`}</AlertDescription></Alert>}
            {data?.xenditEnabled && <div className="rounded-md border border-primary/30 bg-primary/5 p-3 text-sm"><p className="font-medium">Pembayaran otomatis tersedia</p><p className="mt-1 text-muted-foreground">Bayar invoice Xendit; saldo dikreditkan otomatis setelah callback pembayaran terverifikasi.</p></div>}
            {bankDetails?.length ? <div className="rounded-md border bg-muted/30 p-3 text-sm"><p className="font-medium">Informasi pembayaran manual</p>{bankDetails.map((item, i) => <p key={`${i}-${item}`}>{item}</p>)}{data?.bank?.qris_image_url && <a className="text-primary underline" href={data.bank.qris_image_url} target="_blank" rel="noreferrer">Lihat QRIS</a>}</div> : !data?.xenditEnabled ? <Alert><AlertDescription>Informasi rekening belum diatur admin. Hubungi admin sebelum transfer.</AlertDescription></Alert> : null}
            <div className="space-y-1"><Label htmlFor="topup-amount">Nominal (Rp)</Label><Input id="topup-amount" inputMode="numeric" type="number" min="10000" max="1000000000" step="1000" value={amount} onChange={(event) => setAmount(event.target.value)} required /></div>
            <div className="space-y-1"><Label htmlFor="topup-note">Catatan / referensi (opsional)</Label><Textarea id="topup-note" value={note} onChange={(event) => setNote(event.target.value)} maxLength={500} rows={2} /></div>
            {data?.xenditEnabled && <Button type="button" onClick={() => void startAutomaticTopup()} disabled={payingAutomatically || !data.wallet || (!!pendingRequest && !pendingAutomatic)}>{payingAutomatically ? 'Menyiapkan invoice…' : pendingAutomatic ? 'Lanjutkan pembayaran Xendit' : pendingRequest ? 'Selesaikan permintaan yang tertunda' : 'Bayar otomatis via Xendit'}</Button>}
            <form className="space-y-3 border-t pt-3" onSubmit={(event) => void submitTopup(event)}>
              <p className="text-sm font-medium">Atau kirim bukti transfer manual</p>
              <div className="space-y-1"><Label htmlFor="topup-proof">Bukti transfer (JPG/PNG/WebP/PDF, maks. 8 MB)</Label><Input id="topup-proof" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" onChange={(event) => setProof(event.target.files?.[0] ?? null)} required /></div>
              <Button type="submit" variant="outline" disabled={submitting || !data?.wallet || !hasPaymentDetails || !!pendingRequest}><FileUp className="mr-2 h-4 w-4" />{submitting ? 'Mengirim…' : pendingRequest ? 'Ada permintaan yang tertunda' : 'Kirim untuk verifikasi admin'}</Button>
              {!data?.wallet && !isLoading && <p className="text-xs text-destructive">Wallet belum tersedia. Hubungi admin.</p>}
            </form>
          </CardContent>
        </Card>
      </div>
      <Card>
        <CardHeader><CardTitle>Simulasi komisi transaksi</CardTitle><CardDescription>Estimasi sebelum transaksi; nominal final dihitung dari data transaksi di server.</CardDescription></CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-[1fr_auto_1fr] md:items-end">
          {ownerType === 'COURIER' && <div className="space-y-1"><Label htmlFor="estimate-activity">Jenis pekerjaan</Label><select id="estimate-activity" className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm" value={estimateActivity} onChange={(event) => setEstimateActivity(event.target.value as 'RIDE' | 'DELIVERY')}><option value="RIDE">Ojek penumpang</option><option value="DELIVERY">Pengiriman barang</option></select></div>}
          <div className="space-y-1"><Label htmlFor="estimate-base">{ownerType === 'MERCHANT' ? 'Subtotal produk (Rp)' : estimateActivity === 'RIDE' ? 'Perkiraan tarif ride (Rp)' : 'Perkiraan penghasilan courier (Rp)'}</Label><Input id="estimate-base" type="number" min="0" step="1000" inputMode="numeric" value={estimateBase} onChange={(event) => setEstimateBase(event.target.value)} placeholder="Contoh: 20.000" /></div>
          <div className="rounded-md border bg-muted/30 p-3 md:min-w-56"><p className="text-xs text-muted-foreground">Tarif komisi {estimateRate}%</p><p className="text-xl font-semibold">{estimateFee === null ? 'Masukkan nominal' : formatPrice(estimateFee)}</p><p className="text-xs text-muted-foreground">{!data?.fee?.is_enabled ? 'Tarif belum diaktifkan.' : ownerType === 'COURIER' && estimateActivity === 'DELIVERY' && !data.fee.charge_courier_delivery ? 'Komisi delivery dinonaktifkan admin.' : 'Fee dibulatkan ke rupiah terdekat.'}</p></div>
        </CardContent>
        <p className="px-6 pb-5 text-xs text-muted-foreground">{ownerType === 'MERCHANT' ? 'Basis aktual: orders.subtotal, tidak termasuk ongkir.' : estimateActivity === 'RIDE' ? 'Basis aktual: tarif final ride yang dicatat sistem.' : 'Basis aktual: estimasi penghasilan courier; bila kosong sistem menggunakan ongkir.'} Saldo tidak dapat negatif; kekurangan menjadi tagihan yang harus dilunasi sebelum pekerjaan baru.</p>
      </Card>
      <Card>
        <CardHeader className="flex flex-row items-center justify-between"><div><CardTitle>Permintaan top-up</CardTitle><CardDescription>Xendit dikreditkan otomatis setelah webhook terverifikasi; transfer manual menunggu tinjauan admin.</CardDescription></div><Button variant="outline" size="icon" onClick={() => void refetch()} aria-label="Muat ulang"><RefreshCw className="h-4 w-4" /></Button></CardHeader>
        <CardContent>
          {!data?.requests.length ? <p className="py-6 text-center text-sm text-muted-foreground">Belum ada permintaan top-up.</p> : <div className="space-y-2">{data.requests.map((request) => <div key={request.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3"><div><p className="font-medium">{formatPrice(request.amount_rupiah)} · {request.payment_provider === 'XENDIT' ? 'Xendit' : 'Transfer manual'}</p><p className="text-xs text-muted-foreground">{new Date(request.created_at).toLocaleString('id-ID')} · pembayaran {request.payment_status}</p>{request.admin_notes && <p className="mt-1 text-sm">Catatan: {request.admin_notes}</p>}{request.status === 'PENDING' && request.payment_invoice_url && <a className="text-sm text-primary underline" href={request.payment_invoice_url} target="_blank" rel="noreferrer">Buka invoice</a>}</div><Badge variant={request.status === 'APPROVED' ? 'default' : request.status === 'REJECTED' ? 'destructive' : 'secondary'}><Clock3 className="mr-1 h-3 w-3" />{request.status}</Badge></div>)}</div>}
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="gap-4 md:flex-row md:items-end md:justify-between">
          <div><CardTitle>Laporan komisi dan riwayat saldo</CardTitle><CardDescription>Filter periode, lihat ringkasan, lalu unduh CSV untuk rekonsiliasi.</CardDescription></div>
          <div className="flex flex-wrap items-end gap-2">
            <div className="space-y-1"><Label htmlFor="ledger-from">Dari tanggal</Label><Input id="ledger-from" type="date" required value={ledgerFrom} max={ledgerTo || undefined} onChange={(event) => { if (event.target.value) setLedgerFrom(event.target.value); }} /></div>
            <div className="space-y-1"><Label htmlFor="ledger-to">Sampai tanggal</Label><Input id="ledger-to" type="date" required value={ledgerTo} min={ledgerFrom || undefined} max={todayValue()} onChange={(event) => { if (event.target.value) setLedgerTo(event.target.value); }} /></div>
            <Button variant="outline" onClick={exportLedger} disabled={invalidLedgerRange || !data?.ledger.length}><Download className="mr-2 h-4 w-4" />Ekspor CSV</Button>
          </div>
        </CardHeader>
        <CardContent>
          {invalidLedgerRange ? <Alert variant="destructive"><AlertCircle className="h-4 w-4" /><AlertTitle>Rentang tanggal tidak valid</AlertTitle><AlertDescription>Tanggal awal harus sebelum atau sama dengan tanggal akhir.</AlertDescription></Alert> : <>
            <p className="mb-3 text-xs text-muted-foreground">Periode {ledgerFrom} sampai {ledgerTo} · maksimal 1.000 mutasi per permintaan. Gunakan rentang yang lebih pendek untuk menelusuri riwayat yang lebih besar.</p>
            <div className="mb-4 grid gap-2 sm:grid-cols-3">
              <div className="rounded-md border p-3"><p className="text-xs text-muted-foreground">Komisi dipotong</p><p className="font-semibold">{formatPrice(ledgerSummary.commission)}</p></div>
              <div className="rounded-md border p-3"><p className="text-xs text-muted-foreground">Top-up diterima</p><p className="font-semibold">{formatPrice(ledgerSummary.topups)}</p></div>
              <div className="rounded-md border p-3"><p className="text-xs text-muted-foreground">Komisi dibalik karena refund</p><p className="font-semibold">{formatPrice(ledgerSummary.refunds)}</p></div>
            </div>
            {!data?.ledger.length ? <p className="py-6 text-center text-sm text-muted-foreground">Tidak ada mutasi pada periode ini.</p> : <div className="space-y-2">{data.ledger.map((entry) => <div key={entry.id} className="flex flex-wrap items-center justify-between gap-3 border-b py-3 last:border-0"><div><p className="font-medium">{entry.entry_type === 'COMMISSION' ? 'Komisi transaksi' : entry.entry_type === 'TOPUP' ? 'Top-up' : entry.entry_type === 'REFUND' ? 'Pembalikan komisi refund' : entry.entry_type}</p><p className="text-xs text-muted-foreground">{new Date(entry.created_at).toLocaleString('id-ID')} · {entry.source_type}{entry.source_id ? ` · ${entry.source_id}` : ''}{entry.fee_percent !== null ? ` · tarif ${entry.fee_percent}% dari ${formatPrice(entry.base_amount_rupiah ?? 0)}` : ''}</p>{entry.debt_delta_rupiah !== 0 && <p className={entry.debt_delta_rupiah > 0 ? 'text-xs text-destructive' : 'text-xs text-primary'}>{entry.debt_delta_rupiah > 0 ? 'Tagihan bertambah ' : 'Tagihan berkurang '}{formatPrice(Math.abs(entry.debt_delta_rupiah))}</p>}{entry.note && <p className="text-xs text-muted-foreground">{entry.note}</p>}</div><span className={entry.amount_delta_rupiah < 0 ? 'font-semibold text-destructive' : 'font-semibold text-primary'}>{entry.amount_delta_rupiah < 0 ? '−' : '+'}{formatPrice(Math.abs(entry.amount_delta_rupiah))}</span></div>)}</div>}
          </>}
        </CardContent>
      </Card>
      <p className="flex items-start gap-2 text-xs text-muted-foreground"><ArrowDownToLine className="mt-0.5 h-3.5 w-3.5 shrink-0" />Saldo kuota lama tidak dikonversi dan paket lama dihentikan. Bukti transfer manual disimpan privat; kredit manual menunggu persetujuan admin.</p>
    </div>
  );

  if (ownerType === 'MERCHANT') return <MerchantLayout title={title} subtitle="Top-up saldo dan lihat potongan komisi marketplace">{content}</MerchantLayout>;
  return <CourierLayout title={title} subtitle="Top-up saldo dan lihat potongan komisi ojek/pengiriman">{content}</CourierLayout>;
}

export function MerchantCommissionWalletPage() {
  const guard = useMerchantGuard();
  return <WalletPanel ownerType="MERCHANT" ownerId={guard.merchantId} ownerName={guard.merchantName} loading={guard.loading} />;
}

export function CourierCommissionWalletPage() {
  const guard = useCourierGuard();
  return <WalletPanel ownerType="COURIER" ownerId={guard.courierId} ownerName={guard.courierName} loading={guard.loading} />;
}
