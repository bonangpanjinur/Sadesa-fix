import { COURIER_ALARM_VIBRATION_PATTERN } from './notificationVibrationPattern';

export { COURIER_ALARM_VIBRATION_PATTERN };

export function vibrateCourierAlarm(): boolean {
  if (typeof navigator === 'undefined' || typeof navigator.vibrate !== 'function') return false;
  try {
    return navigator.vibrate(COURIER_ALARM_VIBRATION_PATTERN);
  } catch {
    return false;
  }
}
