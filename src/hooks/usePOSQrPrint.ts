import { useCallback, useState } from 'react';
import { toast } from 'sonner';
import { enqueueReceiptData, flushReceiptOutbox } from '@/lib/printOutbox';
import { createPOSQrReceipt, type POSQrTable, type POSQrTenant } from '@/lib/posQrPrint';

interface UsePOSQrPrintArgs {
  tenant: POSQrTenant | null;
  outletId?: string | null;
}

export function usePOSQrPrint({ tenant, outletId }: UsePOSQrPrintArgs) {
  const [printing, setPrinting] = useState(false);

  const printQR = useCallback(async (table: POSQrTable) => {
    if (!tenant) return false;
    setPrinting(true);
    try {
      const receipt = createPOSQrReceipt(tenant, table, outletId);
      const job = enqueueReceiptData(receipt);
      const result = await flushReceiptOutbox((candidate) => candidate.jobId === job.jobId);
      if (result.failed > 0) throw new Error('Print Bridge atau printer belum siap. Job disimpan untuk dicoba lagi.');
      toast.success(`QR ${table.name} berhasil dikirim ke printer`);
      return true;
    } catch (error: unknown) {
      toast.error(error instanceof Error ? error.message : 'Gagal mencetak QR');
      return false;
    } finally {
      setPrinting(false);
    }
  }, [tenant, outletId]);

  const printAllQR = useCallback(async (tables: POSQrTable[]) => {
    if (!tenant || tables.length === 0) return false;
    setPrinting(true);
    let printed = 0;
    try {
      const jobs = tables.map((table) => enqueueReceiptData(createPOSQrReceipt(tenant, table, outletId)));
      const jobIds = new Set(jobs.map((job) => job.jobId));
      const result = await flushReceiptOutbox((candidate) => jobIds.has(candidate.jobId));
      printed = result.printed;
      if (result.failed > 0) throw new Error(`Sebanyak ${result.failed} QR belum tercetak dan tetap tersimpan di antrean.`);
      toast.success(`${printed} QR menu berhasil dikirim ke printer`);
      return true;
    } catch (error: unknown) {
      toast.error(error instanceof Error ? error.message : `Gagal setelah mencetak ${printed} QR`);
      return false;
    } finally {
      setPrinting(false);
    }
  }, [tenant, outletId]);

  return { printing, printQR, printAllQR };
}
