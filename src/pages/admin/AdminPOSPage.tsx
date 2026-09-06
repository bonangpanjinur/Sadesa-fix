import { useState, useEffect } from 'react';
import { Receipt, Check, X, Eye, Package, Plus, Trash2, Save, Loader2, Settings, Clock, CreditCard, Link2, AlertTriangle, CheckCircle2, MoreHorizontal, Ban, RotateCcw, CalendarPlus, Play } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Textarea } from '@/components/ui/textarea';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';
import { getSettingByKey, updateAppSetting } from '@/lib/adminApi';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

interface POSPackage {
  id: string;
  name: string;
  description: string | null;
  duration_months: number;
  price: number;
  is_active: boolean;
  sort_order: number;
}

interface POSSubscriptionRow extends POSSubscription {
  merchants?: { name: string | null } | null;
  pos_packages?: { name: string | null } | null;
}

interface POSConfig {
  trial_days?: number;
}

interface POSSubscription {
  id: string;
  merchant_id: string;
  merchant_name?: string;
  package_name?: string;
  package_id: string | null;
  package_duration_months?: number;
  status: string;
  payment_amount: number;
  payment_proof_url: string | null;
  payment_status: string;
  started_at: string | null;
  expired_at: string | null;
  is_trial: boolean;
  rejection_reason: string | null;
  created_at: string;
  tenant_status?: string;
  tenant_is_active?: boolean;
}

interface POSIntegrationHealth {
  tenant_id: string;
  tenant_name: string;
  merchant_id: string | null;
  merchant_name: string | null;
  owner_user_id: string;
  outlet_count: number;
  source_product_count: number;
  linked_product_count: number;
  unlinked_pos_product_count: number;
  sync_gap_count: number | null;
  status: 'READY' | 'NEEDS_MAPPING' | 'NEEDS_SYNC' | 'NEEDS_OUTLET';
}

