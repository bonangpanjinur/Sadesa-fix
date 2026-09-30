export type CsvCell = string | number | boolean | null | undefined;

/** Escape a cell according to RFC 4180 and preserve spreadsheet-safe text. */
export function escapeCsvCell(value: CsvCell): string {
  const text = value === null || value === undefined ? '' : String(value);
  const safeText = /^[=+\-@]/.test(text) ? `'${text}` : text;
  return /[",\r\n]/.test(safeText) ? `"${safeText.replace(/"/g, '""')}"` : safeText;
}

export function toCsv(rows: CsvCell[][], includeBom = true): string {
  const csv = rows.map((row) => row.map(escapeCsvCell).join(',')).join('\r\n');
  return `${includeBom ? '\uFEFF' : ''}${csv}\r\n`;
}

export function downloadCsv(filename: string, rows: CsvCell[][]): void {
  const blob = new Blob([toCsv(rows)], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
