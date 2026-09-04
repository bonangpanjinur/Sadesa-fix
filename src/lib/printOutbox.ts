import { createPrintJob, type PrintJobEnvelope, type ReceiptSnapshot } from '@/lib/receiptDomain';
import { printBridgeClient } from '@/lib/printBridgeClient';
import { getPrinterSettings, getUniversalPrinter } from '@/lib/thermalPrinter';

const OUTBOX_KEY = 'pos_receipt_print_outbox_v1';

interface StoredJob extends Omit<PrintJobEnvelope, 'receipt'> {
  receipt: Omit<PrintJobEnvelope['receipt'], 'date'> & { date: string };
  status: 'pending' | 'printed' | 'failed';
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

export function enqueueReceiptData(receipt: PrintJobEnvelope['receipt'], copies = getPrinterSettings().printCopies): PrintJobEnvelope {
  const job: PrintJobEnvelope = {
    jobId: receipt.jobId,
    saleId: receipt.saleId,
    saleNumber: receipt.saleNumber,
    outletId: receipt.outletId,
    createdAt: receipt.createdAt,
    copies: Math.max(1, copies),
    receipt,
  };
  const jobs = readJobs();
  if (!jobs.some(existing => existing.jobId === job.jobId)) {
    jobs.push({ ...job, receipt: { ...job.receipt, date: job.receipt.date.toISOString() }, status: 'pending' });
    writeJobs(jobs);
  }
  return job;
}

export function enqueueReceiptJob(snapshot: ReceiptSnapshot, cashierName?: string): PrintJobEnvelope {
  return enqueueReceiptData(createPrintJob(snapshot, cashierName, getPrinterSettings().printCopies).receipt);
}

export async function flushReceiptOutbox(filter?: (job: PrintJobEnvelope) => boolean): Promise<{ printed: number; failed: number }> {
  const jobs = readJobs();
  let printed = 0;
  let failed = 0;
  for (const stored of jobs.filter(job => job.status !== 'printed' && (!filter || filter(hydrate(job))))) {
    try {
      const receipt = hydrate(stored).receipt;
      if (getPrinterSettings().connectionType === 'usb') {
        await getUniversalPrinter().printReceipt(receipt, stored.copies);
      } else {
        const submitted = await printBridgeClient.submitReceipt(receipt);
        const finalJob = submitted.status === 'printed' || submitted.status === 'failed'
          ? submitted
          : await printBridgeClient.waitForJob(submitted.jobId);
        if (finalJob.status !== 'printed') throw new Error(finalJob.error || 'Printer gagal');
      }
      stored.status = 'printed'; stored.lastError = undefined; printed += 1;
    } catch (error) {
      stored.status = 'failed'; stored.lastError = error instanceof Error ? error.message : String(error); failed += 1;
      break;
    }
  }
  writeJobs(jobs);
  return { printed, failed };
}

export function getPendingReceiptCount(): number {
  return readJobs().filter(job => job.status !== 'printed').length;
}
