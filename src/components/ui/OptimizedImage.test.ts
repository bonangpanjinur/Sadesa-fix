import { describe, expect, it } from 'vitest';
import { getOptimizedImageSrcSet, optimizeSupabaseImage } from './OptimizedImage';

const source = 'https://project.supabase.co/storage/v1/object/public/catalog/item.jpg';

describe('Supabase optimized image URLs', () => {
  it('requests resized WebP variants from public storage', () => {
    const url = new URL(optimizeSupabaseImage(source, 360));

    expect(url.pathname).toBe('/storage/v1/render/image/public/catalog/item.jpg');
    expect(url.searchParams.get('width')).toBe('360');
    expect(url.searchParams.get('quality')).toBe('75');
    expect(url.searchParams.get('format')).toBe('webp');
    expect(url.searchParams.get('resize')).toBe('cover');
  });

  it('builds a width-descriptor srcset for responsive candidates', () => {
    const srcSet = getOptimizedImageSrcSet(source, [240, 360, 480]);

    expect(srcSet).toContain('width=240');
    expect(srcSet).toContain(' 240w');
    expect(srcSet).toContain('width=360');
    expect(srcSet).toContain(' 360w');
    expect(srcSet).toContain('width=480');
    expect(srcSet).toContain(' 480w');
  });

  it('leaves non-Supabase sources unchanged and omits a duplicate srcset', () => {
    const external = 'https://images.example.com/item.jpg';

    expect(optimizeSupabaseImage(external, 360)).toBe(external);
    expect(getOptimizedImageSrcSet(external, [240, 360, 480])).toBeUndefined();
  });
});
