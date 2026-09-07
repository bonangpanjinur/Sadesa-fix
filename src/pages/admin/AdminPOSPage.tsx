import { useState, useEffect } from 'react';
import { Receipt, Check, X, Eye, Package, Plus, Trash2, Save, Loader2, Settings, Clock, CreditCard, Link2, AlertTriangle, CheckCircle2, MoreHorizontal, Ban, RotateCcw, CalendarPlus, Play, Pencil, History } from 'lucide-react';
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
  max_outlets: number;
  max_users: number;
  add_on_user_price: number;
  priority_support: boolean;
  onboarding_discount_percent: number;
  onboarding_discount_expires_at: string | null;
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

interface POSPackageHistory {
  id: string;
  package_id: string | null;
  package_name: string;
  description: string | null;
  duration_months: number;
  price: number;
  is_active: boolean;
  sort_order: number;
  change_type: string;
  changed_by: string | null;
  change_reason: string | null;
  created_at: string;
}

interface POSPromotion {
  id: string;
  code: string;
  name: string;
  description: string | null;
  partner_type: string | null;
  discount_percent: number;
  starts_at: string;
  expires_at: string;
  max_redemptions: number | null;
  redeemed_count: number;
  is_active: boolean;
}

export default function AdminPOSPage() {
  const [packages, setPackages] = useState<POSPackage[]>([]);
  const [packageHistory, setPackageHistory] = useState<POSPackageHistory[]>([]);
  const [subscriptions, setSubscriptions] = useState<POSSubscription[]>([]);
  const [loading, setLoading] = useState(true);
  const [trialDays, setTrialDays] = useState(30);
  const [savingConfig, setSavingConfig] = useState(false);
  const [addPkgOpen, setAddPkgOpen] = useState(false);
  const [newPkg, setNewPkg] = useState({
    name: '', description: '', duration_months: 1, price: 0,
    max_outlets: 1, max_users: 2, add_on_user_price: 25000,
    priority_support: false, onboarding_discount_percent: 0, onboarding_discount_expires_at: '',
  });
  const [viewProofUrl, setViewProofUrl] = useState<string | null>(null);
  const [detailSub, setDetailSub] = useState<POSSubscription | null>(null);
  const [extensionSub, setExtensionSub] = useState<POSSubscription | null>(null);
  const [extensionMonths, setExtensionMonths] = useState(1);
  const [actioningId, setActioningId] = useState<string | null>(null);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [rejectSubId, setRejectSubId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [integrationHealth, setIntegrationHealth] = useState<POSIntegrationHealth[]>([]);
  const [editPkg, setEditPkg] = useState<POSPackage | null>(null);
  const [editPkgForm, setEditPkgForm] = useState({
    name: '', description: '', duration_months: 1, price: 0, reason: '',
    max_outlets: 1, max_users: 2, add_on_user_price: 25000,
    priority_support: false, onboarding_discount_percent: 0, onboarding_discount_expires_at: '',
  });
  const [promotions, setPromotions] = useState<POSPromotion[]>([]);
  const [newPromotion, setNewPromotion] = useState({
    code: '', name: '', description: '', partner_type: 'Desa/Koperasi',
    discount_percent: 10, starts_at: '', expires_at: '', max_redemptions: '',
  });

  useEffect(() => { loadData(); }, []);

  const loadData = async () => {
    try {
      const [pkgsRes, subsRes, config, healthRes, promotionsRes] = await Promise.all([
        supabase.from('pos_packages').select('*').order('sort_order'),
        supabase.from('pos_subscriptions').select('*, merchants(name), pos_packages(name)').order('created_at', { ascending: false }),
        getSettingByKey('pos_config'),
        supabase.rpc('get_pos_integration_health' as never),
        supabase.from('pos_onboarding_promotions' as never).select('*').order('created_at', { ascending: false }),
      ]);
      const historyRes = await supabase.rpc('get_pos_package_history' as never, { p_limit: 200 } as never);
      const tenantRes = await supabase.from('pos_tenants').select('merchant_id, status, is_active');
      const tenantByMerchant = new Map((tenantRes.data || []).map((tenant) => [tenant.merchant_id, tenant]));

      setPackages(pkgsRes.data || []);
      if (!historyRes.error) setPackageHistory((historyRes.data || []) as unknown as POSPackageHistory[]);
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
      if (!promotionsRes.error) setPromotions((promotionsRes.data || []) as unknown as POSPromotion[]);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleAddPromotion = async () => {
    const code = newPromotion.code.trim().toUpperCase();
    if (!code || !newPromotion.name.trim() || !newPromotion.expires_at) {
      toast.error('Kode, nama, dan tanggal berakhir wajib diisi');
      return;
    }
    const startsAt = newPromotion.starts_at ? new Date(newPromotion.starts_at).toISOString() : new Date().toISOString();
    const expiresAt = new Date(newPromotion.expires_at).toISOString();
    if (new Date(expiresAt) <= new Date(startsAt)) {
      toast.error('Tanggal berakhir harus setelah tanggal mulai');
      return;
    }
    const { error } = await supabase.from('pos_onboarding_promotions' as never).insert({
      code,
      name: newPromotion.name.trim(),
      description: newPromotion.description.trim() || null,
      partner_type: newPromotion.partner_type.trim() || null,
      discount_percent: Math.min(100, Math.max(0, newPromotion.discount_percent)),
      starts_at: startsAt,
      expires_at: expiresAt,
      max_redemptions: newPromotion.max_redemptions ? Math.max(1, parseInt(newPromotion.max_redemptions, 10) || 1) : null,
    } as never);
    if (error) {
      toast.error(`Gagal membuat promo: ${error.message}`);
      return;
    }
    toast.success('Promo partner berhasil dibuat');
    setNewPromotion({ code: '', name: '', description: '', partner_type: 'Desa/Koperasi', discount_percent: 10, starts_at: '', expires_at: '', max_redemptions: '' });
    await loadData();
  };

  const handleDeactivatePromotion = async (promotion: POSPromotion) => {
    const { error } = await supabase.from('pos_onboarding_promotions' as never)
      .update({ is_active: false } as never)
      .eq('id', promotion.id);
    if (error) {
      toast.error(`Gagal menonaktifkan promo: ${error.message}`);
      return;
    }
    toast.success(`Promo ${promotion.code} dinonaktifkan`);
    await loadData();
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
      max_outlets: newPkg.max_outlets,
      max_users: newPkg.max_users,
      add_on_user_price: newPkg.add_on_user_price,
      priority_support: newPkg.priority_support,
      onboarding_discount_percent: newPkg.onboarding_discount_percent,
      onboarding_discount_expires_at: newPkg.onboarding_discount_expires_at || null,
      sort_order: packages.length,
    });
    if (error) { toast.error('Gagal menambah paket'); return; }
    toast.success('Paket berhasil ditambahkan');
    setAddPkgOpen(false);
    setNewPkg({
      name: '', description: '', duration_months: 1, price: 0,
      max_outlets: 1, max_users: 2, add_on_user_price: 25000,
      priority_support: false, onboarding_discount_percent: 0, onboarding_discount_expires_at: '',
    });
    loadData();
  };

  const handleDeletePackage = async (id: string) => {
    const { error } = await supabase.from('pos_packages').delete().eq('id', id);
    if (error) { toast.error('Gagal menghapus paket'); return; }
    toast.success('Paket dihapus');
    loadData();
  };

  const handleUpdatePackage = async () => {
    if (!editPkg) return;
    if (!editPkgForm.name.trim() || !editPkgForm.reason.trim()) {
      toast.error('Nama paket dan alasan perubahan wajib diisi');
      return;
    }

    const nextValue = {
      name: editPkgForm.name.trim(),
      description: editPkgForm.description.trim() || null,
      duration_months: Math.max(1, editPkgForm.duration_months),
      price: Math.max(0, editPkgForm.price),
    };
    const { error } = await supabase.rpc('admin_update_pos_package' as never, {
      p_package_id: editPkg.id,
      p_name: nextValue.name,
      p_description: nextValue.description,
      p_duration_months: nextValue.duration_months,
      p_price: nextValue.price,
        p_max_outlets: editPkgForm.max_outlets,
        p_max_users: editPkgForm.max_users,
        p_add_on_user_price: editPkgForm.add_on_user_price,
        p_priority_support: editPkgForm.priority_support,
        p_onboarding_discount_percent: editPkgForm.onboarding_discount_percent,
        p_onboarding_discount_expires_at: editPkgForm.onboarding_discount_expires_at || null,
      p_reason: editPkgForm.reason.trim(),
    } as never);
    if (error) {
      toast.error(`Gagal memperbarui paket: ${error.message}`);
      return;
    }
    toast.success('Paket berhasil diperbarui dan perubahan dicatat');
    setEditPkg(null);
     setEditPkgForm({
       name: '', description: '', duration_months: 1, price: 0, reason: '',
       max_outlets: 1, max_users: 2, add_on_user_price: 25000,
       priority_support: false, onboarding_discount_percent: 0, onboarding_discount_expires_at: '',
     });
    await loadData();
  };

  type SubscriptionAction = 'APPROVE' | 'REJECT' | 'SUSPEND' | 'REACTIVATE' | 'EXTEND' | 'CANCEL';

  const runSubscriptionAction = async (
    id: string,
    action: SubscriptionAction,
    options: { extensionMonths?: number; rejectionReason?: string; reason?: string } = {},
  ) => {
    setActioningId(id);
    const { error } = await supabase.rpc('admin_manage_pos_subscription' as never, {
      p_subscription_id: id,
      p_action: action,
      p_extension_months: options.extensionMonths || 1,
      p_rejection_reason: options.rejectionReason || null,
      p_reason: options.reason || options.rejectionReason || null,
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
    const reason = window.prompt(`Alasan penangguhan akses POS untuk ${sub.merchant_name}:`);
    if (reason?.trim() && window.confirm(`Tangguhkan akses POS untuk ${sub.merchant_name}?`)) {
      await runSubscriptionAction(sub.id, 'SUSPEND', { reason: reason.trim() });
    }
  };

  const handleCancel = async (sub: POSSubscription) => {
    const reason = window.prompt(`Alasan pembatalan langganan POS ${sub.merchant_name}:`);
    if (reason?.trim() && window.confirm(`Batalkan langganan POS ${sub.merchant_name}? Akses operasional akan dihentikan.`)) {
      await runSubscriptionAction(sub.id, 'CANCEL', { reason: reason.trim() });
    }
  };

  const handleReactivate = async (sub: POSSubscription) => {
    const reason = window.prompt(`Alasan reaktivasi POS untuk ${sub.merchant_name}:`);
    if (reason?.trim()) await runSubscriptionAction(sub.id, 'REACTIVATE', { reason: reason.trim() });
  };

  const handleApprove = async (sub: POSSubscription) => {
    const reason = window.prompt(`Catatan persetujuan POS untuk ${sub.merchant_name} (opsional):`) || undefined;
    await runSubscriptionAction(sub.id, 'APPROVE', { reason: reason?.trim() || undefined });
  };

  const handleExtend = async () => {
    if (!extensionSub || extensionMonths < 1) return;
    const reason = window.prompt(`Alasan perpanjangan langganan POS untuk ${extensionSub.merchant_name}:`);
    if (!reason?.trim()) return;
    const ok = await runSubscriptionAction(extensionSub.id, 'EXTEND', { extensionMonths, reason: reason.trim() });
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
          <TabsTrigger value="promotions">Promo Partner</TabsTrigger>
          <TabsTrigger value="package-history"><History className="mr-1 h-4 w-4" />Riwayat Paket</TabsTrigger>
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
                                   <Button size="sm" onClick={() => handleApprove(sub)} disabled={actioningId === sub.id}>
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
                                        <DropdownMenuItem onClick={() => handleApprove(sub)}>
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
                        <div className="flex items-center gap-1">
                          <Button
                            variant="ghost"
                            size="icon"
                            title="Edit paket"
                            onClick={() => {
                              setEditPkg(pkg);
                              setEditPkgForm({
                                name: pkg.name,
                                description: pkg.description || '',
                                duration_months: pkg.duration_months,
                                price: pkg.price,
                                max_outlets: pkg.max_outlets ?? 1,
                                max_users: pkg.max_users ?? 2,
                                add_on_user_price: pkg.add_on_user_price ?? 25000,
                                priority_support: pkg.priority_support ?? false,
                                onboarding_discount_percent: pkg.onboarding_discount_percent ?? 0,
                                onboarding_discount_expires_at: pkg.onboarding_discount_expires_at?.slice(0, 10) || '',
                                reason: '',
                              });
                            }}
                          >
                            <Pencil className="h-4 w-4" />
                          </Button>
                          <Button variant="ghost" size="icon" onClick={() => handleDeletePackage(pkg.id)} className="text-destructive" title="Hapus paket">
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                      {pkg.description && <p className="text-sm text-muted-foreground">{pkg.description}</p>}
                      <p className="text-2xl font-bold text-primary">{formatPrice(pkg.price)}</p>
                      <p className="text-xs text-muted-foreground">{pkg.duration_months} bulan</p>
                      <div className="grid grid-cols-2 gap-2 pt-2 text-xs text-muted-foreground">
                        <span>{pkg.max_outlets ?? 1} outlet</span>
                        <span>{pkg.max_users ?? 2} pengguna</span>
                        <span>Add-on: {formatPrice(pkg.add_on_user_price ?? 25000)}/pengguna</span>
                        <span>{pkg.priority_support ? 'Dukungan prioritas' : 'Dukungan standar'}</span>
                      </div>
                      {(pkg.onboarding_discount_percent ?? 0) > 0 && (
                        <Badge variant="secondary">Promo onboarding {pkg.onboarding_discount_percent}%</Badge>
                      )}
                    </CardContent>
                  </Card>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="promotions" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Program Partner Desa/Koperasi</CardTitle>
              <CardDescription>Buat kode onboarding ber-expiry dengan kuota redemption dan audit penggunaan.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-2"><Label>Kode promo</Label><Input value={newPromotion.code} onChange={e => setNewPromotion(p => ({ ...p, code: e.target.value.toUpperCase() }))} placeholder="KOPERASI2026" /></div>
                <div className="space-y-2"><Label>Nama program</Label><Input value={newPromotion.name} onChange={e => setNewPromotion(p => ({ ...p, name: e.target.value }))} placeholder="Promo Koperasi Kecamatan" /></div>
                <div className="space-y-2"><Label>Partner</Label><Input value={newPromotion.partner_type} onChange={e => setNewPromotion(p => ({ ...p, partner_type: e.target.value }))} placeholder="Desa/Koperasi" /></div>
                <div className="space-y-2 md:col-span-2"><Label>Deskripsi</Label><Input value={newPromotion.description} onChange={e => setNewPromotion(p => ({ ...p, description: e.target.value }))} placeholder="Keterangan eligibility partner" /></div>
                <div className="space-y-2"><Label>Diskon (%)</Label><Input type="number" min={0} max={100} value={newPromotion.discount_percent} onChange={e => setNewPromotion(p => ({ ...p, discount_percent: Math.min(100, Math.max(0, parseInt(e.target.value, 10) || 0)) }))} /></div>
                <div className="space-y-2"><Label>Mulai (opsional)</Label><Input type="datetime-local" value={newPromotion.starts_at} onChange={e => setNewPromotion(p => ({ ...p, starts_at: e.target.value }))} /></div>
                <div className="space-y-2"><Label>Berakhir</Label><Input type="datetime-local" value={newPromotion.expires_at} onChange={e => setNewPromotion(p => ({ ...p, expires_at: e.target.value }))} /></div>
                <div className="space-y-2"><Label>Maks. redemption (opsional)</Label><Input type="number" min={1} value={newPromotion.max_redemptions} onChange={e => setNewPromotion(p => ({ ...p, max_redemptions: e.target.value }))} placeholder="Tidak terbatas" /></div>
              </div>
              <Button onClick={handleAddPromotion}><Plus className="h-4 w-4 mr-2" /> Buat Promo</Button>
              <div className="rounded-md border overflow-hidden">
                <Table>
                  <TableHeader><TableRow><TableHead>Kode</TableHead><TableHead>Partner</TableHead><TableHead>Diskon</TableHead><TableHead>Berlaku</TableHead><TableHead>Redemption</TableHead><TableHead>Status</TableHead><TableHead /></TableRow></TableHeader>
                  <TableBody>
                    {promotions.map(promotion => {
                      const expired = new Date(promotion.expires_at) <= new Date();
                      return (
                        <TableRow key={promotion.id}>
                          <TableCell><div className="font-mono font-medium">{promotion.code}</div><div className="text-xs text-muted-foreground">{promotion.name}</div></TableCell>
                          <TableCell>{promotion.partner_type || '-'}</TableCell>
                          <TableCell>{promotion.discount_percent}%</TableCell>
                          <TableCell className="text-xs">{new Date(promotion.expires_at).toLocaleDateString('id-ID')}</TableCell>
                          <TableCell>{promotion.redeemed_count}{promotion.max_redemptions ? ` / ${promotion.max_redemptions}` : ''}</TableCell>
                          <TableCell><Badge variant={promotion.is_active && !expired ? 'success' : 'secondary'}>{!promotion.is_active ? 'Nonaktif' : expired ? 'Kedaluwarsa' : 'Aktif'}</Badge></TableCell>
                          <TableCell className="text-right">{promotion.is_active && !expired && <Button size="sm" variant="outline" onClick={() => handleDeactivatePromotion(promotion)}>Nonaktifkan</Button>}</TableCell>
                        </TableRow>
                      );
                    })}
                    {promotions.length === 0 && <TableRow><TableCell colSpan={7} className="text-center py-8 text-muted-foreground">Belum ada promo partner.</TableCell></TableRow>}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="package-history">
          <Card>
            <CardHeader>
              <CardTitle>Riwayat Paket dan Harga</CardTitle>
              <CardDescription>Snapshot perubahan paket untuk menjaga transparansi harga dan audit admin.</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="rounded-md border overflow-hidden">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Waktu</TableHead>
                      <TableHead>Paket</TableHead>
                      <TableHead>Harga</TableHead>
                      <TableHead>Durasi</TableHead>
                      <TableHead>Perubahan</TableHead>
                      <TableHead>Alasan</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {packageHistory.map((entry) => (
                      <TableRow key={entry.id}>
                        <TableCell className="text-sm text-muted-foreground whitespace-nowrap">{new Date(entry.created_at).toLocaleString('id-ID')}</TableCell>
                        <TableCell className="font-medium">{entry.package_name}</TableCell>
                        <TableCell>{formatPrice(entry.price)}</TableCell>
                        <TableCell>{entry.duration_months} bulan</TableCell>
                        <TableCell><Badge variant={entry.change_type === 'INITIAL' ? 'secondary' : 'info'}>{entry.change_type === 'INITIAL' ? 'Awal' : 'Diperbarui'}</Badge></TableCell>
                        <TableCell className="max-w-xs truncate">{entry.change_reason || (entry.change_type === 'INITIAL' ? 'Snapshot awal' : '-')}</TableCell>
                      </TableRow>
                    ))}
                    {packageHistory.length === 0 && (
                      <TableRow><TableCell colSpan={6} className="py-10 text-center text-muted-foreground">Belum ada riwayat paket.</TableCell></TableRow>
                    )}
                  </TableBody>
                </Table>
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
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2"><Label>Maks. outlet</Label><Input type="number" min={1} value={newPkg.max_outlets} onChange={e => setNewPkg(p => ({ ...p, max_outlets: Math.max(1, parseInt(e.target.value) || 1) }))} /></div>
              <div className="space-y-2"><Label>Maks. pengguna/kasir</Label><Input type="number" min={1} value={newPkg.max_users} onChange={e => setNewPkg(p => ({ ...p, max_users: Math.max(1, parseInt(e.target.value) || 1) }))} /></div>
              <div className="space-y-2"><Label>Harga add-on pengguna</Label><Input type="number" min={0} value={newPkg.add_on_user_price} onChange={e => setNewPkg(p => ({ ...p, add_on_user_price: Math.max(0, parseInt(e.target.value) || 0) }))} /></div>
              <div className="space-y-2"><Label>Diskon onboarding (%)</Label><Input type="number" min={0} max={100} value={newPkg.onboarding_discount_percent} onChange={e => setNewPkg(p => ({ ...p, onboarding_discount_percent: Math.min(100, Math.max(0, parseInt(e.target.value) || 0)) }))} /></div>
              <div className="space-y-2 col-span-2"><Label>Promo berlaku sampai (opsional)</Label><Input type="date" value={newPkg.onboarding_discount_expires_at} onChange={e => setNewPkg(p => ({ ...p, onboarding_discount_expires_at: e.target.value }))} /></div>
              <label className="col-span-2 flex items-center gap-2 text-sm"><input type="checkbox" checked={newPkg.priority_support} onChange={e => setNewPkg(p => ({ ...p, priority_support: e.target.checked }))} /> Dukungan prioritas dengan SLA 4 jam</label>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAddPkgOpen(false)}>Batal</Button>
            <Button onClick={handleAddPackage} disabled={!newPkg.name}>Simpan</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!editPkg} onOpenChange={(open) => !open && setEditPkg(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Edit Paket POS</DialogTitle></DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Nama Paket</Label>
              <Input value={editPkgForm.name} onChange={(e) => setEditPkgForm((p) => ({ ...p, name: e.target.value }))} />
            </div>
            <div className="space-y-2">
              <Label>Deskripsi</Label>
              <Input value={editPkgForm.description} onChange={(e) => setEditPkgForm((p) => ({ ...p, description: e.target.value }))} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Durasi (bulan)</Label>
                <Input type="number" min={1} value={editPkgForm.duration_months} onChange={(e) => setEditPkgForm((p) => ({ ...p, duration_months: Math.max(1, parseInt(e.target.value, 10) || 1) }))} />
              </div>
              <div className="space-y-2">
                <Label>Harga (Rp)</Label>
                <Input type="number" min={0} value={editPkgForm.price} onChange={(e) => setEditPkgForm((p) => ({ ...p, price: Math.max(0, parseInt(e.target.value, 10) || 0) }))} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2"><Label>Maks. outlet</Label><Input type="number" min={1} value={editPkgForm.max_outlets} onChange={e => setEditPkgForm(p => ({ ...p, max_outlets: Math.max(1, parseInt(e.target.value) || 1) }))} /></div>
              <div className="space-y-2"><Label>Maks. pengguna/kasir</Label><Input type="number" min={1} value={editPkgForm.max_users} onChange={e => setEditPkgForm(p => ({ ...p, max_users: Math.max(1, parseInt(e.target.value) || 1) }))} /></div>
              <div className="space-y-2"><Label>Harga add-on pengguna</Label><Input type="number" min={0} value={editPkgForm.add_on_user_price} onChange={e => setEditPkgForm(p => ({ ...p, add_on_user_price: Math.max(0, parseInt(e.target.value) || 0) }))} /></div>
              <div className="space-y-2"><Label>Diskon onboarding (%)</Label><Input type="number" min={0} max={100} value={editPkgForm.onboarding_discount_percent} onChange={e => setEditPkgForm(p => ({ ...p, onboarding_discount_percent: Math.min(100, Math.max(0, parseInt(e.target.value) || 0)) }))} /></div>
              <div className="space-y-2 col-span-2"><Label>Promo berlaku sampai (opsional)</Label><Input type="date" value={editPkgForm.onboarding_discount_expires_at} onChange={e => setEditPkgForm(p => ({ ...p, onboarding_discount_expires_at: e.target.value }))} /></div>
              <label className="col-span-2 flex items-center gap-2 text-sm"><input type="checkbox" checked={editPkgForm.priority_support} onChange={e => setEditPkgForm(p => ({ ...p, priority_support: e.target.checked }))} /> Dukungan prioritas dengan SLA 4 jam</label>
            </div>
            <div className="space-y-2">
              <Label>Alasan perubahan</Label>
              <Textarea value={editPkgForm.reason} onChange={(e) => setEditPkgForm((p) => ({ ...p, reason: e.target.value }))} placeholder="Contoh: Penyesuaian harga uji paket Starter" rows={3} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditPkg(null)}>Batal</Button>
            <Button onClick={handleUpdatePackage} disabled={!editPkgForm.name.trim() || !editPkgForm.reason.trim()}>Simpan Perubahan</Button>
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
