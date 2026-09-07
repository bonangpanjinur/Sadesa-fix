import type { ReceiptData } from '@/lib/thermalPrinter';
import { getPrinterSettings, printReceiptBrowser } from '@/lib/thermalPrinter';
import {
  enqueueReceiptData,
  flushReceiptOutbox,
  getReceiptJobStatus,
  markReceiptJobPrinted,
} from '@/lib/printOutbox';

export type ReceiptPrintChannel = 'usb' | 'bridge' | 'browser' | 'outbox';

export interface ReceiptPrintResult {
  status: 'printed' | 'queued';
  channel: ReceiptPrintChannel;
  error?: string;
}

/**
 * Single receipt contract for checkout, reprint, and retry.
 * A job is always persisted before attempting a printer, so a failed print
 * can be retried without creating a second sale or duplicate outbox entry.
 */
export async function printReceiptWithContract(
  receipt: ReceiptData,
  options: { allowBrowserFallback?: boolean } = {},
): Promise<ReceiptPrintResult> {
  const allowBrowserFallback = options.allowBrowserFallback ?? true;
  const settings = getPrinterSettings();
  const job = enqueueReceiptData(receipt);

  try {
    const result = await flushReceiptOutbox((candidate) => candidate.jobId === job.jobId);
    if (result.failed === 0 && (result.printed > 0 || getReceiptJobStatus(job.jobId) === 'printed')) {
      return {
        status: 'printed',
        channel: settings.connectionType === 'usb' ? 'usb' : 'bridge',
      };
    }
  } catch (error: unknown) {
    if (!allowBrowserFallback || settings.connectionType === 'usb') {
      return {
        status: 'queued',
        channel: 'outbox',
        error: error instanceof Error ? error.message : String(error),
      };
    }
  }

  if (!allowBrowserFallback || settings.connectionType === 'usb') {
    return {
      status: 'queued',
      channel: 'outbox',
      error: 'Printer belum siap; job disimpan di antrean.',
    };
  }

  try {
    await printReceiptBrowser(receipt);
    markReceiptJobPrinted(job.jobId);
    return { status: 'printed', channel: 'browser' };
  } catch (error: unknown) {
    return {
      status: 'queued',
      channel: 'outbox',
      error: error instanceof Error ? error.message : 'Aktifkan popup untuk mencetak.',
    };
  }
}