import { ReactNode } from 'react';
import { AlertCircle, CheckCircle2, ChevronLeft, ChevronRight, Inbox, Loader2, RefreshCw, Search } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

interface AdminPageHeaderProps {
  title: string;
  description?: string;
  eyebrow?: string;
  actions?: ReactNode;
}

export function AdminPageHeader({ title, description, eyebrow, actions }: AdminPageHeaderProps) {
  return (
    <div className="mb-6 flex flex-col gap-4 border-b border-border pb-5 sm:flex-row sm:items-end sm:justify-between">
      <div className="min-w-0">
        {eyebrow && <p className="mb-1 text-[10px] font-bold uppercase tracking-[0.16em] text-primary">{eyebrow}</p>}
        <h2 className="text-xl font-bold tracking-tight text-foreground sm:text-2xl">{title}</h2>
        {description && <p className="mt-1 max-w-2xl text-sm text-muted-foreground">{description}</p>}
      </div>
      {actions && <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

interface AdminStatePanelProps {
  type: 'loading' | 'empty' | 'error' | 'success';
  title?: string;
  description?: string;
  actionLabel?: string;
  onAction?: () => void;
  className?: string;
}

const stateDefaults = {
  loading: { title: 'Memuat data...', description: 'Mohon tunggu sebentar.' },
  empty: { title: 'Belum ada data', description: 'Belum ada informasi yang dapat ditampilkan.' },
  error: { title: 'Data gagal dimuat', description: 'Terjadi kendala saat mengambil data. Silakan coba lagi.' },
  success: { title: 'Berhasil', description: '' },
};

export function AdminStatePanel({ type, title, description, actionLabel, onAction, className }: AdminStatePanelProps) {
  const defaults = stateDefaults[type];
  const Icon = type === 'loading' ? Loader2 : type === 'empty' ? Inbox : type === 'error' ? AlertCircle : CheckCircle2;
  const iconClass = type === 'error' ? 'text-destructive' : type === 'success' ? 'text-emerald-600' : 'text-primary';

  return (
    <div className={cn('flex min-h-[220px] flex-col items-center justify-center rounded-xl border border-dashed border-border bg-card/60 p-8 text-center', className)} role={type === 'error' ? 'alert' : undefined}>
      <Icon className={cn('mb-3 h-9 w-9', iconClass, type === 'loading' && 'animate-spin')} />
      <h3 className="text-sm font-semibold text-foreground">{title || defaults.title}</h3>
      {(description || defaults.description) && <p className="mt-1 max-w-md text-xs text-muted-foreground">{description || defaults.description}</p>}
      {onAction && actionLabel && (
        <Button type="button" variant="outline" size="sm" className="mt-4 gap-2" onClick={onAction}>
          {type === 'error' && <RefreshCw className="h-3.5 w-3.5" />}
          {actionLabel}
        </Button>
      )}
    </div>
  );
}

interface AdminFilterBarProps {
  search?: string;
  onSearchChange?: (value: string) => void;
  searchPlaceholder?: string;
  children?: ReactNode;
  onReset?: () => void;
  hasFilters?: boolean;
  actions?: ReactNode;
}

export function AdminFilterBar({ search = '', onSearchChange, searchPlaceholder = 'Cari data...', children, onReset, hasFilters = false, actions }: AdminFilterBarProps) {
  return (
    <div className="mb-4 flex flex-col gap-3 rounded-xl border border-border bg-card p-3 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex min-w-0 flex-1 flex-col gap-2 sm:flex-row sm:items-center">
        {onSearchChange && (
          <div className="relative min-w-0 flex-1 sm:max-w-sm">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input value={search} onChange={(event) => onSearchChange(event.target.value)} placeholder={searchPlaceholder} className="pl-9" aria-label={searchPlaceholder} />
          </div>
        )}
        {children && <div className="flex flex-wrap items-center gap-2">{children}</div>}
        {hasFilters && onReset && <Button type="button" variant="ghost" size="sm" onClick={onReset}>Reset</Button>}
      </div>
      {actions && <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

interface AdminPaginationProps {
  page: number;
  totalPages: number;
  totalItems: number;
  pageSize: number;
  onPageChange: (page: number) => void;
}

export function AdminPagination({ page, totalPages, totalItems, pageSize, onPageChange }: AdminPaginationProps) {
  if (totalPages <= 1) return null;
  const start = (page - 1) * pageSize + 1;
  const end = Math.min(page * pageSize, totalItems);

  return (
    <div className="mt-4 flex flex-col gap-3 text-xs text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
      <span>Menampilkan <strong className="text-foreground">{start}–{end}</strong> dari <strong className="text-foreground">{totalItems}</strong> data</span>
      <div className="flex items-center gap-2">
        <Button type="button" variant="outline" size="icon" className="h-8 w-8" onClick={() => onPageChange(Math.max(1, page - 1))} disabled={page <= 1} aria-label="Halaman sebelumnya">
          <ChevronLeft className="h-4 w-4" />
        </Button>
        <span className="min-w-16 text-center font-medium text-foreground">{page} / {totalPages}</span>
        <Button type="button" variant="outline" size="icon" className="h-8 w-8" onClick={() => onPageChange(Math.min(totalPages, page + 1))} disabled={page >= totalPages} aria-label="Halaman berikutnya">
          <ChevronRight className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
