import { importLibrary, setOptions } from '@googlemaps/js-api-loader';

let googleMapsPromise: Promise<typeof google> | null = null;

export function loadGoogleMaps(): Promise<typeof google> {
  if (googleMapsPromise) return googleMapsPromise;

  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string | undefined;
  if (!apiKey) return Promise.reject(new Error('VITE_GOOGLE_MAPS_API_KEY belum dikonfigurasi'));

  setOptions({ key: apiKey, v: 'weekly' });
  googleMapsPromise = Promise.all([
    importLibrary('maps'),
    importLibrary('places'),
  ]).then(() => window.google);

  return googleMapsPromise;
}
