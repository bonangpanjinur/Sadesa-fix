import { describe, expect, it } from 'vitest';
import { fitImageDimensions } from './imageCompression';

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
