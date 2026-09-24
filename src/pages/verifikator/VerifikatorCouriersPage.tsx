import { useState } from 'react';
import { Bike, Check, Eye, FileText, MoreHorizontal, X } from 'lucide-react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { VerifikatorLayout } from '@/components/verifikator/VerifikatorLayout';
import { DataTable } from '@/components/admin/DataTable';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { reviewCourier } from '@/lib/adminApi';
import { toast } from 'sonner';

interface CourierReviewRow {
  id: string;
  name: string;
  phone: string;
  email: string | null;
  city: string;
  district: string;
  address: string;
  ktp_number: string;
  ktp_image_url: string;
  photo_url: string;
  vehicle_type: string;
  vehicle_plate: string | null;
  vehicle_image_url: string;
  registration_status: string;
  status: string;
  rejection_reason: string | null;
  registered_at: string | null;
  village_id: string | null;
  villages?: { name: string } | null;
}

async function createDocumentUrl(path: string | null | undefined) {
  if (!path || path.startsWith('http')) return path || null;
  const { data, error } = await supabase.storage.from('courier-documents').createSignedUrl(path, 10 * 60);
  return error ? null : data?.signedUrl || null;
}

export default function VerifikatorCouriersPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [selectedCourier, setSelectedCourier] = useState<CourierReviewRow | null>(null);
  const [detailOpen, setDetailOpen] = useState(false);
  const [rejectCourierId, setRejectCourierId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState('');

  const { data: couriers = [], isLoading } = useQuery<CourierReviewRow[]>({
    queryKey: ['verifikator-couriers', user?.id],
    enabled: !!user,
    staleTime: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('couriers')
        .select('id, name, phone, email, city, district, address, ktp_number, ktp_image_url, photo_url, vehicle_type, vehicle_plate, vehicle_image_url, registration_status, status, rejection_reason, registered_at, village_id, villages(name)')
        .order('registered_at', { ascending: false });
      if (error) throw error;
      return (data || []) as unknown as CourierReviewRow[];
    },
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['verifikator-couriers', user?.id] });
  const reviewMutation = useMutation({
    mutationFn: ({ id, decision, reason }: { id: string; decision: 'APPROVED' | 'REJECTED'; reason?: string }) => reviewCourier(id, decision, reason),
    onSuccess: (success, variables) => {
      if (!success) {
        toast.error('Anda tidak berwenang atau data ojek sudah berubah');
        return;
      }
      toast.success(variables.decision === 'APPROVED' ? 'Ojek berhasil diverifikasi' : 'Ojek ditolak');
      setRejectCourierId(null);
      setRejectReason('');
      invalidate();
    },
    onError: () => toast.error('Gagal memproses verifikasi ojek'),
  });

  const openDetail = (courier: CourierReviewRow) => {
    setSelectedCourier(courier);
    setDetailOpen(true);
  };

  const confirmReject = () => {
    if (!rejectCourierId || !rejectReason.trim()) {
      toast.error('Alasan penolakan wajib diisi');
      return;
    }
    reviewMutation.mutate({ id: rejectCourierId, decision: 'REJECTED', reason: rejectReason.trim() });
  };

  const statusBadge = (status: string) => {
    if (status === 'PENDING') return <Badge variant="warning">Menunggu</Badge>;
    if (status === 'APPROVED') return <Badge variant="success">Disetujui</Badge>;
    if (status === 'REJECTED') return <Badge variant="destructive">Ditolak</Badge>;
    return <Badge variant="outline">{status}</Badge>;
  };

  const columns = [
    {
      key: 'name',
      header: 'Nama Ojek',
      render: (item: CourierReviewRow) => <div><p className="font-medium">{item.name}</p><p className="text-xs text-muted-foreground">{item.phone}</p></div>,
    },
    {
      key: 'vehicle',
      header: 'Kendaraan',
      render: (item: CourierReviewRow) => <div><p className="capitalize">{item.vehicle_type}</p><p className="text-xs font-mono text-muted-foreground">{item.vehicle_plate || '-'}</p></div>,
    },
    {
      key: 'village',
      header: 'Wilayah',
      render: (item: CourierReviewRow) => item.villages?.name || `${item.district}, ${item.city}`,
    },
    {
      key: 'documents',
      header: 'Dokumen',
      render: (item: CourierReviewRow) => <span className="inline-flex items-center gap-1 text-xs text-muted-foreground"><FileText className="h-3.5 w-3.5" />KTP + kendaraan</span>,
    },
    { key: 'status', header: 'Status', render: (item: CourierReviewRow) => statusBadge(item.registration_status) },
    {
      key: 'actions',
      header: '',
      render: (item: CourierReviewRow) => <DropdownMenu>
        <DropdownMenuTrigger asChild><Button variant="ghost" size="icon"><MoreHorizontal className="h-4 w-4" /></Button></DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={() => openDetail(item)}><Eye className="mr-2 h-4 w-4" />Lihat dokumen</DropdownMenuItem>
          {item.registration_status === 'PENDING' && <>
            <DropdownMenuItem onClick={() => reviewMutation.mutate({ id: item.id, decision: 'APPROVED' })} className="text-emerald-600"><Check className="mr-2 h-4 w-4" />Setujui ojek</DropdownMenuItem>
            <DropdownMenuItem onClick={() => { setRejectCourierId(item.id); setRejectReason(''); }} className="text-destructive"><X className="mr-2 h-4 w-4" />Tolak ojek</DropdownMenuItem>
          </>}
        </DropdownMenuContent>
      </DropdownMenu>,
    },
  ];

  return <VerifikatorLayout title="Verifikasi Ojek" subtitle="Ojek di wilayah desa yang ditugaskan kepada Anda">
    <div className="mb-4 flex items-center gap-2"><Bike className="h-5 w-5 text-primary" /><span className="text-sm text-muted-foreground">{couriers.length} ojek • {couriers.filter(c => c.registration_status === 'PENDING').length} menunggu verifikasi</span></div>
    <DataTable data={couriers} columns={columns} searchKeys={['name', 'phone', 'vehicle_plate']} searchPlaceholder="Cari nama atau plat..." filters={[{ key: 'registration_status', label: 'Status Verifikasi', options: [{ value: 'PENDING', label: 'Menunggu' }, { value: 'APPROVED', label: 'Disetujui' }, { value: 'REJECTED', label: 'Ditolak' }] }]} loading={isLoading} emptyMessage="Belum ada ojek di wilayah verifikasi Anda" />

    <CourierDetailDialog courier={selectedCourier} open={detailOpen} onOpenChange={setDetailOpen} />

    <Dialog open={!!rejectCourierId} onOpenChange={(open) => { if (!open) setRejectCourierId(null); }}>
      <DialogContent className="max-w-md"><DialogHeader><DialogTitle>Tolak Ojek</DialogTitle><DialogDescription>Alasan ini akan disimpan sebagai catatan perbaikan pendaftar.</DialogDescription></DialogHeader>
        <div className="py-4"><Label htmlFor="courier-reject-reason">Alasan penolakan *</Label><Textarea id="courier-reject-reason" value={rejectReason} onChange={e => setRejectReason(e.target.value)} rows={4} className="mt-2" placeholder="Contoh: foto KTP tidak terbaca..." /></div>
        <DialogFooter><Button variant="outline" onClick={() => setRejectCourierId(null)}>Batal</Button><Button variant="destructive" onClick={confirmReject} disabled={reviewMutation.isPending || !rejectReason.trim()}>Tolak Ojek</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </VerifikatorLayout>;
}

