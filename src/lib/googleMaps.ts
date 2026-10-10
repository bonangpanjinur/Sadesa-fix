import { importLibrary, setOptions } from '@googlemaps/js-api-loader';

let googleMapsPromise: Promise<typeof google> | null = null;

export function loadGoogleMaps(): Promise<typeof google> {
  if (googleMapsPromise) return googleMapsPromise;

  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string | undefined;
  if (!apiKey) return Promise.reject(new Error('VITE_GOOGLE_MAPS_API_KEY belum dikonfigurasi'));

  setOptions({ key: apiKey, v: 'weekly' });
  const pending = Promise.all([
    importLibrary('maps'),
    importLibrary('places'),
  ]).then(() => window.google);

  googleMapsPromise = pending.catch((error: unknown) => {
    // A rejected promise must not permanently poison the loader: transient
    // network failures and corrected API restrictions should be retryable.
    googleMapsPromise = null;
    throw error;
  });

  return googleMapsPromise;
}

export function isGoogleMapsBrowserKeyConfigured(): boolean {
  return Boolean(import.meta.env.VITE_GOOGLE_MAPS_API_KEY);
}
