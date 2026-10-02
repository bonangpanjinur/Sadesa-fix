import { useEffect, useState } from 'react';
import { fetchGuestCheckoutEnabled } from '@/lib/guestCheckoutFeature';
import { getGuestCheckoutSessionKey } from '@/lib/guestCheckout';

export function useGuestCheckoutEnabled(isAuthenticated: boolean) {
  const [enabled, setEnabled] = useState(isAuthenticated);
  const [loading, setLoading] = useState(!isAuthenticated);

  useEffect(() => {
    if (isAuthenticated) {
      setEnabled(true);
      setLoading(false);
      return;
    }

    let active = true;
    setLoading(true);
    void fetchGuestCheckoutEnabled(getGuestCheckoutSessionKey()).then((nextEnabled) => {
      if (!active) return;
      setEnabled(nextEnabled);
      setLoading(false);
    });

    return () => {
      active = false;
    };
  }, [isAuthenticated]);

  return { enabled, loading };
}
