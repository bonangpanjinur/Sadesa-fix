import { useState, useEffect, useCallback, useRef } from 'react';
import { POSLayout } from '@/components/pos/POSLayout';
import { printBridgeClient } from '@/lib/printBridgeClient';
import type { ReceiptData } from '@/lib/thermalPrinter';
import { usePOS } from '@/contexts/POSContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { toast } from 'sonner';
import { QRCodeSVG } from 'qrcode.react';
import {
  QrCode, Download, Printer, RefreshCw, Table2, Users,
  Copy, CheckCircle, ExternalLink, Info
} from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';

interface TableItem {
  id: string;
  name: string;
  section: string;
  capacity: number;
  status: 'available' | 'occupied' | 'reserved' | 'cleaning';
  is_active: boolean;
}

const STATUS_COLORS: Record<string, string> = {
  available: 'bg-emerald-100 text-emerald-700 border-emerald-300',
  occupied:  'bg-red-100 text-red-700 border-red-300',
  reserved:  'bg-yellow-100 text-yellow-700 border-yellow-300',
  cleaning:  'bg-blue-100 text-blue-700 border-blue-300',
};
const STATUS_LABELS: Record<string, string> = {
  available: 'Tersedia', occupied: 'Terisi',
  reserved: 'Reservasi', cleaning: 'Dibersihkan',
};

function getMenuUrl(tenantId: string, tableId: string): string {
  const base = window.location.origin;
  return `${base}/menu/${tenantId}/${tableId}`;
}

