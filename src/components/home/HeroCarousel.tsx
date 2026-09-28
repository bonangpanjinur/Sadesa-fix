import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronRight, ChevronLeft } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';

// Local fallback assets keep the first carousel render independent of remote image hosts.
import heroVillage from '@/assets/hero-village.webp';
import villageBojong from '@/assets/village-bojong.webp';
import villageSukamaju from '@/assets/village-sukamaju.webp';
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

export function HeroCarousel({ slides, autoPlayInterval = 5000, onView, onClick }: HeroCarouselProps) {
  const [currentIndex, setCurrentIndex] = useState(0);
  const [direction, setDirection] = useState(0);
  const [isPaused, setIsPaused] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(false);

  const slideCount = slides.length;

  useEffect(() => {
    if (slideCount === 0) return;
    setCurrentIndex((prev) => Math.min(prev, slideCount - 1));
  }, [slideCount]);

  useEffect(() => {
    const mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    const updateMotionPreference = () => setReducedMotion(mediaQuery.matches);
    updateMotionPreference();
    mediaQuery.addEventListener('change', updateMotionPreference);
    return () => mediaQuery.removeEventListener('change', updateMotionPreference);
  }, []);

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
    if (slideCount <= 1 || isPaused || reducedMotion) return;
    
    const interval = setInterval(nextSlide, autoPlayInterval);
    return () => clearInterval(interval);
  }, [nextSlide, autoPlayInterval, slideCount, isPaused, reducedMotion]);

  const viewedSlideId = slides[currentIndex]?.id;
  useEffect(() => {
    if (viewedSlideId) onView?.(viewedSlideId);
  }, [viewedSlideId, onView]);

  if (slides.length === 0) {
    return null;
  }

  const currentSlide = slides[currentIndex];
  const promoCopy = (
        <div className="max-w-[15rem] sm:max-w-md">
          <h2 className="line-clamp-2 font-serif text-[1.35rem] font-bold leading-[0.98] tracking-[-0.025em] text-white sm:text-2xl">{currentSlide.title}</h2>
          {currentSlide.subtitle && <p className="mt-1 line-clamp-2 text-[9px] leading-snug text-white/85 sm:text-xs">{currentSlide.subtitle}</p>}
          {currentSlide.linkUrl && (
            <span className="mt-2 inline-flex h-8 items-center gap-1.5 rounded-full bg-white px-3 text-[10px] font-bold text-[#015730] shadow-sm transition group-hover:bg-[#f1f8ec] sm:text-xs">
              Jelajahi sekarang
              <ChevronRight className="h-3.5 w-3.5" aria-hidden="true" />
            </span>
          )}
    </div>
  );

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

  return (
    <section
      role="region"
      aria-roledescription="carousel"
      aria-label="Promo pilihan SaDesa"
      className="group relative mx-4 overflow-hidden rounded-[1.25rem] border border-[#015730]/15 bg-[#015730] shadow-[0_14px_28px_-18px_rgba(1,87,48,0.65)] sm:mx-5"
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
          transition={reducedMotion ? { duration: 0 } : {
            x: { type: 'spring', stiffness: 300, damping: 30 },
            opacity: { duration: 0.2 },
          }}
          className="relative"
        >
          <div className="relative aspect-[2.6/1] w-full overflow-hidden bg-[#015730] sm:aspect-[3/1]">
            {currentSlide.image && (
              <motion.img
                src={currentSlide.image}
                alt={currentSlide.title}
                loading="eager"
                decoding="async"
                fetchPriority="high"
                initial={{ scale: 1.08 }}
                animate={{ scale: 1 }}
                transition={{ duration: reducedMotion ? 0 : autoPlayInterval / 1000, ease: 'linear' }}
                className="absolute inset-0 h-full w-full object-cover"
              />
            )}
            <div className="absolute inset-0 bg-gradient-to-r from-[#015730] via-[#015730]/90 to-[#0c7749]/15" />
            {currentSlide.linkUrl ? (
              <Link to={currentSlide.linkUrl} onClick={() => onClick?.(currentSlide.id)} className="group absolute inset-y-0 left-0 z-[1] flex w-[70%] items-center px-4 py-3 text-white sm:w-[64%] sm:px-6">
                {promoCopy}
              </Link>
            ) : (
              <div className="absolute inset-y-0 left-0 z-[1] flex w-[70%] items-center px-4 py-3 text-white sm:w-[64%] sm:px-6">{promoCopy}</div>
            )}
            {slideCount > 1 && (
              <div className="absolute bottom-2 left-1/2 z-[2] flex -translate-x-1/2 items-center gap-1.5 rounded-full bg-white/80 px-2 py-1 backdrop-blur-sm">
                {slides.map((_, index) => (
                  <button
                    key={index}
                    type="button"
                    onClick={() => goToSlide(index)}
                    className={cn('h-1.5 w-1.5 rounded-full transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#44a31b]', index === currentIndex ? 'w-4 bg-[#44a31b]' : 'bg-slate-400/60 hover:bg-slate-500')}
                    aria-label={`Buka slide ${index + 1}`}
                  />
                ))}
              </div>
            )}
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
            className="absolute left-2 top-1/2 z-10 h-8 w-8 -translate-y-1/2 rounded-full border border-white/70 bg-white/85 text-emerald-800 backdrop-blur-md transition hover:bg-white focus-visible:ring-2 focus-visible:ring-white/80"
            aria-label="Slide sebelumnya"
          >
            <ChevronLeft className="h-5 w-5" />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={nextSlide}
            className="absolute right-2 top-1/2 z-10 h-8 w-8 -translate-y-1/2 rounded-full border border-white/70 bg-white/85 text-emerald-800 backdrop-blur-md transition hover:bg-white focus-visible:ring-2 focus-visible:ring-white/80"
            aria-label="Slide berikutnya"
          >
            <ChevronRight className="h-5 w-5" />
          </Button>
        </>
      )}

      {slideCount > 1 && !isPaused && !reducedMotion && (
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
