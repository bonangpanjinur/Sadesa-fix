import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { Store, Eye, Check, X, MoreHorizontal, Plus, Trash2, User, Power } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { useAdminCategories } from '@/hooks/useAdminCategories';
import { DataTable } from '@/components/admin/DataTable';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { approveMerchant, rejectMerchant, deleteMerchant, setMerchantStatus } from '@/lib/adminApi';
import { MerchantAddDialog } from '@/components/admin/MerchantAddDialog';

interface MerchantRow {
  id: string;
  name: string;
  phone: string | null;
  city: string | null;
  district: string | null;
  business_category: string | null;
  registration_status: string;
  status: string;
  registered_at: string | null;
  user_id: string | null;
  villages: { name: string } | null;
  // Joined from profiles
  ownerName: string | null;
  ownerPhone: string | null;
}

export default function AdminMerchantsPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { data: categories = [] } = useAdminCategories();
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [merchantAction, setMerchantAction] = useState<'reject' | 'delete' | null>(null);
  const [selectedMerchant, setSelectedMerchant] = useState<MerchantRow | null>(null);
  const [actionReason, setActionReason] = useState('');
  const [actionLoading, setActionLoading] = useState(false);

  const fetchMerchantsData = async (): Promise<MerchantRow[]> => {
    const { data, error } = await supabase
      .from('merchants')
      .select('id, name, phone, city, district, business_category, registration_status, status, registered_at, user_id, villages(name)')
      .order('registered_at', { ascending: false });
    if (error) throw error;
    const userIds = (data || []).map(m => m.user_id).filter(Boolean) as string[];
    let profilesMap: Record<string, { full_name: string | null; phone: string | null }> = {};
    if (userIds.length > 0) {
      const { data: profiles } = await supabase.from('profiles').select('user_id, full_name, phone').in('user_id', userIds);
      if (profiles) profilesMap = Object.fromEntries(profiles.map(p => [p.user_id, { full_name: p.full_name, phone: p.phone }]));
    }
    return (data || []).map(m => ({
      ...m,
      ownerName: m.user_id ? profilesMap[m.user_id]?.full_name || null : null,
      ownerPhone: m.user_id ? profilesMap[m.user_id]?.phone || null : null,
    })) as unknown as MerchantRow[];
  };

  const { data: merchants = [], isLoading: loading, error, refetch } = useQuery<MerchantRow[]>({
    queryKey: ['admin-merchants-list'],
    queryFn: fetchMerchantsData,
    staleTime: 30_000,
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['admin-merchants-list'] });
  const fetchMerchants = invalidate;

  const handleApprove = async (id: string) => {
    setActionLoading(true);
    try {
      const success = await approveMerchant(id);
      if (success) { toast.success('Merchant berhasil disetujui'); await invalidate(); }
      else toast.error('Gagal menyetujui merchant');
    } finally {
      setActionLoading(false);
    }
  };

  const handleToggleStatus = async (merchant: MerchantRow) => {
    const nextStatus = merchant.status === 'ACTIVE' ? 'INACTIVE' : 'ACTIVE';
    setActionLoading(true);
    try {
      const success = await setMerchantStatus(merchant.id, nextStatus);
      if (!success) throw new Error(`Gagal ${nextStatus === 'ACTIVE' ? 'mengaktifkan' : 'menonaktifkan'} merchant`);
      toast.success(nextStatus === 'ACTIVE' ? 'Merchant berhasil diaktifkan' : 'Merchant berhasil dinonaktifkan');
      await invalidate();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Status merchant gagal diperbarui');
    } finally {
      setActionLoading(false);
    }
  };

  const openMerchantAction = (merchant: MerchantRow, action: 'reject' | 'delete') => {
    setSelectedMerchant(merchant);
    setMerchantAction(action);
    setActionReason('');
  };

  const closeMerchantAction = () => {
    setSelectedMerchant(null);
    setMerchantAction(null);
    setActionReason('');
  };

  const handleMerchantAction = async () => {
    if (!selectedMerchant || !merchantAction) return;
    if (merchantAction === 'reject' && actionReason.trim().length < 10) {
      toast.error('Alasan penolakan minimal 10 karakter');
      return;
    }
    setActionLoading(true);
    try {
      const success = merchantAction === 'reject'
        ? await rejectMerchant(selectedMerchant.id, actionReason.trim())
        : await deleteMerchant(selectedMerchant.id);
      if (!success) throw new Error(merchantAction === 'reject' ? 'Gagal menolak merchant' : 'Gagal menghapus merchant');
      toast.success(merchantAction === 'reject' ? 'Merchant ditolak' : 'Merchant berhasil dihapus');
      closeMerchantAction();
      await invalidate();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Aksi merchant gagal diproses');
    } finally {
      setActionLoading(false);
    }
  };

  const getStatusBadge = (status: string, regStatus: string) => {
    if (regStatus === 'PENDING') {
      return <Badge variant="secondary" className="bg-warning/10 text-warning">Menunggu</Badge>;
    }
    if (regStatus === 'REJECTED') {
      return <Badge variant="destructive">Ditolak</Badge>;
    }
    if (status === 'ACTIVE') {
      return <Badge className="bg-success/10 text-success">Aktif</Badge>;
    }
    return <Badge variant="outline">Nonaktif</Badge>;
  };

  const columns = [
    {
      key: 'name',
      header: 'Nama Merchant',
      render: (item: MerchantRow) => (
        <div>
          <p className="font-medium">{item.name}</p>
          <p className="text-xs text-muted-foreground">{item.business_category || '-'}</p>
        </div>
      ),
    },
    {
      key: 'owner',
      header: 'Pemilik (User)',
      render: (item: MerchantRow) => (
        <div className="text-sm">
          {item.user_id ? (
            <div className="flex items-center gap-1.5">
              <User className="h-3.5 w-3.5 text-muted-foreground" />
              <div>
                <p className="font-medium text-xs">{item.ownerName || 'Tanpa Nama'}</p>
                <p className="text-xs text-muted-foreground">{item.ownerPhone || item.user_id.slice(0, 8) + '...'}</p>
              </div>
            </div>
          ) : (
            <span className="text-xs text-muted-foreground italic">Belum terhubung</span>
          )}
        </div>
      ),
    },
    {
      key: 'location',
      header: 'Lokasi',
      render: (item: MerchantRow) => (
        <div className="text-sm">
          <p>{item.villages?.name || '-'}</p>
          <p className="text-xs text-muted-foreground">{item.district}, {item.city}</p>
        </div>
      ),
    },
    {
      key: 'phone',
      header: 'Telepon',
      render: (item: MerchantRow) => item.phone || '-',
    },
    {
      key: 'status',
      header: 'Status',
      render: (item: MerchantRow) => getStatusBadge(item.status, item.registration_status),
    },
    {
      key: 'registered_at',
      header: 'Terdaftar',
      render: (item: MerchantRow) => 
        item.registered_at 
          ? new Date(item.registered_at).toLocaleDateString('id-ID') 
          : '-',
    },
    {
      key: 'actions',
      header: '',
      render: (item: MerchantRow) => (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon">
              <MoreHorizontal className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => navigate(`/admin/merchants/${item.id}`)}>
              <Eye className="h-4 w-4 mr-2" />
              Lihat Detail
            </DropdownMenuItem>
            {item.registration_status === 'PENDING' && (
              <>
                <DropdownMenuItem onClick={() => handleApprove(item.id)}>
                  <Check className="h-4 w-4 mr-2" />
                  Setujui
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => openMerchantAction(item, 'reject')} className="text-destructive">
                  <X className="h-4 w-4 mr-2" />
                  Tolak
                </DropdownMenuItem>
              </>
            )}
            {item.registration_status === 'APPROVED' && (
              <DropdownMenuItem onClick={() => void handleToggleStatus(item)} disabled={actionLoading}>
                <Power className="h-4 w-4 mr-2" />
                {item.status === 'ACTIVE' ? 'Nonaktifkan Merchant' : 'Aktifkan Merchant'}
              </DropdownMenuItem>
            )}
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={() => openMerchantAction(item, 'delete')} className="text-destructive">
              <Trash2 className="h-4 w-4 mr-2" />
              Hapus Merchant
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      ),
    },
  ];

  const filters = [
    {
      key: 'registration_status',
      label: 'Status Verifikasi',
      options: [
        { value: 'PENDING', label: 'Menunggu' },
        { value: 'APPROVED', label: 'Disetujui' },
        { value: 'REJECTED', label: 'Ditolak' },
      ],
    },
    {
      key: 'business_category',
      label: 'Kategori',
      options: [
        ...categories.map(({ slug, name }) => ({ value: slug, label: name })),
      ],
    },
  ];

  return (
    <AdminLayout title="Manajemen Merchant" subtitle="Kelola semua merchant yang terdaftar">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <Store className="h-5 w-5 text-primary" />
          <span className="text-muted-foreground text-sm">{merchants.length} merchant terdaftar</span>
        </div>
        <Button onClick={() => setAddDialogOpen(true)} className="gap-2">
          <Plus className="h-4 w-4" />
          Tambah Merchant
        </Button>
      </div>

      <DataTable
        data={merchants}
        columns={columns}
        searchKeys={['name']}
        searchPlaceholder="Cari nama merchant..."
        filters={filters}
        loading={loading}
        error={error instanceof Error ? error.message : error ? 'Gagal memuat data merchant. Silakan coba lagi.' : null}
        onRetry={() => void refetch()}
        emptyMessage="Belum ada merchant terdaftar"
      />

      <MerchantAddDialog
        open={addDialogOpen}
        onOpenChange={setAddDialogOpen}
        onSuccess={fetchMerchants}
      />

      <Dialog open={merchantAction !== null} onOpenChange={(open) => { if (!open) closeMerchantAction(); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{merchantAction === 'reject' ? 'Tolak merchant' : 'Hapus merchant'}</DialogTitle>
            <DialogDescription>
              {merchantAction === 'reject'
                ? `Berikan alasan yang jelas untuk ${selectedMerchant?.name ?? 'merchant ini'}. Alasan akan disimpan sebagai bagian dari audit.`
                : `Penghapusan ${selectedMerchant?.name ?? 'merchant ini'} bersifat destruktif dan tidak dapat dibatalkan.`}
            </DialogDescription>
          </DialogHeader>
          {merchantAction === 'reject' ? (
            <div className="space-y-2 py-2">
              <label htmlFor="merchant-rejection-reason" className="text-sm font-medium">Alasan penolakan</label>
              <Textarea id="merchant-rejection-reason" value={actionReason} onChange={(event) => setActionReason(event.target.value)} minLength={10} maxLength={500} placeholder="Contoh: Data legalitas usaha belum lengkap..." rows={4} />
              <p className="text-xs text-muted-foreground">Minimal 10 karakter.</p>
            </div>
          ) : (
            <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive">Pastikan merchant ini memang harus dihapus. Data terkait dapat ikut terhapus sesuai kebijakan database.</div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={closeMerchantAction} disabled={actionLoading}>Batal</Button>
            <Button variant="destructive" onClick={() => void handleMerchantAction()} disabled={actionLoading || (merchantAction === 'reject' && actionReason.trim().length < 10)}>
              {actionLoading ? 'Memproses...' : merchantAction === 'reject' ? 'Tolak merchant' : 'Hapus merchant'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}
