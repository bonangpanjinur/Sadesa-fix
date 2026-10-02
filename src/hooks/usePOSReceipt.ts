import { useCallback, useState } from 'react';
import { toast } from 'sonner';
import { printBridgeClient } from '@/lib/printBridgeClient';
import { createPrintJob } from '@/lib/receiptDomain';
import { printReceiptWithContract } from '@/lib/receiptPrintContract';
import type { ReceiptStore, LastSale } from '@/components/pos/kasir/types';

interface UsePOSReceiptArgs {
  tenant: ReceiptStore | null;
  outletReady: boolean;
  lastSale: LastSale | null;
  userEmail?: string;
}

export function usePOSReceipt({ tenant, outletReady, lastSale, userEmail }: UsePOSReceiptArgs) {
  const [thermalConnected, setThermalConnected] = useState(false);
  const [thermalConnecting, setThermalConnecting] = useState(false);

  const connectThermalPrinter = useCallback(async () => {
    setThermalConnecting(true);
    try {
      const health = await printBridgeClient.health();
      const printers = await printBridgeClient.listPrinters();
      const defaultPrinter = printers.find((printer) => printer.isDefault);
      if (!health.ok || !defaultPrinter) throw new Error('Print Bridge aktif, tetapi printer default belum dikonfigurasi.');
      setThermalConnected(true);
      toast.success(`Print Bridge siap · ${defaultPrinter.name}`);
      return true;
    } catch (error: unknown) {
      setThermalConnected(false);
      toast.error(`Print Bridge belum siap: ${error instanceof Error ? error.message : 'Pastikan service lokal berjalan'}`);
      return false;
    } finally {
      setThermalConnecting(false);
    }
  }, []);

  const printReceipt = useCallback(async () => {
    if (!lastSale || !tenant || !outletReady) return false;
    const receiptJob = createPrintJob({ store: tenant, sale: lastSale }, userEmail);
    const result = await printReceiptWithContract(receiptJob.receipt);
    if (result.status === 'queued') {
      setThermalConnected(false);
      toast.error(result.error || 'Struk disimpan di antrean; printer belum siap.');
      return false;
    }
    setThermalConnected(result.channel !== 'browser');
    if (result.channel === 'browser') toast.info('Printer lokal tidak tersedia. Struk dibuka melalui dialog print browser.');
    else toast.success('Struk berhasil dikirim ke printer');
    return true;
  }, [lastSale, tenant, outletReady, userEmail]);

  return { thermalConnected, thermalConnecting, connectThermalPrinter, printReceipt };
}
