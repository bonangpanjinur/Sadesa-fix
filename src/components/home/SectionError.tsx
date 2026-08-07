import { AlertTriangle, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface SectionErrorProps {
  title?: string;
  message?: string;
  onRetry: () => void;
  compact?: boolean;
}

export function SectionError({
  title = 'Gagal memuat data',
  message = 'Terjadi kesalahan saat mengambil data. Coba lagi.',
  onRetry,
  compact = false,
}: SectionErrorProps) {
  return (
    <section className={compact ? 'mt-4 px-5' : 'mt-6 px-5'}>
      <div className="rounded-xl border border-border bg-card p-4 flex items-start gap-3">
        <div className="w-8 h-8 rounded-lg bg-destructive/10 text-destructive flex items-center justify-center shrink-0">
          <AlertTriangle className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-foreground">{title}</p>
          <p className="text-xs text-muted-foreground mt-0.5">{message}</p>
          <Button
            variant="outline"
            size="sm"
            onClick={onRetry}
            className="mt-3 h-7 text-xs rounded-full"
          >
            <RefreshCw className="h-3 w-3 mr-1.5" />
            Coba Lagi
          </Button>
        </div>
      </div>
    </section>
  );
}
