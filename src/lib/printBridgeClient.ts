import { buildReceiptBytes, getPrinterSettings } from '@/lib/thermalPrinter';
import type { ReceiptData } from '@/lib/thermalPrinter';

export const PRINT_BRIDGE_URL = 'http://127.0.0.1:18181';

export type PrintJobStatus = 'queued' | 'printing' | 'printed' | 'failed';

export interface PrintBridgeJob {
  jobId: string;
  saleId: string;
  saleNumber: string;
  outletId: string;
  createdAt: string;
  printerId: string | null;
  copies: number;
  data: string;
  status: PrintJobStatus;
  attempts: number;
  error: string | null;
  updatedAt: string;
}

export interface PrintBridgeHealth {
  ok: boolean;
  service: string;
  version: string;
  queue: number;
  time: string;
}

export interface PrintBridgePrinter {
  id: string;
  name: string;
  type: 'tcp' | 'serial';
  host?: string;
  port?: number;
  path?: string;
  baudRate?: number;
  isDefault?: boolean;
}

function bytesToBase64(bytes: number[]): string {
  let binary = '';
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.slice(index, index + chunkSize));
  }
  return btoa(binary);
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${PRINT_BRIDGE_URL}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init?.headers || {}) },
    signal: AbortSignal.timeout(2500),
  });
  const payload = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(payload.error || `Print Bridge HTTP ${response.status}`);
  return payload;
}

export const printBridgeClient = {
  async health(): Promise<PrintBridgeHealth> {
    return request<PrintBridgeHealth>('/health');
  },

  async listPrinters(): Promise<PrintBridgePrinter[]> {
    const result = await request<{ printers: PrintBridgePrinter[] }>('/printers');
    return result.printers;
  },

  async testPrint(): Promise<PrintBridgeJob> {
    const now = new Date().toISOString();
    return this.submitReceipt({
      saleId: `test-${Date.now()}`,
      saleNumber: 'TEST-PRINT',
      createdAt: now,
      outletId: 'test',
      jobId: `test-print:${Date.now()}`,
      storeName: 'SaDesa POS',
      receiptHeader: 'PRINT BRIDGE TEST',
      receiptFooter: 'Printer siap digunakan',
      invoiceNo: 'TEST-PRINT',
      date: new Date(now),
      items: [{ name: 'Test koneksi printer', qty: 1, price: 0, discount: 0 }],
      subtotal: 0,
      discountAmount: 0,
      taxAmount: 0,
      total: 0,
      paidAmount: 0,
      changeAmount: 0,
      paymentMethod: 'TEST',
    });
  },

  async submitReceipt(receipt: ReceiptData): Promise<PrintBridgeJob> {
    const settings = getPrinterSettings();
    const result = await request<PrintBridgeJob>('/jobs', {
      method: 'POST',
      body: JSON.stringify({
        jobId: receipt.jobId,
        saleId: receipt.saleId,
        saleNumber: receipt.saleNumber,
        outletId: receipt.outletId,
        createdAt: receipt.createdAt,
        copies: settings.printCopies,
        data: bytesToBase64(buildReceiptBytes(receipt, settings.paperWidth)),
      }),
    });
    return result;
  },

  async getJob(jobId: string): Promise<PrintBridgeJob> {
    return request<PrintBridgeJob>(`/jobs/${encodeURIComponent(jobId)}`);
  },

  async waitForJob(jobId: string, timeoutMs = 15000): Promise<PrintBridgeJob> {
    const startedAt = Date.now();
    let lastJob: PrintBridgeJob | null = null;
    while (Date.now() - startedAt < timeoutMs) {
      lastJob = await this.getJob(jobId);
      if (lastJob.status === 'printed' || lastJob.status === 'failed') return lastJob;
      await new Promise(resolve => window.setTimeout(resolve, 250));
    }
    throw new Error(lastJob?.error || 'Timeout menunggu printer');
  },
};
