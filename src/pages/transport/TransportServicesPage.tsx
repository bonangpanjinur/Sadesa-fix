import { useEffect, useState } from 'react';
import { ArrowLeft, Bike, ChevronRight, History, Loader2 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { TransportServiceCards } from '@/components/transport/TransportServiceCards';
import { supabase } from '@/integrations/supabase/client';

export default function TransportServicesPage() {
  const navigate = useNavigate();
  const [onlineCourierCount, setOnlineCourierCount] = useState<number | null>(null);
  const [availabilityLoading, setAvailabilityLoading] = useState(true);

  useEffect(() => {
    let disposed = false;

    const loadAvailability = async () => {
      setAvailabilityLoading(true);
      const { count, error } = await supabase
        .from('public_couriers')
        .select('id', { count: 'exact', head: true })
        .eq('is_available', true)
        .eq('status', 'ACTIVE');

      if (disposed) return;
      setOnlineCourierCount(error ? null : count ?? 0);
      setAvailabilityLoading(false);
    };

    void loadAvailability();
    const refresh = window.setInterval(() => void loadAvailability(), 30000);

    return () => {
      disposed = true;
      window.clearInterval(refresh);
    };
  }, []);

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

        {(availabilityLoading || onlineCourierCount !== null) && (
          <div className="mb-4 flex items-center gap-3 rounded-2xl border border-emerald-200 bg-emerald-50/70 px-4 py-3 dark:border-emerald-900 dark:bg-emerald-950/25">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-600 text-white">
              {availabilityLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Bike className="h-4 w-4" />}
            </div>
            <div className="min-w-0">
              <p className="text-sm font-semibold text-foreground">
                {availabilityLoading
                  ? 'Memeriksa ojek online...'
                  : onlineCourierCount === 0
                    ? 'Belum ada ojek online saat ini'
                    : `${onlineCourierCount} ojek sedang online`}
              </p>
              <p className="mt-0.5 text-xs text-muted-foreground">
                Peta dan posisi ojek tampil setelah Anda memilih Ojek Penumpang.
              </p>
            </div>
          </div>
        )}

        <TransportServiceCards />

        <div className="mt-6 space-y-3">
          <p className="px-1 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Akses cepat</p>
          <Button variant="outline" className="h-11 w-full justify-between rounded-xl" onClick={() => navigate('/ride/history')}>
            <span className="flex items-center gap-2"><History className="h-4 w-4 text-primary" /> Riwayat perjalanan</span>
            <ChevronRight className="h-4 w-4 text-muted-foreground" />
          </Button>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}
