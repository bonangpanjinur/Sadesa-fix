// Utility functions for merchant operating hours

export interface MerchantOperatingStatus {
  isCurrentlyOpen: boolean;
  isManuallyOpen: boolean;
  openTime: string;
  closeTime: string;
  nextOpenAt?: string;
  reason: string;
}

/**
 * Check if the current time is within merchant's operating hours
 */
/**
 * Current minutes-since-midnight in Asia/Jakarta (WIB).
 * Merchant operating hours are stored as local Indonesian time, so they must be
 * compared against WIB and not the visitor's device timezone (which would show
 * every shop as closed for users/devices outside Indonesia).
 */
export function getJakartaMinutesNow(date: Date = new Date()): number {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Jakarta',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(date);
  const hour = Number(parts.find((p) => p.type === 'hour')?.value ?? '0');
  const minute = Number(parts.find((p) => p.type === 'minute')?.value ?? '0');
  return (hour % 24) * 60 + minute;
}

export function isWithinOperatingHours(openTime: string, closeTime: string): boolean {
  if (!openTime || !closeTime) return true; // If no hours set, assume open

  const currentTime = getJakartaMinutesNow();
  
  // Parse time strings (format: "HH:mm" or "HH:mm:ss")
  const [openHours, openMinutes] = openTime.split(':').map(Number);
  const [closeHours, closeMinutes] = closeTime.split(':').map(Number);
  
  const openTimeMinutes = openHours * 60 + openMinutes;
  const closeTimeMinutes = closeHours * 60 + closeMinutes;
  
  // Handle overnight hours (e.g., 22:00 - 06:00)
  if (closeTimeMinutes < openTimeMinutes) {
    return currentTime >= openTimeMinutes || currentTime <= closeTimeMinutes;
  }
  
  return currentTime >= openTimeMinutes && currentTime <= closeTimeMinutes;
}

/**
 * Get comprehensive merchant operating status
 */
export function getMerchantOperatingStatus(
  isManuallyOpen: boolean,
  openTime: string | null,
  closeTime: string | null
): MerchantOperatingStatus {
  const open = openTime || '08:00';
  const close = closeTime || '17:00';
  const withinHours = isWithinOperatingHours(open, close);
  
  // Merchant is only open if both manually open AND within operating hours
  const isCurrentlyOpen = isManuallyOpen && withinHours;
  
  let reason = '';
  let nextOpenAt: string | undefined;
  
  if (!isManuallyOpen) {
    reason = 'Toko sedang tutup sementara';
  } else if (!withinHours) {
    reason = `Toko buka pukul ${formatTime(open)} - ${formatTime(close)}`;
    nextOpenAt = open;
  } else {
    reason = 'Toko sedang buka';
  }
  
  return {
    isCurrentlyOpen,
    isManuallyOpen,
    openTime: open,
    closeTime: close,
    nextOpenAt,
    reason,
  };
}

/**
 * Format time for display (e.g., "08:00" -> "08.00")
 */
export function formatTime(time: string): string {
  if (!time) return '';
  return time.replace(':', '.').substring(0, 5);
}

/**
 * Get time until next open (in minutes)
 */
export function getTimeUntilOpen(openTime: string): number {
  const currentMinutes = getJakartaMinutesNow();

  const [openHours, openMinutes] = openTime.split(':').map(Number);
  const openTimeMinutes = openHours * 60 + openMinutes;
  
  if (currentMinutes < openTimeMinutes) {
    return openTimeMinutes - currentMinutes;
  }
  
  // Next day
  return (24 * 60 - currentMinutes) + openTimeMinutes;
}

/**
 * Format minutes to human readable time
 */
export function formatMinutesToReadable(minutes: number): string {
  if (minutes < 60) {
    return `${minutes} menit`;
  }
  
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  
  if (remainingMinutes === 0) {
    return `${hours} jam`;
  }
  
  return `${hours} jam ${remainingMinutes} menit`;
}
