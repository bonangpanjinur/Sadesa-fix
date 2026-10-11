/* eslint-disable react-refresh/only-export-components -- This module intentionally exports a reusable helper or variant alongside its component. */
import { useState, useRef, useEffect } from 'react';
import { cn } from '@/lib/utils';

interface OptimizedImageProps {
  src: string;
  alt: string;
  className?: string;
  width?: number;
  height?: number;
  transformWidth?: number;
  srcSetWidths?: number[];
  sizes?: string;
  fallback?: string;
  lazy?: boolean;
  blur?: boolean;
  aspectRatio?: 'square' | '16/9' | '4/3' | '3/2' | 'auto';
  objectFit?: 'cover' | 'contain' | 'fill' | 'none';
  onLoad?: () => void;
  onError?: () => void;
}

const aspectRatioClasses = {
  square: 'aspect-square',
  '16/9': 'aspect-video',
  '4/3': 'aspect-[4/3]',
  '3/2': 'aspect-[3/2]',
  auto: '',
};

export function optimizeSupabaseImage(src: string, requestedWidth: number): string {
  try {
    const url = new URL(src, window.location.origin);
    const match = url.pathname.match(/^\/storage\/v1\/object\/public\/(.+)$/);
    if (!match || !url.hostname.includes('supabase')) return src;

    url.pathname = `/storage/v1/render/image/public/${match[1]}`;
    url.search = '';
    url.searchParams.set('width', String(Math.min(Math.max(Math.round(requestedWidth), 160), 1280)));
    url.searchParams.set('quality', '75');
    url.searchParams.set('format', 'webp');
    url.searchParams.set('resize', 'cover');
    return url.toString();
  } catch {
    return src;
  }
}

export function getOptimizedImageSrcSet(src: string, widths: number[]): string | undefined {
  const candidates = [...new Set(widths
    .filter((width) => Number.isFinite(width) && width > 0)
    .map((width) => Math.min(Math.max(Math.round(width), 160), 1280)))].sort((a, b) => a - b);
  const urls = candidates.map((width) => optimizeSupabaseImage(src, width));
  if (new Set(urls).size < 2) return undefined;
  return urls.map((url, index) => `${url} ${candidates[index]}w`).join(', ');
}

export function OptimizedImage({
  src,
  alt,
  className,
  width,
  height,
  transformWidth,
  srcSetWidths,
  sizes,
  fallback = '/placeholder.svg',
  lazy = true,
  blur = true,
  aspectRatio = 'auto',
  objectFit = 'cover',
  onLoad,
  onError,
}: OptimizedImageProps) {
  const [isLoaded, setIsLoaded] = useState(false);
  const [hasError, setHasError] = useState(false);
  const [useOriginalSrc, setUseOriginalSrc] = useState(false);
  const [isInView, setIsInView] = useState(!lazy);
  const imgRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!lazy) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsInView(true);
          observer.disconnect();
        }
      },
      {
        rootMargin: '50px',
        threshold: 0.01,
      }
    );

    if (imgRef.current) {
      observer.observe(imgRef.current);
    }

    return () => observer.disconnect();
  }, [lazy]);

  const handleLoad = () => {
    setIsLoaded(true);
    onLoad?.();
  };

  const handleError = () => {
    if (!useOriginalSrc) {
      setUseOriginalSrc(true);
      return;
    }
    setHasError(true);
    onError?.();
  };

  const optimizedSrc = optimizeSupabaseImage(src, transformWidth ?? width ?? 640);
  const imageSrc = hasError ? fallback : useOriginalSrc ? src : optimizedSrc;
  const imageSrcSet = useOriginalSrc || hasError || !srcSetWidths
    ? undefined
    : getOptimizedImageSrcSet(src, srcSetWidths);
  const objectFitClass = {
    cover: 'object-cover',
    contain: 'object-contain',
    fill: 'object-fill',
    none: 'object-none',
  }[objectFit];

  return (
    <div
      ref={imgRef}
      className={cn(
        'relative overflow-hidden bg-muted',
        aspectRatioClasses[aspectRatio],
        className
      )}
      style={{ width, height }}
    >
      {blur && !isLoaded && (
        <div className="absolute inset-0 bg-muted animate-pulse" />
      )}

      {isInView && (
        <img
          src={imageSrc}
          srcSet={imageSrcSet}
          sizes={imageSrcSet ? sizes : undefined}
          alt={alt}
          width={width}
          height={height}
          loading={lazy ? 'lazy' : 'eager'}
          decoding="async"
          onLoad={handleLoad}
          onError={handleError}
          className={cn(
            'w-full h-full transition-opacity duration-300',
            objectFitClass,
            isLoaded ? 'opacity-100' : 'opacity-0'
          )}
        />
      )}
    </div>
  );
}

export function preloadImage(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve();
    img.onerror = reject;
    img.src = src;
  });
}

export function useImagePreloader(imageSrcs: string[]) {
  const [loadedImages, setLoadedImages] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function loadImages() {
      for (const src of imageSrcs) {
        if (cancelled) break;
        try {
          await preloadImage(src);
          if (!cancelled) {
            setLoadedImages(prev => new Set([...prev, src]));
          }
        } catch (error) {
          console.warn(`Failed to preload image: ${src}`);
        }
      }
      if (!cancelled) {
        setIsLoading(false);
      }
    }

    loadImages();

    return () => {
      cancelled = true;
    };
  }, [imageSrcs]);

  return { loadedImages, isLoading };
}
