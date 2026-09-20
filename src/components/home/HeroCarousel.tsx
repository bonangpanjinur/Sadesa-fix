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
  isSponsored?: boolean;
}

interface HeroCarouselProps {
  slides: BannerSlide[];
  autoPlayInterval?: number;
  onView?: (slideId: string) => void;
  onClick?: (slideId: string) => void;
}

const fallbackImages = [heroVillage, villageBojong, villageSukamaju];

export function HeroCarousel({ slides, autoPlayInterval = 5000, onView, onClick }: HeroCarouselProps) {
  const [currentIndex, setCurrentIndex] = useState(0);
  const [direction, setDirection] = useState(0);
  const [isPaused, setIsPaused] = useState(false);

  const slideCount = slides.length;

  useEffect(() => {
    if (slideCount === 0) return;
    setCurrentIndex((prev) => Math.min(prev, slideCount - 1));
  }, [slideCount]);

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
    if (slideCount <= 1 || isPaused) return;
    
    const interval = setInterval(nextSlide, autoPlayInterval);
    return () => clearInterval(interval);
  }, [nextSlide, autoPlayInterval, slideCount, isPaused]);

  const viewedSlideId = slides[currentIndex]?.id;
  useEffect(() => {
    if (viewedSlideId) onView?.(viewedSlideId);
  }, [viewedSlideId, onView]);

  if (slides.length === 0) {
    return (
      <section className="mx-5 mt-5 flex h-[10.5rem] items-center justify-center rounded-[1.5rem] bg-muted sm:mx-6">
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
    <motion.div
      initial="hidden"
      animate="visible"
      variants={{
        hidden: {},
        visible: { transition: { staggerChildren: 0.07, delayChildren: 0.08 } },
      }}
    >
      <motion.h2 className="max-w-[min(72vw,280px)] font-heading text-[1.5rem] font-extrabold leading-[1.05] tracking-[-0.025em] text-primary-foreground drop-shadow-[0_1px_3px_rgb(0_0_0/0.2)] sm:max-w-[340px] sm:text-2xl" variants={{ hidden: { opacity: 0, y: 8 }, visible: { opacity: 1, y: 0 } }} transition={{ duration: 0.25 }}>
        {currentSlide.title}
      </motion.h2>
      {currentSlide.subtitle && (
        <motion.p className="mt-2 max-w-[min(68vw,260px)] text-[0.78rem] font-medium leading-[1.4] text-white drop-shadow-[0_1px_2px_rgb(0_0_0/0.18)] sm:max-w-[300px] sm:text-sm" variants={{ hidden: { opacity: 0, y: 8 }, visible: { opacity: 1, y: 0 } }} transition={{ duration: 0.25 }}>
          {currentSlide.subtitle}
        </motion.p>
      )}
      {currentSlide.linkUrl && (
          <motion.span className="mt-5 inline-flex h-11 items-center gap-2 rounded-full bg-white px-5 text-sm font-extrabold text-primary shadow-[0_6px_16px_-10px_hsl(var(--primary)/0.45)] transition hover:bg-orange-50" variants={{ hidden: { opacity: 0, scale: 0.96 }, visible: { opacity: 1, scale: 1 } }} transition={{ duration: 0.22 }}>
          Lihat Sekarang
          <ChevronRight className="h-3.5 w-3.5" />
        </motion.span>
      )}
    </motion.div>
  );

  return (
    <section
      role="region"
      aria-roledescription="carousel"
      aria-label="Promo pilihan SaDesa"
      className="group relative mx-4 mt-5 h-[13.75rem] overflow-hidden rounded-[1.65rem] bg-muted shadow-[0_14px_32px_-20px_hsl(var(--primary)/0.35)] sm:mx-6 sm:h-[14.5rem]"
      onMouseEnter={() => setIsPaused(true)}
      onMouseLeave={() => setIsPaused(false)}
      onFocus={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setIsPaused(true);
      }}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setIsPaused(false);
      }}
    >
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
          <motion.img
            src={slideImage}
            alt={currentSlide.title}
            initial={{ scale: 1.08 }}
            animate={{ scale: 1 }}
            transition={{ duration: autoPlayInterval / 1000, ease: 'linear' }}
            className="h-full w-full object-cover"
          />
          <div className="absolute inset-0 flex items-center bg-gradient-to-r from-foreground/35 via-foreground/8 to-transparent">
            <div className="max-w-[78%] px-5 py-5 sm:max-w-[72%] sm:px-6">
              {currentSlide.linkUrl ? (
                <Link to={currentSlide.linkUrl} className="block" onClick={() => onClick?.(currentSlide.id)}>
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
            className="absolute left-3 top-1/2 z-10 h-10 w-10 -translate-y-1/2 rounded-full border border-white/70 bg-white/75 text-primary backdrop-blur-md transition hover:bg-white focus-visible:ring-2 focus-visible:ring-white/80"
            aria-label="Previous slide"
          >
            <ChevronLeft className="h-5 w-5" />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={nextSlide}
            className="absolute right-3 top-1/2 z-10 h-10 w-10 -translate-y-1/2 rounded-full border border-white/70 bg-white/75 text-primary backdrop-blur-md transition hover:bg-white focus-visible:ring-2 focus-visible:ring-white/80"
            aria-label="Next slide"
          >
            <ChevronRight className="h-5 w-5" />
          </Button>
        </>
      )}

      {/* Dot Indicators */}
      {slideCount > 1 && (
        <div className="absolute bottom-3.5 left-1/2 z-10 flex -translate-x-1/2 items-center gap-1.5 rounded-full bg-white/60 px-2.5 py-1.5 backdrop-blur-sm">
          {slides.map((_, index) => (
            <button
              key={index}
              type="button"
              onClick={() => goToSlide(index)}
              className={cn(
                "h-1.5 w-1.5 rounded-full transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white",
                index === currentIndex
                  ? "w-5 bg-white"
                  : "bg-primary/35 hover:bg-primary/60"
              )}
              aria-label={`Go to slide ${index + 1}`}
            />
          ))}
        </div>
      )}

      {slideCount > 1 && !isPaused && (
        <motion.div
          key={`progress-${currentIndex}`}
          className="absolute bottom-0 left-0 z-10 h-1 bg-accent"
          initial={{ width: '0%' }}
          animate={{ width: '100%' }}
          transition={{ duration: autoPlayInterval / 1000, ease: 'linear' }}
        />
      )}
    </section>
  );
}
