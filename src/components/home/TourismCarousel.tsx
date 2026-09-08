import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { MapPin, Eye, ChevronLeft, ChevronRight } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { cn } from '@/lib/utils';
import type { Tourism } from '@/types';
import { Button } from '@/components/ui/button';

interface TourismCarouselProps {
  tourismSpots: Tourism[];
  maxSlots?: number;
  autoPlayInterval?: number;
}

export function TourismCarousel({ 
  tourismSpots, 
  maxSlots = 3,
  autoPlayInterval = 4000 
}: TourismCarouselProps) {
  const [currentIndex, setCurrentIndex] = useState(0);
  const [direction, setDirection] = useState(0);

  // Limit to maxSlots
  const limitedSpots = tourismSpots.slice(0, maxSlots);
  const slideCount = limitedSpots.length;

  const nextSlide = useCallback(() => {
    if (slideCount <= 1) return;
    setDirection(1);
    setCurrentIndex((prev) => (prev + 1) % slideCount);
  }, [slideCount]);

  const prevSlide = useCallback(() => {
    if (slideCount <= 1) return;
    setDirection(-1);
    setCurrentIndex((prev) => (prev - 1 + slideCount) % slideCount);
  }, [slideCount]);

  // Auto-play
  useEffect(() => {
    if (slideCount <= 1) return;
    
    const interval = setInterval(nextSlide, autoPlayInterval);
    return () => clearInterval(interval);
  }, [nextSlide, autoPlayInterval, slideCount]);

  if (limitedSpots.length === 0) return null;

  const currentSpot = limitedSpots[currentIndex];

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
    <div className="relative h-40 overflow-hidden rounded-lg bg-muted shadow-md">
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
          <Link to={`/tourism/${currentSpot.id}`} className="block h-full">
            <img
              src={currentSpot.image}
              alt={currentSpot.name}
              className="w-full h-full object-cover"
            />
            <div className="absolute inset-0 flex items-end bg-gradient-to-r from-foreground/90 via-foreground/45 to-transparent">
              <div className="max-w-[76%] px-4 pb-5">
                {currentSpot.viewCount && (
                  <span className="inline-flex items-center gap-1 bg-card/20 backdrop-blur text-primary-foreground text-[9px] px-2 py-0.5 rounded-full mb-1.5">
                    <Eye className="h-2.5 w-2.5" />
                    {currentSpot.viewCount.toLocaleString('id-ID')} views
                  </span>
                )}
                <h3 className="font-heading text-base font-bold leading-tight text-primary-foreground line-clamp-1">
                  {currentSpot.name}
                </h3>
                <div className="flex items-center gap-1 text-primary-foreground/70 text-[10px] mt-0.5">
                  <MapPin className="h-2.5 w-2.5" />
                  <span className="line-clamp-1">{currentSpot.villageName}</span>
                </div>
              </div>
            </div>
          </Link>
        </motion.div>
      </AnimatePresence>

      {/* Navigation Arrows */}
      {slideCount > 1 && (
        <>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={(e) => { e.preventDefault(); prevSlide(); }}
            className="absolute left-2 top-1/2 z-10 h-8 w-8 -translate-y-1/2 rounded-lg bg-background/30 text-primary-foreground backdrop-blur-sm hover:bg-background/50"
            aria-label="Previous"
          >
            <ChevronLeft className="h-3.5 w-3.5" />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={(e) => { e.preventDefault(); nextSlide(); }}
            className="absolute right-2 top-1/2 z-10 h-8 w-8 -translate-y-1/2 rounded-lg bg-background/30 text-primary-foreground backdrop-blur-sm hover:bg-background/50"
            aria-label="Next"
          >
            <ChevronRight className="h-3.5 w-3.5" />
          </Button>
        </>
      )}

      {/* Dot Indicators */}
      {slideCount > 1 && (
        <div className="absolute bottom-2 left-1/2 -translate-x-1/2 flex gap-1 z-10">
          {limitedSpots.map((_, index) => (
            <button
              key={index}
              onClick={() => {
                setDirection(index > currentIndex ? 1 : -1);
                setCurrentIndex(index);
              }}
              className={cn(
                "w-1 h-1 rounded-full transition-all",
                index === currentIndex
                  ? "bg-primary-foreground w-3"
                  : "bg-primary-foreground/40 hover:bg-primary-foreground/60"
              )}
              aria-label={`Go to slide ${index + 1}`}
            />
          ))}
        </div>
      )}

      {/* "Iklan" badge */}
      <div className="absolute top-2 right-2 z-10">
        <span className="rounded-md bg-accent px-2 py-1 text-[8px] font-bold uppercase text-accent-foreground">
          Promo
        </span>
      </div>
    </div>
  );
}
