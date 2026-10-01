import { ArrowLeft, Bike, Box, ChevronRight, History, MapPin } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { TransportServiceCards } from '@/components/transport/TransportServiceCards';
import { BUSINESS_PROFILE } from '@/config/businessProfile';

export default function TransportServicesPage() {
  const navigate = useNavigate();

  return (
    <div className="mobile-shell min-h-screen bg-background">
      <Header />
      <main className="px-5 pb-28 pt-5">
        <div className="mb-6 flex items-center gap-3">
          <Button variant="ghost" size="icon" className="h-9 w-9" onClick={() => navigate('/')}>
            <ArrowLeft className="h-4 w-4" />
            <span className="sr-only">Kembali</span>
          </Button>
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wide text-primary">Layanan antar</p>
            <h1 className="font-heading text-xl font-bold">Pilih layanan Anda</h1>
          </div>
        </div>

        <Card className="mb-5 overflow-hidden border-0 bg-primary p-5 text-primary-foreground shadow-[var(--shadow-brand)]">
          <div className="flex items-start gap-3">
            <div className="rounded-xl bg-white/15 p-2.5">
              <MapPin className="h-5 w-5" />
            </div>
            <div>
              <h2 className="font-heading text-base font-bold">Antar dari desa, untuk Anda</h2>
              <p className="mt-1 text-xs leading-relaxed text-primary-foreground/80">
                Pesan ojek penumpang atau gunakan layanan Antar Barang dalam satu tempat.
              </p>
            </div>
          </div>
        </Card>

        <Card className="mb-5 border-emerald-200 bg-emerald-50/60 dark:border-emerald-900 dark:bg-emerald-950/20">
          <CardContent className="space-y-3 p-4 text-sm">
            <div><p className="text-xs font-bold uppercase tracking-wide text-primary">Informasi layanan publik</p><p className="mt-1 leading-relaxed text-muted-foreground">Layanan tersedia di {BUSINESS_PROFILE.serviceArea}</p></div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div><p className="font-semibold">Contoh tarif</p><p className="text-muted-foreground">Ojek penumpang mulai Rp10.000. Kurir barang mulai Rp8.000. Tarif final dihitung berdasarkan jarak, jenis layanan, dan detail pesanan.</p></div>
              <div><p className="font-semibold">Cara pemesanan</p><p className="text-muted-foreground">Pilih layanan, isi titik jemput dan tujuan, tinjau estimasi tarif, lalu konfirmasi setelah login.</p></div>
            </div>
          </CardContent>
        </Card>

        <TransportServiceCards />

        <div className="mt-6 space-y-3">
          <p className="px-1 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Akses cepat</p>
          <Button variant="outline" className="h-11 w-full justify-between rounded-xl" onClick={() => navigate('/ride/history')}>
            <span className="flex items-center gap-2"><History className="h-4 w-4 text-primary" /> Riwayat perjalanan</span>
            <ChevronRight className="h-4 w-4 text-muted-foreground" />
          </Button>
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-3 dark:border-emerald-900 dark:bg-emerald-950/30">
              <Bike className="mb-2 h-5 w-5 text-emerald-600" />
              <p className="text-xs font-bold">Ojek penumpang</p>
              <p className="mt-1 text-[10px] leading-relaxed text-muted-foreground">Estimasi tarif sebelum konfirmasi.</p>
            </div>
            <div className="rounded-xl border border-amber-200 bg-amber-50 p-3 dark:border-amber-900 dark:bg-amber-950/30">
              <Box className="mb-2 h-5 w-5 text-amber-600" />
              <p className="text-xs font-bold">Kurir barang</p>
              <p className="mt-1 text-[10px] leading-relaxed text-muted-foreground">Kurir mengambil dari pickup dan mengantar ke tujuan.</p>
            </div>
          </div>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}
