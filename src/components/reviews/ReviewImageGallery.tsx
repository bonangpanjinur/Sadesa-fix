import { useState } from 'react';
import { ImageLightbox } from '@/components/ui/ImageLightbox';

interface ReviewImageGalleryProps {
  imageUrls: string[] | null | undefined;
  className?: string;
}

export function ReviewImageGallery({ imageUrls, className }: ReviewImageGalleryProps) {
  const images = Array.isArray(imageUrls)
    ? imageUrls.filter((url): url is string => typeof url === 'string' && url.trim().length > 0)
    : [];
  const [activeIndex, setActiveIndex] = useState(0);
  const [open, setOpen] = useState(false);

  if (images.length === 0) return null;

  return (
    <>
      <div className={className || 'mt-2 flex flex-wrap gap-2'} aria-label="Foto ulasan pembeli">
        {images.map((url, index) => (
          <button
            key={`${url}-${index}`}
            type="button"
            onClick={() => {
              setActiveIndex(index);
              setOpen(true);
            }}
            aria-label={`Buka foto ulasan ${index + 1}`}
            className="h-20 w-20 shrink-0 overflow-hidden rounded-lg border border-border bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <img
              src={url}
              alt={`Foto dari ulasan pembeli ${index + 1}`}
              loading="lazy"
              className="h-full w-full object-cover transition-transform hover:scale-105"
            />
          </button>
        ))}
      </div>
      <ImageLightbox images={images} initialIndex={activeIndex} open={open} onOpenChange={setOpen} />
    </>
  );
}
