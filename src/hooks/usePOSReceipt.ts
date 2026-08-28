import { useCallback, useState } from 'react';
import { toast } from 'sonner';
import { printBridgeClient } from '@/lib/printBridgeClient';
import { enqueueReceiptJob, flushReceiptOutbox } from '@/lib/printOutbox';
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
      if (!health.ok || printers.length === 0) throw new Error('Print Bridge aktif, tetapi belum ada printer yang dikonfigurasi.');
      setThermalConnected(true);
      toast.success(`Print Bridge siap · ${printers.find((printer) => printer.isDefault)?.name || printers[0].name}`);
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
    try {
      enqueueReceiptJob({ store: tenant, sale: lastSale }, userEmail);
      const result = await flushReceiptOutbox();
      if (result.failed > 0) {
        setThermalConnected(false);
        toast.error('Struk disimpan di antrean. Print Bridge atau printer belum siap.');
        return false;
      }
      setThermalConnected(true);
      toast.success('Struk berhasil dikirim ke printer');
      return true;
    } catch (error: unknown) {
      setThermalConnected(false);
      toast.error(`Struk disimpan, tetapi belum tercetak: ${error instanceof Error ? error.message : 'Jalankan Print Bridge'}`);
      return false;
    }
  }, [lastSale, tenant, outletReady, userEmail]);

  return { thermalConnected, thermalConnecting, connectThermalPrinter, printReceipt };
}