export default function AdminPOSPage() {
  const [packages, setPackages] = useState<POSPackage[]>([]);
  const [subscriptions, setSubscriptions] = useState<POSSubscription[]>([]);
  const [loading, setLoading] = useState(true);
  const [trialDays, setTrialDays] = useState(30);
  const [savingConfig, setSavingConfig] = useState(false);
  const [addPkgOpen, setAddPkgOpen] = useState(false);
  const [newPkg, setNewPkg] = useState({ name: '', description: '', duration_months: 1, price: 0 });
  const [viewProofUrl, setViewProofUrl] = useState<string | null>(null);
  const [detailSub, setDetailSub] = useState<POSSubscription | null>(null);
  const [extensionSub, setExtensionSub] = useState<POSSubscription | null>(null);
  const [extensionMonths, setExtensionMonths] = useState(1);
  const [actioningId, setActioningId] = useState<string | null>(null);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [rejectSubId, setRejectSubId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [integrationHealth, setIntegrationHealth] = useState<POSIntegrationHealth[]>([]);

  useEffect(() => { loadData(); }, []);

  const loadData = async () => {
    try {
      const [pkgsRes, subsRes, config, healthRes] = await Promise.all([
        supabase.from('pos_packages').select('*').order('sort_order'),
        supabase.from('pos_subscriptions').select('*, merchants(name), pos_packages(name)').order('created_at', { ascending: false }),
        getSettingByKey('pos_config'),
        supabase.rpc('get_pos_integration_health' as never),
      ]);
      const tenantRes = await supabase.from('pos_tenants').select('merchant_id, status, is_active');
      const tenantByMerchant = new Map((tenantRes.data || []).map((tenant) => [tenant.merchant_id, tenant]));

      setPackages(pkgsRes.data || []);
      setSubscriptions((subsRes.data || []).map((s: POSSubscriptionRow) => ({
        ...s,
        merchant_name: s.merchants?.name || '-',
        package_name: s.pos_packages?.name || (s.is_trial ? 'Trial Gratis' : '-'),
        package_duration_months: (s.pos_packages as { duration_months?: number } | null)?.duration_months,
        tenant_status: tenantByMerchant.get(s.merchant_id)?.status,
        tenant_is_active: tenantByMerchant.get(s.merchant_id)?.is_active,
      })));
      if (config?.value) {
        setTrialDays(((config.value as POSConfig).trial_days) || 30);
      }
      if (!healthRes.error) setIntegrationHealth((healthRes.data || []) as unknown as POSIntegrationHealth[]);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleSaveConfig = async () => {
    setSavingConfig(true);
    const ok = await updateAppSetting('pos_config', { trial_days: trialDays, is_enabled: true });
    if (ok) toast.success('Konfigurasi POS berhasil disimpan');
    else toast.error('Gagal menyimpan');
    setSavingConfig(false);
  };

  const handleAddPackage = async () => {
    const { error } = await supabase.from('pos_packages').insert({
      name: newPkg.name,
      description: newPkg.description || null,
      duration_months: newPkg.duration_months,
      price: newPkg.price,
      sort_order: packages.length,
    });
    if (error) { toast.error('Gagal menambah paket'); return; }
    toast.success('Paket berhasil ditambahkan');
    setAddPkgOpen(false);
    setNewPkg({ name: '', description: '', duration_months: 1, price: 0 });
    loadData();
  };

  const handleDeletePackage = async (id: string) => {
    const { error } = await supabase.from('pos_packages').delete().eq('id', id);
    if (error) { toast.error('Gagal menghapus paket'); return; }
    toast.success('Paket dihapus');
    loadData();
  };

  type SubscriptionAction = 'APPROVE' | 'REJECT' | 'SUSPEND' | 'REACTIVATE' | 'EXTEND' | 'CANCEL';

  const runSubscriptionAction = async (
    id: string,
    action: SubscriptionAction,
    options: { extensionMonths?: number; rejectionReason?: string } = {},
  ) => {
    setActioningId(id);
    const { error } = await supabase.rpc('admin_manage_pos_subscription' as never, {
      p_subscription_id: id,
      p_action: action,
      p_extension_months: options.extensionMonths || 1,
      p_rejection_reason: options.rejectionReason || null,
    } as never);
    if (error) {
      toast.error(`Gagal ${action.toLowerCase()}: ${error.message}`);
      setActioningId(null);
      return false;
    }
    toast.success(action === 'EXTEND' ? 'Langganan berhasil diperpanjang' : 'Aksi langganan berhasil diterapkan');
    await loadData();
    setActioningId(null);
    return true;
  };

  const handleRejectSub = async () => {
    if (!rejectSubId) return;
    if (!rejectReason.trim()) { toast.error('Alasan penolakan wajib diisi'); return; }
    const ok = await runSubscriptionAction('' + rejectSubId, 'REJECT', { rejectionReason: rejectReason.trim() });
    if (!ok) return;
    setRejectDialogOpen(false);
    setRejectSubId(null);
    setRejectReason('');
  };

  const handleSuspend = async (sub: POSSubscription) => {
    if (window.confirm(`Tangguhkan akses POS untuk ${sub.merchant_name}?`)) {
      await runSubscriptionAction(sub.id, 'SUSPEND');
    }
  };

  const handleCancel = async (sub: POSSubscription) => {
    if (window.confirm(`Batalkan langganan POS ${sub.merchant_name}? Akses operasional akan dihentikan.`)) {
      await runSubscriptionAction(sub.id, 'CANCEL');
    }
  };

  const handleReactivate = async (sub: POSSubscription) => {
    await runSubscriptionAction(sub.id, 'REACTIVATE');
  };

  const handleExtend = async () => {
    if (!extensionSub || extensionMonths < 1) return;
    const ok = await runSubscriptionAction(extensionSub.id, 'EXTEND', { extensionMonths });
    if (ok) {
      setExtensionSub(null);
      setExtensionMonths(1);
    }
  };

  const pendingCount = subscriptions.filter(s => s.status === 'PENDING').length;

  return (
    <AdminLayout title="Manajemen Langganan POS" subtitle="Kelola paket, verifikasi pembayaran, dan akses fitur kasir">
      <Tabs defaultValue="subscriptions" className="space-y-6">
        <TabsList className="flex-wrap h-auto gap-1">
          <TabsTrigger value="subscriptions" className="flex items-center gap-2">
              Review Langganan {pendingCount > 0 && <Badge variant="destructive" className="text-[10px] px-1.5">{pendingCount}</Badge>}
          </TabsTrigger>
          <TabsTrigger value="packages">Paket & Fitur</TabsTrigger>
          <TabsTrigger value="integration" className="flex items-center gap-2"><Link2 className="h-4 w-4" />Integrasi Merchant–POS</TabsTrigger>
          <TabsTrigger value="config">Konfigurasi</TabsTrigger>
        </TabsList>

        {/* Subscriptions Tab */}
        <TabsContent value="subscriptions">
          <Card>
            <CardHeader>
              <CardTitle>Permintaan Langganan Kasir</CardTitle>
              <CardDescription>Kelola permintaan pengaktifan fitur kasir dari merchant</CardDescription>
            </CardHeader>
            <CardContent>
              {loading ? (
                <div className="flex justify-center py-10"><Loader2 className="h-8 w-8 animate-spin text-primary" /></div>
              ) : (
                <div className="rounded-md border overflow-hidden">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Merchant</TableHead>
                        <TableHead>Paket</TableHead>
                        <TableHead>Jumlah</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead>Bukti</TableHead>
                        <TableHead>Tanggal</TableHead>
                        <TableHead className="text-right">Aksi</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {subscriptions.map(sub => (
                        <TableRow key={sub.id}>
                          <TableCell className="font-medium">{sub.merchant_name}</TableCell>
                          <TableCell>
                            {sub.is_trial ? <Badge variant="info">Trial</Badge> : sub.package_name}
                          </TableCell>
                          <TableCell>{formatPrice(sub.payment_amount)}</TableCell>
                          <TableCell>
                            <Badge variant={sub.status === 'ACTIVE' ? 'success' : sub.status === 'PENDING' ? 'warning' : 'destructive'}>
                              {sub.status}
                            </Badge>
                          </TableCell>
                          <TableCell>
                            {sub.payment_proof_url ? (
                              <Button variant="ghost" size="sm" onClick={() => setViewProofUrl(sub.payment_proof_url)}>
                                <Eye className="h-4 w-4" />
                              </Button>
                            ) : '-'}
                          </TableCell>
                          <TableCell className="text-sm text-muted-foreground">
                            {new Date(sub.created_at).toLocaleDateString('id-ID')}
                          </TableCell>
                           <TableCell className="text-right">
                             <div className="flex items-center justify-end gap-1">
                               {sub.status === 'PENDING' && (
                                 <>
                                   <Button size="sm" onClick={() => runSubscriptionAction(sub.id, 'APPROVE')} disabled={actioningId === sub.id}>
                                     <Check className="h-3 w-3 mr-1" /> Setuju
                                   </Button>
                                   <Button size="sm" variant="destructive" onClick={() => {
                                     setRejectSubId(sub.id);
                                     setRejectDialogOpen(true);
                                   }} disabled={actioningId === sub.id}>
                                     <X className="h-3 w-3" />
                                   </Button>
                                 </>
                               )}
                               <Button variant="ghost" size="icon" title="Lihat detail" aria-label={`Lihat detail ${sub.merchant_name}`} onClick={() => setDetailSub(sub)}>
                                 <Eye className="h-4 w-4" />
                               </Button>
                               {(sub.status === 'ACTIVE' || sub.status === 'EXPIRED') && (
                                 <Button variant="ghost" size="icon" title="Perpanjang" aria-label={`Perpanjang ${sub.merchant_name}`} onClick={() => { setExtensionSub(sub); setExtensionMonths(1); }} disabled={actioningId === sub.id}>
                                   <CalendarPlus className="h-4 w-4" />
                                 </Button>
                               )}
                               {sub.status === 'ACTIVE' && (
                                 <Button variant="ghost" size="icon" title="Tangguhkan akses" aria-label={`Tangguhkan ${sub.merchant_name}`} onClick={() => handleSuspend(sub)} disabled={actioningId === sub.id}>
                                   <Ban className="h-4 w-4" />
                                 </Button>
                               )}
                               {['SUSPENDED', 'CANCELLED', 'EXPIRED', 'REJECTED'].includes(sub.status) && (
                                 <Button variant="ghost" size="icon" title="Aktifkan kembali" aria-label={`Aktifkan kembali ${sub.merchant_name}`} onClick={() => handleReactivate(sub)} disabled={actioningId === sub.id}>
                                   <Play className="h-4 w-4" />
                                 </Button>
                               )}
                               {sub.status !== 'CANCELLED' && sub.status !== 'REJECTED' && (
                                 <Button variant="ghost" size="icon" className="text-destructive hover:text-destructive" title="Batalkan langganan" aria-label={`Batalkan ${sub.merchant_name}`} onClick={() => handleCancel(sub)} disabled={actioningId === sub.id}>
                                   <RotateCcw className="h-4 w-4" />
                                 </Button>
                               )}
                               <DropdownMenu>
                                 <DropdownMenuTrigger asChild>
                                   <Button variant="outline" size="icon" aria-label={`Aksi ${sub.merchant_name}`} disabled={actioningId === sub.id}>
                                     {actioningId === sub.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <MoreHorizontal className="h-4 w-4" />}
                                   </Button>
                                 </DropdownMenuTrigger>
                                 <DropdownMenuContent align="end" className="w-52">
                                   <DropdownMenuItem onClick={() => setDetailSub(sub)}>
                                     <Eye className="mr-2 h-4 w-4" /> Lihat detail
                                   </DropdownMenuItem>
                                   {sub.status === 'PENDING' && (
                                     <>
                                       <DropdownMenuItem onClick={() => runSubscriptionAction(sub.id, 'APPROVE')}>
                                         <Check className="mr-2 h-4 w-4" /> Setujui permintaan
                                       </DropdownMenuItem>
                                       <DropdownMenuItem onClick={() => { setRejectSubId(sub.id); setRejectDialogOpen(true); }}>
                                         <X className="mr-2 h-4 w-4" /> Tolak permintaan
                                       </DropdownMenuItem>
                                     </>
                                   )}
                                   {(sub.status === 'ACTIVE' || sub.status === 'EXPIRED') && (
                                     <DropdownMenuItem onClick={() => { setExtensionSub(sub); setExtensionMonths(1); }}>
                                       <CalendarPlus className="mr-2 h-4 w-4" /> Perpanjang
                                     </DropdownMenuItem>
                                   )}
                                   {sub.status === 'ACTIVE' && (
                                     <DropdownMenuItem onClick={() => handleSuspend(sub)}>
                                       <Ban className="mr-2 h-4 w-4" /> Tangguhkan akses
                                     </DropdownMenuItem>
                                   )}
                                   {['SUSPENDED', 'CANCELLED', 'EXPIRED', 'REJECTED'].includes(sub.status) && (
                                     <DropdownMenuItem onClick={() => handleReactivate(sub)}>
                                       <Play className="mr-2 h-4 w-4" /> Aktifkan kembali
                                     </DropdownMenuItem>
                                   )}
                                   {sub.status !== 'CANCELLED' && sub.status !== 'REJECTED' && (
                                     <>
                                       <DropdownMenuSeparator />
                                       <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => handleCancel(sub)}>
                                         <RotateCcw className="mr-2 h-4 w-4" /> Batalkan langganan
                                       </DropdownMenuItem>
                                     </>
                                   )}
                                 </DropdownMenuContent>
                               </DropdownMenu>
                             </div>
                          </TableCell>
                        </TableRow>
                      ))}
                      {subscriptions.length === 0 && (
                        <TableRow><TableCell colSpan={7} className="text-center py-10 text-muted-foreground">Belum ada permintaan</TableCell></TableRow>
                      )}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* Packages Tab */}
        <TabsContent value="packages">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between">
              <div>
                <CardTitle>Paket Harga Kasir</CardTitle>
                <CardDescription>Atur paket langganan kasir POS</CardDescription>
              </div>
              <Button onClick={() => setAddPkgOpen(true)}>
                <Plus className="h-4 w-4 mr-2" /> Tambah Paket
              </Button>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {packages.map(pkg => (
                  <Card key={pkg.id}>
                    <CardContent className="p-4 space-y-2">
                      <div className="flex items-center justify-between">
                        <h4 className="font-bold">{pkg.name}</h4>
                        <Button variant="ghost" size="icon" onClick={() => handleDeletePackage(pkg.id)} className="text-destructive">
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                      {pkg.description && <p className="text-sm text-muted-foreground">{pkg.description}</p>}
                      <p className="text-2xl font-bold text-primary">{formatPrice(pkg.price)}</p>
                      <p className="text-xs text-muted-foreground">{pkg.duration_months} bulan</p>
                    </CardContent>
                  </Card>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        {/* Config Tab */}
        <TabsContent value="config">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2"><Settings className="h-5 w-5" /> Konfigurasi POS</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 max-w-md">
              <div className="space-y-2">
                <Label>Masa Trial Gratis (hari)</Label>
                <Input
                  type="number"
                  value={trialDays}
                  onChange={e => setTrialDays(parseInt(e.target.value) || 0)}
                />
                <p className="text-xs text-muted-foreground">Merchant akan mendapatkan akses gratis selama {trialDays} hari</p>
              </div>
              <Button onClick={handleSaveConfig} disabled={savingConfig}>
                {savingConfig ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Save className="h-4 w-4 mr-2" />}
                Simpan Konfigurasi
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="integration" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Kontrol Integrasi Merchant–POS</CardTitle>
              <CardDescription>
                Merchant adalah identitas dan sumber katalog. POS menyimpan proyeksi operasional dan stok per outlet.
              </CardDescription>
            </CardHeader>
            <CardContent>
              {integrationHealth.length === 0 ? (
                <div className="py-10 text-center text-muted-foreground">Belum ada tenant POS yang terdaftar.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Tenant POS</TableHead>
                      <TableHead>Merchant</TableHead>
                      <TableHead>Outlet</TableHead>
                      <TableHead>Katalog</TableHead>
                      <TableHead>Produk POS</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {integrationHealth.map((row) => {
                      const ready = row.status === 'READY';
                      return (
                        <TableRow key={row.tenant_id}>
                          <TableCell className="font-medium">{row.tenant_name}</TableCell>
                          <TableCell>{row.merchant_name || <span className="text-muted-foreground">Belum terhubung</span>}</TableCell>
                          <TableCell>{row.outlet_count}</TableCell>
                          <TableCell>{row.source_product_count} / {row.linked_product_count}</TableCell>
                          <TableCell>
                            <div className="text-sm">{row.unlinked_pos_product_count} legacy</div>
                            {row.sync_gap_count ? <div className="text-xs text-amber-600">{row.sync_gap_count} belum tersinkron</div> : null}
                          </TableCell>
                          <TableCell>
                            <Badge className={ready ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}>
                              {ready ? <CheckCircle2 className="h-3 w-3 mr-1" /> : <AlertTriangle className="h-3 w-3 mr-1" />}
                              {row.status === 'READY' ? 'Siap' : row.status === 'NEEDS_MAPPING' ? 'Perlu mapping' : row.status === 'NEEDS_SYNC' ? 'Perlu sinkronisasi' : 'Perlu outlet'}
                            </Badge>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Add Package Dialog */}
      <Dialog open={addPkgOpen} onOpenChange={setAddPkgOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Tambah Paket POS</DialogTitle></DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Nama Paket</Label>
              <Input value={newPkg.name} onChange={e => setNewPkg(p => ({ ...p, name: e.target.value }))} placeholder="Contoh: Paket 1 Bulan" />
            </div>
            <div className="space-y-2">
              <Label>Deskripsi</Label>
              <Input value={newPkg.description} onChange={e => setNewPkg(p => ({ ...p, description: e.target.value }))} placeholder="Deskripsi paket" />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Durasi (bulan)</Label>
                <Input type="number" value={newPkg.duration_months} onChange={e => setNewPkg(p => ({ ...p, duration_months: parseInt(e.target.value) || 1 }))} />
              </div>
              <div className="space-y-2">
                <Label>Harga (Rp)</Label>
                <Input type="number" value={newPkg.price} onChange={e => setNewPkg(p => ({ ...p, price: parseInt(e.target.value) || 0 }))} />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAddPkgOpen(false)}>Batal</Button>
            <Button onClick={handleAddPackage} disabled={!newPkg.name}>Simpan</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* View Proof Dialog */}
      <Dialog open={!!viewProofUrl} onOpenChange={() => setViewProofUrl(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Bukti Pembayaran</DialogTitle></DialogHeader>
          {viewProofUrl && (
            <img src={viewProofUrl} alt="Bukti" className="w-full rounded-lg" />
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={!!detailSub} onOpenChange={(open) => !open && setDetailSub(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Detail langganan POS</DialogTitle></DialogHeader>
          {detailSub && (
            <div className="grid grid-cols-2 gap-x-4 gap-y-3 py-4 text-sm">
              <span className="text-muted-foreground">Merchant</span><span className="font-medium">{detailSub.merchant_name}</span>
              <span className="text-muted-foreground">Paket</span><span>{detailSub.package_name}</span>
              <span className="text-muted-foreground">Status langganan</span><span>{detailSub.status}</span>
              <span className="text-muted-foreground">Status tenant POS</span><span>{detailSub.tenant_status || 'Belum dibuat'}</span>
              <span className="text-muted-foreground">Pembayaran</span><span>{detailSub.payment_status}</span>
              <span className="text-muted-foreground">Mulai</span><span>{detailSub.started_at ? new Date(detailSub.started_at).toLocaleDateString('id-ID') : '-'}</span>
              <span className="text-muted-foreground">Berakhir</span><span>{detailSub.expired_at ? new Date(detailSub.expired_at).toLocaleDateString('id-ID') : '-'}</span>
              {detailSub.rejection_reason && <><span className="text-muted-foreground">Catatan</span><span>{detailSub.rejection_reason}</span></>}
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={!!extensionSub} onOpenChange={(open) => !open && setExtensionSub(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Perpanjang langganan</DialogTitle>
            <CardDescription>{extensionSub?.merchant_name} akan tetap memakai paket saat ini.</CardDescription>
          </DialogHeader>
          <div className="space-y-2 py-4">
            <Label htmlFor="extension-months">Tambahan durasi (bulan)</Label>
            <Input id="extension-months" type="number" min={1} value={extensionMonths} onChange={(event) => setExtensionMonths(Math.max(1, Number(event.target.value) || 1))} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setExtensionSub(null)}>Batal</Button>
            <Button onClick={handleExtend} disabled={!!actioningId}><CalendarPlus className="mr-2 h-4 w-4" />Perpanjang</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reject Dialog */}
      <Dialog open={rejectDialogOpen} onOpenChange={setRejectDialogOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Tolak Permintaan</DialogTitle></DialogHeader>
          <div className="py-4">
            <Textarea value={rejectReason} onChange={e => setRejectReason(e.target.value)} placeholder="Alasan penolakan..." rows={3} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejectDialogOpen(false)}>Batal</Button>
            <Button variant="destructive" onClick={handleRejectSub} disabled={!rejectReason.trim()}>Tolak</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}
