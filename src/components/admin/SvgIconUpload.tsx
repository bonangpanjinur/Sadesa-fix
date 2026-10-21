import { useRef, useState } from 'react';
import DOMPurify from 'dompurify';
import { FileCode2, Loader2, Upload, X } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { uploadFile } from '@/lib/storage';

interface SvgIconUploadProps {
  value?: string | null;
  path: string;
  onChange: (url: string | null) => void;
  maxSizeMB?: number;
  placeholder?: string;
  disabled?: boolean;
}

const SVG_MIME_TYPE = 'image/svg+xml';

function isSvgFile(file: File) {
  return file.type === SVG_MIME_TYPE || file.name.toLowerCase().endsWith('.svg');
}

async function sanitizeSvgFile(file: File): Promise<File> {
  const source = await file.text();
  const parsed = new DOMParser().parseFromString(source, 'image/svg+xml');
  if (parsed.querySelector('parsererror') || parsed.documentElement.tagName.toLowerCase() !== 'svg') {
    throw new Error('File bukan SVG yang valid.');
  }

  const sanitized = DOMPurify.sanitize(source, {
    USE_PROFILES: { svg: true, svgFilters: true },
  });
  if (!sanitized || !/<svg[\s>]/i.test(sanitized)) {
    throw new Error('SVG tidak dapat dibersihkan dengan aman.');
  }

  return new File([sanitized], 'icon.svg', { type: SVG_MIME_TYPE, lastModified: Date.now() });
}

export function SvgIconUpload({
  value,
  path,
  onChange,
  maxSizeMB = 2,
  placeholder = 'Upload ikon SVG',
  disabled = false,
}: SvgIconUploadProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [isUploading, setIsUploading] = useState(false);

  const handleFile = async (file: File) => {
    if (!isSvgFile(file)) {
      toast.error('Gunakan file SVG dengan ekstensi .svg.');
      return;
    }
    if (file.size > maxSizeMB * 1024 * 1024) {
      toast.error(`Ukuran SVG maksimal ${maxSizeMB}MB.`);
      return;
    }

    setIsUploading(true);
    try {
      const safeFile = await sanitizeSvgFile(file);
      const result = await uploadFile({
        bucket: 'admin-assets',
        path,
        file: safeFile,
        fileName: 'icon.svg',
        upsert: true,
      });
      if (result.error || !result.url) {
        toast.error(result.error || 'Gagal mengupload ikon SVG.');
      } else {
        onChange(result.url);
        toast.success('Ikon SVG berhasil diupload.');
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Gagal mengupload ikon SVG.');
    } finally {
      setIsUploading(false);
    }
  };

  const handleInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file) void handleFile(file);
    event.target.value = '';
  };

  return (
    <div className="space-y-2">
      <input
        ref={inputRef}
        type="file"
        accept="image/svg+xml,.svg"
        onChange={handleInputChange}
        disabled={disabled || isUploading}
        className="hidden"
      />
      <div
        onClick={() => !disabled && !isUploading && inputRef.current?.click()}
        onDragOver={(event) => event.preventDefault()}
        onDrop={(event) => {
          event.preventDefault();
          if (!disabled && !isUploading) {
            const file = event.dataTransfer.files?.[0];
            if (file) void handleFile(file);
          }
        }}
        className={cn(
          'relative flex min-h-36 cursor-pointer items-center justify-center overflow-hidden rounded-xl border-2 border-dashed bg-muted/20 p-4 transition-colors hover:border-primary/60 hover:bg-primary/5',
          disabled && 'cursor-not-allowed opacity-50',
        )}
      >
        {value ? (
          <>
            <img src={value} alt="Preview ikon SVG" className="h-24 w-24 object-contain" />
            {!disabled && (
              <Button
                type="button"
                variant="destructive"
                size="icon"
                className="absolute right-2 top-2 h-8 w-8"
                aria-label="Hapus ikon SVG"
                onClick={(event) => {
                  event.stopPropagation();
                  onChange(null);
                }}
              >
                <X className="h-4 w-4" />
              </Button>
            )}
          </>
        ) : isUploading ? (
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        ) : (
          <div className="flex flex-col items-center gap-2 text-center text-muted-foreground">
            <FileCode2 className="h-8 w-8" />
            <span className="text-sm font-medium">{placeholder}</span>
            <span className="text-xs">SVG saja, maksimal {maxSizeMB}MB</span>
            <Upload className="h-4 w-4" />
          </div>
        )}
      </div>
    </div>
  );
}
