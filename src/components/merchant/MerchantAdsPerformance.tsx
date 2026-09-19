import { BarChart3, Eye, MousePointerClick, TrendingUp } from 'lucide-react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
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

export function MerchantAdsPerformance({ ads }: MerchantAdsPerformanceProps) {
  const totalViews = ads.reduce((sum, ad) => sum + (ad.view_count || 0), 0);
  const totalClicks = ads.reduce((sum, ad) => sum + (ad.click_count || 0), 0);
  const totalSpend = ads.filter((ad) => ad.status !== 'rejected').reduce((sum, ad) => sum + (ad.payment_amount || 0), 0);
  const ctr = totalViews > 0 ? (totalClicks / totalViews) * 100 : 0;
  const chartData = [...ads]
    .sort((a, b) => (b.view_count || 0) - (a.view_count || 0))
    .slice(0, 8)
    .map((ad) => ({
      name: ad.title.length > 18 ? `${ad.title.slice(0, 18)}…` : ad.title,
      Impresi: ad.view_count || 0,
      Klik: ad.click_count || 0,
    }));

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
          <Card key={metric.label}>
            <CardContent className="p-4">
              <div className="flex items-center gap-2">
                <div className={`rounded-lg p-2 ${metric.color}`}><metric.icon className="h-4 w-4" /></div>
                <div className="min-w-0">
                  <p className="truncate text-xs text-muted-foreground">{metric.label}</p>
                  <p className="text-lg font-bold">{metric.value}</p>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Impresi & klik per iklan</CardTitle>
          <p className="text-xs text-muted-foreground">Performa agregat dari semua kampanye yang pernah diajukan.</p>
        </CardHeader>
        <CardContent>
          {chartData.length > 0 ? (
            <div className="h-[260px] w-full">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartData} margin={{ top: 8, right: 8, left: -18, bottom: 42 }} barGap={4}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-muted" />
                  <XAxis dataKey="name" angle={-28} textAnchor="end" interval={0} height={58} tick={{ fontSize: 10 }} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 10 }} />
                  <Tooltip formatter={(value: number) => value.toLocaleString('id-ID')} />
                  <Bar dataKey="Impresi" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="Klik" fill="#8b5cf6" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          ) : (
            <div className="py-12 text-center text-sm text-muted-foreground">Belum ada data performa iklan.</div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Ringkasan per kampanye</CardTitle></CardHeader>
        <CardContent className="space-y-2">
          {ads.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">Ajukan iklan pertama Anda untuk mulai melihat performa.</p>
          ) : (
            ads.map((ad) => {
              const adCtr = ad.view_count > 0 ? (ad.click_count / ad.view_count) * 100 : 0;
              return (
                <div key={ad.id} className="rounded-xl border p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold">{ad.title}</p>
                      <p className="mt-0.5 text-xs text-muted-foreground">{placementLabels[ad.placement_type] || ad.placement_type}</p>
                    </div>
                    <Badge variant={ad.status === 'active' ? 'default' : ad.status === 'rejected' ? 'destructive' : 'secondary'}>
                      {statusLabels[ad.status] || ad.status}
                    </Badge>
                  </div>
                  <div className="mt-3 grid grid-cols-3 gap-2 text-center text-xs">
                    <div className="rounded-lg bg-muted/50 p-2"><p className="text-muted-foreground">Impresi</p><p className="font-bold">{(ad.view_count || 0).toLocaleString('id-ID')}</p></div>
                    <div className="rounded-lg bg-muted/50 p-2"><p className="text-muted-foreground">Klik</p><p className="font-bold">{(ad.click_count || 0).toLocaleString('id-ID')}</p></div>
                    <div className="rounded-lg bg-muted/50 p-2"><p className="text-muted-foreground">CTR</p><p className="font-bold">{adCtr.toFixed(1)}%</p></div>
                  </div>
                  <div className="mt-2 flex justify-between text-[11px] text-muted-foreground">
                    <span>{formatDate(ad.start_date)} — {formatDate(ad.end_date)}</span>
                    <span>{formatPrice(ad.payment_amount)}</span>
                  </div>
                </div>
              );
            })
          )}
        </CardContent>
      </Card>
    </div>
  );
}
