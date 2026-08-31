import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  Banknote,
  CheckCircle2,
  CreditCard,
  Gift,
  Loader2,
  Percent,
  QrCode,
  Star,
  Ticket,
  WifiOff,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Customer, LoyaltyProgram, Promotion, Voucher } from './types';

const paymentMethods = [
  { value: 'cash', label: 'Tunai', icon: <Banknote className="h-4 w-4" />, hint: 'Hitung kembalian otomatis' },
  { value: 'qris', label: 'QRIS', icon: <QrCode className="h-4 w-4" />, hint: 'Pastikan pembayaran berhasil' },
  { value: 'transfer', label: 'Transfer', icon: <CreditCard className="h-4 w-4" />, hint: 'Konfirmasi dana masuk' },
  { value: 'debit', label: 'Debit', icon: <CreditCard className="h-4 w-4" />, hint: 'Konfirmasi dari mesin EDC' },
];

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  subtotal: number;
  taxAmount: number;
  discount: number;
  promoDiscount: number;
  voucherDiscount: number;
  pointsDiscount: number;
  total: number;
  paymentMethod: string;
  paymentAmount: string;
  isSplitPayment: boolean;
  splitMethod2: string;
  splitAmount1: string;
  splitAmount2: string;
  appliedPromo: Promotion | null;
  appliedVoucher: Voucher | null;
  pointsToRedeem: number;
  pointsEarned: number;
  selectedCustomer: Customer | null;
  loyaltyProgram: LoyaltyProgram | null;
  isOnline: boolean;
  formatCurrency: (n: number) => string;
  onChange: (field: string, value: string | boolean) => void;
  onProcess: () => void | Promise<unknown>;
}

