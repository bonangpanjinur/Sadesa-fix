import { createPrintJob, type PrintJobEnvelope, type ReceiptSnapshot, type PrintIntent } from '@/lib/receiptDomain';
import { printBridgeClient } from '@/lib/printBridgeClient';
import { getPrinterSettings, getUniversalPrinter } from '@/lib/thermalPrinter';
import type { PrinterScope } from '@/lib/thermalPrinter';
import { printReceiptViaAndroidService } from '@/lib/androidPrintService';

const OUTBOX_KEY = 'pos_receipt_print_outbox_v1';

interface StoredJob extends Omit<PrintJobEnvelope, 'receipt'> {
  receipt: Omit<PrintJobEnvelope['receipt'], 'date'> & { date: string };
  status: 'pending' | 'printed' | 'failed';
  printIntent: PrintIntent;
  attemptId: string;
  requestedAt: string;
  lastError?: string;
}

function readJobs(): StoredJob[] {
  try { return JSON.parse(localStorage.getItem(OUTBOX_KEY) || '[]') as StoredJob[]; }
  catch { return []; }
}

function writeJobs(jobs: StoredJob[]) {
  localStorage.setItem(OUTBOX_KEY, JSON.stringify(jobs.slice(-100)));
}

function hydrate(job: StoredJob): PrintJobEnvelope {
  return { ...job, receipt: { ...job.receipt, date: new Date(job.receipt.date) } } as PrintJobEnvelope;
}

export function enqueueReceiptData(receipt: PrintJobEnvelope['receipt'], copies = getPrinterSettings(receipt.printerScope).printCopies): PrintJobEnvelope {
  const job: PrintJobEnvelope = {
    jobId: receipt.jobId || `receipt:attempt:${Date.now()}`,
    printIntent: receipt.printIntent ?? (receipt.jobId?.startsWith('receipt:reprint:') ? 'reprint' : 'manual'),
    attemptId: receipt.attemptId || receipt.jobId || `attempt:${Date.now()}`,
    requestedAt: receipt.requestedAt || new Date().toISOString(),
    saleId: receipt.saleId,
    saleNumber: receipt.saleNumber,
    outletId: receipt.outletId,
    createdAt: receipt.createdAt,
    copies: Math.max(1, copies),
    receipt,
  };
  const jobs = readJobs();
  if (!jobs.some(existing => existing.jobId === job.jobId)) {
    jobs.push({ ...job, receipt: { ...job.receipt, date: job.receipt.date.toISOString() }, status: 'pending', printIntent: job.printIntent, attemptId: job.attemptId, requestedAt: job.requestedAt });
    writeJobs(jobs);
  }
  return job;
}

export function enqueueReceiptJob(snapshot: ReceiptSnapshot, cashierName?: string): PrintJobEnvelope {
  const scope = snapshot.store.id && snapshot.sale.outletId ? { tenantId: snapshot.store.id, outletId: snapshot.sale.outletId } : undefined;
  return enqueueReceiptData(createPrintJob(snapshot, cashierName, getPrinterSettings(scope).printCopies).receipt);
}

async function sendToConfiguredPrinter(receipt: PrintJobEnvelope['receipt'], copies: number): Promise<void> {
  const settings = getPrinterSettings(receipt.printerScope);
  const universal = getUniversalPrinter();

  if (settings.connectionType === 'android_bluetooth') {
    await printReceiptViaAndroidService(receipt, copies);
    return;
  }

  // Direct Web Serial/Web Bluetooth is fast when already authorised. If the
  // browser lost the device connection, continue through the local bridge.
  if ((settings.connectionType === 'usb' || settings.connectionType === 'bluetooth') && universal.isConnected(receipt.printerScope)) {
    try {
      await universal.printReceipt(receipt, copies);
      return;
    } catch (nativeError) {
      try {
        const bridgeJob = await printBridgeClient.submitReceipt(receipt);
        const finalJob = bridgeJob.status === 'printed' || bridgeJob.status === 'failed'
          ? bridgeJob
          : await printBridgeClient.waitForJob(bridgeJob.jobId);
        if (finalJob.status === 'printed') return;
        throw new Error(finalJob.error || 'Print Bridge gagal mencetak');
      } catch (bridgeError) {
        throw new Error(`Native printer gagal: ${nativeError instanceof Error ? nativeError.message : String(nativeError)}; Print Bridge gagal: ${bridgeError instanceof Error ? bridgeError.message : String(bridgeError)}`);
      }
    }
  }

  // WiFi/LAN and bridge-managed USB/Bluetooth are printed without opening a
  // browser dialog, including when the PWA is installed in standalone mode.
  const bridgeJob = await printBridgeClient.submitReceipt(receipt);
  const finalJob = bridgeJob.status === 'printed' || bridgeJob.status === 'failed'
    ? bridgeJob
    : await printBridgeClient.waitForJob(bridgeJob.jobId);
  if (finalJob.status !== 'printed') throw new Error(finalJob.error || 'Printer gagal');
}

export async function flushReceiptOutbox(filter?: (job: PrintJobEnvelope) => boolean): Promise<{ printed: number; failed: number }> {
  const jobs = readJobs();
  let printed = 0;
  let failed = 0;
  for (const stored of jobs.filter(job => job.status !== 'printed' && (!filter || filter(hydrate(job))))) {
    try {
      const receipt = hydrate(stored).receipt;
      await sendToConfiguredPrinter(receipt, stored.copies);
      stored.status = 'printed'; stored.lastError = undefined; printed += 1;
    } catch (error) {
      stored.status = 'failed'; stored.lastError = error instanceof Error ? error.message : String(error); failed += 1;
      break;
    }
  }
  writeJobs(jobs);
  return { printed, failed };
}

export function getPendingReceiptCount(scope?: PrinterScope): number {
  return readJobs().filter(job => {
    if (job.status === 'printed') return false;
    if (!scope) return true;
    return job.receipt.printerScope?.tenantId === scope.tenantId && job.receipt.printerScope?.outletId === scope.outletId;
  }).length;
}

export function getReceiptJobStatus(jobId: string): StoredJob['status'] | null {
  return readJobs().find(job => job.jobId === jobId)?.status || null;
}

export function markReceiptJobPrinted(jobId: string): boolean {
  const jobs = readJobs();
  const job = jobs.find(candidate => candidate.jobId === jobId);
  if (!job) return false;
  job.status = 'printed';
  job.lastError = undefined;
  writeJobs(jobs);
  return true;
}
