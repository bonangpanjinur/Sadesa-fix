const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const ALLOWED_DOCUMENT_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);
const SAFE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'webp', 'pdf']);

export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

export function validateUploadFile(
  file: File,
  options: { documents?: boolean; maxBytes?: number } = {},
): { valid: true; extension: string } | { valid: false; error: string } {
  const maxBytes = options.maxBytes ?? MAX_UPLOAD_BYTES;
  const allowedTypes = options.documents ? ALLOWED_DOCUMENT_TYPES : ALLOWED_IMAGE_TYPES;
  const extension = file.name.includes('.') ? file.name.split('.').pop()?.toLowerCase() ?? '' : '';

  if (file.size <= 0 || file.size > maxBytes) {
    return { valid: false, error: 'Ukuran file tidak valid atau melebihi batas 5MB' };
  }
  if (!allowedTypes.has(file.type) || !SAFE_EXTENSIONS.has(extension)) {
    return { valid: false, error: options.documents ? 'Format harus JPG, PNG, WebP, atau PDF' : 'Format harus JPG, PNG, atau WebP' };
  }
  return { valid: true, extension: extension === 'jpeg' ? 'jpg' : extension };
}
