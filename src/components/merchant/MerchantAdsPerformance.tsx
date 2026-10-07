import { BarChart3, Download, Eye, FileDown, MousePointerClick, TrendingUp } from 'lucide-react';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { loadPdfExportLibraries } from '@/lib/loadPdfExport';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { formatPrice } from '@/lib/utils';

interface MerchantAdPerformance {
  id: string;
  title: string;
  placement_type: string;
  status: string;
  payment_amount: number;
  view_count: number;
  click_count: number;
  start_date: string | null;
  end_date: string | null;
}

interface MerchantAdsPerformanceProps {
  ads: MerchantAdPerformance[];
}

const placementLabels: Record<string, string> = {
  home_banner: 'Banner di Atas Menu',
  search_top: 'Teratas Pencarian',
  category_top: 'Teratas Kategori',
  product_recommend: 'Rekomendasi Produk',
};

const statusLabels: Record<string, string> = {
  active: 'Aktif',
  pending: 'Menunggu',
  expired: 'Berakhir',
  rejected: 'Ditolak',
};

function formatDate(date: string | null) {
  if (!date) return 'Belum aktif';
  return new Intl.DateTimeFormat('id-ID', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(date));
}

function escapeCsv(value: string | number) {
  return `"${String(value).replace(/"/g, '""')}"`;
}

