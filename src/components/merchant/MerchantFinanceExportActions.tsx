import { FileSpreadsheet, FileText } from 'lucide-react';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

export type FinanceExportRow = {
  id: string;
  date: string;
  customer: string;
  status: string;
  payment: string;
  subtotal: number;
  shipping: number;
  total: number;
  commission: number;
  net: number;
};

const rupiah = (value: number) => `Rp ${new Intl.NumberFormat('id-ID').format(value)}`;
const escapeHtml = (value: string | number) => String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[char] ?? char));

export function MerchantFinanceExportActions({ rows, merchantName, from, to }: { rows: FinanceExportRow[]; merchantName: string | null; from: string; to: string }) {
  const filePrefix = `laporan-keuangan-${(merchantName || 'merchant').toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${from}-${to}`;
  const exportExcel = () => {
    const headers = ['ID Transaksi', 'Tanggal', 'Pelanggan', 'Status', 'Pembayaran', 'Subtotal', 'Ongkir', 'Total', 'Komisi Platform', 'Saldo Bersih'];
    const body = rows.map((row) => [row.id, row.date, row.customer, row.status, row.payment, rupiah(row.subtotal), rupiah(row.shipping), rupiah(row.total), rupiah(row.commission), rupiah(row.net)]);
    const table = `<table><thead><tr>${headers.map((header) => `<th>${escapeHtml(header)}</th>`).join('')}</tr></thead><tbody>${body.map((line) => `<tr>${line.map((cell) => `<td>${escapeHtml(cell)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
    const html = `<html><head><meta charset="UTF-8"><style>body{font-family:Arial}h2{color:#047857}table{border-collapse:collapse;width:100%}th,td{border:1px solid #cbd5e1;padding:7px;text-align:left}th{background:#d1fae5}td:nth-child(n+6){text-align:right}</style></head><body><h2>Laporan Keuangan Merchant</h2><p>Periode: ${escapeHtml(from)} sampai ${escapeHtml(to)}</p>${table}</body></html>`;
    const blob = new Blob([`\ufeff${html}`], { type: 'application/vnd.ms-excel;charset=utf-8' });
    const url = URL.createObjectURL(blob); const anchor = document.createElement('a'); anchor.href = url; anchor.download = `${filePrefix}.xls`; anchor.click(); URL.revokeObjectURL(url);
    toast.success('Laporan Excel berhasil diekspor');
  };
  const exportPdf = () => {
    const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
    doc.setFontSize(16); doc.setTextColor(4, 120, 87); doc.text('Laporan Keuangan Merchant', 14, 16);
    doc.setFontSize(9); doc.setTextColor(71, 85, 105); doc.text(`Merchant: ${merchantName || '-'} | Periode: ${from} s/d ${to}`, 14, 23);
    autoTable(doc, { startY: 29, head: [['ID', 'Tanggal', 'Pelanggan', 'Status', 'Pembayaran', 'Subtotal', 'Total', 'Komisi', 'Bersih']], body: rows.map((row) => [row.id.slice(0, 8).toUpperCase(), row.date, row.customer, row.status, row.payment, rupiah(row.subtotal), rupiah(row.total), rupiah(row.commission), rupiah(row.net)]), styles: { fontSize: 8, cellPadding: 2.5 }, headStyles: { fillColor: [4, 120, 87] }, alternateRowStyles: { fillColor: [240, 253, 250] }, columnStyles: { 5: { halign: 'right' }, 6: { halign: 'right' }, 7: { halign: 'right' }, 8: { halign: 'right' } } });
    doc.save(`${filePrefix}.pdf`); toast.success('Laporan PDF berhasil diekspor');
  };
  return <div className="flex flex-wrap items-center gap-2"><Button variant="outline" size="sm" onClick={exportExcel} disabled={!rows.length}><FileSpreadsheet className="mr-2 h-4 w-4 text-emerald-600" />Excel</Button><Button variant="outline" size="sm" onClick={exportPdf} disabled={!rows.length}><FileText className="mr-2 h-4 w-4 text-red-600" />PDF</Button></div>;
}
