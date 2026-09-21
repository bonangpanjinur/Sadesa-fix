import { Loader } from '@googlemaps/js-api-loader';

let googleMapsPromise: Promise<typeof google> | null = null;

export function loadGoogleMaps(): Promise<typeof google> {
  if (googleMapsPromise) return googleMapsPromise;

  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string | undefined;
  if (!apiKey) return Promise.reject(new Error('VITE_GOOGLE_MAPS_API_KEY belum dikonfigurasi'));

  googleMapsPromise = new Loader({
    apiKey,
    version: 'weekly',
    libraries: ['places'],
  }).load();

  return googleMapsPromise;
}
