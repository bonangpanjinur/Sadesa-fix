import { useQuery } from '@tanstack/react-query';
import { AlertCircle, ArrowUpRight, Receipt, TrendingUp } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice } from '@/lib/utils';
import { MerchantCardError, MerchantCardLoading } from './MerchantDataState';

interface POSDailySummaryCardProps {
  tenantId: string;
  activeOutletId?: string;
  activeOutletName?: string;
}

interface SaleRow {
  total: number | null;
  outlet_id: string | null;
}

function getTodayRange() {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { start: start.toISOString(), end: end.toISOString() };
}

export function POSDailySummaryCard({ tenantId, activeOutletId, activeOutletName }: POSDailySummaryCardProps) {
  const navigate = useNavigate();
  const { data, isLoading, isError, error, refetch } = useQuery({
    queryKey: ['merchant-pos-daily-summary', tenantId, activeOutletId],
    queryFn: async () => {
      const { start, end } = getTodayRange();
      const { data: sales, error: salesError } = await supabase
        .from('pos_unified_transaction_history' as never)
        .select('total, outlet_id')
        .eq('tenant_id', tenantId)
        .eq('status', 'completed')
        .gte('created_at', start)
        .lt('created_at', end);
      if (salesError) throw salesError;

      const rows = (sales || []) as unknown as SaleRow[];
      const totalRevenue = rows.reduce((sum, sale) => sum + Number(sale.total || 0), 0);
      const outletRows = activeOutletId
        ? rows.filter((sale) => sale.outlet_id === activeOutletId)
        : [];
      return {
        totalRevenue,
        totalTransactions: rows.length,
        outletRevenue: outletRows.reduce((sum, sale) => sum + Number(sale.total || 0), 0),
        outletTransactions: outletRows.length,
      };
    },
    enabled: Boolean(tenantId),
    staleTime: 30_000,
  });

  if (isLoading) return <MerchantCardLoading label="Memuat penjualan POS hari ini..." />;
  if (isError) {
    return (
      <MerchantCardError
        message={error instanceof Error ? error.message : 'Penjualan POS hari ini gagal dimuat.'}
        onRetry={() => void refetch()}
      />
    );
  }

  return (
    <Card className="border-emerald-200 bg-emerald-50/50 shadow-sm dark:border-emerald-900/50 dark:bg-emerald-950/20">
      <CardContent className="p-5 sm:p-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="flex items-start gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-600/10 text-emerald-700 dark:text-emerald-300">
              <TrendingUp className="h-5 w-5" />
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-emerald-700/80 dark:text-emerald-300/80">
                Penjualan POS hari ini
              </p>
              <p className="mt-1 text-sm text-muted-foreground">Scope global seluruh outlet dan outlet aktif ditampilkan terpisah.</p>
            </div>
          </div>
          <Button variant="outline" size="sm" onClick={() => navigate('/merchant/pos/laporan')}>
            Lihat laporan <ArrowUpRight className="ml-1.5 h-3.5 w-3.5" />
          </Button>
        </div>

        <div className="mt-5 grid gap-3 sm:grid-cols-2">
          <div className="rounded-xl bg-background/75 p-4">
            <p className="text-xs text-muted-foreground">Semua outlet</p>
            <p className="mt-1 text-xl font-semibold">{formatPrice(data?.totalRevenue || 0)}</p>
            <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
              <Receipt className="h-3.5 w-3.5" aria-hidden="true" />
              {data?.totalTransactions || 0} transaksi selesai
            </p>
          </div>
          <div className="rounded-xl bg-background/75 p-4">
            <p className="text-xs text-muted-foreground">{activeOutletName || 'Outlet aktif'}</p>
            <p className="mt-1 text-xl font-semibold">{formatPrice(data?.outletRevenue || 0)}</p>
            <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
              <Receipt className="h-3.5 w-3.5" aria-hidden="true" />
              {data?.outletTransactions || 0} transaksi selesai
            </p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}