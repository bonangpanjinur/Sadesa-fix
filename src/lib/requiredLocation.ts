export interface RequiredLocation {
  lat: number;
  lng: number;
}

/** Request a fresh GPS fix only when the user is starting a location-based order. */
export function requestRequiredLocation(): Promise<RequiredLocation | null> {
  if (typeof navigator === 'undefined' || !navigator.geolocation) return Promise.resolve(null);

  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (position) => resolve({ lat: position.coords.latitude, lng: position.coords.longitude }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 },
    );
  });
}
