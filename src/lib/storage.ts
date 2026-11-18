import { supabase } from '@/integrations/supabase/client';
import { observe, reportObservability } from '@/lib/observability';
import { fitImageDimensions, type ImageCompressionOptions } from '@/lib/imageCompression';

export type StorageBucket = 'products' | 'product-images' | 'tourism-images' | 'profile-images' | 'merchant-images' | 'qris-merchant-static' | 'promotions' | 'pod-images' | 'village-images' | 'payment-proofs' | 'admin-assets';

interface UploadOptions {
  bucket: StorageBucket;
  path: string;
  file: File;
  fileName?: string;
  upsert?: boolean;
  onProgress?: (progress: number) => void;
}

interface UploadResult {
  url: string | null;
  path: string | null;
  error: string | null;
}

/**
 * Upload a file to Supabase Storage
 */
export async function uploadFile({ bucket, path, file, fileName, upsert = false }: UploadOptions): Promise<UploadResult> {
  const context = { bucket, fileType: file.type || 'unknown', sizeBytes: file.size };
  try {
    return await observe('upload', 'file_upload', async () => {
    // Callers may pass a stable filename when overwriting is desired;
    // otherwise each upload receives a unique object name.
    const fileExt = file.name.split('.').pop()?.toLowerCase() || 'jpg';
    const objectName = fileName
      ? `${path}/${fileName}`
      : `${path}/${Date.now()}-${Math.random().toString(36).substring(7)}.${fileExt}`;

    const { error: uploadError } = await supabase.storage
      .from(bucket)
      .upload(objectName, file, {
        cacheControl: '3600',
        upsert,
      });

    if (uploadError) throw uploadError;

    // Get public URL
    const { data: urlData } = supabase.storage
      .from(bucket)
      .getPublicUrl(objectName);

    return { url: urlData.publicUrl, path: objectName, error: null };
    }, context);
  } catch (err) {
    reportObservability('upload', 'file_upload_result_error', 'error', context, err);
    return { url: null, path: null, error: err instanceof Error ? err.message : 'Gagal mengupload file' };
  }
}

/**
 * Delete a file from Supabase Storage
 */
export async function deleteFile(bucket: StorageBucket, url: string): Promise<boolean> {
  try {
    reportObservability('upload', 'file_delete_started', 'info', { bucket });
    // Extract path from URL
    let filePath = url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      const urlObj = new URL(url);
      const pathParts = urlObj.pathname.split(`/storage/v1/object/public/${bucket}/`);
      if (pathParts.length < 2) return false;
      filePath = decodeURIComponent(pathParts[1]);
    }
    if (!filePath || filePath.startsWith('/') || filePath.includes('..')) return false;
    
    const { error } = await supabase.storage
      .from(bucket)
      .remove([filePath]);

    if (error) throw error;

    reportObservability('upload', 'file_delete_succeeded', 'info', { bucket });
    return true;
  } catch (err) {
    reportObservability('upload', 'file_delete_failed', 'error', { bucket }, err);
    return false;
  }
}

/**
 * Validate file before upload
 */
export function validateFile(file: File, maxSizeMB: number = 5): string | null {
  const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
  
  if (!allowedTypes.includes(file.type)) {
    return 'Format file tidak didukung. Gunakan JPG, PNG, WebP, atau GIF.';
  }
  
  if (file.size > maxSizeMB * 1024 * 1024) {
    return `Ukuran file maksimal ${maxSizeMB}MB.`;
  }
  
  return null;
}

/**
 * Compress image before upload
 */
export async function compressImage(
  file: File,
  optionsOrMaxWidth: ImageCompressionOptions | number = 1200,
  legacyQuality: number = 0.8,
): Promise<File> {
  const options: ImageCompressionOptions = typeof optionsOrMaxWidth === 'number'
    ? { maxWidth: optionsOrMaxWidth, quality: legacyQuality }
    : optionsOrMaxWidth;
  const maxWidth = options.maxWidth ?? 1200;
  const maxHeight = options.maxHeight;
  const quality = options.quality ?? 0.8;
  const minSizeBytes = options.minSizeBytes ?? 500 * 1024;
  const force = options.force ?? false;
  const outputFormat = options.outputFormat ?? 'jpeg';
  const mimeType = outputFormat === 'png' ? 'image/png' : 'image/jpeg';

  return new Promise((resolve) => {
    // Keep current behavior for general uploads unless a caller explicitly
    // requests compression. Forced compression converts GIFs to a static JPEG.
    if (!force && (file.size < minSizeBytes || file.type === 'image/gif')) {
      resolve(file);
      return;
    }

    const img = new Image();
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');

    img.onload = () => {
      const { width, height } = fitImageDimensions(img.width, img.height, { maxWidth, maxHeight });

      canvas.width = width;
      canvas.height = height;
      
      ctx?.drawImage(img, 0, 0, width, height);
      
      canvas.toBlob(
        (blob) => {
          if (blob) {
            const compressedFile = new File([blob], file.name, {
              type: mimeType,
              lastModified: Date.now(),
            });
            resolve(compressedFile);
          } else {
            resolve(file);
          }
        },
        mimeType,
        quality
      );
      URL.revokeObjectURL(img.src);
    };

    img.onerror = () => {
      URL.revokeObjectURL(img.src);
      resolve(file);
    };
    img.src = URL.createObjectURL(file);
  });
}
