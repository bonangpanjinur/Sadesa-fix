import { useState, useEffect } from 'react';
import { POSLayout } from '@/components/pos/POSLayout';
import { usePOS } from '@/contexts/POSContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { Building2, Store, Plus, Pencil, Phone, MapPin, Printer, Wifi, Bluetooth, Usb, CheckCircle2, XCircle, TestTube2, Copy, RefreshCw, Info } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useCallback } from 'react';
import {
  getPrinterSettings, savePrinterSettings, getPrinterScope, DEFAULT_SETTINGS,
  USBPrinter, BluetoothPrinter, WiFiPrinter, getUniversalPrinter,
} from '@/lib/thermalPrinter';
import type { PrinterSettings, ConnectionType } from '@/lib/thermalPrinter';
import { printBridgeClient } from '@/lib/printBridgeClient';
import { flushReceiptOutbox, getPendingReceiptCount } from '@/lib/printOutbox';
import { isAndroidPrintServiceSupported, testPrintViaAndroidService } from '@/lib/androidPrintService';

interface Outlet {
  id: string;
  name: string;
  address: string | null;
  phone: string | null;
  is_active: boolean;
}

export default function POSPengaturanPage() {
  const { tenant, outlets, activeOutlet, refetchTenant, refetchOutlets } = usePOS();
  const { user } = useAuth();
  const [tenantForm, setTenantForm] = useState({
    name: '', phone: '', address: '', receipt_header: '', receipt_footer: '', timezone: 'Asia/Jakarta', currency: 'IDR',
  });
  const [outletDialog, setOutletDialog] = useState(false);
  const [editingOutlet, setEditingOutlet] = useState<Outlet | null>(null);
  const [outletForm, setOutletForm] = useState({ name: '', address: '', phone: '' });
  const [brandDialogOpen, setBrandDialogOpen] = useState(false);
  const [brandName, setBrandName] = useState('');
  const [brands, setBrands] = useState<{ id: string; name: string }[]>([]);
  const [saving, setSaving] = useState(false);
  const [isNewTenant, setIsNewTenant] = useState(false);

  // ── Printer Settings ──────────────────────────────────────
  const [printerSettings, setPrinterSettings] = useState<PrinterSettings>(() => getPrinterSettings());
  const printerScope = tenant && activeOutlet ? getPrinterScope(tenant.id, activeOutlet.id) : undefined;
  const [printerStatus, setPrinterStatus] = useState<'idle' | 'connecting' | 'connected' | 'error'>('idle');
  const [printerMsg, setPrinterMsg] = useState('');
  const [testingPrint, setTestingPrint] = useState(false);
  const [pendingPrintJobs, setPendingPrintJobs] = useState(() => getPendingReceiptCount());
  const [flushingPrintJobs, setFlushingPrintJobs] = useState(false);

  const uniPrinter = getUniversalPrinter();
  const bluetoothSupported = BluetoothPrinter.isSupported();
  const bluetoothSupportMessage = BluetoothPrinter.getSupportMessage();

  const updatePrinter = (patch: Partial<PrinterSettings>) => {
    setPrinterSettings(prev => ({ ...prev, ...patch }));
  };

  const savePrinter = () => {
    savePrinterSettings(printerSettings, printerScope);
    toast.success('Pengaturan printer tersimpan');
  };

  const getBridgePrinters = async () => {
    const { health, printers } = await printBridgeClient.status();
    if (!health.ok) throw new Error('Print Bridge aktif tetapi health check gagal. Restart service lalu coba lagi.');
    return printers;
  };

  const connectUSB = async () => {
    setPrinterStatus('connecting');
    setPrinterMsg('Membuka pemilihan printer USB di tablet...');
    try {
      const connected = await uniPrinter.usb.connect(printerSettings.baudRate);
      if (!connected) throw new Error('Pemilihan printer dibatalkan.');
      savePrinterSettings(printerSettings, printerScope);
      setPrinterStatus('connected');
      setPrinterMsg('Printer USB terhubung langsung ke tablet');
      toast.success('Printer USB siap digunakan dari tablet');
    } catch (err: unknown) {
      setPrinterStatus('error');
      setPrinterMsg(err instanceof Error ? err.message : String(err));
      toast.error(err instanceof Error ? err.message : String(err));
    }
  };

  const connectBluetooth = async () => {
    setPrinterStatus('connecting');
    setPrinterMsg('Mencoba koneksi Bluetooth langsung dari browser/PWA...');
    try {
      const connected = uniPrinter.bluetooth.connected || await uniPrinter.bluetooth.connect();
      if (connected) {
        setPrinterStatus('connected');
        setPrinterMsg(`Printer Bluetooth siap: ${uniPrinter.bluetooth.deviceName}`);
        toast.success('Printer Bluetooth siap digunakan langsung dari browser/PWA');
        return;
      }
      throw new Error('Pemilihan printer Bluetooth dibatalkan.');
    } catch (err: unknown) {
      try {
        const printers = await getBridgePrinters();
        const printer = printers.find(item => item.name.toLowerCase().includes('bluetooth'));
        if (!printer) throw err;
        setPrinterStatus('connected');
        setPrinterMsg(`Printer Bluetooth via Print Bridge: ${printer.name}`);
        toast.success('Printer Bluetooth siap melalui Print Bridge');
      } catch (bridgeError: unknown) {
        setPrinterStatus('error');
        setPrinterMsg(bridgeError instanceof Error ? bridgeError.message : String(bridgeError));
        toast.error(bridgeError instanceof Error ? bridgeError.message : String(bridgeError));
      }
    }
  };

  const testWifiConnection = async () => {
    if (!printerSettings.wifiIp) { toast.error('Masukkan IP printer dulu'); return; }
    setPrinterStatus('connecting');
    setPrinterMsg(`Mengecek ${printerSettings.wifiIp}:${printerSettings.wifiPort}...`);
    try {
      const printers = await getBridgePrinters();
      const printer = printers.find(item => item.type === 'tcp' && item.host === printerSettings.wifiIp && Number(item.port || 9100) === printerSettings.wifiPort);
      if (!printer) throw new Error('Printer WiFi/LAN belum dikonfigurasi di Print Bridge.');
      const job = await printBridgeClient.testPrint(printerScope);
      const finalJob = job.status === 'printed' || job.status === 'failed'
        ? job
        : await printBridgeClient.waitForJob(job.jobId);
      if (finalJob.status === 'failed') throw new Error(finalJob.error || 'Printer WiFi/LAN menolak test print');
      setPrinterStatus('connected');
      setPrinterMsg(`Test print berhasil: ${printer.name} (${printerSettings.wifiIp}:${printerSettings.wifiPort})`);
      toast.success('Printer WiFi merespons test print!');
    } catch (err: unknown) {
      setPrinterStatus('error');
      setPrinterMsg(err instanceof Error ? err.message : String(err));
      toast.error(err instanceof Error ? err.message : String(err));
    }
  };

  const doTestPrint = async () => {
    savePrinterSettings(printerSettings, printerScope);
    setTestingPrint(true);
    try {
      if (printerSettings.connectionType === 'android_bluetooth') {
        await testPrintViaAndroidService();
        toast.success('Perintah test print dikirim ke ESC/POS Bluetooth Print Service');
        setPrinterStatus('idle');
        setPrinterMsg('Perintah dikirim ke aplikasi Android. Periksa kertas secara fisik.');
        return;
      }
      const nativeSelected = printerSettings.connectionType === 'usb' || printerSettings.connectionType === 'bluetooth';
      if (nativeSelected && uniPrinter.connected) {
        try {
          await uniPrinter.testPrint(printerScope);
        } catch (nativeError) {
          const job = await printBridgeClient.testPrint(printerScope);
          const finalJob = job.status === 'printed' || job.status === 'failed'
            ? job
            : await printBridgeClient.waitForJob(job.jobId);
          if (finalJob.status === 'failed') throw new Error(`${nativeError instanceof Error ? nativeError.message : 'Koneksi native gagal'}; ${finalJob.error || 'Print Bridge gagal'}`);
        }
      } else {
        const job = await printBridgeClient.testPrint(printerScope);
        const finalJob = job.status === 'printed' || job.status === 'failed'
          ? job
          : await printBridgeClient.waitForJob(job.jobId);
        if (finalJob.status === 'failed') throw new Error(finalJob.error || 'Printer menolak test print');
      }
      toast.success('Test print berhasil dikirim ke printer!');
      setPrinterStatus('connected');
      setPrinterMsg('Test print berhasil');
    } catch (err: unknown) {
      setPrinterStatus('error');
      setPrinterMsg(err instanceof Error ? err.message : String(err));
      toast.error(`Test print gagal: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setTestingPrint(false);
    }
  };

  const retryPrintJobs = async () => {
    setFlushingPrintJobs(true);
    try {
      const result = await flushReceiptOutbox(candidate => {
        if (!printerScope) return false;
        return candidate.receipt.printerScope?.tenantId === printerScope.tenantId
          && candidate.receipt.printerScope?.outletId === printerScope.outletId;
      });
      setPendingPrintJobs(getPendingReceiptCount(printerScope));
      if (result.failed > 0) toast.error('Sebagian job masih gagal; periksa koneksi printer.');
      else toast.success(result.printed > 0 ? `${result.printed} job berhasil dicetak.` : 'Tidak ada job yang dapat dicetak.');
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Gagal memproses antrean print');
    } finally { setFlushingPrintJobs(false); }
  };

  const disconnectPrinter = async () => {
    setPrinterStatus('idle');
    setPrinterMsg('Konfigurasi tersimpan; bridge akan memakai printer default berikutnya.');
    toast.info('Status printer direset');
  };
  const selectedConnectionLabel = printerSettings.connectionType === 'usb'
    ? 'USB kabel'
    : printerSettings.connectionType === 'wifi'
      ? 'WiFi / LAN'
      : printerSettings.connectionType === 'android_bluetooth'
        ? 'Aplikasi Android Bluetooth'
        : 'Bluetooth';

  useEffect(() => {
    if (tenant && activeOutlet) {
      const scope = getPrinterScope(tenant.id, activeOutlet.id);
      setPrinterSettings(getPrinterSettings(scope));
      setPendingPrintJobs(getPendingReceiptCount(scope));
      setPrinterStatus('idle');
      setPrinterMsg('');
    }
  }, [tenant, activeOutlet]);

  useEffect(() => {
    if (tenant) {
      setTenantForm({
        name: tenant.name || '',
        phone: (tenant as unknown as { phone?: string }).phone || '',
        address: (tenant as unknown as { address?: string }).address || '',
        receipt_header: (tenant as unknown as { receipt_header?: string }).receipt_header || '',
        receipt_footer: (tenant as unknown as { receipt_footer?: string }).receipt_footer || '',
        timezone: tenant.timezone || 'Asia/Jakarta',
        currency: tenant.currency || 'IDR',
      });
    } else {
      setIsNewTenant(true);
    }
  }, [tenant]);

  const fetchBrands = useCallback(async () => {
    if (!tenant) return;
    const { data } = await supabase.from('pos_brands' as never).select('id, name').eq('tenant_id', tenant.id).order('name');
    setBrands((data || []) as unknown as { id: string; name: string }[]);
  }, [tenant]);

  useEffect(() => { if (tenant) fetchBrands(); }, [tenant, fetchBrands]);

  const saveTenant = async () => {
    if (!user) return;
    if (!tenantForm.name.trim()) { toast.error('Nama usaha wajib diisi'); return; }
    setSaving(true);
    try {
      if (tenant) {
        const { error } = await supabase.from('pos_tenants' as never).update({
          name: tenantForm.name,
          phone: tenantForm.phone || null,
          address: tenantForm.address || null,
          timezone: tenantForm.timezone,
          currency: tenantForm.currency,
          receipt_header: tenantForm.receipt_header || null,
          receipt_footer: tenantForm.receipt_footer || null,
        }).eq('id', tenant.id);
        if (error) throw error;
        toast.success('Profil usaha berhasil disimpan');
        await refetchTenant();
      } else {
        const { error } = await supabase.rpc('ensure_merchant_pos_workspace' as never, {
          p_name: tenantForm.name,
          p_phone: tenantForm.phone || null,
          p_address: tenantForm.address || null,
          p_timezone: tenantForm.timezone,
          p_currency: tenantForm.currency,
          p_outlet_name: `${tenantForm.name} - Outlet Utama`,
          p_outlet_address: tenantForm.address || null,
          p_outlet_phone: tenantForm.phone || null,
        } as never);
        if (error) throw error;
        toast.success('Usaha berhasil dibuat!');
        await refetchTenant();
        window.location.reload();
      }
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  const openAddOutlet = () => {
    setEditingOutlet(null);
    setOutletForm({ name: '', address: '', phone: '' });
    setOutletDialog(true);
  };

  const openEditOutlet = (o: Outlet) => {
    setEditingOutlet(o);
    setOutletForm({ name: o.name, address: o.address || '', phone: o.phone || '' });
    setOutletDialog(true);
  };

  const saveOutlet = async () => {
    if (!tenant) return;
    if (!outletForm.name.trim()) { toast.error('Nama outlet wajib diisi'); return; }
    const payload = { ...outletForm, tenant_id: tenant.id, address: outletForm.address || null, phone: outletForm.phone || null };
    try {
      if (editingOutlet) {
        const { error } = await supabase.from('pos_outlets' as never).update(payload).eq('id', editingOutlet.id);
        if (error) throw error;
        toast.success('Outlet diperbarui');
      } else {
        const { error } = await supabase.rpc('create_pos_outlet_with_entitlement_guard' as never, {
          p_tenant_id: tenant.id,
          p_name: outletForm.name,
          p_address: outletForm.address || null,
          p_phone: outletForm.phone || null,
        } as never);
        if (error) throw error;
        toast.success('Outlet berhasil ditambahkan');
      }
      setOutletDialog(false);
      await refetchOutlets();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : String(err));
    }
  };

  const toggleOutlet = async (outlet: Outlet) => {
    await supabase.from('pos_outlets' as never).update({ is_active: !outlet.is_active }).eq('id', outlet.id);
    await refetchOutlets();
    toast.success(outlet.is_active ? 'Outlet dinonaktifkan' : 'Outlet diaktifkan');
  };

  const addBrand = async () => {
    if (!tenant || !brandName.trim()) return;
    await supabase.from('pos_brands' as never).insert({ name: brandName.trim(), tenant_id: tenant.id });
    setBrandName('');
    setBrandDialogOpen(false);
    fetchBrands();
    toast.success('Brand ditambahkan');
  };

  const deleteBrand = async (id: string) => {
    await supabase.from('pos_brands' as never).delete().eq('id', id);
    fetchBrands();
  };

  return (
    <POSLayout title="Pengaturan" subtitle="Konfigurasi usaha, outlet, dan profil sistem">
      <Tabs defaultValue="usaha">
        <TabsList aria-label="Kategori pengaturan POS" className="mb-4 h-auto w-full justify-start gap-1 overflow-x-auto p-1 sm:w-auto sm:flex-wrap">
          <TabsTrigger value="usaha">Profil Usaha</TabsTrigger>
          <TabsTrigger value="outlet">Outlet</TabsTrigger>
          <TabsTrigger value="master">Master Data</TabsTrigger>
          <TabsTrigger value="struk">Pengaturan Struk</TabsTrigger>
          <TabsTrigger value="printer" className="flex items-center gap-1.5">
            <Printer className="h-3.5 w-3.5" />Printer
          </TabsTrigger>
        </TabsList>

        <TabsContent value="usaha">
          <Card className="border-0 shadow-sm">
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Building2 className="h-4 w-4 text-emerald-600" />
                Informasi Usaha
              </CardTitle>
              <CardDescription>Data ini tampil di struk, laporan, dan profil sistem.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              {isNewTenant && !tenant && (
                <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 text-sm text-blue-800">
                  Anda belum memiliki usaha. Isi data di bawah untuk membuat usaha baru.
                </div>
              )}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <Label>Nama Usaha *</Label>
                  <Input className="mt-1" value={tenantForm.name} onChange={e => setTenantForm(p => ({ ...p, name: e.target.value }))} placeholder="Nama usaha Anda" />
                </div>
                <div>
                  <Label>Nomor Telepon</Label>
                  <Input className="mt-1" value={tenantForm.phone} onChange={e => setTenantForm(p => ({ ...p, phone: e.target.value }))} placeholder="08xxxxxxxxxx" />
                </div>
              </div>
              <div>
                <Label>Alamat Usaha</Label>
                <Textarea className="mt-1" value={tenantForm.address} onChange={e => setTenantForm(p => ({ ...p, address: e.target.value }))} rows={2} placeholder="Alamat lengkap usaha" />
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <Label>Zona Waktu</Label>
                  <Select value={tenantForm.timezone} onValueChange={v => setTenantForm(p => ({ ...p, timezone: v }))}>
                    <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Asia/Jakarta">WIB (Asia/Jakarta)</SelectItem>
                      <SelectItem value="Asia/Makassar">WITA (Asia/Makassar)</SelectItem>
                      <SelectItem value="Asia/Jayapura">WIT (Asia/Jayapura)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Mata Uang</Label>
                  <Select value={tenantForm.currency} onValueChange={v => setTenantForm(p => ({ ...p, currency: v }))}>
                    <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="IDR">IDR — Rupiah Indonesia</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={saveTenant} disabled={saving}>
                {saving ? 'Menyimpan...' : 'Simpan Perubahan'}
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="outlet">
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="font-semibold">Daftar Outlet</h3>
                <p className="text-sm text-muted-foreground">{outlets.length} outlet terdaftar</p>
              </div>
              <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700" onClick={openAddOutlet} disabled={!tenant}>
                <Plus className="h-4 w-4 mr-1" />Tambah Outlet
              </Button>
            </div>
            {outlets.length === 0 ? (
              <Card className="border-dashed">
                <CardContent className="py-8 text-center">
                  <Store className="h-10 w-10 text-muted-foreground mx-auto mb-2" />
                  <p className="text-sm text-muted-foreground">Belum ada outlet. Simpan profil usaha terlebih dahulu.</p>
                </CardContent>
              </Card>
            ) : (
              <div className="space-y-2">
                {outlets.map(o => (
                  <Card key={o.id} className={`border shadow-sm ${!(o as unknown as Outlet).is_active ? 'opacity-60' : ''}`}>
                    <CardContent className="flex items-center gap-3 p-3 sm:p-4">
                      <div className="w-10 h-10 bg-emerald-100 rounded-lg flex items-center justify-center flex-shrink-0">
                        <Store className="h-5 w-5 text-emerald-600" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-medium text-sm">{o.name}</span>
                          {!(o as unknown as Outlet).is_active && <Badge variant="outline" className="text-xs">Nonaktif</Badge>}
                        </div>
                        <div className="text-xs text-muted-foreground mt-0.5 space-y-0.5">
                          {(o as unknown as Outlet).phone && <p className="flex items-center gap-1"><Phone className="h-3 w-3" />{(o as unknown as Outlet).phone}</p>}
                          {(o as unknown as Outlet).address && <p className="flex items-center gap-1"><MapPin className="h-3 w-3" />{(o as unknown as Outlet).address}</p>}
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <Switch checked={(o as unknown as Outlet).is_active !== false} onCheckedChange={() => toggleOutlet(o as unknown as Outlet)} />
                        <Button variant="ghost" size="icon" aria-label={`Edit outlet ${o.name}`} className="h-8 w-8" onClick={() => openEditOutlet(o as unknown as Outlet)}>
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>
        </TabsContent>

        <TabsContent value="master">
          <Card className="border-0 shadow-sm">
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="text-base">Manajemen Brand</CardTitle>
                  <CardDescription>Brand/merek produk yang dijual di toko.</CardDescription>
                </div>
                <Button size="sm" variant="outline" onClick={() => setBrandDialogOpen(true)} disabled={!tenant}>
                  <Plus className="h-4 w-4 mr-1" />Tambah Brand
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              {brands.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-6">Belum ada brand. Tambahkan brand produk Anda.</p>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {brands.map(b => (
                    <div key={b.id} className="flex items-center gap-1.5 px-3 py-1.5 bg-muted rounded-full text-sm">
                      <span>{b.name}</span>
                      <button onClick={() => deleteBrand(b.id)} className="text-muted-foreground hover:text-destructive ml-1">×</button>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="struk">
          <Card className="border-0 shadow-sm">
            <CardHeader>
              <CardTitle className="text-base">Pengaturan Struk</CardTitle>
              <CardDescription>Header dan footer yang muncul di struk cetak.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <Label>Header Struk</Label>
                <Textarea className="mt-1" value={tenantForm.receipt_header} onChange={e => setTenantForm(p => ({ ...p, receipt_header: e.target.value }))} rows={3} placeholder="Teks header struk (opsional)&#10;Contoh: Terima kasih telah berbelanja!" />
              </div>
              <div>
                <Label>Footer Struk</Label>
                <Textarea className="mt-1" value={tenantForm.receipt_footer} onChange={e => setTenantForm(p => ({ ...p, receipt_footer: e.target.value }))} rows={3} placeholder="Teks footer struk (opsional)&#10;Contoh: Barang yang sudah dibeli tidak dapat dikembalikan" />
              </div>
              <div className="border rounded-lg p-4 bg-muted/30">
                <p className="text-xs font-semibold text-muted-foreground uppercase mb-3">Preview Struk</p>
                <div className="font-mono text-xs space-y-1 text-center">
                  <p className="font-bold text-sm">{tenantForm.name || 'Nama Usaha'}</p>
                  {tenantForm.phone && <p>{tenantForm.phone}</p>}
                  {tenantForm.address && <p>{tenantForm.address}</p>}
                  <div className="border-t border-dashed my-2" />
                  {tenantForm.receipt_header && <p className="text-muted-foreground">{tenantForm.receipt_header}</p>}
                  <div className="border-t border-dashed my-2" />
                  <p className="text-left">Produk A          Rp 15.000</p>
                  <p className="text-left">Produk B x2       Rp 20.000</p>
                  <div className="border-t border-dashed my-2" />
                  <p className="font-bold">Total             Rp 35.000</p>
                  <div className="border-t border-dashed my-2" />
                  {tenantForm.receipt_footer && <p className="text-muted-foreground">{tenantForm.receipt_footer}</p>}
                </div>
              </div>
              <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={saveTenant} disabled={saving || !tenant}>
                {saving ? 'Menyimpan...' : 'Simpan Pengaturan Struk'}
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        {/* ── TAB PRINTER ─────────────────────────────────────── */}
        <TabsContent value="printer">
          <div className="space-y-4">
            <Card className="border-emerald-200 bg-emerald-50/70 shadow-sm">
              <CardHeader className="pb-3">
                <CardTitle className="text-base flex items-center gap-2 text-emerald-950">
                  <Printer className="h-4 w-4 text-emerald-700" />
                  Cara cepat menghubungkan printer
                </CardTitle>
                <CardDescription className="text-emerald-900/75">
                  PWA tetap berjalan di atas browser. Cetak langsung memakai printer native bila didukung; untuk cetak tanpa dialog browser gunakan Print Bridge lokal.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-3 text-sm text-emerald-950">
                <div className="grid gap-3 sm:grid-cols-3">
                  <div className="rounded-lg border border-emerald-200 bg-white/80 p-3">
                    <Badge className="mb-2 bg-emerald-700">1</Badge>
                    <p className="font-semibold">Nyalakan printer</p>
                    <p className="mt-1 text-xs text-muted-foreground">Pastikan kertas terpasang dan printer siap.</p>
                  </div>
                  <div className="rounded-lg border border-emerald-200 bg-white/80 p-3">
                    <Badge className="mb-2 bg-emerald-700">2</Badge>
                    <p className="font-semibold">Pilih jenis koneksi</p>
                    <p className="mt-1 text-xs text-muted-foreground">Pilih USB kabel, WiFi/LAN, atau Bluetooth. Jika koneksi native gagal, aplikasi mencoba Print Bridge lalu fallback browser.</p>
                  </div>
                  <div className="rounded-lg border border-emerald-200 bg-white/80 p-3">
                    <Badge className="mb-2 bg-emerald-700">3</Badge>
                    <p className="font-semibold">Simpan & Test Print</p>
                    <p className="mt-1 text-xs text-muted-foreground">Satu tombol untuk menyimpan dan mencetak struk percobaan.</p>
                  </div>
                </div>
                <p className="rounded-lg border border-emerald-200 bg-white/80 px-3 py-2 text-xs">
                  <strong>Scope konfigurasi:</strong> {tenant?.name || 'Tenant'} · {activeOutlet?.name || 'Outlet belum dipilih'}. <strong>Koneksi:</strong> {selectedConnectionLabel}. Jika menggunakan komputer kasir tetap, WiFi/LAN biasanya paling stabil.
                </p>
              </CardContent>
            </Card>
            {/* Status bar */}
            <Card className="border-dashed">
              <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
                <div><p className="font-semibold">Antrean print: {pendingPrintJobs}</p><p className="text-xs text-muted-foreground">Job gagal atau tertunda akan tetap disimpan dan dapat dicoba ulang.</p></div>
                <Button variant="outline" size="sm" onClick={() => void retryPrintJobs()} disabled={flushingPrintJobs || pendingPrintJobs === 0}><RefreshCw className="mr-2 h-4 w-4" />{flushingPrintJobs ? 'Memproses...' : 'Coba ulang antrean'}</Button>
              </CardContent>
            </Card>

            <Card className="border-sky-200 bg-sky-50/70 shadow-sm">
              <CardHeader className="pb-3">
                <CardTitle className="flex items-center gap-2 text-base text-sky-950">
                  <Info className="h-4 w-4 text-sky-700" />
                  Cara menggunakan pengaturan print
                </CardTitle>
                <CardDescription className="text-sky-900/75">
                  Pengaturan di bawah ini berlaku untuk perangkat kasir yang sedang dipakai pada outlet aktif.
                </CardDescription>
              </CardHeader>
              <CardContent className="grid gap-3 text-sm text-sky-950 md:grid-cols-2">
                <div className="rounded-lg border border-sky-200 bg-white/80 p-3">
                  <p className="font-semibold">1. Pastikan scope sudah benar</p>
                  <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                    Cek label <strong>Scope konfigurasi</strong> di atas: {tenant?.name || 'tenant'} · {activeOutlet?.name || 'outlet belum dipilih'}. Jika berganti outlet, pilih outlet terlebih dahulu lalu simpan pengaturan printer untuk outlet tersebut.
                  </p>
                </div>
                <div className="rounded-lg border border-sky-200 bg-white/80 p-3">
                  <p className="font-semibold">2. Simpan lalu lakukan Test Print</p>
                  <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                    Pilih koneksi, isi detail yang diminta, aktifkan <strong>Auto Print</strong> bila struk ingin langsung dicetak setelah pembayaran, lalu tekan <strong>Simpan Pengaturan Printer</strong> dan <strong>Test Print</strong>.
                  </p>
                </div>
                <div className="rounded-lg border border-sky-200 bg-white/80 p-3">
                  <p className="font-semibold">3. Pilih cara koneksi sesuai perangkat</p>
                  <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                    USB/Bluetooth membutuhkan izin browser dan tombol hubungkan. WiFi/LAN membutuhkan Print Bridge yang aktif pada komputer kasir dan IP/port yang benar. Android Bluetooth membutuhkan aplikasi Print Service di tablet Android.
                  </p>
                </div>
                <div className="rounded-lg border border-sky-200 bg-white/80 p-3">
                  <p className="font-semibold">4. Jika print gagal</p>
                  <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                    Struk tidak hilang: job disimpan di <strong>Antrean print</strong>. Perbaiki koneksi atau nyalakan printer, lalu tekan <strong>Coba ulang antrean</strong>. Hanya antrean tenant/outlet aktif yang diproses.
                  </p>
                </div>
                <div className="rounded-lg border border-sky-200 bg-white/80 p-3 md:col-span-2">
                  <p className="font-semibold">Cetak ulang transaksi</p>
                  <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                    Untuk mencetak ulang tanpa membuat transaksi baru, buka menu <strong>Transaksi</strong>, lihat detail transaksi, lalu tekan <strong>Cetak Ulang</strong>. Sistem membuat percobaan print baru untuk transaksi yang sama dan tetap mencatatnya sebagai reprint.
                  </p>
                </div>
              </CardContent>
            </Card>

            <div className={`flex items-center gap-2.5 px-4 py-3 rounded-lg border text-sm font-medium
              ${printerStatus === 'connected' ? 'bg-emerald-50 border-emerald-300 text-emerald-800'
              : printerStatus === 'error' ? 'bg-red-50 border-red-300 text-red-800'
              : printerStatus === 'connecting' ? 'bg-amber-50 border-amber-300 text-amber-800'
              : 'bg-muted border-border text-muted-foreground'}`}>
              {printerStatus === 'connected' ? <CheckCircle2 className="h-4 w-4 flex-shrink-0" />
                : printerStatus === 'error' ? <XCircle className="h-4 w-4 flex-shrink-0" />
                : <Printer className="h-4 w-4 flex-shrink-0" />}
              <span className="flex-1">{printerMsg || 'Belum ada printer terhubung'}</span>
              {printerStatus === 'error' && (
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 px-2 text-xs"
                  onClick={() => {
                    if (printerSettings.connectionType === 'wifi') void testWifiConnection();
                    else if (printerSettings.connectionType === 'bluetooth') void connectBluetooth();
                    else if (printerSettings.connectionType === 'android_bluetooth') void testPrintViaAndroidService().catch(error => toast.error(error instanceof Error ? error.message : String(error)));
                    else void connectUSB();
                  }}
                >Coba lagi</Button>
              )}
              {(printerStatus === 'connected') && (
                <Button variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={disconnectPrinter}>Reset status</Button>
              )}
            </div>

            {/* Jenis Koneksi */}
            <Card className="border-0 shadow-sm">
              <CardHeader className="pb-3">
                <CardTitle className="text-base flex items-center gap-2">
                  <Printer className="h-4 w-4 text-emerald-600" />
                  Jenis Koneksi Printer
                </CardTitle>
                <CardDescription>Pilih cara menghubungkan printer thermal ESC/POS ke sistem kasir.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                {/* USB */}
                <button
                  onClick={() => updatePrinter({ connectionType: 'usb' })}
                  className={`w-full flex items-start gap-3 p-4 rounded-xl border-2 transition-all text-left
                    ${printerSettings.connectionType === 'usb' ? 'border-emerald-500 bg-emerald-50' : 'border-border hover:border-emerald-300'}`}>
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0
                    ${printerSettings.connectionType === 'usb' ? 'bg-emerald-500 text-white' : 'bg-muted text-muted-foreground'}`}>
                    <Usb className="h-5 w-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="font-semibold text-sm">USB kabel</p>
                      {printerSettings.connectionType === 'usb' && <Badge className="bg-emerald-100 text-emerald-700 border-0 text-xs">Dipilih</Badge>}
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">Hubungkan printer ke perangkat kasir dengan kabel USB. Cocok jika printer berada di sebelah kasir.</p>
                    <p className="text-xs text-emerald-600 mt-1">✓ Browser akan meminta Anda memilih printer saat pertama kali.</p>
                  </div>
                </button>

                {/* WiFi */}
                <button
                  onClick={() => updatePrinter({ connectionType: 'wifi' })}
                  className={`w-full flex items-start gap-3 p-4 rounded-xl border-2 transition-all text-left
                    ${printerSettings.connectionType === 'wifi' ? 'border-emerald-500 bg-emerald-50' : 'border-border hover:border-emerald-300'}`}>
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0
                    ${printerSettings.connectionType === 'wifi' ? 'bg-emerald-500 text-white' : 'bg-muted text-muted-foreground'}`}>
                    <Wifi className="h-5 w-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="font-semibold text-sm">WiFi / LAN</p>
                      {printerSettings.connectionType === 'wifi' && <Badge className="bg-emerald-100 text-emerald-700 border-0 text-xs">Dipilih</Badge>}
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">Printer dan komputer kasir harus terhubung ke WiFi/LAN yang sama. Cocok untuk beberapa perangkat kasir.</p>
                    <p className="text-xs text-blue-600 mt-1">✓ Paling stabil untuk operasional harian. Memerlukan Print Bridge lokal di komputer kasir.</p>
                  </div>
                </button>

                {/* Bluetooth */}
                <button
                  onClick={() => updatePrinter({ connectionType: 'bluetooth' })}
                  className={`w-full flex items-start gap-3 p-4 rounded-xl border-2 transition-all text-left
                    ${printerSettings.connectionType === 'bluetooth' ? 'border-emerald-500 bg-emerald-50' : 'border-border hover:border-emerald-300'}`}>
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0
                    ${printerSettings.connectionType === 'bluetooth' ? 'bg-emerald-500 text-white' : 'bg-muted text-muted-foreground'}`}>
                    <Bluetooth className="h-5 w-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="font-semibold text-sm">Bluetooth</p>
                      {printerSettings.connectionType === 'bluetooth' && <Badge className="bg-emerald-100 text-emerald-700 border-0 text-xs">Dipilih</Badge>}
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">Untuk printer portabel. Dukungan bergantung pada tipe printer dan memerlukan Print Bridge lokal.</p>
                    <p className="text-xs text-amber-600 mt-1">⚠ Jika ragu, pilih USB kabel atau WiFi/LAN.</p>
                  </div>
                </button>

                {/* Android print service */}
                <button
                  onClick={() => updatePrinter({ connectionType: 'android_bluetooth' })}
                  className={`w-full flex items-start gap-3 p-4 rounded-xl border-2 transition-all text-left
                    ${printerSettings.connectionType === 'android_bluetooth' ? 'border-emerald-500 bg-emerald-50' : 'border-border hover:border-emerald-300'}`}>
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0
                    ${printerSettings.connectionType === 'android_bluetooth' ? 'bg-emerald-500 text-white' : 'bg-muted text-muted-foreground'}`}>
                    <Bluetooth className="h-5 w-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="font-semibold text-sm">ESC/POS Bluetooth Print Service</p>
                      {printerSettings.connectionType === 'android_bluetooth' && <Badge className="bg-emerald-100 text-emerald-700 border-0 text-xs">Dipilih</Badge>}
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">Untuk tablet Android tanpa mini PC. Struk dikirim ke aplikasi pihak ketiga melalui app link Android.</p>
                    <p className="text-xs text-blue-600 mt-1">✓ Install dan pilih printer sekali di aplikasi ESC/POS Bluetooth Print Service.</p>
                  </div>
                </button>

                {printerSettings.connectionType === 'android_bluetooth' && (
                  <div className="rounded-xl border-2 border-sky-300 bg-sky-50 p-4 text-sm text-sky-950">
                    <p className="font-semibold">Panduan Android + aplikasi pihak ketiga</p>
                    <ol className="mt-2 list-decimal space-y-1.5 pl-5 text-xs leading-relaxed text-sky-900">
                      <li>Instal aplikasi <strong>ESCPOS Bluetooth Print Service</strong> dari Looped Labs di tablet Android.</li>
                      <li>Aktifkan Bluetooth, pasangkan printer di pengaturan Android, lalu buka aplikasi tersebut.</li>
                      <li>Di aplikasi pihak ketiga, pilih printer, ukuran kertas, tipe printer ESC/POS, dan jalankan test print dari aplikasinya.</li>
                      <li>Kembali ke SaDesa melalui Chrome Android, pastikan outlet aktif benar, lalu tekan <strong>Simpan Pengaturan Printer</strong>.</li>
                      <li>Tekan <strong>Test Print</strong>. SaDesa membuka app link <code className="rounded bg-white px-1">print://</code>; aplikasi pihak ketiga menerima HTML dan mengirimkannya ke printer.</li>
                    </ol>
                    <div className="mt-3 space-y-1 border-t border-sky-200 pt-2 text-xs text-sky-800">
                      <p><strong>Syarat:</strong> tablet Android, HTTPS, aplikasi versi yang mendukung app links (minimal 2.1.6; parameter jumlah salinan memerlukan 2.3.2+), dan printer Bluetooth ESC/POS.</p>
                      <p><strong>Penting:</strong> status “perintah dikirim” bukan bukti kertas sudah keluar. Periksa kertas dan lakukan test print fisik. Bila tidak ada respons, buka kembali aplikasi pihak ketiga dan pastikan printer yang dipilih benar.</p>
                      {!isAndroidPrintServiceSupported() && <p className="font-semibold text-amber-700">Perangkat ini bukan Android; mode ini hanya dapat dites dari tablet Android.</p>}
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Pengaturan spesifik per koneksi */}
            {printerSettings.connectionType === 'wifi' && (
              <Card className="border-0 shadow-sm">
                <CardHeader className="pb-3">
                  <CardTitle className="text-sm flex items-center gap-2"><Wifi className="h-4 w-4 text-blue-500" />Konfigurasi WiFi/LAN</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                    <div className="col-span-2">
                      <Label>IP Address Printer</Label>
                      <Input className="mt-1 font-mono" value={printerSettings.wifiIp}
                        onChange={e => updatePrinter({ wifiIp: e.target.value })}
                        placeholder="192.168.1.100" />
                      <p className="text-xs text-muted-foreground mt-1">Cek di pengaturan printer atau router Anda</p>
                    </div>
                    <div>
                      <Label>Port TCP</Label>
                      <Input className="mt-1 font-mono" type="number" value={printerSettings.wifiPort}
                        onChange={e => updatePrinter({ wifiPort: Number(e.target.value) })}
                        placeholder="9100" />
                      <p className="text-xs text-muted-foreground mt-1">Default: 9100</p>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <Button variant="outline" size="sm" onClick={testWifiConnection} disabled={printerStatus === 'connecting'}>
                      <Wifi className="h-3.5 w-3.5 mr-1.5" />
                      {printerStatus === 'connecting' ? 'Mengecek...' : 'Test Koneksi'}
                    </Button>
                  </div>
                  <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 text-xs text-blue-800 space-y-1">
                    <p className="font-semibold">Cara cari IP printer:</p>
                    <p>1. Tekan tombol Feed di printer saat pertama hidup → akan cetak konfigurasi termasuk IP</p>
                    <p>2. Atau cek di router: Devices / DHCP Clients, cari nama printer</p>
                    <p>3. Pastikan printer dan server SaDesa berada di jaringan WiFi yang SAMA</p>
                  </div>
                </CardContent>
              </Card>
            )}

            {printerSettings.connectionType === 'usb' && (
              <Card className="border-0 shadow-sm">
                <CardHeader className="pb-3">
                  <CardTitle className="text-sm flex items-center gap-2"><Usb className="h-4 w-4 text-gray-600" />Konfigurasi USB</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="max-w-xs">
                    <Label>Baud Rate</Label>
                    <Select value={String(printerSettings.baudRate)} onValueChange={v => updatePrinter({ baudRate: Number(v) })}>
                      <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="9600">9600 bps (default thermal)</SelectItem>
                        <SelectItem value="19200">19200 bps</SelectItem>
                        <SelectItem value="38400">38400 bps</SelectItem>
                        <SelectItem value="57600">57600 bps</SelectItem>
                        <SelectItem value="115200">115200 bps (high speed)</SelectItem>
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-muted-foreground mt-1">Kebanyakan printer thermal: 9600 atau 115200</p>
                    <p className="text-xs text-blue-700 mt-2">Tablet Android: gunakan Chrome terbaru dan adaptor USB OTG. Saat tombol ditekan, pilih printer pada dialog perangkat.</p>
                  </div>
                  <Button onClick={connectUSB} disabled={printerStatus === 'connecting'} className="bg-gray-800 hover:bg-gray-900 text-white">
                    <Usb className="h-4 w-4 mr-1.5" />
                    {uniPrinter.usb.connected ? 'Printer USB Terhubung ✓' : printerStatus === 'connecting' ? 'Menghubungkan...' : 'Hubungkan Printer USB'}
                  </Button>
                  <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-xs text-amber-800 space-y-1">
                    <p className="font-semibold">Catatan USB:</p>
                    <p>• Browser akan meminta izin memilih port pertama kali</p>
                    <p>• Jika printer tidak muncul: coba cabut lalu pasang ulang kabel USB</p>
                    <p>• Tablet harus mendukung USB OTG dan printer harus terdeteksi oleh sistem</p>
                    <p>• Koneksi dapat hilang jika halaman ditutup atau printer dicabut — hubungkan ulang</p>
                    <p>• Jika tombol tidak bekerja, browser tablet mungkin belum mendukung Web Serial</p>
                  </div>
                </CardContent>
              </Card>
            )}

            {printerSettings.connectionType === 'bluetooth' && (
              <Card className="border-0 shadow-sm">
                <CardHeader className="pb-3">
                  <CardTitle className="text-sm flex items-center gap-2"><Bluetooth className="h-4 w-4 text-blue-600" />Konfigurasi Bluetooth</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="p-4 border rounded-xl space-y-3">
                    {uniPrinter.bluetooth.connected ? (
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 bg-emerald-100 rounded-full flex items-center justify-center">
                          <Bluetooth className="h-5 w-5 text-emerald-600" />
                        </div>
                        <div>
                          <p className="font-medium text-sm">{uniPrinter.bluetooth.deviceName}</p>
                          <p className="text-xs text-emerald-600">Terhubung via Bluetooth</p>
                        </div>
                      </div>
                    ) : (
                      <div className="text-center py-2">
                        <Bluetooth className="h-8 w-8 text-muted-foreground mx-auto mb-2" />
                        <p className="text-sm text-muted-foreground">Belum ada printer dipasangkan</p>
                        <p className="text-xs text-muted-foreground mt-1">Pastikan printer Bluetooth menyala, sudah dipilih dari dialog browser, dan berada dalam jangkauan</p>
                        {!bluetoothSupported && (
                          <p className="text-xs text-amber-700 mt-2">{bluetoothSupportMessage}</p>
                        )}
                      </div>
                    )}
                    <Button
                      onClick={uniPrinter.bluetooth.connected ? disconnectPrinter : connectBluetooth}
                      disabled={printerStatus === 'connecting' || (!uniPrinter.bluetooth.connected && !bluetoothSupported)}
                      className={uniPrinter.bluetooth.connected ? '' : 'bg-blue-600 hover:bg-blue-700 text-white w-full'}>
                      <Bluetooth className="h-4 w-4 mr-1.5" />
                      {uniPrinter.bluetooth.connected ? 'Putuskan Bluetooth' : printerStatus === 'connecting' ? 'Mencari printer...' : bluetoothSupported ? 'Cari & Hubungkan Printer Bluetooth' : 'Bluetooth tidak tersedia di perangkat ini'}
                    </Button>
                  </div>
                  <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 text-xs text-blue-800 space-y-1">
                    <p className="font-semibold">Printer Bluetooth yang didukung:</p>
                    <p>• Nordic UART Service (GATT) — paling umum</p>
                    <p>• Generic Printer Profile (Zicox, Xprinter, HPRT, Sewoo, Bixolon)</p>
                    <p>• Merek: MTP-II, RPP300, PTP-II, Bluetherm, Rongta, iDPRT</p>
                    <p className="mt-1 text-amber-700">⚠ Web Bluetooth tidak tersedia di iOS Safari/Firefox dan tidak dapat terhubung ke printer Bluetooth Classic/SPP. Gunakan Chrome/Edge desktop atau Android dengan HTTPS, atau pilih USB/WiFi.</p>
                  </div>
                </CardContent>
              </Card>
            )}

            {/* Pengaturan umum */}
            <Card className="border-0 shadow-sm">
              <CardHeader className="pb-3">
                <CardTitle className="text-sm">Pengaturan Cetak</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label>Lebar Kertas</Label>
                    <Select value={String(printerSettings.paperWidth)} onValueChange={v => updatePrinter({ paperWidth: Number(v) as never })}>
                      <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="58">58mm (mini thermal)</SelectItem>
                        <SelectItem value="80">80mm (standard)</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div>
                    <Label>Jumlah Salinan</Label>
                    <Select value={String(printerSettings.printCopies)} onValueChange={v => updatePrinter({ printCopies: Number(v) })}>
                      <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="1">1 lembar</SelectItem>
                        <SelectItem value="2">2 lembar</SelectItem>
                        <SelectItem value="3">3 lembar</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                <div className="flex items-center justify-between py-2 border-t">
                  <div>
                    <p className="text-sm font-medium">Cetak Otomatis Setelah Transaksi</p>
                    <p className="text-xs text-muted-foreground">Langsung cetak struk tanpa konfirmasi</p>
                  </div>
                  <Switch checked={printerSettings.autoPrint} onCheckedChange={v => updatePrinter({ autoPrint: v })} />
                </div>
              </CardContent>
            </Card>

            {/* Tombol Aksi */}
            <div className="flex gap-3 flex-wrap">
              <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={savePrinter}>
                Simpan Pengaturan Printer
              </Button>
              <Button variant="outline" onClick={doTestPrint} disabled={testingPrint}>
                <TestTube2 className="h-4 w-4 mr-1.5" />
                {testingPrint ? 'Menyimpan & mencetak...' : 'Simpan & Test Print'}
              </Button>
            </div>

            {/* Daftar printer yang diketahui kompatibel */}
            <Card className="border-0 shadow-sm bg-muted/30">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm text-muted-foreground">Printer yang Direkomendasikan</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-3 text-xs">
                  <div className="space-y-1">
                    <p className="font-semibold flex items-center gap-1"><Usb className="h-3 w-3" />USB</p>
                    <p className="text-muted-foreground">Epson TM-T82X</p>
                    <p className="text-muted-foreground">Epson TM-T88VI</p>
                    <p className="text-muted-foreground">Xprinter XP-58 / XP-80</p>
                    <p className="text-muted-foreground">Zicox ZCP-58</p>
                    <p className="text-muted-foreground">HPRT TP809</p>
                  </div>
                  <div className="space-y-1">
                    <p className="font-semibold flex items-center gap-1"><Wifi className="h-3 w-3" />WiFi/LAN</p>
                    <p className="text-muted-foreground">Epson TM-T82X (Ethernet)</p>
                    <p className="text-muted-foreground">Xprinter XP-N160II</p>
                    <p className="text-muted-foreground">Rongta RP76III (LAN)</p>
                    <p className="text-muted-foreground">HPRT TP80A (WiFi)</p>
                    <p className="text-muted-foreground">Sewoo LK-TL212 (LAN)</p>
                  </div>
                  <div className="space-y-1">
                    <p className="font-semibold flex items-center gap-1"><Bluetooth className="h-3 w-3" />Bluetooth</p>
                    <p className="text-muted-foreground">Rongta RPP300</p>
                    <p className="text-muted-foreground">Xprinter XP-P300E</p>
                    <p className="text-muted-foreground">HPRT MPT-II</p>
                    <p className="text-muted-foreground">iDPRT SP410BT</p>
                    <p className="text-muted-foreground">Zicox ZCP-58BT</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>
        </TabsContent>
      </Tabs>

      <Dialog open={outletDialog} onOpenChange={setOutletDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editingOutlet ? 'Edit Outlet' : 'Tambah Outlet Baru'}</DialogTitle>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div>
              <Label>Nama Outlet *</Label>
              <Input className="mt-1" value={outletForm.name} onChange={e => setOutletForm(p => ({ ...p, name: e.target.value }))} placeholder="Contoh: Cabang Selatan" />
            </div>
            <div>
              <Label>Nomor Telepon</Label>
              <Input className="mt-1" value={outletForm.phone} onChange={e => setOutletForm(p => ({ ...p, phone: e.target.value }))} placeholder="08xxxxxxxxxx" />
            </div>
            <div>
              <Label>Alamat</Label>
              <Textarea className="mt-1" value={outletForm.address} onChange={e => setOutletForm(p => ({ ...p, address: e.target.value }))} rows={2} placeholder="Alamat outlet" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOutletDialog(false)}>Batal</Button>
            <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={saveOutlet}>Simpan</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={brandDialogOpen} onOpenChange={setBrandDialogOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Tambah Brand</DialogTitle></DialogHeader>
          <div className="py-2">
            <Label>Nama Brand</Label>
            <Input className="mt-1" value={brandName} onChange={e => setBrandName(e.target.value)} placeholder="Contoh: Indomie, Aqua, Nestle" onKeyDown={e => e.key === 'Enter' && addBrand()} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setBrandDialogOpen(false)}>Batal</Button>
            <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={addBrand}>Tambah</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </POSLayout>
  );
}
