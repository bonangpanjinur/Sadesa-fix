import { describe, expect, it } from 'vitest';
import { validateUploadFile } from './fileValidation';

const file = (name: string, type: string, size = 100) =>
  new File([new Uint8Array(size)], name, { type });

describe('validateUploadFile', () => {
  it('accepts supported image files', () => {
    expect(validateUploadFile(file('photo.png', 'image/png'))).toEqual({ valid: true, extension: 'png' });
    expect(validateUploadFile(file('photo.jpeg', 'image/jpeg'))).toEqual({ valid: true, extension: 'jpg' });
  });

  it('rejects an empty file', () => {
    expect(validateUploadFile(file('photo.png', 'image/png', 0)).valid).toBe(false);
  });

  it('rejects mismatched MIME and extension', () => {
    expect(validateUploadFile(file('photo.exe', 'image/png')).valid).toBe(false);
    expect(validateUploadFile(file('photo.png', 'application/pdf')).valid).toBe(false);
  });

  it('accepts documents only when document mode is enabled', () => {
    expect(validateUploadFile(file('proof.pdf', 'application/pdf')).valid).toBe(false);
    expect(validateUploadFile(file('proof.pdf', 'application/pdf'), { documents: true })).toEqual({ valid: true, extension: 'pdf' });
  });

  it('rejects files larger than the limit', () => {
    expect(validateUploadFile(file('large.png', 'image/png', 5 * 1024 * 1024 + 1)).valid).toBe(false);
  });
});
