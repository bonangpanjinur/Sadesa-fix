export function formatPOSDateTime(value: string | number | Date, timeZone = 'Asia/Jakarta') {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return new Intl.DateTimeFormat('id-ID', {
    timeZone,
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

export function formatPOSTime(value: string | number | Date, timeZone = 'Asia/Jakarta') {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return new Intl.DateTimeFormat('id-ID', { timeZone, timeStyle: 'medium' }).format(date);
}

export function getPOSDayRange(date = new Date(), timeZone = 'Asia/Jakarta') {
  const formatter = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' });
  const parts = Object.fromEntries(formatter.formatToParts(date).filter((part) => part.type !== 'literal').map((part) => [part.type, part.value]));
  return { start: `${parts.year}-${parts.month}-${parts.day}T00:00:00`, end: `${parts.year}-${parts.month}-${parts.day}T23:59:59.999` };
}
