// Per-section skeleton placeholders for the Home page so the shell paints instantly.

export function HeroSkeleton() {
  return <div className="mx-5 mt-5 h-64 animate-pulse rounded-3xl bg-muted" />;
}

export function CategoriesSkeleton() {
  return (
    <section className="mt-7 px-5">
      <div className="mb-3 space-y-1.5">
        <div className="h-4 w-32 animate-pulse rounded bg-muted" />
        <div className="h-2.5 w-44 animate-pulse rounded bg-muted" />
      </div>
      <div className="grid grid-cols-2 gap-3">
        {[1, 2].map((i) => (
          <div key={i} className="flex h-20 items-center gap-3 rounded-2xl border border-border bg-card p-3">
            <div className="h-12 w-12 shrink-0 animate-pulse rounded-xl bg-muted" />
            <div className="flex-1 space-y-2">
              <div className="h-3 w-16 animate-pulse rounded bg-muted" />
              <div className="h-2 w-full animate-pulse rounded bg-muted" />
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

export function SectionHeaderSkeleton() {
  return (
    <div className="flex items-center gap-2 mb-3">
      <div className="w-7 h-7 bg-muted animate-pulse rounded-lg" />
      <div className="space-y-1.5">
        <div className="w-28 h-3 bg-muted animate-pulse rounded" />
        <div className="w-20 h-2 bg-muted animate-pulse rounded" />
      </div>
    </div>
  );
}

function CardSkeleton({ className = '' }: { className?: string }) {
  return (
    <div className={`overflow-hidden rounded-2xl border border-border bg-card p-2.5 ${className}`}>
      <div className="aspect-square animate-pulse rounded-xl bg-muted" />
      <div className="p-2.5 space-y-2">
        <div className="h-3 w-20 bg-muted animate-pulse rounded" />
        <div className="h-4 w-full bg-muted animate-pulse rounded" />
        <div className="flex justify-between items-center">
          <div className="h-4 w-16 bg-muted animate-pulse rounded" />
          <div className="h-6 w-6 bg-muted animate-pulse rounded-lg" />
        </div>
      </div>
    </div>
  );
}

export function CarouselSkeleton({ count = 3 }: { count?: number }) {
  return (
    <section className="mt-6 px-5">
      <SectionHeaderSkeleton />
      <div className="flex gap-3 overflow-hidden pb-2">
        {Array.from({ length: count }).map((_, i) => (
          <CardSkeleton key={i} className="min-w-[160px]" />
        ))}
      </div>
    </section>
  );
}

export function ProductGridSkeleton({ count = 4 }: { count?: number }) {
  return (
    <section className="mt-6 px-5">
      <SectionHeaderSkeleton />
      <div className="grid grid-cols-2 gap-3 pb-2">
        {Array.from({ length: count }).map((_, i) => (
          <CardSkeleton key={i} />
        ))}
      </div>
    </section>
  );
}
