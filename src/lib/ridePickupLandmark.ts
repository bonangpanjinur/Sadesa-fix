export const RIDE_PICKUP_LANDMARK_MAX_LENGTH = 240;
export const RIDE_PICKUP_LANDMARK_MIN_LENGTH = 3;

export function normalizeRidePickupLandmark(value: string): string | null {
  const landmark = value.trim();
  if (landmark.length < RIDE_PICKUP_LANDMARK_MIN_LENGTH || landmark.length > RIDE_PICKUP_LANDMARK_MAX_LENGTH) {
    return null;
  }
  return landmark;
}
