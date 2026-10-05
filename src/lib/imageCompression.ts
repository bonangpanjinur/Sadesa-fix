export interface ImageCompressionOptions {
  maxWidth?: number;
  maxHeight?: number;
  quality?: number;
  minSizeBytes?: number;
  force?: boolean;
}

export function fitImageDimensions(
  width: number,
  height: number,
  bounds: Pick<ImageCompressionOptions, 'maxWidth' | 'maxHeight'> = {},
): { width: number; height: number } {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return { width: 1, height: 1 };
  }

  const maxWidth = bounds.maxWidth ?? 1200;
  const maxHeight = bounds.maxHeight;
  const scale = Math.min(
    1,
    maxWidth / width,
    maxHeight ? maxHeight / height : 1,
  );

  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}
