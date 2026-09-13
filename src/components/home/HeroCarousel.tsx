import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronRight, ChevronLeft } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';

// Import fallback images
import heroVillage from '@/assets/hero-village.jpg';
import villageBojong from '@/assets/village-bojong.jpg';
import villageSukamaju from '@/assets/village-sukamaju.jpg';

export interface BannerSlide {
  id: string;
  title: string;
  subtitle?: string;
  image?: string;
  linkUrl?: string;
}

interface HeroCarouselProps {
  slides: BannerSlide[];
  autoPlayInterval?: number;
}

const fallbackImages = [heroVillage, villageBojong, villageSukamaju];

export function HeroCarousel({ slides, autoPlayInterval = 5000 }: HeroCarouselProps) {
  const [currentIndex, setCurrentIndex] = useState(0);
  const [direction, setDirection] = useState(0);

  const slideCount = slides.length;

  const nextSlide = useCallback(() => {
    setDirection(1);
    setCurrentIndex((prev) => (prev + 1) % slideCount);
  }, [slideCount]);

  const prevSlide = useCallback(() => {
    setDirection(-1);
    setCurrentIndex((prev) => (prev - 1 + slideCount) % slideCount);
  }, [slideCount]);

  const goToSlide = (index: number) => {
    setDirection(index > currentIndex ? 1 : -1);
    setCurrentIndex(index);
  };

  // Auto-play
  useEffect(() => {
    if (slideCount <= 1) return;
    
    const interval = setInterval(nextSlide, autoPlayInterval);
    return () => clearInterval(interval);
  }, [nextSlide, autoPlayInterval, slideCount]);

  if (slides.length === 0) {
    return (
      <section className="mx-5 mt-5 flex h-[11.5rem] items-center justify-center rounded-[1.5rem] bg-muted sm:mx-6">
        <p className="text-muted-foreground text-sm">No banners available</p>
      </section>
    );
  }

  const currentSlide = slides[currentIndex];
  const slideImage = currentSlide.image || fallbackImages[currentIndex % fallbackImages.length];

  const variants = {
    enter: (direction: number) => ({
      x: direction > 0 ? '100%' : '-100%',
      opacity: 0,
    }),
    center: {
      x: 0,
      opacity: 1,
    },
    exit: (direction: number) => ({
      x: direction < 0 ? '100%' : '-100%',
      opacity: 0,
    }),
  };

  const slideContent = (
    <>
      <div className="mb-2 flex items-center gap-1.5">
          <span className="rounded-full bg-accent px-3 py-1.5 text-[9px] font-bold uppercase tracking-wide text-accent-foreground shadow-sm">
            Pilihan minggu ini
        </span>
      </div>
      <h2 className="max-w-[min(72vw,260px)] font-heading text-[1.3rem] font-bold leading-[1.12] text-primary-foreground sm:text-xl">
        {currentSlide.title}
      </h2>
      {currentSlide.subtitle && (
        <p className="mt-1.5 max-w-[min(68vw,240px)] text-[0.7rem] leading-relaxed text-primary-foreground/80 sm:text-xs">
          {currentSlide.subtitle}
        </p>
      )}
      {currentSlide.linkUrl && (
          <span className="mt-4 inline-flex items-center gap-1.5 rounded-full bg-card px-4 py-2.5 text-xs font-bold text-primary shadow-md transition hover:bg-secondary">
          Lihat Sekarang
          <ChevronRight className="h-3.5 w-3.5" />
        </span>
      )}
    </>
  );

  return (
    <section className="relative mx-5 mt-5 h-[13rem] overflow-hidden rounded-[1.5rem] bg-muted shadow-[0_16px_35px_-18px_hsl(var(--foreground)/0.65)] sm:mx-6 sm:h-48">
      <AnimatePresence initial={false} custom={direction} mode="popLayout">
        <motion.div
          key={currentIndex}
          custom={direction}
          variants={variants}
          initial="enter"
          animate="center"
          exit="exit"
          transition={{
            x: { type: 'spring', stiffness: 300, damping: 30 },
            opacity: { duration: 0.2 },
          }}
          className="absolute inset-0"
        >
          <img
            src={slideImage}
            alt={currentSlide.title}
            className="w-full h-full object-cover"
          />
          <div className="absolute inset-0 flex items-center bg-gradient-to-r from-foreground/90 via-foreground/60 to-foreground/5">
            <div className="px-5 py-4 sm:px-6">
              {currentSlide.linkUrl ? (
                <Link to={currentSlide.linkUrl} className="block">
                  {slideContent}
                </Link>
              ) : (
                <div>{slideContent}</div>
              )}
            </div>
          </div>
        </motion.div>
      </AnimatePresence>

      {/* Navigation Arrows */}
      {slideCount > 1 && (
        <>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={prevSlide}
            className="absolute left-2 top-1/2 z-10 h-8 w-8 -translate-y-1/2 rounded-lg bg-background/35 text-primary-foreground backdrop-blur-sm hover:bg-background/55"
            aria-label="Previous slide"
          >
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={nextSlide}
            className="absolute right-2 top-1/2 z-10 h-8 w-8 -translate-y-1/2 rounded-lg bg-background/35 text-primary-foreground backdrop-blur-sm hover:bg-background/55"
            aria-label="Next slide"
          >
            <ChevronRight className="h-4 w-4" />
          </Button>
        </>
      )}

      {/* Dot Indicators */}
      {slideCount > 1 && (
        <div className="absolute bottom-3 left-1/2 -translate-x-1/2 flex gap-1.5 z-10">
          {slides.map((_, index) => (
            <button
              key={index}
              onClick={() => goToSlide(index)}
              className={cn(
                "w-1.5 h-1.5 rounded-full transition-all",
                index === currentIndex
                  ? "bg-primary-foreground w-4"
                  : "bg-primary-foreground/40 hover:bg-primary-foreground/60"
              )}
              aria-label={`Go to slide ${index + 1}`}
            />
          ))}
        </div>
      )}
    </section>
  );
}
