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
  const [isPaused, setIsPaused] = useState(false);

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
    if (slideCount <= 1 || isPaused) return;
    
    const interval = setInterval(nextSlide, autoPlayInterval);
    return () => clearInterval(interval);
  }, [nextSlide, autoPlayInterval, slideCount, isPaused]);

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
      <motion.div className="mb-2.5 flex items-center gap-1.5" variants={{ hidden: { opacity: 0, y: 6 }, visible: { opacity: 1, y: 0 } }} transition={{ duration: 0.22 }}>
          <span className="rounded-full bg-accent px-3 py-1.5 text-[9px] font-bold uppercase tracking-[0.08em] text-accent-foreground shadow-sm">
            Pilihan minggu ini
          </span>
      </motion.div>
      <motion.h2 className="max-w-[min(70vw,270px)] font-heading text-[1.28rem] font-extrabold leading-[1.08] tracking-[-0.02em] text-primary-foreground sm:max-w-[310px] sm:text-xl" variants={{ hidden: { opacity: 0, y: 8 }, visible: { opacity: 1, y: 0 } }} transition={{ duration: 0.25 }}>
        {currentSlide.title}
      </motion.h2>
      {currentSlide.subtitle && (
        <motion.p className="mt-2 max-w-[min(66vw,245px)] text-[0.7rem] leading-[1.45] text-primary-foreground/85 sm:max-w-[280px] sm:text-xs" variants={{ hidden: { opacity: 0, y: 8 }, visible: { opacity: 1, y: 0 } }} transition={{ duration: 0.25 }}>
          {currentSlide.subtitle}
        </motion.p>
      )}
      {currentSlide.linkUrl && (
          <motion.span className="mt-4 inline-flex h-10 items-center gap-1.5 rounded-full bg-white px-4 text-xs font-extrabold text-primary shadow-[0_8px_20px_-10px_hsl(var(--foreground)/0.75)] transition hover:bg-orange-50" variants={{ hidden: { opacity: 0, scale: 0.96 }, visible: { opacity: 1, scale: 1 } }} transition={{ duration: 0.22 }}>
          Lihat Sekarang
          <ChevronRight className="h-3.5 w-3.5" />
        </motion.span>
      )}
    </motion.div>
  );

  return (
    <section
      className="group relative mx-4 mt-5 h-[13.75rem] overflow-hidden rounded-[1.65rem] bg-muted shadow-[0_18px_38px_-18px_hsl(var(--foreground)/0.65)] sm:mx-6 sm:h-[14.5rem]"
      onMouseEnter={() => setIsPaused(true)}
      onMouseLeave={() => setIsPaused(false)}
      onFocus={() => setIsPaused(true)}
      onBlur={() => setIsPaused(false)}
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
          <div className="absolute inset-0 flex items-center bg-gradient-to-r from-foreground/90 via-foreground/62 to-foreground/10">
            <div className="max-w-[78%] px-5 py-5 sm:max-w-[72%] sm:px-6">
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
            className="absolute left-3 top-1/2 z-10 h-10 w-10 -translate-y-1/2 rounded-full border border-white/20 bg-black/25 text-white backdrop-blur-md transition hover:bg-black/40 focus-visible:ring-2 focus-visible:ring-white/80"
            aria-label="Previous slide"
          >
            <ChevronLeft className="h-5 w-5" />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={nextSlide}
            className="absolute right-3 top-1/2 z-10 h-10 w-10 -translate-y-1/2 rounded-full border border-white/20 bg-black/25 text-white backdrop-blur-md transition hover:bg-black/40 focus-visible:ring-2 focus-visible:ring-white/80"
            aria-label="Next slide"
          >
            <ChevronRight className="h-5 w-5" />
          </Button>
        </>
      )}

      {/* Dot Indicators */}
      {slideCount > 1 && (
        <div className="absolute bottom-3.5 left-1/2 z-10 flex -translate-x-1/2 items-center gap-1.5 rounded-full bg-black/20 px-2.5 py-1.5 backdrop-blur-sm">
          {slides.map((_, index) => (
            <button
              key={index}
              onClick={() => goToSlide(index)}
              className={cn(
                "h-1.5 w-1.5 rounded-full transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white",
                index === currentIndex
                  ? "w-5 bg-white"
                  : "bg-white/50 hover:bg-white/80"
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
