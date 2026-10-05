import { describe, expect, it } from 'vitest';
import { fitImageDimensions, isImageAspectRatioValid } from './imageCompression';

describe('isImageAspectRatioValid', () => {
  const homepageCardRatio = { ratio: 1.12, tolerance: 0.01 };

  it('accepts the recommended 1120 × 1000 ratio', () => {
    expect(isImageAspectRatioValid(1120, 1000, homepageCardRatio)).toBe(true);
  });

  it('accepts a ratio within the configured tolerance', () => {
    expect(isImageAspectRatioValid(1110, 1000, homepageCardRatio)).toBe(true);
  });

  it('rejects images that would need substantial cropping', () => {
    expect(isImageAspectRatioValid(1600, 1200, homepageCardRatio)).toBe(false);
  });

  it('rejects invalid image dimensions', () => {
    expect(isImageAspectRatioValid(0, 1000, homepageCardRatio)).toBe(false);
  });
});

describe('fitImageDimensions', () => {
  it('shrinks large images to stay within both bounds without changing their ratio', () => {
    expect(fitImageDimensions(5600, 5000, { maxWidth: 1120, maxHeight: 1000 })).toEqual({
      width: 1120,
      height: 1000,
    });
  });

  it('limits a wide image by width', () => {
    expect(fitImageDimensions(3000, 1688, { maxWidth: 1120, maxHeight: 1000 })).toEqual({
      width: 1120,
      height: 630,
    });
  });

  it('does not enlarge images that already fit', () => {
    expect(fitImageDimensions(800, 700, { maxWidth: 1120, maxHeight: 1000 })).toEqual({
      width: 800,
      height: 700,
    });
  });

  it('returns safe dimensions for invalid image metadata', () => {
    expect(fitImageDimensions(0, 900, { maxWidth: 1120, maxHeight: 1000 })).toEqual({
      width: 1,
      height: 1,
    });
  });
});
