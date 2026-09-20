// Utility functions for merchant operating hours.

export interface OperatingDaySchedule {
  day_of_week: number;
  open_time: string | null;
  close_time: string | null;
  is_closed: boolean;
}

export interface MerchantOperatingStatus {
  isCurrentlyOpen: boolean;
  isManuallyOpen: boolean;
  openTime: string;
  closeTime: string;
  nextOpenAt?: string;
  reason: string;
}

export function getJakartaParts(date: Date = new Date()): { dayOfWeek: number; minutes: number } {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Jakarta', weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
  });
  const parts = Object.fromEntries(formatter.formatToParts(date).map(({ type, value }) => [type, value]));
  const days: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  return { dayOfWeek: days[parts.weekday] ?? 0, minutes: (Number(parts.hour) % 24) * 60 + Number(parts.minute) };
}

export function getJakartaMinutesNow(date: Date = new Date()): number {
  return getJakartaParts(date).minutes;
}

function toMinutes(time: string | null | undefined): number | null {
  if (!time) return null;
  const [hours, minutes] = time.split(':').map(Number);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return null;
  return hours * 60 + minutes;
}

export function isWithinOperatingHours(openTime: string, closeTime: string, currentMinutes = getJakartaMinutesNow()): boolean {
  const open = toMinutes(openTime);
  const close = toMinutes(closeTime);
  if (open === null || close === null) return true;
  if (open === close) return true;
  if (close < open) return currentMinutes >= open || currentMinutes < close;
  return currentMinutes >= open && currentMinutes < close;
}

export function getMerchantOperatingStatus(
  isManuallyOpen: boolean,
  openTime: string | null,
  closeTime: string | null,
  weeklySchedule?: OperatingDaySchedule[] | null,
  now: Date = new Date(),
): MerchantOperatingStatus {
  const legacyOpen = openTime || '08:00';
  const legacyClose = closeTime || '17:00';
  const jakarta = getJakartaParts(now);
  const today = weeklySchedule?.find((schedule) => schedule.day_of_week === jakarta.dayOfWeek);
  const effectiveOpen = today?.open_time || legacyOpen;
  const effectiveClose = today?.close_time || legacyClose;
  const withinHours = today?.is_closed ? false : isWithinOperatingHours(effectiveOpen, effectiveClose, jakarta.minutes);
  const isCurrentlyOpen = isManuallyOpen && withinHours;

  let reason = 'Toko sedang buka';
  let nextOpenAt: string | undefined;
  if (!isManuallyOpen) reason = 'Toko sedang tutup sementara';
  else if (today?.is_closed) reason = 'Toko tutup hari ini';
  else if (!withinHours) {
    reason = `Toko buka pukul ${formatTime(effectiveOpen)} - ${formatTime(effectiveClose)}`;
    nextOpenAt = effectiveOpen;
  }

  return { isCurrentlyOpen, isManuallyOpen, openTime: effectiveOpen, closeTime: effectiveClose, nextOpenAt, reason };
}

export function formatTime(time: string | null | undefined): string {
  return time ? time.replace(':', '.').substring(0, 5) : '';
}

export function getTimeUntilOpen(openTime: string): number {
  const currentMinutes = getJakartaMinutesNow();
  const open = toMinutes(openTime) ?? 0;
  return currentMinutes < open ? open - currentMinutes : (24 * 60 - currentMinutes) + open;
}

export function formatMinutesToReadable(minutes: number): string {
  if (minutes < 60) return `${minutes} menit`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return remainingMinutes === 0 ? `${hours} jam` : `${hours} jam ${remainingMinutes} menit`;
}