export default function POSMenuQRPage() {
  const { tenant, activeOutlet } = usePOS();
  const [tables, setTables] = useState<TableItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeSection, setActiveSection] = useState('semua');
  const [search, setSearch] = useState('');
  const [qrDialog, setQrDialog] = useState(false);
  const [selectedTable, setSelectedTable] = useState<TableItem | null>(null);
  const [copied, setCopied] = useState(false);
  const [bridgeStatus, setBridgeStatus] = useState<'checking' | 'online' | 'offline'>('checking');
  const [printing, setPrinting] = useState(false);
  const qrRef = useRef<SVGSVGElement | null>(null);

  const fetchTables = useCallback(async () => {
    if (!tenant) return;
    setLoading(true);
    try {
      let q = supabase
        .from('pos_tables' as never)
        .select('*')
        .eq('tenant_id', tenant.id)
        .eq('is_active', true)
        .order('section')
        .order('name');
      if (activeOutlet) q = q.eq('outlet_id', activeOutlet.id);
      const { data } = await q;
      setTables((data || []) as unknown as TableItem[]);
    } catch (err: unknown) {
      toast.error('Gagal memuat meja: ' + (err instanceof Error ? err.message : String(err)));
    } finally {
      setLoading(false);
    }
  }, [tenant, activeOutlet]);

  useEffect(() => { fetchTables(); }, [fetchTables]);

  const checkPrintBridge = useCallback(async () => {
    try {
      await printBridgeClient.health();
      setBridgeStatus('online');
    } catch {
      setBridgeStatus('offline');
    }
  }, []);

  useEffect(() => { void checkPrintBridge(); }, [checkPrintBridge]);

  const sections = ['semua', ...Array.from(new Set(tables.map(t => t.section))).sort()];

  const filtered = tables.filter(t => {
    const matchSection = activeSection === 'semua' || t.section === activeSection;
    const matchSearch = !search || t.name.toLowerCase().includes(search.toLowerCase());
    return matchSection && matchSearch;
  });

  const openQR = (table: TableItem) => {
    setSelectedTable(table);
    setQrDialog(true);
    setCopied(false);
  };

  const copyLink = async () => {
    if (!tenant || !selectedTable) return;
    await navigator.clipboard.writeText(getMenuUrl(tenant.id, selectedTable.id));
    setCopied(true);
    toast.success('Link disalin!');
    setTimeout(() => setCopied(false), 2000);
  };

  const downloadQR = () => {
    if (!selectedTable || !qrRef.current) return;
    const svg = qrRef.current;
    const svgData = new XMLSerializer().serializeToString(svg);
    const canvas = document.createElement('canvas');
    const size = 400;
    canvas.width = size;
    canvas.height = size + 60;
    const ctx = canvas.getContext('2d')!;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    const img = new Image();
    const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(svgBlob);
    img.onload = () => {
      ctx.drawImage(img, 0, 0, size, size);
      ctx.fillStyle = '#1a1a1a';
      ctx.font = 'bold 18px Arial';
      ctx.textAlign = 'center';
      ctx.fillText(`Scan untuk memesan — ${selectedTable.name}`, size / 2, size + 35);
      const link = document.createElement('a');
      link.download = `qr-menu-${selectedTable.name.replace(/\s+/g, '-').toLowerCase()}.png`;
      link.href = canvas.toDataURL('image/png');
      link.click();
      URL.revokeObjectURL(url);
    };
    img.src = url;
  };

  const makeQrReceipt = (table: TableItem): ReceiptData => {
    if (!tenant) throw new Error('Tenant belum siap');
    const now = new Date().toISOString();
    return {
      saleId: `qr-menu:${tenant.id}:${table.id}`,
      saleNumber: `QR-${table.name}`,
      createdAt: now,
      outletId: activeOutlet?.id || 'all-outlets',
      jobId: `qr-menu:${tenant.id}:${table.id}:${Date.now()}`,
      storeName: tenant.store_name || tenant.name,
      receiptHeader: table.section,
      receiptFooter: 'Scan untuk melihat menu & memesan',
      invoiceNo: `QR-${table.name}`,
      date: new Date(now),
      items: [],
      subtotal: 0,
      discountAmount: 0,
      taxAmount: 0,
      total: 0,
      paidAmount: 0,
      changeAmount: 0,
      paymentMethod: 'QR MENU',
      qrData: getMenuUrl(tenant.id, table.id),
    };
  };

  const printQR = async (table = selectedTable) => {
    if (!table || !tenant) return;
    setPrinting(true);
    try {
      const job = await printBridgeClient.submitReceipt(makeQrReceipt(table));
      const finished = await printBridgeClient.waitForJob(job.jobId);
      if (finished.status === 'failed') throw new Error(finished.error || 'Printer menolak job QR');
      setBridgeStatus('online');
      toast.success(`QR ${table.name} dikirim ke printer`);
    } catch (error) {
      setBridgeStatus('offline');
      toast.error(error instanceof Error ? error.message : 'Gagal mencetak QR melalui Print Bridge');
    } finally {
      setPrinting(false);
    }
  };

  const printAllQR = async () => {
    if (!tenant || filtered.length === 0) return;
    setPrinting(true);
    let printed = 0;
    try {
      for (const table of filtered) {
        const job = await printBridgeClient.submitReceipt(makeQrReceipt(table));
        const finished = await printBridgeClient.waitForJob(job.jobId);
        if (finished.status === 'failed') throw new Error(finished.error || `QR ${table.name} gagal dicetak`);
        printed += 1;
      }
      setBridgeStatus('online');
      toast.success(`${printed} QR menu dikirim ke printer`);
    } catch (error) {
      setBridgeStatus('offline');
      toast.error(error instanceof Error ? error.message : `Gagal setelah mencetak ${printed} QR`);
    } finally {
      setPrinting(false);
    }
  };

  return (
    <POSLayout title="Menu Digital QR" subtitle="Buat & cetak QR code untuk setiap meja restoran">
      <div className="p-6 space-y-6">

        {/* Info Banner */}
        <div className="flex items-start gap-3 bg-emerald-50 border border-emerald-200 rounded-lg p-4">
          <Info className="h-5 w-5 text-emerald-600 mt-0.5 shrink-0" />
          <div className="text-sm text-emerald-800">
            <p className="font-medium mb-1">Cara menggunakan Menu Digital QR</p>
            <ol className="list-decimal list-inside space-y-0.5 text-emerald-700">
              <li>Cetak QR code untuk setiap meja dan tempelkan di meja</li>
              <li>Pelanggan scan QR → langsung melihat menu di HP tanpa install aplikasi</li>
              <li>Pelanggan memilih menu dan kirim pesanan → langsung masuk ke dapur (KDS)</li>
            </ol>
          </div>
        </div>

        {/* Print Bridge diagnostic */}
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card px-4 py-3">
          <div className="flex items-center gap-2 text-sm">
            <span className={`h-2.5 w-2.5 rounded-full ${bridgeStatus === 'online' ? 'bg-emerald-500' : bridgeStatus === 'checking' ? 'bg-amber-500 animate-pulse' : 'bg-red-500'}`} aria-hidden="true" />
            <span className="font-medium">Print Bridge: {bridgeStatus === 'online' ? 'Terhubung' : bridgeStatus === 'checking' ? 'Memeriksa...' : 'Tidak tersedia'}</span>
          </div>
          <Button variant="ghost" size="sm" onClick={() => void checkPrintBridge()} disabled={bridgeStatus === 'checking'}>
            <RefreshCw className="mr-1 h-4 w-4" /> Periksa koneksi
          </Button>
        </div>

        {/* Controls */}
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div className="flex gap-2 flex-wrap">
            <Input
              placeholder="Cari meja..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="w-48 h-9"
            />
            <Button variant="outline" size="sm" onClick={fetchTables}>
              <RefreshCw className="h-4 w-4 mr-1" /> Refresh
            </Button>
          </div>
          <div className="flex gap-2">
            {tenant && (
              <Button
                variant="outline"
                size="sm"
                className="border-emerald-400 text-emerald-600 hover:bg-emerald-50"
                onClick={() => window.open(`/menu/${tenant.id}`, '_blank')}
              >
                <ExternalLink className="h-4 w-4 mr-1" /> Preview Menu
              </Button>
            )}
              <Button
                size="sm"
                className="bg-emerald-600 hover:bg-emerald-700"
                onClick={() => void printAllQR()}
                disabled={filtered.length === 0 || printing}
              >
              <Printer className="h-4 w-4 mr-1" /> Cetak Semua QR
            </Button>
          </div>
        </div>

        {/* Section Filter */}
        {sections.length > 2 && (
          <div className="flex gap-2 flex-wrap">
            {sections.map(s => (
              <button
                key={s}
                onClick={() => setActiveSection(s)}
                className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-colors ${
                  activeSection === s
                    ? 'bg-emerald-600 text-white border-emerald-600'
                    : 'border-border text-muted-foreground hover:border-emerald-400'
                }`}
              >
                {s === 'semua' ? 'Semua Area' : s}
              </button>
            ))}
          </div>
        )}

        {/* Table Grid */}
        {loading ? (
          <div className="text-center py-16 text-muted-foreground">Memuat daftar meja...</div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-16">
            <Table2 className="h-12 w-12 text-muted-foreground mx-auto mb-3" />
            <p className="text-muted-foreground">Belum ada meja. Tambahkan meja di halaman <strong>Manajemen Meja</strong>.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {filtered.map(table => {
              const menuUrl = tenant ? getMenuUrl(tenant.id, table.id) : '';
              return (
                <Card key={table.id} className="hover:shadow-md transition-shadow">
                  <CardHeader className="pb-3">
                    <div className="flex items-start justify-between">
                      <div>
                        <CardTitle className="text-base">{table.name}</CardTitle>
                        <p className="text-xs text-muted-foreground mt-0.5">{table.section}</p>
                      </div>
                      <Badge className={`text-xs border ${STATUS_COLORS[table.status] || ''}`}>
                        {STATUS_LABELS[table.status] || table.status}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-1 text-xs text-muted-foreground mt-1">
                      <Users className="h-3 w-3" />
                      <span>{table.capacity} orang</span>
                    </div>
                  </CardHeader>
                  <CardContent className="pt-0">
                    {/* QR Preview */}
                    <div className="flex justify-center mb-4 bg-white p-3 rounded-lg border">
                      {tenant ? (
                        <QRCodeSVG
                          value={menuUrl}
                          size={120}
                          level="M"
                          includeMargin={false}
                        />
                      ) : (
                        <div className="w-[120px] h-[120px] bg-gray-100 rounded flex items-center justify-center">
                          <QrCode className="h-8 w-8 text-gray-300" />
                        </div>
                      )}
                    </div>

                    {/* Actions */}
                    <div className="grid grid-cols-2 gap-2">
                      <Button
                        size="sm"
                        className="bg-emerald-600 hover:bg-emerald-700 h-8 text-xs"
                        onClick={() => openQR(table)}
                      >
                        <QrCode className="h-3.5 w-3.5 mr-1" /> Detail QR
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-8 text-xs"
                        onClick={() => void printQR(table)}
                        disabled={printing}
                      >
                        <Printer className="h-3.5 w-3.5 mr-1" /> Cetak
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </div>

      {/* QR Detail Dialog */}
      <Dialog open={qrDialog} onOpenChange={setQrDialog}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <QrCode className="h-5 w-5 text-emerald-600" />
              QR Menu — {selectedTable?.name}
            </DialogTitle>
          </DialogHeader>
          {selectedTable && tenant && (
            <div className="space-y-4 py-2">
              <div className="bg-white p-5 rounded-xl border-2 border-dashed border-emerald-200 flex flex-col items-center gap-3">
                <p className="font-bold text-center text-sm text-emerald-700">{tenant.name}</p>
                <QRCodeSVG
                  ref={(el: SVGSVGElement | null) => { qrRef.current = el; }}
                  value={getMenuUrl(tenant.id, selectedTable.id)}
                  size={200}
                  level="M"
                  includeMargin={true}
                />
                <p className="text-center">
                  <span className="font-bold text-lg">{selectedTable.name}</span>
                  <span className="text-xs text-muted-foreground block">{selectedTable.section} · {selectedTable.capacity} orang</span>
                </p>
                <p className="text-xs text-emerald-600 font-medium text-center">
                  Scan untuk lihat menu &amp; pesan langsung
                </p>
              </div>

              {/* Link */}
              <div className="flex items-center gap-2 bg-muted rounded-lg px-3 py-2">
                <p className="flex-1 text-xs text-muted-foreground truncate">
                  {getMenuUrl(tenant.id, selectedTable.id)}
                </p>
                <button
                  onClick={copyLink}
                  className="text-emerald-600 hover:text-emerald-700 shrink-0"
                  title="Salin link"
                >
                  {copied ? <CheckCircle className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                </button>
              </div>

              {/* Actions */}
              <div className="grid grid-cols-2 gap-2">
                <Button variant="outline" className="h-9" onClick={downloadQR}>
                  <Download className="h-4 w-4 mr-1.5" /> Unduh PNG
                </Button>
                        <Button className="h-9 bg-emerald-600 hover:bg-emerald-700" onClick={() => void printQR()} disabled={printing}>
<Printer className="h-4 w-4 mr-1.5" /> {printing ? 'Mengirim...' : 'Cetak'}
                        </Button>
              </div>

              <Button
                variant="ghost"
                size="sm"
                className="w-full text-xs text-muted-foreground"
                onClick={() => window.open(`/menu/${tenant.id}/${selectedTable.id}`, '_blank')}
              >
                <ExternalLink className="h-3.5 w-3.5 mr-1" /> Buka di browser baru
              </Button>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </POSLayout>
  );
}
