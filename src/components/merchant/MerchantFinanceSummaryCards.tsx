import { ArrowDownRight, ArrowUpRight, CircleDollarSign, Landmark, Wallet } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { formatPrice } from '@/lib/utils';

export function MerchantFinanceSummaryCards({ totalRevenue, platformCommission, netBalance, feeLabel }: { totalRevenue: number; platformCommission: number; netBalance: number; feeLabel: string }) {
  const items = [
    { label: 'Total pendapatan', value: totalRevenue, detail: 'Omzet dari transaksi selesai', icon: Landmark, tone: 'bg-blue-100 text-blue-700 dark:bg-blue-950/50 dark:text-blue-300' },
    { label: 'Komisi platform', value: platformCommission, detail: feeLabel, icon: CircleDollarSign, tone: 'bg-orange-100 text-orange-700 dark:bg-orange-950/50 dark:text-orange-300' },
    { label: 'Saldo bersih merchant', value: netBalance, detail: 'Pendapatan setelah refund & komisi', icon: Wallet, tone: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300' },
  ];
  return <section aria-label="Ringkasan metrik keuangan" className="grid gap-4 md:grid-cols-3">{items.map(({ label, value, detail, icon: Icon, tone }) => <Card key={label} className="border-border/70 shadow-sm"><CardContent className="flex items-start justify-between gap-4 p-5"><div><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{label}</p><p className="mt-2 text-2xl font-bold tracking-tight">{formatPrice(value)}</p><p className="mt-2 text-xs text-muted-foreground">{detail}</p><span className={`mt-3 inline-flex items-center gap-1 text-xs font-medium ${value < 0 ? 'text-red-600' : 'text-emerald-600'}`}>{value < 0 ? <ArrowDownRight className="h-3.5 w-3.5" /> : <ArrowUpRight className="h-3.5 w-3.5" />}{value < 0 ? 'Perlu ditinjau' : 'Periode aktif'}</span></div><div className={`rounded-2xl p-3 ${tone}`}><Icon className="h-5 w-5" /></div></CardContent></Card>)}</section>;
}
