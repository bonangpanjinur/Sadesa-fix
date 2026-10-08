import { useState, useEffect } from 'react';
import { Star, User } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { ReviewImageGallery } from '@/components/reviews/ReviewImageGallery';

interface Review {
  id: string;
  rating: number;
  comment: string | null;
  created_at: string;
  image_urls: string[] | null;
  buyer_name?: string;
}

type ReviewSort = 'newest' | 'highest' | 'lowest';

export function ProductReviews({ merchantId }: { merchantId: string }) {
  const [reviews, setReviews] = useState<Review[]>([]);
  const [loading, setLoading] = useState(true);
  const [sortBy, setSortBy] = useState<ReviewSort>('newest');

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setLoading(true);
      const baseQuery = supabase
        .from('reviews')
        .select('id, rating, comment, created_at, image_urls')
        .eq('merchant_id', merchantId);
      const orderedQuery = sortBy === 'highest'
        ? baseQuery.order('rating', { ascending: false }).order('created_at', { ascending: false })
        : sortBy === 'lowest'
          ? baseQuery.order('rating', { ascending: true }).order('created_at', { ascending: false })
          : baseQuery.order('created_at', { ascending: false });

      try {
        const { data } = await orderedQuery.limit(5);
        if (!cancelled) setReviews(data || []);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    void load();
    return () => { cancelled = true; };
  }, [merchantId, sortBy]);

  if (loading) return null;
  if (reviews.length === 0) return null;

  return (
    <div className="mb-6">
      <div className="mb-3 flex items-center justify-between gap-3">
        <h3 className="font-bold text-sm text-foreground">Ulasan Pembeli</h3>
        <label className="flex items-center gap-2 text-xs text-muted-foreground">
          <span className="shrink-0">Urutkan</span>
          <select
            aria-label="Urutkan ulasan produk"
            value={sortBy}
            onChange={(event) => setSortBy(event.target.value as ReviewSort)}
            className="rounded-md border border-border bg-background px-2 py-1.5 text-xs text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <option value="newest">Terbaru</option>
            <option value="highest">Rating tertinggi</option>
            <option value="lowest">Rating terendah</option>
          </select>
        </label>
      </div>
      <div className="space-y-3">
        {reviews.map((review) => (
          <div key={review.id} className="bg-secondary rounded-xl p-3 border border-border">
            <div className="flex items-center gap-2 mb-1.5">
              <div className="w-6 h-6 rounded-full bg-muted flex items-center justify-center">
                <User className="h-3 w-3 text-muted-foreground" />
              </div>
              <span className="text-xs text-muted-foreground">Pembeli</span>
              <div className="flex items-center gap-0.5 ml-auto">
                {Array.from({ length: 5 }).map((_, i) => (
                  <Star
                    key={i}
                    className={`h-3 w-3 ${i < review.rating ? 'fill-gold text-gold' : 'text-muted'}`}
                  />
                ))}
              </div>
            </div>
            {review.comment && (
              <p className="text-xs text-foreground/80 leading-relaxed">{review.comment}</p>
            )}
            <ReviewImageGallery imageUrls={review.image_urls} className="mt-2 flex flex-wrap gap-2" />
            <p className="text-[10px] text-muted-foreground mt-1">
              {new Date(review.created_at).toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' })}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