function CourierDetailDialog({ courier, open, onOpenChange }: { courier: CourierReviewRow | null; open: boolean; onOpenChange: (open: boolean) => void }) {
  const [urls, setUrls] = useState<Record<string, string | null>>({});
  const [loading, setLoading] = useState(false);

  const loadDocuments = async () => {
    if (!courier) return;
    setLoading(true);
    const [ktp, photo, vehicle] = await Promise.all([
      createDocumentUrl(courier.ktp_image_url),
      createDocumentUrl(courier.photo_url),
      createDocumentUrl(courier.vehicle_image_url),
    ]);
    setUrls({ ktp, photo, vehicle });
    setLoading(false);
  };

  return <Dialog open={open} onOpenChange={(next) => { onOpenChange(next); if (next) void loadDocuments(); }}>
    <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto"><DialogHeader><DialogTitle>Detail Verifikasi Ojek</DialogTitle><DialogDescription>{courier?.name} • KTP {courier?.ktp_number}</DialogDescription></DialogHeader>
      {courier && <div className="space-y-5"><div className="grid grid-cols-2 gap-3 text-sm"><div><span className="text-muted-foreground">Telepon</span><p>{courier.phone}</p></div><div><span className="text-muted-foreground">Kendaraan</span><p className="capitalize">{courier.vehicle_type} {courier.vehicle_plate || ''}</p></div><div className="col-span-2"><span className="text-muted-foreground">Alamat</span><p>{courier.address}, {courier.district}, {courier.city}</p></div></div>
        {loading ? <p className="text-sm text-muted-foreground">Memuat dokumen privat...</p> : <div className="grid gap-4 md:grid-cols-3">{[['KTP', urls.ktp], ['Foto diri', urls.photo], ['Kendaraan', urls.vehicle]].map(([label, url]) => <div key={label} className="space-y-2"><p className="text-sm font-medium">{label}</p>{url ? <img src={url} alt={`${label} ${courier.name}`} className="aspect-video w-full rounded-lg border object-cover" /> : <div className="flex aspect-video items-center justify-center rounded-lg border bg-muted text-xs text-muted-foreground">Dokumen tidak tersedia</div>}</div>)}</div>}
      </div>}
    </DialogContent>
  </Dialog>;
}
