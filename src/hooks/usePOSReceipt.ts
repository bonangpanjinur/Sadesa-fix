import { useCallback, useState } from 'react';
import { toast } from 'sonner';
import { printBridgeClient } from '@/lib/printBridgeClient';
import { enqueueReceiptData, flushReceiptOutbox } from '@/lib/printOutbox';
import { createPrintJob } from '@/lib/receiptDomain';
import { getPrinterSettings, printReceiptBrowser } from '@/lib/thermalPrinter';
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
    const receiptJob = createPrintJob({ store: tenant, sale: lastSale }, userEmail);
    enqueueReceiptData(receiptJob.receipt);
    try {
      const result = await flushReceiptOutbox();
      if (result.failed > 0) {
        setThermalConnected(false);
        if (getPrinterSettings().connectionType === 'usb') {
          toast.error('Printer USB belum mencetak. Hubungkan printer dari Pengaturan Printer, lalu coba ulang antrean.');
          return false;
        }
        await printReceiptBrowser(receiptJob.receipt);
        toast.info('Print Bridge tidak tersedia. Struk dibuka melalui dialog print browser.');
        return true;
      }
      setThermalConnected(true);
      toast.success('Struk berhasil dikirim ke printer');
      return true;
    } catch (error: unknown) {
      setThermalConnected(false);
      if (getPrinterSettings().connectionType === 'usb') {
        toast.error(`Printer USB belum mencetak: ${error instanceof Error ? error.message : 'Hubungkan printer USB dari Pengaturan Printer.'}`);
        return false;
      }
      try {
        await printReceiptBrowser(receiptJob.receipt);
        toast.info('Print Bridge tidak tersedia. Struk dibuka melalui dialog print browser.');
        return true;
      } catch (fallbackError: unknown) {
        toast.error(`Struk disimpan, tetapi belum tercetak: ${fallbackError instanceof Error ? fallbackError.message : 'Aktifkan popup untuk mencetak'}`);
        return false;
      }
    }
  }, [lastSale, tenant, outletReady, userEmail]);

  return { thermalConnected, thermalConnecting, connectThermalPrinter, printReceipt };
}
