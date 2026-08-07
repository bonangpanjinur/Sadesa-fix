// Per-section skeleton placeholders for the Home page so the shell paints instantly.

export function HeroSkeleton() {
  return <div className="h-44 bg-muted animate-pulse rounded-b-2xl" />;
}

export function CategoriesSkeleton() {
  return (
    <section className="mt-4 px-5">
      <div className="flex gap-2 overflow-hidden pb-2">
        {[1, 2, 3, 4, 5].map((i) => (
          <div key={i} className="flex flex-col items-center gap-1.5 min-w-[60px]">
            <div className="w-12 h-12 rounded-2xl bg-muted animate-pulse" />
            <div className="w-10 h-2 bg-muted animate-pulse rounded" />
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
    <div className={`bg-card rounded-xl border border-border overflow-hidden ${className}`}>
      <div className="h-32 bg-muted animate-pulse" />
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
