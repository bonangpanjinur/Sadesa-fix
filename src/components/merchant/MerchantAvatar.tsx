import { useEffect, useState } from 'react';
import { Store } from 'lucide-react';
import { cn } from '@/lib/utils';

interface MerchantAvatarProps {
  imageUrl?: string | null;
  merchantName: string;
  className?: string;
  iconClassName?: string;
}

/**
 * Public-facing merchant identity image.
 * A store photo is preferred, while the store icon remains a resilient fallback
 * for merchants without a photo or when an old storage URL is no longer valid.
 */
export function MerchantAvatar({
  imageUrl,
  merchantName,
  className,
  iconClassName,
}: MerchantAvatarProps) {
  const [hasError, setHasError] = useState(false);

  useEffect(() => {
    setHasError(false);
  }, [imageUrl]);

  const showImage = Boolean(imageUrl) && !hasError;

  return (
    <div
      className={cn(
        'flex shrink-0 items-center justify-center overflow-hidden bg-gradient-to-br from-primary/20 to-primary/40',
        className,
      )}
      aria-label={`Foto profil ${merchantName}`}
    >
      {showImage ? (
        <img
          src={imageUrl ?? undefined}
          alt={`Foto profil ${merchantName}`}
          className="h-full w-full object-cover"
          loading="lazy"
          decoding="async"
          onError={() => setHasError(true)}
        />
      ) : (
        <Store className={cn('text-primary', iconClassName)} aria-hidden="true" />
      )}
    </div>
  );
}
