import { useEffect, useMemo, useState } from 'react';
import { CheckCircle2, Circle, ExternalLink, Loader2 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { getPrinterSettings } from '@/lib/thermalPrinter';
import { Button } from '@/components/ui/button';

interface POSOnboardingChecklistProps {
  tenantId: string;
  tenantName: string;
  outletCount: number;
  activeOutletName?: string;
  enabledModuleCount: number;
}

export function POSOnboardingChecklist({
  tenantId,
  tenantName,
  outletCount,
  activeOutletName,
  enabledModuleCount,
}: POSOnboardingChecklistProps) {
  const navigate = useNavigate();
  const [hasSale, setHasSale] = useState<boolean | 'error' | null>(null);

  useEffect(() => {
    let mounted = true;
    void Promise.resolve(
      supabase
        .from('pos_sales' as never)
        .select('id', { count: 'exact', head: true })
        .eq('tenant_id', tenantId)
        .then(({ count, error }) => {
          if (mounted) setHasSale(error ? 'error' : (count || 0) > 0);
        }),
    )
      .catch(() => {
        if (mounted) setHasSale('error');
      });
    return () => { mounted = false; };
  }, [tenantId]);

  const printerReady = getPrinterSettings().autoPrint;
  const checks = useMemo(() => [
    { label: 'Workspace POS aktif', detail: tenantName, done: true, href: '/merchant/pos/pengaturan' },
    { label: 'Outlet pertama siap', detail: activeOutletName || `${outletCount} outlet terdaftar`, done: outletCount > 0, href: '/merchant/pos/pengaturan' },
    { label: 'Modul operasional dipilih', detail: `${enabledModuleCount} modul aktif`, done: enabledModuleCount > 0, href: '/merchant/pos/pengaturan' },
    { label: 'Printer struk (opsional)', detail: printerReady ? 'Print Bridge atau USB dipilih' : 'Belum dikonfigurasi — browser print masih tersedia', done: printerReady, optional: true, href: '/merchant/pos/pengaturan' },
    { label: 'Transaksi POS pertama', detail: hasSale === null ? 'Memeriksa transaksi...' : hasSale === 'error' ? 'Status transaksi belum dapat diverifikasi' : hasSale ? 'Transaksi berhasil tercatat' : 'Belum ada transaksi', done: hasSale === true, href: '/merchant/pos/kasir' },
  ], [activeOutletName, enabledModuleCount, hasSale, outletCount, printerReady, tenantName]);

  const requiredChecks = checks.filter((check) => !check.optional);
  const completed = requiredChecks.filter((check) => check.done).length;
  return (
    <section className="rounded-2xl border border-border bg-card p-5 shadow-sm sm:p-6" data-testid="pos-onboarding-checklist">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">Onboarding POS</p>
          <h3 className="mt-1 text-base font-semibold">Siap berjualan di outlet?</h3>
          <p className="mt-1 text-sm text-muted-foreground">{completed} dari {requiredChecks.length} langkah wajib selesai.</p>
        </div>
        <div className="h-2 w-32 overflow-hidden rounded-full bg-muted" aria-label={`${completed} dari ${requiredChecks.length} langkah wajib selesai`}>
          <div className="h-full rounded-full bg-emerald-600 transition-all" style={{ width: `${(completed / requiredChecks.length) * 100}%` }} />
        </div>
      </div>
      <div className="mt-5 grid gap-2 sm:grid-cols-2">
        {checks.map((check) => (
          <button
            key={check.label}
            type="button"
            onClick={() => navigate(check.href)}
            className="flex items-start gap-3 rounded-xl border border-border/70 p-3 text-left transition hover:border-emerald-400 hover:bg-emerald-50/40 dark:hover:bg-emerald-950/20"
          >
            {check.done ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> : check.detail === 'Memeriksa transaksi...' ? <Loader2 className="mt-0.5 h-4 w-4 shrink-0 animate-spin text-muted-foreground" /> : <Circle className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />}
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-medium">{check.label}</span>
              <span className="mt-0.5 block truncate text-xs text-muted-foreground">{check.detail}</span>
            </span>
            <ExternalLink className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          </button>
        ))}
      </div>
      {completed < requiredChecks.length && (
        <Button variant="link" className="mt-3 h-auto px-0 text-emerald-700 dark:text-emerald-300" onClick={() => navigate('/merchant/pos/kasir')}>
          Buka kasir untuk menyelesaikan onboarding
        </Button>
      )}
    </section>
  );
}