export function MerchantAdsPerformance({ ads }: MerchantAdsPerformanceProps) {
  const totalViews = ads.reduce((sum, ad) => sum + (ad.view_count || 0), 0);
  const totalClicks = ads.reduce((sum, ad) => sum + (ad.click_count || 0), 0);
  const totalSpend = ads.filter((ad) => ad.status !== 'rejected').reduce((sum, ad) => sum + (ad.payment_amount || 0), 0);
  const ctr = totalViews > 0 ? (totalClicks / totalViews) * 100 : 0;
  const chartData = [...ads].sort((a, b) => (b.view_count || 0) - (a.view_count || 0)).slice(0, 8).map((ad) => ({
    name: ad.title.length > 18 ? `${ad.title.slice(0, 18)}…` : ad.title,
    Impresi: ad.view_count || 0,
    Klik: ad.click_count || 0,
  }));

  const exportCsv = () => {
    const rows: (string | number)[][] = [
      ['Laporan Performa Iklan Merchant', new Date().toLocaleDateString('id-ID')],
      [],
      ['Ringkasan', 'Nilai'],
      ['Total impresi', totalViews],
      ['Total klik', totalClicks],
      ['CTR rata-rata', `${ctr.toFixed(2)}%`],
      ['Investasi iklan', totalSpend],
      [],
      ['Judul iklan', 'Penempatan', 'Status', 'Impresi', 'Klik', 'CTR', 'Mulai', 'Berakhir', 'Investasi'],
      ...ads.map((ad) => [
        ad.title,
        placementLabels[ad.placement_type] || ad.placement_type,
        statusLabels[ad.status] || ad.status,
        ad.view_count || 0,
        ad.click_count || 0,
        `${(ad.view_count > 0 ? (ad.click_count / ad.view_count) * 100 : 0).toFixed(2)}%`,
        formatDate(ad.start_date),
        formatDate(ad.end_date),
        ad.payment_amount || 0,
      ]),
    ];
    const csv = '\uFEFF' + rows.map((row) => row.map((cell) => escapeCsv(cell ?? '')).join(',')).join('\n');
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8;' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `laporan-performa-iklan-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  };

  const exportPdf = async () => {
    const { jsPDF, autoTable } = await loadPdfExportLibraries();
    const doc = new jsPDF({ orientation: 'landscape' });
    doc.setFontSize(16);
    doc.text('Laporan Performa Iklan Merchant', 14, 16);
    doc.setFontSize(9);
    doc.setTextColor(100);
    doc.text(`Dibuat: ${new Date().toLocaleString('id-ID')}`, 14, 23);
    doc.setTextColor(0);
    doc.text(`Total impresi: ${totalViews.toLocaleString('id-ID')}   Total klik: ${totalClicks.toLocaleString('id-ID')}   CTR: ${ctr.toFixed(2)}%   Investasi: ${formatPrice(totalSpend)}`, 14, 31);
    autoTable(doc, {
      startY: 38,
      head: [['Judul iklan', 'Penempatan', 'Status', 'Impresi', 'Klik', 'CTR', 'Periode', 'Investasi']],
      body: ads.map((ad) => [
        ad.title,
        placementLabels[ad.placement_type] || ad.placement_type,
        statusLabels[ad.status] || ad.status,
        (ad.view_count || 0).toLocaleString('id-ID'),
        (ad.click_count || 0).toLocaleString('id-ID'),
        `${(ad.view_count > 0 ? (ad.click_count / ad.view_count) * 100 : 0).toFixed(2)}%`,
        `${formatDate(ad.start_date)} - ${formatDate(ad.end_date)}`,
        formatPrice(ad.payment_amount),
      ]),
      styles: { fontSize: 8, cellPadding: 2 },
      headStyles: { fillColor: [234, 88, 12] },
    });
    doc.save(`laporan-performa-iklan-${new Date().toISOString().slice(0, 10)}.pdf`);
  };

  const metrics = [
    { label: 'Total impresi', value: totalViews.toLocaleString('id-ID'), icon: Eye, color: 'bg-blue-50 text-blue-600' },
    { label: 'Total klik', value: totalClicks.toLocaleString('id-ID'), icon: MousePointerClick, color: 'bg-purple-50 text-purple-600' },
    { label: 'CTR rata-rata', value: `${ctr.toFixed(1)}%`, icon: TrendingUp, color: 'bg-green-50 text-green-600' },
    { label: 'Investasi iklan', value: formatPrice(totalSpend), icon: BarChart3, color: 'bg-orange-50 text-orange-600' },
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {metrics.map((metric) => (
          <Card key={metric.label}><CardContent className="p-4"><div className="flex items-center gap-2"><div className={`rounded-lg p-2 ${metric.color}`}><metric.icon className="h-4 w-4" /></div><div className="min-w-0"><p className="truncate text-xs text-muted-foreground">{metric.label}</p><p className="text-lg font-bold">{metric.value}</p></div></div></CardContent></Card>
        ))}
      </div>

      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-3 pb-2">
          <div><CardTitle className="text-base">Impresi & klik per iklan</CardTitle><p className="text-xs text-muted-foreground">Performa agregat dari semua kampanye yang pernah diajukan.</p></div>
          <div className="flex shrink-0 gap-2">
            <Button variant="outline" size="sm" onClick={exportCsv} title="Download laporan CSV"><Download className="mr-1.5 h-3.5 w-3.5" /> CSV</Button>
            <Button variant="outline" size="sm" onClick={exportPdf} title="Download laporan PDF"><FileDown className="mr-1.5 h-3.5 w-3.5" /> PDF</Button>
          </div>
        </CardHeader>
        <CardContent>
          {chartData.length > 0 ? <div className="h-[260px] w-full"><ResponsiveContainer width="100%" height="100%"><BarChart data={chartData} margin={{ top: 8, right: 8, left: -18, bottom: 42 }} barGap={4}><CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-muted" /><XAxis dataKey="name" angle={-28} textAnchor="end" interval={0} height={58} tick={{ fontSize: 10 }} /><YAxis allowDecimals={false} tick={{ fontSize: 10 }} /><Tooltip formatter={(value: number) => value.toLocaleString('id-ID')} /><Bar dataKey="Impresi" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} /><Bar dataKey="Klik" fill="#8b5cf6" radius={[4, 4, 0, 0]} /></BarChart></ResponsiveContainer></div> : <div className="py-12 text-center text-sm text-muted-foreground">Belum ada data performa iklan.</div>}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Ringkasan per kampanye</CardTitle></CardHeader>
        <CardContent className="space-y-2">
          {ads.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Ajukan iklan pertama Anda untuk mulai melihat performa.</p> : ads.map((ad) => {
            const adCtr = ad.view_count > 0 ? (ad.click_count / ad.view_count) * 100 : 0;
            return <div key={ad.id} className="rounded-xl border p-3"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="truncate text-sm font-semibold">{ad.title}</p><p className="mt-0.5 text-xs text-muted-foreground">{placementLabels[ad.placement_type] || ad.placement_type}</p></div><Badge variant={ad.status === 'active' ? 'default' : ad.status === 'rejected' ? 'destructive' : 'secondary'}>{statusLabels[ad.status] || ad.status}</Badge></div><div className="mt-3 grid grid-cols-3 gap-2 text-center text-xs"><div className="rounded-lg bg-muted/50 p-2"><p className="text-muted-foreground">Impresi</p><p className="font-bold">{(ad.view_count || 0).toLocaleString('id-ID')}</p></div><div className="rounded-lg bg-muted/50 p-2"><p className="text-muted-foreground">Klik</p><p className="font-bold">{(ad.click_count || 0).toLocaleString('id-ID')}</p></div><div className="rounded-lg bg-muted/50 p-2"><p className="text-muted-foreground">CTR</p><p className="font-bold">{adCtr.toFixed(1)}%</p></div></div><div className="mt-2 flex justify-between text-[11px] text-muted-foreground"><span>{formatDate(ad.start_date)} — {formatDate(ad.end_date)}</span><span>{formatPrice(ad.payment_amount)}</span></div></div>;
          })}
        </CardContent>
      </Card>
    </div>
  );
}
