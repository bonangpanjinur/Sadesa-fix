import { ArrowRight, Bike, Box, Clock3, ShieldCheck } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Card } from '@/components/ui/card';

const services = [
  {
    href: '/ride/passenger',
    icon: Bike,
    eyebrow: 'OJEK PENUMPANG',
    title: 'Antar Anda dengan aman',
    description: 'Jemput dari lokasi Anda dan antar sampai tujuan.',
    accent: 'bg-emerald-100 text-emerald-700',
    iconBackground: 'bg-emerald-600',
  },
  {
    href: '/ride/courier',
    icon: Box,
    eyebrow: 'KURIR BARANG',
    title: 'Antar barang',
    description: 'Kurir mengambil barang dari pickup lalu mengantarkannya ke tujuan.',
    accent: 'bg-amber-100 text-amber-700',
    iconBackground: 'bg-amber-500',
  },
];

interface TransportServiceCardsProps {
  compact?: boolean;
}

export function TransportServiceCards({ compact = false }: TransportServiceCardsProps) {
  return (
    <div className={compact ? 'grid gap-3 sm:grid-cols-2' : 'grid gap-4'}>
      {services.map(({ href, icon: Icon, eyebrow, title, description, accent, iconBackground }) => (
        <Link key={href} to={href} className="group">
          <Card className="h-full overflow-hidden border-border/70 transition hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md">
            <div className="flex items-start gap-4 p-4">
              <div className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl ${iconBackground} text-white shadow-sm`}>
                <Icon className="h-6 w-6" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="mb-1 flex items-center gap-2">
                  <span className={`rounded-full px-2 py-0.5 text-[9px] font-bold uppercase tracking-wide ${accent}`}>
                    {eyebrow}
                  </span>
                  <ArrowRight className="ml-auto h-4 w-4 shrink-0 text-muted-foreground transition group-hover:translate-x-0.5 group-hover:text-primary" />
                </div>
                <h3 className="font-heading text-sm font-bold text-foreground">{title}</h3>
                <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{description}</p>
              </div>
            </div>
            <div className="flex items-center gap-3 border-t border-border/60 bg-muted/30 px-4 py-2.5 text-[10px] text-muted-foreground">
              {href.endsWith('passenger') ? (
                <>
                  <span className="flex items-center gap-1"><Clock3 className="h-3 w-3" /> Jemput sekarang</span>
                  <span className="flex items-center gap-1"><ShieldCheck className="h-3 w-3" /> Mitra terverifikasi</span>
                </>
              ) : (
                <>
                  <span className="flex items-center gap-1"><Clock3 className="h-3 w-3" /> Bisa dijadwalkan</span>
                  <span className="flex items-center gap-1"><ShieldCheck className="h-3 w-3" /> Bukti pengantaran</span>
                </>
              )}
            </div>
          </Card>
        </Link>
      ))}
    </div>
  );
}
