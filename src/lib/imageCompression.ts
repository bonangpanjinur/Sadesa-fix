export interface ImageCompressionOptions {
  maxWidth?: number;
  maxHeight?: number;
  quality?: number;
  minSizeBytes?: number;
  force?: boolean;
  outputFormat?: 'jpeg' | 'png';
}

export interface ImageAspectRatioValidation {
  ratio: number;
  tolerance?: number;
}

export interface ImageDimensions {
  width: number;
  height: number;
}

export function isImageAspectRatioValid(
  width: number,
  height: number,
  validation: ImageAspectRatioValidation,
): boolean {
  const tolerance = validation.tolerance ?? 0.01;
  if (
    !Number.isFinite(width)
    || !Number.isFinite(height)
    || width <= 0
    || height <= 0
    || !Number.isFinite(validation.ratio)
    || validation.ratio <= 0
    || !Number.isFinite(tolerance)
    || tolerance < 0
  ) {
    return false;
  }

  const floatingPointEpsilon = Number.EPSILON * Math.max(1, validation.ratio);
  return Math.abs(width / height - validation.ratio) <= tolerance + floatingPointEpsilon;
}

export function readImageDimensions(file: File): Promise<ImageDimensions | null> {
  return new Promise((resolve) => {
    const image = new Image();
    const objectUrl = URL.createObjectURL(file);
    const releaseUrl = () => URL.revokeObjectURL(objectUrl);

    image.onload = () => {
      const width = image.naturalWidth || image.width;
      const height = image.naturalHeight || image.height;
      releaseUrl();
      resolve(width > 0 && height > 0 ? { width, height } : null);
    };

    image.onerror = () => {
      releaseUrl();
      resolve(null);
    };

    image.src = objectUrl;
  });
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
