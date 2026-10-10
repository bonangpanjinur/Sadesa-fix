import { useState } from 'react';
import { Download, FileText } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { loadPdfExportLibraries } from '@/lib/loadPdfExport';
import { formatPrice } from '@/lib/utils';
import { toast } from 'sonner';

type ReceiptOrder = { id: string; created_at: string; delivery_name: string | null; status: string; payment: string; subtotal: number; shipping: number; discount: number; total: number; commission: number; net: number };

export function MerchantTransactionReceiptButton({ order, merchantName }: { order: ReceiptOrder; merchantName: string | null }) {
  const [downloading, setDownloading] = useState(false);
  const downloadReceipt = async () => {
    setDownloading(true);
    try {
      const { jsPDF, autoTable } = await loadPdfExportLibraries();
      const doc = new jsPDF({ unit: 'mm', format: 'a5' });
      const money = (value: number) => formatPrice(value);
      doc.setTextColor(4, 120, 87); doc.setFontSize(18); doc.text(merchantName || 'Nota Merchant', 14, 18);
      doc.setTextColor(71, 85, 105); doc.setFontSize(9); doc.text('KUITANSI TRANSAKSI', 14, 25); doc.text(`No. transaksi: ${order.id}`, 14, 32); doc.text(`Tanggal: ${new Date(order.created_at).toLocaleString('id-ID')}`, 14, 38);
      doc.setTextColor(15, 23, 42); doc.setFontSize(10); doc.text(`Pelanggan: ${order.delivery_name || 'Pelanggan'}`, 14, 48); doc.text(`Status: ${order.status}`, 14, 54); doc.text(`Pembayaran: ${order.payment}`, 14, 60);
      autoTable(doc, { startY: 68, theme: 'grid', head: [['Rincian', 'Jumlah']], body: [['Subtotal produk', money(order.subtotal)], ['Ongkir', money(order.shipping)], ['Diskon', `-${money(order.discount)}`], ['Total transaksi', money(order.total)], ['Komisi platform', `-${money(order.commission)}`], ['Saldo bersih merchant', money(order.net)]], styles: { fontSize: 9, cellPadding: 3 }, headStyles: { fillColor: [4, 120, 87] }, columnStyles: { 1: { halign: 'right' } } });
      const finalY = (doc as unknown as { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? 115; doc.setFontSize(8); doc.setTextColor(100, 116, 139); doc.text('Kuitansi ini dibuat dari riwayat transaksi merchant.', 14, finalY + 14); doc.save(`kuitansi-${order.id.slice(0, 12)}.pdf`); toast.success('Kuitansi transaksi berhasil diunduh');
    } catch (error) { console.error('Gagal membuat kuitansi transaksi:', error); toast.error('Kuitansi gagal dibuat'); } finally { setDownloading(false); }
  };
  return <Button type="button" variant="ghost" size="sm" className="h-8 px-2" onClick={() => void downloadReceipt()} disabled={downloading} title="Unduh kuitansi"><Download className="mr-1 h-3.5 w-3.5" /><FileText className="h-3.5 w-3.5" /><span className="sr-only">Unduh kuitansi</span></Button>;
}
