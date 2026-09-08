import { useCallback, useEffect, useState } from 'react';
import { POSLayout } from '@/components/pos/POSLayout';
import { usePOS } from '@/contexts/POSContext';
import { fetchPOSCanonicalReport } from '@/lib/posCanonicalReports';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, LineChart, Line, PieChart, Pie, Cell } from 'recharts';
import { TrendingUp, ShoppingCart, Package, CreditCard, FileText, FileSpreadsheet } from 'lucide-react';
import { exportPOSSales, exportToPDF } from '@/lib/exportReport';
import { format, startOfDay, endOfDay, startOfWeek, endOfWeek, startOfMonth, endOfMonth, startOfYear, endOfYear } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';

const COLORS = ['#10b981', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4'];

interface ChartPoint { label: string; total: number; count: number; }
interface TopProduct { name: string; qty: number; total: number; }
interface PaymentMethod { name: string; value: number; }

export default function POSLaporanPage() {
  const { tenant, activeOutlet, formatCurrency } = usePOS();
  const [period, setPeriod] = useState('month');
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({
    totalOmzet: 0, totalTransactions: 0, avgBasket: 0, totalDiscount: 0,
    salesChart: [] as ChartPoint[],
    topProducts: [] as TopProduct[],
    paymentMethods: [] as PaymentMethod[],
    periodLabel: '',
  });

  const getRange = useCallback(() => {
    const now = new Date();
    switch (period) {
      case 'today': return { start: startOfDay(now), end: endOfDay(now) };
      case 'week': return { start: startOfWeek(now, { weekStartsOn: 1 }), end: endOfWeek(now, { weekStartsOn: 1 }) };
      case 'month': return { start: startOfMonth(now), end: endOfMonth(now) };
      case 'year': return { start: startOfYear(now), end: endOfYear(now) };
      default: return { start: startOfMonth(now), end: endOfMonth(now) };
    }
  }, [period]);

  const fetchReport = useCallback(async () => {
    if (!tenant || !activeOutlet) return;
    setLoading(true);
    const { start, end } = getRange();

    try {
      const report = await fetchPOSCanonicalReport({
        tenantId: tenant.id,
        outletId: activeOutlet.id,
        from: start,
        to: end,
      });
      const totalOmzet = report.sales.net_revenue;
      const totalTransactions = report.sales.transactions;
      const totalDiscount = report.sales.discounts;
      const avgBasket = totalTransactions > 0 ? totalOmzet / totalTransactions : 0;

      // Payment methods breakdown
      const paymentLabels: Record<string, string> = { cash: 'Tunai', qris: 'QRIS', transfer: 'Transfer', debit: 'Debit', credit: 'Kredit', split: 'Split' };
      const paymentMethods = Object.entries({
        cash: report.sales.cash,
        qris: report.sales.qris,
        transfer: report.sales.transfer,
        debit: report.sales.debit,
        credit: report.sales.credit,
        split: report.sales.split,
      }).filter(([, value]) => value > 0).map(([key, value]) => ({ name: paymentLabels[key] || key, value }));

      // Sales chart
      const salesChart: ChartPoint[] = report.daily.map((day) => ({
        label: period === 'year' ? format(new Date(`${day.period}T00:00:00`), 'MMM', { locale: idLocale }) : format(new Date(`${day.period}T00:00:00`), period === 'today' ? 'HH:mm' : 'd', { locale: idLocale }),
        total: day.revenue,
        count: day.transactions,
      }));

      // Top products from sale items
      const topProducts = report.top_products.map((product) => ({
        name: product.name,
        qty: product.qty,
        total: product.revenue,
      }));

      const periodLabels: Record<string, string> = { today: 'Hari Ini', week: 'Minggu Ini', month: 'Bulan Ini', year: 'Tahun Ini' };
      setStats({ totalOmzet, totalTransactions, avgBasket, totalDiscount, salesChart, topProducts, paymentMethods, periodLabel: periodLabels[period] });
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  }, [tenant, activeOutlet, getRange, period]);

  useEffect(() => {
    if (tenant && activeOutlet) void fetchReport();
  }, [tenant, activeOutlet, fetchReport]);

  const exportCSV = () => {
    const topProductRows = stats.topProducts.map(p => ({
      name: p.name,
      qty: p.qty,
      total: p.total,
    }));
    exportPOSSales(
      topProductRows.map((p, i) => ({
        invoice_no: String(i + 1),
        created_at: new Date().toISOString(),
        cashier_name: '-',
        customer_name: '-',
        subtotal: p.total,
        discount_amount: 0,
        tax_amount: 0,
        total: p.total,
        payment_method: '-',
        status: 'completed',
      })),
      stats.periodLabel,
      tenant?.name,
    );
  };

  const exportPDF = async () => {
    await exportToPDF({
      title: 'Laporan Penjualan POS',
      storeName: tenant?.name,
      period: stats.periodLabel,
      filename: `laporan-${period}`,
      columns: [
        { header: 'Produk', key: 'name' },
        { header: 'Qty Terjual', key: 'qty', format: 'number' },
        { header: 'Total Omzet', key: 'total', format: 'currency' },
      ],
      rows: stats.topProducts,
      summary: {
        totalOmzet: { label: 'Total Omzet', value: stats.totalOmzet },
        totalTrx: { label: 'Total Transaksi', value: stats.totalTransactions },
        avgBasket: { label: 'Rata-rata per Transaksi', value: stats.avgBasket },
        totalDiskon: { label: 'Total Diskon', value: stats.totalDiscount },
      },
    });
  };

  return (
    <POSLayout title="Laporan Penjualan" subtitle={`${activeOutlet?.name || ''} • ${stats.periodLabel}`}
      actions={
        <div className="flex gap-2">
          <Select value={period} onValueChange={setPeriod}>
            <SelectTrigger className="w-36 h-8 text-sm"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="today">Hari Ini</SelectItem>
              <SelectItem value="week">Minggu Ini</SelectItem>
              <SelectItem value="month">Bulan Ini</SelectItem>
              <SelectItem value="year">Tahun Ini</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline" size="sm" onClick={exportCSV}><FileSpreadsheet className="h-4 w-4 mr-1" />Excel</Button>
          <Button variant="outline" size="sm" onClick={exportPDF}><FileText className="h-4 w-4 mr-1" />PDF</Button>
        </div>
      }>

      {loading ? (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {[...Array(8)].map((_, i) => <div key={i} className="h-28 bg-muted animate-pulse rounded-xl" />)}
        </div>
      ) : (
        <div className="space-y-6">
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <Card className="border-0 shadow-sm bg-gradient-to-br from-emerald-500 to-emerald-600 text-white">
              <CardContent className="p-4">
                <div className="flex items-center justify-between mb-1">
                  <p className="text-emerald-100 text-xs">Total Omzet</p>
                  <TrendingUp className="h-4 w-4 text-emerald-200" />
                </div>
                <p className="text-xl font-bold">{formatCurrency(stats.totalOmzet)}</p>
              </CardContent>
            </Card>
            <Card className="border-0 shadow-sm">
              <CardContent className="p-4">
                <div className="flex items-center justify-between mb-1">
                  <p className="text-muted-foreground text-xs">Jumlah Transaksi</p>
                  <ShoppingCart className="h-4 w-4 text-blue-500" />
                </div>
                <p className="text-xl font-bold">{stats.totalTransactions}</p>
              </CardContent>
            </Card>
            <Card className="border-0 shadow-sm">
              <CardContent className="p-4">
                <div className="flex items-center justify-between mb-1">
                  <p className="text-muted-foreground text-xs">Rata-rata Transaksi</p>
                  <CreditCard className="h-4 w-4 text-purple-500" />
                </div>
                <p className="text-xl font-bold">{formatCurrency(stats.avgBasket)}</p>
              </CardContent>
            </Card>
            <Card className="border-0 shadow-sm">
              <CardContent className="p-4">
                <div className="flex items-center justify-between mb-1">
                  <p className="text-muted-foreground text-xs">Total Diskon</p>
                  <Package className="h-4 w-4 text-orange-500" />
                </div>
                <p className="text-xl font-bold text-red-500">{formatCurrency(stats.totalDiscount)}</p>
              </CardContent>
            </Card>
          </div>

          <Card className="border-0 shadow-sm">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-semibold">Grafik Penjualan</CardTitle>
            </CardHeader>
            <CardContent>
              <ResponsiveContainer width="100%" height={220}>
                <BarChart data={stats.salesChart} margin={{ top: 0, right: 0, left: -20, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                  <XAxis dataKey="label" tick={{ fontSize: 10 }} />
                  <YAxis tick={{ fontSize: 10 }} tickFormatter={v => v >= 1000000 ? `${(v/1000000).toFixed(1)}jt` : v >= 1000 ? `${(v/1000).toFixed(0)}rb` : String(v)} />
                  <Tooltip formatter={(val: number) => formatCurrency(val)} />
                  <Bar dataKey="total" fill="#10b981" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card className="border-0 shadow-sm">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-semibold">Produk Terlaris</CardTitle>
              </CardHeader>
              <CardContent>
                {stats.topProducts.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-4">Belum ada data penjualan</p>
                ) : (
                  <div className="space-y-2">
                    {stats.topProducts.map((p, i) => (
                      <div key={i} className="flex items-center gap-3">
                        <span className={`w-5 h-5 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0 ${i === 0 ? 'bg-amber-100 text-amber-700' : i === 1 ? 'bg-gray-100 text-gray-700' : i === 2 ? 'bg-orange-100 text-orange-700' : 'bg-muted text-muted-foreground'}`}>{i + 1}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium truncate">{p.name}</p>
                          <div className="w-full bg-muted rounded-full h-1.5 mt-1">
                            <div className="bg-emerald-500 h-1.5 rounded-full" style={{ width: `${Math.min(100, (p.total / (stats.topProducts[0]?.total || 1)) * 100)}%` }} />
                          </div>
                        </div>
                        <div className="text-right flex-shrink-0">
                          <p className="text-xs font-medium">{formatCurrency(p.total)}</p>
                          <p className="text-xs text-muted-foreground">{p.qty}x</p>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>

            <Card className="border-0 shadow-sm">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-semibold">Metode Pembayaran</CardTitle>
              </CardHeader>
              <CardContent>
                {stats.paymentMethods.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-4">Belum ada data pembayaran</p>
                ) : (
                  <div className="flex items-center gap-4">
                    <PieChart width={120} height={120}>
                      <Pie data={stats.paymentMethods} cx={55} cy={55} innerRadius={30} outerRadius={55} dataKey="value">
                        {stats.paymentMethods.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
                      </Pie>
                    </PieChart>
                    <div className="flex-1 space-y-2">
                      {stats.paymentMethods.map((m, i) => (
                        <div key={i} className="flex items-center justify-between text-sm">
                          <div className="flex items-center gap-1.5">
                            <div className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: COLORS[i % COLORS.length] }} />
                            <span className="text-muted-foreground">{m.name}</span>
                          </div>
                          <span className="font-medium">{formatCurrency(m.value)}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      )}
    </POSLayout>
  );
}
