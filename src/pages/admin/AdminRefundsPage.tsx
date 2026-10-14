import { useCallback, useState, useEffect } from 'react';
import { RotateCcw, Check, X, Eye, Clock, Store } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { AdminFilterBar, AdminStatePanel } from '@/components/admin/AdminPagePrimitives';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice } from '@/lib/utils';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { logAdminAction } from '@/lib/auditLog';

interface RefundRequest {
  id: string;
  orderId: string;
  buyerId: string;
  merchantId: string;
  amount: number;
  reason: string;
  status: string;
  disputeStatus: string | null;
  merchantResponse: string | null;
  settlementStatus: string | null;
  settlementId: string | null;
  settlementProvider: string | null;
  settlementProviderStatus: string | null;
  settlementProviderReference: string | null;
  settlementEvidencePath: string | null;
  settlementLastError: string | null;
  adminNotes: string | null;
  processedAt: string | null;
  createdAt: string;
  orderTotal: number;
  buyerName: string;
  merchantName: string;
  evidenceUrls: string[];
  refundType: string;
}

export default function AdminRefundsPage() {
  const [refunds, setRefunds] = useState<RefundRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedRefund, setSelectedRefund] = useState<RefundRequest | null>(null);
  const [detailDialogOpen, setDetailDialogOpen] = useState(false);
  const [processDialogOpen, setProcessDialogOpen] = useState(false);
  const [processAction, setProcessAction] = useState<'approve' | 'reject'>('approve');
  const [adminNotes, setAdminNotes] = useState('');
  const [manualReference, setManualReference] = useState('');
  const [manualEvidenceFile, setManualEvidenceFile] = useState<File | null>(null);
  const [manualTransferConfirmed, setManualTransferConfirmed] = useState(false);
  const [manualSettlementLoading, setManualSettlementLoading] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const loadRefunds = useCallback(async () => {
    try {
      setLoading(true);
      setErrorMessage(null);
      
      const { data, error } = await supabase
        .from('refund_requests')
        .select('*, orders(total, merchants(name))')
        .order('created_at', { ascending: false });

      if (error) throw error;

      const settlementIds = [...new Set((data || [])
        .map((refund) => refund.settlement_id)
        .filter((id): id is string => typeof id === 'string' && id.length > 0))];
      const { data: settlementRows, error: settlementError } = settlementIds.length > 0
        ? await supabase.from('refund_settlements').select(
          'id, provider, provider_status, provider_reference, manual_evidence_path, last_error, status',
        ).in('id', settlementIds)
        : { data: [], error: null };
      if (settlementError) throw settlementError;
      const settlementMap = new Map((settlementRows || []).map((settlement) => [settlement.id, settlement]));

      // Fetch buyer names separately
      const buyerIds = [...new Set((data || []).map(r => r.buyer_id))];
      const { data: profiles } = await supabase
        .from('profiles')
        .select('user_id, full_name')
        .in('user_id', buyerIds);

      const profileMap = new Map(profiles?.map(p => [p.user_id, p.full_name]) || []);

      const mapped: RefundRequest[] = (data || []).map(r => {
        const order = r.orders as unknown as {
          merchant_id?: string | null;
          total?: number | null;
          merchants?: { name?: string | null } | null;
        } | null;
        const settlement = r.settlement_id ? settlementMap.get(r.settlement_id) : null;
        return {
        id: r.id,
        orderId: r.order_id,
        buyerId: r.buyer_id,
        merchantId: order?.merchant_id || '',
        amount: r.amount,
        reason: r.reason,
        status: r.status,
        disputeStatus: r.dispute_status || null,
        merchantResponse: r.merchant_response || null,
        settlementStatus: r.settlement_status || settlement?.status || null,
        settlementId: r.settlement_id || null,
        settlementProvider: settlement?.provider || null,
        settlementProviderStatus: settlement?.provider_status || null,
        settlementProviderReference: settlement?.provider_reference || null,
        settlementEvidencePath: settlement?.manual_evidence_path || null,
        settlementLastError: settlement?.last_error || null,
        adminNotes: r.admin_notes,
        processedAt: r.processed_at,
        createdAt: r.created_at,
        orderTotal: order?.total || 0,
        buyerName: profileMap.get(r.buyer_id) || 'Unknown',
        merchantName: order?.merchants?.name || 'Unknown Merchant',
        evidenceUrls: r.evidence_urls || [],
        refundType: 'FULL',
        };
      });

      setRefunds(mapped);
    } catch (error) {
      console.error('Error loading refunds:', error);
      setErrorMessage('Gagal mengambil permintaan refund. Periksa koneksi dan permission database, lalu coba lagi.');
      toast.error('Gagal memuat data refund');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadRefunds();
  }, [loadRefunds]);

  const handleProcess = async () => {
    if (!selectedRefund) return;

    try {
      setActionLoading(true);
      
      const newStatus = processAction === 'approve' ? 'APPROVED' : 'REJECTED';
      
      const { error } = await supabase.rpc('process_refund_decision' as never, {
        p_refund_id: selectedRefund.id,
        p_approve: processAction === 'approve',
        p_notes: adminNotes,
      } as never);
      if (error) throw error;

      await logAdminAction(
        processAction === 'approve' ? 'APPROVE_REFUND' : 'REJECT_REFUND',
        'refund',
        selectedRefund.id,
        { status: 'PENDING' },
        { status: newStatus, admin_notes: adminNotes }
      );

      toast.success(processAction === 'approve'
        ? 'Refund disetujui dan masuk antrean pencairan manual. Dana belum dikirim.'
        : 'Refund ditolak.');
      setProcessDialogOpen(false);
      setAdminNotes('');
      setSelectedRefund(null);
      loadRefunds();
    } catch (error) {
      console.error('Error processing refund:', error);
      toast.error('Gagal memproses refund');
    } finally {
      setActionLoading(false);
    }
  };

  const filteredRefunds = refunds.filter(r => {
    const isManualQueue = r.status === 'APPROVED'
      && r.settlementProvider === 'MANUAL'
      && r.settlementStatus !== 'COMPLETED';
    const matchesStatus = statusFilter === 'all'
      || (statusFilter === 'manual_queue' ? isManualQueue : r.status === statusFilter || r.disputeStatus === statusFilter);
    const matchesSearch = 
      r.orderId.toLowerCase().includes(searchQuery.toLowerCase()) ||
      r.buyerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      r.merchantName.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesStatus && matchesSearch;
  });

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'PENDING':
        return <Badge variant="warning">Menunggu</Badge>;
      case 'APPROVED':
        return <Badge variant="success">Disetujui</Badge>;
      case 'REJECTED':
        return <Badge variant="destructive">Ditolak</Badge>;
      default:
        return <Badge variant="secondary">{status}</Badge>;
    }
  };

  const getDisputeLabel = (status: string | null) => ({
    OPEN: 'Diajukan',
    MERCHANT_RESPONDED: 'Merchant merespons',
    IN_MEDIATION: 'Dalam mediasi',
    RESOLVED_REFUND: 'Selesai - refund',
    RESOLVED_REJECTED: 'Selesai - ditolak',
    CLOSED: 'Ditutup',
  }[status || ''] || status || 'Belum ada');

  const getDisputeBadge = (status: string | null) => {
    if (status === 'MERCHANT_RESPONDED') return <Badge variant="warning">Menunggu keputusan admin</Badge>;
    if (status === 'IN_MEDIATION') return <Badge variant="default">Dalam mediasi admin</Badge>;
    if (status === 'RESOLVED_REFUND') return <Badge variant="success">Refund disetujui</Badge>;
    if (status === 'RESOLVED_REJECTED') return <Badge variant="destructive">Refund ditolak</Badge>;
    return getStatusBadge(status || 'PENDING');
  };

  const getSettlementLabel = (status: string | null) => ({
    NOT_REQUIRED: 'Tidak diperlukan',
    PENDING: 'Menunggu pencairan',
    PROCESSING: 'Sedang dicairkan',
    COMPLETED: 'Sudah dicairkan',
    FAILED: 'Pencairan gagal',
  }[status || ''] || status || 'Belum dibuat');

  const openRefundDetails = (refund: RefundRequest) => {
    setSelectedRefund(refund);
    setManualReference('');
    setManualEvidenceFile(null);
    setManualTransferConfirmed(false);
    setDetailDialogOpen(true);
  };

  const handleManualSettlement = async () => {
    if (!selectedRefund?.settlementId) return;
    const reference = manualReference.trim();
    const file = manualEvidenceFile;
    if (!reference || !file || !manualTransferConfirmed) {
      toast.error('Isi reference, unggah bukti, dan konfirmasi bahwa transfer benar-benar berhasil.');
      return;
    }
    const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
    if (!allowedTypes.includes(file.type) || file.size > 10 * 1024 * 1024) {
      toast.error('Bukti harus berupa JPG, PNG, WebP, atau PDF maksimal 10 MB.');
      return;
    }

    const extensionByType: Record<string, string> = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'application/pdf': 'pdf',
    };
    const evidencePath = `settlements/${selectedRefund.settlementId}/${crypto.randomUUID()}.${extensionByType[file.type]}`;
    let uploaded = false;
    try {
      setManualSettlementLoading(true);
      const { error: uploadError } = await supabase.storage
        .from('refund-settlement-evidence')
        .upload(evidencePath, file, { cacheControl: '3600', upsert: false, contentType: file.type });
      if (uploadError) throw uploadError;
      uploaded = true;

      const { error } = await supabase.rpc('complete_manual_refund_settlement', {
        p_settlement_id: selectedRefund.settlementId,
        p_provider_reference: reference,
        p_provider_amount: selectedRefund.amount,
        p_evidence_path: evidencePath,
      });
      if (error) throw error;

      await logAdminAction(
        'COMPLETE_MANUAL_REFUND',
        'refund_settlement',
        selectedRefund.settlementId,
        { status: selectedRefund.settlementStatus },
        { status: 'COMPLETED', provider_reference: reference, amount: selectedRefund.amount, evidence_path: evidencePath },
      );
      toast.success('Pencairan manual tercatat; order dan settlement ditandai selesai.');
      setDetailDialogOpen(false);
      setSelectedRefund(null);
      await loadRefunds();
    } catch (error) {
      if (uploaded) {
        await supabase.storage.from('refund-settlement-evidence').remove([evidencePath]);
      }
      console.error('Error completing manual refund settlement:', error);
      toast.error(error instanceof Error ? error.message : 'Gagal mencatat pencairan manual.');
    } finally {
      setManualSettlementLoading(false);
    }
  };

  const pendingCount = refunds.filter(r => r.status === 'PENDING').length;

  return (
    <AdminLayout title="Manajemen Refund" subtitle="Kelola permintaan pengembalian dana">
      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-5 gap-4 mb-6">
        <div className="bg-card border border-border rounded-lg p-4">
          <p className="text-sm text-muted-foreground">Total Permintaan</p>
          <p className="text-2xl font-bold">{refunds.length}</p>
        </div>
        <div className="bg-card border border-border rounded-lg p-4">
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4 text-warning" />
            <p className="text-sm text-muted-foreground">Menunggu</p>
          </div>
          <p className="text-2xl font-bold text-warning">{pendingCount}</p>
        </div>
        <div className="bg-card border border-border rounded-lg p-4">
          <p className="text-sm text-muted-foreground">Disetujui</p>
          <p className="text-2xl font-bold text-primary">{refunds.filter(r => r.status === 'APPROVED').length}</p>
        </div>
        <div className="bg-card border border-amber-300 rounded-lg p-4">
          <p className="text-sm text-muted-foreground">Antrean payout manual</p>
          <p className="text-2xl font-bold text-amber-700">{refunds.filter(r => r.status === 'APPROVED' && r.settlementProvider === 'MANUAL' && r.settlementStatus !== 'COMPLETED').length}</p>
        </div>
        <div className="bg-card border border-border rounded-lg p-4">
          <p className="text-sm text-muted-foreground">Ditolak</p>
          <p className="text-2xl font-bold text-destructive">{refunds.filter(r => r.status === 'REJECTED').length}</p>
        </div>
      </div>

      {/* Filter & Search */}
      <AdminFilterBar
        search={searchQuery}
        onSearchChange={setSearchQuery}
        searchPlaceholder="Cari Order ID, pembeli, atau merchant..."
        hasFilters={statusFilter !== 'all' || searchQuery.length > 0}
        onReset={() => { setSearchQuery(''); setStatusFilter('all'); }}
        actions={<Button variant="outline" size="sm" onClick={() => void loadRefunds()} disabled={loading} className="gap-2"><RotateCcw className={loading ? 'h-4 w-4 animate-spin' : 'h-4 w-4'} /> Segarkan</Button>}
      >
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="h-9 w-full sm:w-40"><SelectValue placeholder="Filter status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Semua status</SelectItem>
            <SelectItem value="PENDING">Menunggu</SelectItem>
            <SelectItem value="MERCHANT_RESPONDED">Merchant merespons</SelectItem>
            <SelectItem value="IN_MEDIATION">Dalam mediasi</SelectItem>
            <SelectItem value="APPROVED">Disetujui</SelectItem>
            <SelectItem value="manual_queue">Antrean payout manual</SelectItem>
            <SelectItem value="REJECTED">Ditolak</SelectItem>
          </SelectContent>
        </Select>
      </AdminFilterBar>

      {/* Table */}
      {loading ? (
        <AdminStatePanel type="loading" title="Memuat permintaan refund" description="Menyiapkan detail order, pembeli, merchant, dan status refund." />
      ) : errorMessage ? (
        <AdminStatePanel type="error" description={errorMessage} actionLabel="Coba lagi" onAction={() => void loadRefunds()} />
      ) : (
        <div className="bg-card border border-border rounded-xl overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Order ID</TableHead>
                <TableHead>Pembeli</TableHead>
                <TableHead>Merchant</TableHead>
                <TableHead>Jumlah</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Tanggal</TableHead>
                <TableHead className="text-right">Aksi</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredRefunds.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={7} className="text-center py-10 text-muted-foreground">
                    <RotateCcw className="h-10 w-10 mx-auto mb-2 opacity-50" />
                    Tidak ada permintaan refund
                  </TableCell>
                </TableRow>
              ) : (
                filteredRefunds.map((refund) => (
                  <TableRow key={refund.id}>
                    <TableCell className="font-mono text-sm">{refund.orderId.slice(0, 8)}</TableCell>
                    <TableCell>{refund.buyerName}</TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1">
                        <Store className="h-3 w-3 text-muted-foreground" />
                        <span className="text-sm">{refund.merchantName}</span>
                      </div>
                    </TableCell>
                    <TableCell className="font-medium">{formatPrice(refund.amount)}</TableCell>
                    <TableCell>
                      <div className="space-y-1">
                        {getDisputeBadge(refund.disputeStatus)}
                        <p className="text-xs text-muted-foreground">Refund: {getStatusBadge(refund.status)}</p>
                      </div>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {format(new Date(refund.createdAt), 'dd MMM yyyy', { locale: idLocale })}
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-2">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => openRefundDetails(refund)}
                        >
                          <Eye className="h-4 w-4" />
                        </Button>
                        {refund.status === 'PENDING' && (
                          <>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-green-600 hover:text-green-700"
                              onClick={() => {
                                setSelectedRefund(refund);
                                setProcessAction('approve');
                                setProcessDialogOpen(true);
                              }}
                            >
                              <Check className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-destructive hover:text-destructive"
                              onClick={() => {
                                setSelectedRefund(refund);
                                setProcessAction('reject');
                                setProcessDialogOpen(true);
                              }}
                            >
                              <X className="h-4 w-4" />
                            </Button>
                          </>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </div>
      )}

      {/* Detail Dialog */}
      <Dialog open={detailDialogOpen} onOpenChange={setDetailDialogOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Detail Permintaan Refund</DialogTitle>
          </DialogHeader>
          {selectedRefund && (
            <div className="space-y-6">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-muted-foreground">Order ID</p>
                  <p className="font-mono">{selectedRefund.orderId}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Status</p>
                  {getStatusBadge(selectedRefund.status)}
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Status Dispute</p>
                  <Badge variant="outline">{getDisputeLabel(selectedRefund.disputeStatus)}</Badge>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Status Pencairan</p>
                  <Badge variant={selectedRefund.settlementStatus === 'FAILED' ? 'destructive' : selectedRefund.settlementStatus === 'COMPLETED' ? 'success' : 'outline'}>
                    {selectedRefund.settlementProvider === 'MANUAL' && selectedRefund.settlementStatus !== 'COMPLETED'
                      ? 'Antrean pencairan manual'
                      : getSettlementLabel(selectedRefund.settlementStatus)}
                  </Badge>
                </div>
                {selectedRefund.settlementProvider && (
                  <div>
                    <p className="text-sm text-muted-foreground">Metode pencairan</p>
                    <p className="font-medium">{selectedRefund.settlementProvider === 'MANUAL' ? 'Transfer manual (legacy)' : selectedRefund.settlementProvider}</p>
                  </div>
                )}
                {selectedRefund.settlementProviderStatus && (
                  <div>
                    <p className="text-sm text-muted-foreground">Status provider / antrean</p>
                    <p className="font-medium">{selectedRefund.settlementProviderStatus}</p>
                  </div>
                )}
                <div>
                  <p className="text-sm text-muted-foreground">Pembeli</p>
                  <p className="font-medium">{selectedRefund.buyerName}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Merchant</p>
                  <p className="font-medium">{selectedRefund.merchantName}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Jumlah Refund</p>
                  <p className="font-bold text-primary">{formatPrice(selectedRefund.amount)}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Tipe Refund</p>
                  <Badge variant="outline">{selectedRefund.refundType}</Badge>
                </div>
              </div>

              <div>
                <p className="text-sm text-muted-foreground mb-1">Alasan Refund</p>
                <div className="bg-muted p-3 rounded-lg text-sm">
                  {selectedRefund.reason}
                </div>
              </div>

              <div>
                <p className="text-sm text-muted-foreground mb-1">Respons Merchant</p>
                <div className="bg-emerald-50 border border-emerald-100 text-emerald-950 p-3 rounded-lg text-sm">
                  {selectedRefund.merchantResponse || 'Merchant belum memberikan respons.'}
                </div>
              </div>

              {selectedRefund.evidenceUrls.length > 0 && (
                <div>
                  <p className="text-sm text-muted-foreground mb-2">Bukti Pendukung</p>
                  <div className="grid grid-cols-3 gap-2">
                    {selectedRefund.evidenceUrls.map((url, i) => (
                      <a key={i} href={url} target="_blank" rel="noreferrer" className="aspect-square rounded-lg overflow-hidden border border-border hover:opacity-80 transition-opacity">
                        <img src={url} alt={`Evidence ${i+1}`} className="w-full h-full object-cover" />
                      </a>
                    ))}
                  </div>
                </div>
              )}

              {selectedRefund.adminNotes && (
                <div>
                  <p className="text-sm text-muted-foreground mb-1">Catatan Admin</p>
                  <div className="bg-blue-50 text-blue-800 p-3 rounded-lg text-sm border border-blue-100">
                    {selectedRefund.adminNotes}
                  </div>
                </div>
              )}

              {selectedRefund.settlementLastError && selectedRefund.settlementProvider === 'MANUAL' && (
                <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950">
                  {selectedRefund.settlementLastError}
                </div>
              )}

              {selectedRefund.settlementProviderReference && (
                <div>
                  <p className="text-sm text-muted-foreground mb-1">Reference transfer</p>
                  <p className="font-mono text-sm">{selectedRefund.settlementProviderReference}</p>
                </div>
              )}
              {selectedRefund.settlementEvidencePath && (
                <div className="flex items-center gap-2">
                  <p className="text-sm text-muted-foreground">Bukti pencairan sudah tersimpan secara privat.</p>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={async () => {
                      const { data, error } = await supabase.storage
                        .from('refund-settlement-evidence')
                        .createSignedUrl(selectedRefund.settlementEvidencePath!, 60);
                      if (error || !data?.signedUrl) {
                        toast.error('Bukti pencairan tidak dapat dibuka.');
                        return;
                      }
                      window.open(data.signedUrl, '_blank', 'noopener,noreferrer');
                    }}
                  >
                    Lihat bukti
                  </Button>
                </div>
              )}

              {selectedRefund.status === 'APPROVED'
                && selectedRefund.settlementProvider === 'MANUAL'
                && selectedRefund.settlementStatus !== 'COMPLETED'
                && selectedRefund.settlementId && (
                  <div className="space-y-4 rounded-lg border border-border p-4">
                    <div>
                      <h3 className="font-semibold">Catat pencairan manual</h3>
                      <p className="mt-1 text-sm text-muted-foreground">
                        Lakukan transfer di luar sistem terlebih dahulu. Setelah transfer berhasil, masukkan reference unik dan bukti. Sistem hanya menandai refund selesai setelah data tersebut tervalidasi.
                      </p>
                    </div>
                    <div className="space-y-2">
                      <label htmlFor="manual-refund-reference" className="text-sm font-medium">Reference transfer</label>
                      <input
                        id="manual-refund-reference"
                        value={manualReference}
                        onChange={(event) => setManualReference(event.target.value)}
                        maxLength={200}
                        placeholder="Nomor referensi dari bank/provider"
                        className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                      />
                    </div>
                    <div className="text-sm">
                      Nominal yang harus dibayar: <strong>{formatPrice(selectedRefund.amount)}</strong>
                    </div>
                    <div className="space-y-2">
                      <label htmlFor="manual-refund-evidence" className="text-sm font-medium">Bukti transfer (JPG, PNG, WebP, atau PDF; maks. 10 MB)</label>
                      <input
                        id="manual-refund-evidence"
                        type="file"
                        accept="image/jpeg,image/png,image/webp,application/pdf"
                        onChange={(event) => setManualEvidenceFile(event.target.files?.[0] || null)}
                        className="w-full text-sm"
                      />
                      {manualEvidenceFile && <p className="text-xs text-muted-foreground">{manualEvidenceFile.name}</p>}
                    </div>
                    <label className="flex items-start gap-2 text-sm">
                      <input
                        type="checkbox"
                        checked={manualTransferConfirmed}
                        onChange={(event) => setManualTransferConfirmed(event.target.checked)}
                        className="mt-1"
                      />
                      <span>Saya sudah memverifikasi transfer sebesar nominal refund berhasil dilakukan ke penerima yang benar.</span>
                    </label>
                    <Button
                      onClick={() => void handleManualSettlement()}
                      disabled={manualSettlementLoading || !manualReference.trim() || !manualEvidenceFile || !manualTransferConfirmed}
                    >
                      {manualSettlementLoading ? 'Menyimpan bukti...' : 'Catat payout selesai'}
                    </Button>
                  </div>
                )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Process Dialog */}
      <Dialog open={processDialogOpen} onOpenChange={setProcessDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {processAction === 'approve' ? 'Setujui Refund' : 'Tolak Refund'}
            </DialogTitle>
            <DialogDescription>
              {processAction === 'approve' 
                ? 'Refund ini akan masuk antrean pencairan manual. Dana tidak dikirim otomatis; admin harus melakukan transfer di luar sistem dan mencatat reference serta bukti setelah transfer berhasil.'
                : 'Berikan alasan mengapa permintaan refund ini ditolak.'}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <label className="text-sm font-medium">Catatan Admin</label>
              <Textarea
                placeholder="Masukkan catatan atau alasan..."
                value={adminNotes}
                onChange={(e) => setAdminNotes(e.target.value)}
                rows={4}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setProcessDialogOpen(false)}>
              Batal
            </Button>
            <Button
              variant={processAction === 'approve' ? 'default' : 'destructive'}
              onClick={handleProcess}
              disabled={actionLoading}
            >
              {actionLoading ? 'Memproses...' : processAction === 'approve' ? 'Setujui' : 'Tolak'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}