export function POSPaymentDialog({
  open,
  onOpenChange,
  subtotal,
  taxAmount,
  discount,
  promoDiscount,
  voucherDiscount,
  pointsDiscount,
  total,
  paymentMethod,
  paymentAmount,
  isSplitPayment,
  splitMethod2,
  splitAmount1,
  splitAmount2,
  appliedPromo,
  appliedVoucher,
  pointsToRedeem,
  pointsEarned,
  selectedCustomer,
  loyaltyProgram,
  isOnline,
  formatCurrency,
  onChange,
  onProcess,
}: Props) {
  const [isProcessing, setIsProcessing] = useState(false);
  const cashAmount = Number(paymentAmount) || 0;
  const splitPaid = (Number(splitAmount1) || 0) + (Number(splitAmount2) || 0);
  const change = !isSplitPayment && paymentMethod === 'cash' ? Math.max(0, cashAmount - total) : 0;
  const cashShortfall = Math.max(0, total - cashAmount);
  const cashIsValid = paymentAmount.trim() !== '' && cashAmount >= total;
  const splitIsValid = splitPaid === total;
  const cashlessOffline = !isOnline && (isSplitPayment || paymentMethod !== 'cash');
  const canSubmit = total > 0 && !cashlessOffline && (
    isSplitPayment ? splitIsValid : paymentMethod !== 'cash' || cashIsValid
  );
  const selectedMethod = paymentMethods.find(method => method.value === paymentMethod) ?? paymentMethods[0];
  const splitProgress = total > 0 ? Math.min(100, Math.round((splitPaid / total) * 100)) : 0;
  const quickAmounts = [
    total,
    Math.ceil(total / 5000) * 5000,
    Math.ceil(total / 10000) * 10000,
    Math.ceil(total / 50000) * 50000,
  ].filter((value, index, values) => values.indexOf(value) === index && value >= total).slice(0, 4);

  const handleProcess = async () => {
    if (isProcessing || !canSubmit) return;
    setIsProcessing(true);
    try {
      await onProcess();
    } finally {
      setIsProcessing(false);
    }
  };

  const handleOpenChange = (nextOpen: boolean) => {
    if (!isProcessing) onOpenChange(nextOpen);
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="flex h-[min(92dvh,760px)] w-[calc(100%-1rem)] max-w-2xl flex-col gap-0 overflow-hidden p-0 sm:h-auto sm:max-h-[calc(100dvh-2rem)]">
        <DialogHeader className="shrink-0 border-b bg-background/95 px-4 py-4 pr-12 backdrop-blur sm:px-6 sm:py-5">
          <DialogTitle className="flex items-center justify-between gap-3 text-left">
            <span>Proses Pembayaran</span>
            <span className="text-sm font-bold text-emerald-600 sm:text-base">{formatCurrency(total)}</span>
          </DialogTitle>
          <DialogDescription className="sr-only">Tinjau total transaksi, pilih metode pembayaran, dan selesaikan pembayaran.</DialogDescription>
        </DialogHeader>

        <div className="min-h-0 flex-1 overflow-y-auto p-4 sm:p-6">
          <div className="space-y-5">
            {/* Ringkasan transaksi */}
            <section className="rounded-2xl border border-emerald-100 bg-gradient-to-br from-emerald-50 to-slate-50 p-4 shadow-sm sm:p-5" aria-live="polite">
              <div className="mb-3 flex items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.12em] text-emerald-700">Ringkasan transaksi</p>
                  <p className="mt-1 text-xs text-muted-foreground">Periksa total sebelum menerima pembayaran.</p>
                </div>
                <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600" />
              </div>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between gap-3 text-muted-foreground"><span>Subtotal</span><span>{formatCurrency(subtotal)}</span></div>
                {taxAmount > 0 && <div className="flex justify-between gap-3 text-muted-foreground"><span>Pajak</span><span>{formatCurrency(taxAmount)}</span></div>}
                {discount > 0 && <div className="flex justify-between gap-3 text-muted-foreground"><span>Diskon manual</span><span>-{formatCurrency(discount)}</span></div>}
                {promoDiscount > 0 && (
                  <div className="flex justify-between gap-3 text-orange-600">
                    <span className="flex min-w-0 items-center gap-1"><Percent className="h-3 w-3 shrink-0" /><span className="truncate">{appliedPromo?.name}</span></span>
                    <span className="shrink-0">-{formatCurrency(promoDiscount)}</span>
                  </div>
                )}
                {voucherDiscount > 0 && (
                  <div className="flex justify-between gap-3 text-purple-600">
                    <span className="flex min-w-0 items-center gap-1"><Ticket className="h-3 w-3 shrink-0" /><span className="truncate">{appliedVoucher?.code}</span></span>
                    <span className="shrink-0">-{formatCurrency(voucherDiscount)}</span>
                  </div>
                )}
                {pointsDiscount > 0 && (
                  <div className="flex justify-between gap-3 text-emerald-600">
                    <span className="flex min-w-0 items-center gap-1"><Star className="h-3 w-3 shrink-0" /><span className="truncate">{pointsToRedeem.toLocaleString('id-ID')} poin</span></span>
                    <span className="shrink-0">-{formatCurrency(pointsDiscount)}</span>
                  </div>
                )}
                <div className="mt-3 flex items-end justify-between gap-3 border-t border-emerald-100 pt-3">
                  <span className="text-base font-bold">Total Tagihan</span>
                  <span className="text-xl font-extrabold text-emerald-600 sm:text-2xl">{formatCurrency(total)}</span>
                </div>
                {selectedCustomer && loyaltyProgram && pointsEarned > 0 && (
                  <div className="flex justify-between gap-3 rounded-lg bg-white/80 px-3 py-2 text-xs text-emerald-600">
                    <span className="flex items-center gap-1"><Gift className="h-3 w-3" />Poin yang akan diperoleh</span>
                    <span className="font-bold">+{pointsEarned.toLocaleString('id-ID')}</span>
                  </div>
                )}
              </div>
            </section>

            {/* Metode pembayaran */}
            <section>
              <div className="mb-2 flex items-end justify-between gap-3">
                <div>
                  <Label className="text-sm font-semibold">Metode pembayaran</Label>
                  <p className="mt-0.5 text-xs text-muted-foreground">Pilih cara pembayaran yang diterima.</p>
                </div>
                {!isOnline && <span className="inline-flex items-center gap-1 rounded-full bg-amber-50 px-2 py-1 text-[10px] font-semibold text-amber-700"><WifiOff className="h-3 w-3" />Offline</span>}
              </div>
              <div className="grid grid-cols-2 gap-2 sm:gap-3">
                {paymentMethods.map(method => (
                  <button
                    key={method.value}
                    type="button"
                    aria-pressed={paymentMethod === method.value}
                    onClick={() => onChange('paymentMethod', method.value)}
                    className={cn(
                      'flex min-h-14 items-center gap-2 rounded-xl border px-3 py-2 text-left transition-all active:scale-[0.98] sm:min-h-16 sm:px-4',
                      paymentMethod === method.value
                        ? 'border-emerald-500 bg-emerald-50 text-emerald-700 shadow-sm ring-2 ring-emerald-100'
                        : 'bg-background hover:border-emerald-300 hover:bg-emerald-50/40',
                    )}
                  >
                    <span className={cn('flex h-8 w-8 shrink-0 items-center justify-center rounded-lg', paymentMethod === method.value ? 'bg-emerald-100' : 'bg-muted')}>
                      {method.icon}
                    </span>
                    <span className="min-w-0">
                      <span className="block text-sm font-semibold">{method.label}</span>
                      <span className="block truncate text-[10px] font-normal text-muted-foreground">{method.hint}</span>
                    </span>
                  </button>
                ))}
              </div>
              {cashlessOffline && (
                <div className="mt-3 flex items-start gap-2 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2.5 text-xs text-amber-800" role="alert">
                  <WifiOff className="mt-0.5 h-4 w-4 shrink-0" />
                  <span>Pembayaran non-tunai memerlukan koneksi internet. Gunakan Tunai atau tunggu sampai online.</span>
                </div>
              )}
            </section>

            {/* Split payment */}
            <section className="rounded-2xl border bg-card p-3 sm:p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <Label htmlFor="split-payment-toggle" className="text-sm font-semibold">Pembayaran split</Label>
                  <p className="mt-0.5 text-xs text-muted-foreground">Gunakan dua metode untuk satu transaksi.</p>
                </div>
                <button
                  id="split-payment-toggle"
                  type="button"
                  role="switch"
                  aria-checked={isSplitPayment}
                  aria-label="Aktifkan pembayaran split"
                  className={cn('relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2', isSplitPayment ? 'bg-emerald-500' : 'bg-muted-foreground/30')}
                  onClick={() => onChange('isSplitPayment', !isSplitPayment)}
                >
                  <span className={cn('inline-block h-4 w-4 rounded-full bg-white shadow transition-transform', isSplitPayment ? 'translate-x-6' : 'translate-x-1')} />
                </button>
              </div>

              {isSplitPayment && (
                <div className="mt-4 space-y-3 border-t pt-4">
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <div className="space-y-1.5">
                      <Label className="text-xs">Metode 1</Label>
                      <Select value={paymentMethod} onValueChange={value => onChange('paymentMethod', value)}>
                        <SelectTrigger className="h-10 text-xs"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {paymentMethods.map(method => <SelectItem key={method.value} value={method.value}>{method.label}</SelectItem>)}
                        </SelectContent>
                      </Select>
                      <Input className="h-10 text-sm" type="number" inputMode="numeric" min="0" value={splitAmount1} onChange={event => onChange('splitAmount1', event.target.value)} placeholder="Nominal metode 1" />
                    </div>
                    <div className="space-y-1.5">
                      <div className="flex items-center justify-between gap-2">
                        <Label className="text-xs">Metode 2</Label>
                        <Button type="button" variant="ghost" size="sm" className="h-6 px-1.5 text-[10px] text-emerald-700" onClick={() => onChange('splitAmount2', String(Math.max(0, total - (Number(splitAmount1) || 0))))}>Isi sisa</Button>
                      </div>
                      <Select value={splitMethod2} onValueChange={value => onChange('splitMethod2', value)}>
                        <SelectTrigger className="h-10 text-xs"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {paymentMethods.map(method => <SelectItem key={method.value} value={method.value}>{method.label}</SelectItem>)}
                        </SelectContent>
                      </Select>
                      <Input className="h-10 text-sm" type="number" inputMode="numeric" min="0" value={splitAmount2} onChange={event => onChange('splitAmount2', event.target.value)} placeholder="Nominal metode 2" />
                    </div>
                  </div>
                  <div className="space-y-2" aria-live="polite">
                    <div className="flex justify-between gap-3 text-xs">
                      <span className="text-muted-foreground">Progress pembayaran</span>
                      <span className={cn('font-semibold', splitIsValid ? 'text-emerald-600' : splitPaid > total ? 'text-red-600' : 'text-muted-foreground')}>
                        {formatCurrency(splitPaid)} / {formatCurrency(total)}
                      </span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-muted">
                      <div className={cn('h-full rounded-full transition-all', splitPaid > total ? 'bg-red-500' : splitIsValid ? 'bg-emerald-500' : 'bg-amber-400')} style={{ width: `${splitProgress}%` }} />
                    </div>
                    <p className={cn('text-xs', splitIsValid ? 'text-emerald-700' : splitPaid > total ? 'text-red-700' : 'text-amber-700')}>
                      {splitIsValid ? 'Nominal split sudah sesuai total.' : splitPaid > total ? `Kurangi ${formatCurrency(splitPaid - total)}.` : `Masih kurang ${formatCurrency(total - splitPaid)}.`}
                    </p>
                  </div>
                </div>
              )}
            </section>

            {/* Nominal pembayaran */}
            {!isSplitPayment && paymentMethod === 'cash' ? (
              <section className="rounded-2xl border border-emerald-100 bg-emerald-50/40 p-3 sm:p-4">
                <div className="flex items-end justify-between gap-3">
                  <div>
                    <Label htmlFor="payment-amount" className="text-sm font-semibold">Jumlah bayar</Label>
                    <p className="mt-0.5 text-xs text-muted-foreground">Masukkan uang yang diterima dari pelanggan.</p>
                  </div>
                  <span className="text-xs font-medium text-muted-foreground">Minimal {formatCurrency(total)}</span>
                </div>
                <Input
                  id="payment-amount"
                  className="mt-3 h-14 border-emerald-400 bg-background text-xl font-bold shadow-sm focus-visible:ring-emerald-500 sm:text-2xl"
                  type="number"
                  inputMode="numeric"
                  min="0"
                  value={paymentAmount}
                  onChange={event => onChange('paymentAmount', event.target.value)}
                  placeholder="0"
                  autoFocus
                />
                <div className="mt-3 flex gap-2 overflow-x-auto pb-1">
                  {quickAmounts.map(value => (
                    <Button key={value} type="button" variant="outline" size="sm" className="h-9 shrink-0 bg-background text-xs" onClick={() => onChange('paymentAmount', String(value))}>
                      {formatCurrency(value)}
                    </Button>
                  ))}
                </div>
                {paymentAmount.trim() !== '' && (
                  <div className={cn('mt-3 rounded-xl border p-3', cashIsValid ? 'border-blue-200 bg-blue-50' : 'border-red-200 bg-red-50')} role="status">
                    {cashIsValid ? (
                      <p className="text-sm text-blue-800">Kembalian: <strong>{formatCurrency(change)}</strong></p>
                    ) : (
                      <p className="text-sm text-red-700">Nominal masih kurang <strong>{formatCurrency(cashShortfall)}</strong>.</p>
                    )}
                  </div>
                )}
              </section>
            ) : !isSplitPayment ? (
              <section className="flex items-start gap-3 rounded-2xl border border-blue-100 bg-blue-50/70 p-3 text-xs text-blue-800 sm:p-4" role="status">
                <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
                <span><strong>{selectedMethod.label}</strong> dipilih. Pastikan pembayaran sebesar <strong>{formatCurrency(total)}</strong> sudah diterima sebelum menekan Selesaikan.</span>
              </section>
            ) : null}
          </div>
        </div>

        <DialogFooter className="shrink-0 gap-2 border-t bg-background/95 p-4 backdrop-blur supports-[backdrop-filter]:bg-background/80 sm:flex-row sm:justify-end sm:space-x-2 sm:p-6">
          <Button type="button" variant="outline" className="w-full sm:w-auto" onClick={() => handleOpenChange(false)} disabled={isProcessing}>Batal</Button>
          <Button type="button" className="w-full bg-emerald-600 hover:bg-emerald-700 sm:w-auto" onClick={() => void handleProcess()} disabled={isProcessing || !canSubmit}>
            {isProcessing ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <CheckCircle2 className="mr-2 h-4 w-4" />}
            {isProcessing ? 'Memproses...' : 'Selesaikan'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
