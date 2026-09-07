import { AlertCircle, Loader2, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';

export function MerchantCardLoading({ label = 'Memuat data...' }: { label?: string }) {
  return (
    <div className="flex min-h-32 items-center justify-center rounded-xl border border-dashed bg-card p-5">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin text-primary" aria-hidden="true" />
        {label}
      </div>
    </div>
  );
}

export function MerchantCardError({
  message = 'Data belum dapat dimuat.',
  onRetry,
}: {
  message?: string;
  onRetry?: () => void;
}) {
  return (
    <div role="alert" className="rounded-xl border border-destructive/25 bg-destructive/5 p-5">
      <div className="flex items-start gap-3">
        <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-destructive" aria-hidden="true" />
        <div className="min-w-0">
          <p className="text-sm font-semibold">Data belum dapat dimuat</p>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">{message}</p>
          {onRetry && (
            <Button type="button" variant="outline" size="sm" className="mt-3" onClick={onRetry}>
              <RefreshCw className="mr-2 h-3.5 w-3.5" aria-hidden="true" />
              Coba lagi
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}