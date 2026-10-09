import { ArrowLeft, ChevronRight, History } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { TransportServiceCards } from '@/components/transport/TransportServiceCards';

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
