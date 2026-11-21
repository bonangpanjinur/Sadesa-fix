import { useEffect, useMemo, useState } from 'react';
import { CheckCircle2, Clock3, FileText, Loader2, QrCode, RefreshCw, ShieldCheck, XCircle } from 'lucide-react';
import { toast } from 'sonner';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { QRCodeSVG } from 'qrcode.react';
import { previewGdcQrisMpm, type GdcQrisMpmPreview } from '@/lib/gdcQrisMpmApi';

type AppStatus = 'SUBMITTED' | 'IN_REVIEW' | 'NEEDS_CORRECTION' | 'REJECTED' | 'APPROVED_PENDING_ISSUANCE' | 'ISSUED_PENDING_ACTIVATION' | 'ACTIVE';
type QrisApplication = {
  id: string;
  application_number: string;
  merchant_id: string;
  applicant_user_id: string;
  default_bank_name: string | null;
  default_account_number: string | null;
  default_account_name: string | null;
  business_criteria_code: string;
  business_age_code: string;
  qris_merchant_name_short: string;
  qris_merchant_name: string;
  documents: Record<string, string>;
  status: AppStatus;
  decision_note: string | null;
  qris_reference: string | null;
  qris_asset_key: string | null;
  gdc_merchant_id: string | null;
  gdc_account_number: string | null;
  gdc_mpm_enabled: boolean;
  submitted_at: string;
  revision_number: number;
  merchant?: { name: string; city: string | null } | null;
};

// qris_applications is a newly introduced table not yet present in generated Supabase types.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const db = supabase as any;
const labels: Record<AppStatus, string> = {
  SUBMITTED: 'Menunggu Verifikasi',
  IN_REVIEW: 'Sedang Diverifikasi',
  NEEDS_CORRECTION: 'Perlu Perbaikan',
  REJECTED: 'Ditolak',
  APPROVED_PENDING_ISSUANCE: 'Disetujui — Menunggu Penerbitan',
  ISSUED_PENDING_ACTIVATION: 'Menunggu Aktivasi',
  ACTIVE: 'QRIS Aktif',
};
type DisplayStatus = 'WAITING_ADMIN_ACTIVATION' | 'NEEDS_CORRECTION' | 'REJECTED' | 'ACTIVE';
const displayLabels: Record<DisplayStatus, string> = {
  WAITING_ADMIN_ACTIVATION: 'Menunggu Aktivasi Admin',
  NEEDS_CORRECTION: 'Perlu Perbaikan',
  REJECTED: 'Ditolak',
  ACTIVE: 'QRIS Aktif',
};
const businessCriteriaLabels: Record<string, string> = {
  UMI: 'UMI — Usaha Mikro (UMKM)',
  UME: 'UME — Usaha Menengah (UMKM)',
  UBE: 'UBE — Usaha Besar (bukan UMKM)',
};
const displayStatusFor = (status: AppStatus): DisplayStatus => {
  switch (status) {
    case 'SUBMITTED':
    case 'IN_REVIEW':
    case 'APPROVED_PENDING_ISSUANCE':
    case 'ISSUED_PENDING_ACTIVATION':
      return 'WAITING_ADMIN_ACTIVATION';
    case 'NEEDS_CORRECTION':
      return 'NEEDS_CORRECTION';
    case 'REJECTED':
      return 'REJECTED';
    case 'ACTIVE':
      return 'ACTIVE';
  }
};
const docLabels: Record<string, string> = {
  OWNER_ID: 'Foto KTP Pemilik',
  OWNER_SELFIE: 'Foto Selfie Pemilik',
  BUSINESS_LOCATION: 'Foto Lokasi Usaha',
  PRODUCT: 'Foto Produk',
};
const requiredDocumentTypes = Object.keys(docLabels);

export default function AdminQrisApplicationsPage() {
  const { user } = useAuth();
  const [applications, setApplications] = useState<QrisApplication[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [documentUrls, setDocumentUrls] = useState<Record<string, string>>({});
  const [correctionNote, setCorrectionNote] = useState('');
  const [gdcMerchantId, setGdcMerchantId] = useState('');
  const [gdcAccountNumber, setGdcAccountNumber] = useState('');
  const [filter, setFilter] = useState('ALL');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [previewing, setPreviewing] = useState(false);
  const [qrisPreview, setQrisPreview] = useState<{ applicationId: string; payment: GdcQrisMpmPreview } | null>(null);
  const selected = applications.find((item) => item.id === selectedId) || null;
  const pendingCount = useMemo(() => applications.filter((item) => displayStatusFor(item.status) === 'WAITING_ADMIN_ACTIVATION').length, [applications]);

  const load = async () => {
    setLoading(true);
    try {
      const { data, error } = await db.from('qris_applications').select('*, merchant:merchants(name,city)').order('submitted_at', { ascending: false });
      if (error) throw error;
      setApplications((data || []) as QrisApplication[]);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Daftar pengajuan QRIS gagal dimuat.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);

  useEffect(() => {
    let active = true;
    const loadDocuments = async () => {
      if (!selected) {
        setDocumentUrls({});
        return;
      }
      const pairs = await Promise.all(Object.entries(selected.documents || {}).map(async ([type, path]) => {
        const { data } = await supabase.storage.from('qris-applications').createSignedUrl(path, 300);
        return [type, data?.signedUrl || ''] as const;
      }));
      if (active) setDocumentUrls(Object.fromEntries(pairs));
      setGdcMerchantId(selected.gdc_merchant_id || '');
      setGdcAccountNumber(selected.gdc_account_number || '');
      setCorrectionNote('');
      setQrisPreview(null);
    };
    void loadDocuments();
    return () => { active = false; };
  }, [selected]);

  const setStatus = async (application: QrisApplication, status: AppStatus, note?: string) => {
    if (!user) return;
    setSaving(true);
    try {
      const patch: Record<string, unknown> = { status, updated_at: new Date().toISOString() };
      if (['REJECTED', 'NEEDS_CORRECTION'].includes(status)) patch.decision_note = note?.trim();
      if (status === 'IN_REVIEW') patch.assigned_admin_id = user.id;
      if (status === 'REJECTED' || status === 'APPROVED_PENDING_ISSUANCE') {
        patch.decision_by_admin_id = user.id;
        patch.decision_note = note?.trim() || null;
      }
      const { error } = await db.from('qris_applications').update(patch).eq('id', application.id);
      if (error) throw error;
      toast.success(`Status diperbarui: ${labels[status]}`);
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Perubahan status gagal disimpan.');
    } finally {
      setSaving(false);
    }
  };

  const saveGdcMpmIdentity = async (application: QrisApplication) => {
    if (!user || !gdcMerchantId.trim() || !gdcAccountNumber.trim()) {
      return toast.error('MID dan Account Number GDC wajib diisi.');
    }
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_configure_qris_mpm', {
        p_application_id: application.id,
        p_gdc_merchant_id: gdcMerchantId.trim(),
        p_gdc_account_number: gdcAccountNumber.trim(),
      });
      if (error) throw error;
      toast.success('MID dan Account Number GDC tersimpan. Pengajuan menunggu aktivasi admin untuk QRIS dinamis.');
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Mapping GDC gagal disimpan.');
    } finally {
      setSaving(false);
    }
  };

  const previewGdcMpm = async (application: QrisApplication) => {
    if (!application.gdc_merchant_id?.trim() || !application.gdc_account_number?.trim()) {
      toast.error('Simpan MID dan Account Number GDC terlebih dahulu sebelum uji QR.');
      return;
    }
    setPreviewing(true);
    setQrisPreview(null);
    try {
      const payment = await previewGdcQrisMpm(application.id);
      setQrisPreview({ applicationId: application.id, payment });
      toast.success('QR uji GDC sandbox berhasil dibuat. QR ini bukan untuk pembayaran produksi.');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Preview QRIS dinamis gagal dibuat.');
    } finally {
      setPreviewing(false);
    }
  };

  const setGdcMpmEnabled = async (application: QrisApplication, enabled: boolean) => {
    if (!user) return;
    if (enabled && (!application.gdc_merchant_id?.trim() || !application.gdc_account_number?.trim())) {
      toast.error('Simpan MID dan Account Number GDC yang sudah disetujui provider sebelum mengaktifkan.');
      return;
    }
    if (enabled && !window.confirm(`Pastikan MID dan Account Number GDC yang disetujui provider sudah cocok dengan toko ${application.merchant?.name || 'ini'}. Aktifkan QRIS MPM Dinamis?`)) return;
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_set_qris_mpm_enabled', {
        p_application_id: application.id,
        p_enabled: enabled,
      });
      if (error) throw error;
      toast.success(enabled ? 'QRIS MPM Dinamis diaktifkan untuk toko ini.' : 'QRIS MPM Dinamis dinonaktifkan untuk toko ini.');
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Status QRIS MPM Dinamis gagal diperbarui.');
    } finally {
      setSaving(false);
    }
  };

  const activate = async (application: QrisApplication) => {
    if (!user) return;
    if (!application.gdc_merchant_id?.trim() || !application.gdc_account_number?.trim()) {
      toast.error('Simpan MID dan Account Number GDC yang telah disetujui sebelum mengaktifkan QRIS dinamis.');
      return;
    }
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_activate_qris', { p_application_id: application.id });
      if (error) throw error;
      toast.success('QRIS Sadesa aktif untuk merchant. QRIS MPM Dinamis dapat diaktifkan secara terpisah oleh admin.');
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Aktivasi QRIS gagal.');
    } finally {
      setSaving(false);
    }
  };

  const shown = applications.filter((item) => filter === 'ALL' || displayStatusFor(item.status) === filter);
  const hasGdcIdentity = Boolean(selected?.gdc_merchant_id?.trim() && selected.gdc_account_number?.trim());
  const missingRequiredDocuments = selected
    ? requiredDocumentTypes.filter((type) => !selected.documents?.[type])
    : requiredDocumentTypes;
  const mappingMatchesSelected = Boolean(selected
    && gdcMerchantId.trim() === selected.gdc_merchant_id?.trim()
    && gdcAccountNumber.trim() === selected.gdc_account_number?.trim());

  return (
    <AdminLayout title="Pengajuan QRIS Sadesa" subtitle="Daftarkan merchant secara manual ke GDC, lalu aktifkan QRIS setelah data yang dimasukkan admin disetujui GDC.">
      <div className="grid gap-4 xl:grid-cols-[minmax(300px,0.9fr)_minmax(0,1.5fr)]">
        <Card className="h-fit">
          <CardHeader>
            <div className="flex items-center justify-between gap-2">
              <div>
                <CardTitle className="flex items-center gap-2"><QrCode className="h-5 w-5" />Antrean Pengajuan</CardTitle>
                <CardDescription>{pendingCount} pengajuan perlu ditangani</CardDescription>
              </div>
              <Button variant="outline" size="icon" onClick={() => void load()} aria-label="Muat ulang">
                <RefreshCw className="h-4 w-4" />
              </Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
            <select className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={filter} onChange={(event) => setFilter(event.target.value)}>
              <option value="ALL">Semua status</option>
              {Object.entries(displayLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
            {loading ? (
              <div className="flex items-center gap-2 py-8 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />Memuat pengajuan…</div>
            ) : shown.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">Belum ada pengajuan pada status ini.</p>
            ) : shown.map((application) => (
              <button key={application.id} onClick={() => setSelectedId(application.id)} className={`w-full rounded-lg border p-3 text-left transition-colors ${selectedId === application.id ? 'border-primary bg-primary/5' : 'hover:bg-muted/60'}`}>
                <div className="flex items-start justify-between gap-2">
                  <span className="font-medium">{application.merchant?.name || 'Merchant'}</span>
                  <Badge variant={application.status === 'ACTIVE' ? 'default' : 'secondary'}>{displayLabels[displayStatusFor(application.status)]}</Badge>
                </div>
                <p className="mt-1 text-xs text-muted-foreground">{application.application_number} · {new Date(application.submitted_at).toLocaleDateString('id-ID')}</p>
                <p className="mt-1 text-xs text-muted-foreground">{application.business_criteria_code} · {application.qris_merchant_name}</p>
                {application.status === 'ACTIVE' && <p className="mt-1 text-xs font-medium">MPM GDC: {application.gdc_mpm_enabled ? 'Aktif' : 'Nonaktif'}</p>}
              </button>
            ))}
          </CardContent>
        </Card>

        {!selected ? (
          <Card><CardContent className="flex min-h-64 flex-col items-center justify-center gap-3 text-center text-muted-foreground"><FileText className="h-8 w-8" /><p>Pilih pengajuan untuk melihat data dan melakukan verifikasi.</p></CardContent></Card>
        ) : (
          <Card>
            <CardHeader>
              <CardTitle>{selected.merchant?.name || 'Merchant'} <span className="text-sm font-normal text-muted-foreground">· {selected.application_number}</span></CardTitle>
              <CardDescription>Revisi {selected.revision_number} · Diajukan {new Date(selected.submitted_at).toLocaleString('id-ID')}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
              <div className="grid gap-3 rounded-lg bg-muted/50 p-4 text-sm sm:grid-cols-2">
                <p><strong>Kriteria bisnis:</strong> {businessCriteriaLabels[selected.business_criteria_code] ?? selected.business_criteria_code}</p>
                <p><strong>Lama usaha:</strong> {selected.business_age_code}</p>
                <p><strong>Nama QRIS (25):</strong> {selected.qris_merchant_name_short}</p>
                <p><strong>Nama QRIS (50):</strong> {selected.qris_merchant_name}</p>
                <p><strong>Bank default:</strong> {selected.default_bank_name || '—'}</p>
                <p><strong>Nomor akun:</strong> {selected.default_account_number || '—'}</p>
                <p><strong>Atas nama:</strong> {selected.default_account_name || '—'}</p>
              </div>

              <div>
                <h3 className="mb-3 font-semibold">Dokumen Merchant</h3>
                {missingRequiredDocuments.length > 0 && (
                  <p className="mb-3 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900" role="alert">
                    Pengajuan belum dapat disetujui. Dokumen wajib belum tersedia: {missingRequiredDocuments.map((type) => docLabels[type]).join(', ')}.
                  </p>
                )}
                <div className="grid gap-3 sm:grid-cols-2">
                  {Object.entries(docLabels).map(([type, label]) => (
                    <div key={type} className="rounded-lg border p-3">
                      <p className="mb-2 text-sm font-medium">{label}</p>
                      {documentUrls[type] ? <a href={documentUrls[type]} target="_blank" rel="noreferrer" className="text-sm text-primary underline">Lihat dokumen (tautan berlaku 5 menit)</a> : <p className="text-xs text-destructive">Dokumen tidak ditemukan</p>}
                    </div>
                  ))}
                </div>
              </div>

              {selected.decision_note && <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm"><strong>Catatan sebelumnya:</strong> {selected.decision_note}</div>}

              {['SUBMITTED', 'IN_REVIEW'].includes(selected.status) && (
                <div className="space-y-3 rounded-lg border p-4">
                  <h3 className="font-semibold">Keputusan Verifikasi</h3>
                  <Textarea value={correctionNote} onChange={(event) => setCorrectionNote(event.target.value)} placeholder="Catatan untuk merchant, wajib untuk permintaan perbaikan atau penolakan" />
                  <div className="flex flex-wrap gap-2">
                    <Button variant="outline" disabled={saving} onClick={() => void setStatus(selected, 'IN_REVIEW')}><Clock3 className="mr-2 h-4 w-4" />Mulai Verifikasi</Button>
                    <Button variant="outline" disabled={saving || correctionNote.trim().length < 8} onClick={() => void setStatus(selected, 'NEEDS_CORRECTION', correctionNote)}><FileText className="mr-2 h-4 w-4" />Minta Perbaikan</Button>
                    <Button variant="destructive" disabled={saving || correctionNote.trim().length < 8} onClick={() => void setStatus(selected, 'REJECTED', correctionNote)}><XCircle className="mr-2 h-4 w-4" />Tolak</Button>
                    <Button disabled={saving || missingRequiredDocuments.length > 0} onClick={() => void setStatus(selected, 'APPROVED_PENDING_ISSUANCE', 'Data dan dokumen telah diverifikasi.')}><CheckCircle2 className="mr-2 h-4 w-4" />Setujui</Button>
                  </div>
                </div>
              )}

              {selected.status === 'APPROVED_PENDING_ISSUANCE' && (
                <div className="space-y-3 rounded-lg border border-primary/20 p-4">
                  <h3 className="font-semibold">Mapping merchant GDC untuk QRIS MPM</h3>
                  <p className="text-sm text-muted-foreground">Daftarkan merchant secara manual di dashboard GDC. Masukkan MID dan Account Number yang sudah disetujui GDC. QR pembayaran akan dibuat dinamis per pesanan melalui GDC; Sadesa tidak memakai gambar QR statis atau validasi otomatis provider.</p>
                  <div className="space-y-2">
                    <Label htmlFor="gdc-merchant-id">GDC Merchant ID (MID)</Label>
                    <Input id="gdc-merchant-id" value={gdcMerchantId} onChange={(event) => setGdcMerchantId(event.target.value)} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="gdc-account-number">GDC Account Number</Label>
                    <Input id="gdc-account-number" value={gdcAccountNumber} onChange={(event) => setGdcAccountNumber(event.target.value)} maxLength={100} autoComplete="off" />
                  </div>
                  <Button disabled={saving || !gdcMerchantId.trim() || !gdcAccountNumber.trim()} onClick={() => void saveGdcMpmIdentity(selected)}>Simpan Data GDC — Menunggu Aktivasi Admin</Button>
                </div>
              )}

              {selected.status === 'ISSUED_PENDING_ACTIVATION' && (
                <div className="space-y-4 rounded-lg border p-4">
                  <div>
                    <h3 className="font-semibold">Aktivasi QRIS MPM Dinamis</h3>
                    <p className="mt-1 text-sm text-muted-foreground">MID dan Account Number harus sudah didaftarkan dan disetujui di GDC. Setelah admin mengaktifkan, Edge Function dapat memakai mapping ini untuk request <code>qr-mpm-generate</code>.</p>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="pending-gdc-merchant-id">GDC Merchant ID (MID)</Label>
                    <Input id="pending-gdc-merchant-id" value={gdcMerchantId} onChange={(event) => { setGdcMerchantId(event.target.value); setQrisPreview(null); }} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="pending-gdc-account-number">GDC Account Number</Label>
                    <Input id="pending-gdc-account-number" value={gdcAccountNumber} onChange={(event) => { setGdcAccountNumber(event.target.value); setQrisPreview(null); }} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button variant="outline" disabled={saving || !gdcMerchantId.trim() || !gdcAccountNumber.trim()} onClick={() => void saveGdcMpmIdentity(selected)}>Simpan Mapping (MPM tetap nonaktif)</Button>
                    <Button disabled={saving || !hasGdcIdentity || !mappingMatchesSelected} onClick={() => void activate(selected)}><ShieldCheck className="mr-2 h-4 w-4" />Aktifkan QRIS Dinamis</Button>
                  </div>
                </div>
              )}

              {selected.status === 'ACTIVE' && (
                <div className="space-y-4 rounded-lg border border-emerald-300 p-4">
                  <div>
                    <h3 className="font-semibold">QRIS MPM Dinamis GDC</h3>
                    <p className="mt-1 text-sm text-muted-foreground">Status: <strong>{selected.gdc_mpm_enabled ? 'Aktif' : 'Nonaktif'}</strong>. Masukkan hanya mapping yang sudah disetujui GDC secara manual. Mengubah mapping menonaktifkan QRIS Dinamis sampai admin mengaktifkannya kembali. Perubahan status dan mapping dicatat tanpa menyalin nilai MID/account ke log.</p>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="active-gdc-merchant-id">GDC Merchant ID (MID)</Label>
                    <Input id="active-gdc-merchant-id" value={gdcMerchantId} onChange={(event) => { setGdcMerchantId(event.target.value); setQrisPreview(null); }} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="active-gdc-account-number">GDC Account Number</Label>
                    <Input id="active-gdc-account-number" value={gdcAccountNumber} onChange={(event) => { setGdcAccountNumber(event.target.value); setQrisPreview(null); }} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button variant="outline" disabled={saving || !gdcMerchantId.trim() || !gdcAccountNumber.trim()} onClick={() => void saveGdcMpmIdentity(selected)}>Simpan Mapping (Dinamis Dinonaktifkan)</Button>
                    <Button disabled={saving || (!selected.gdc_mpm_enabled && (!hasGdcIdentity || !mappingMatchesSelected))} variant={selected.gdc_mpm_enabled ? 'destructive' : 'default'} onClick={() => void setGdcMpmEnabled(selected, !selected.gdc_mpm_enabled)}>
                      {selected.gdc_mpm_enabled ? 'Nonaktifkan QRIS Dinamis' : 'Aktifkan QRIS Dinamis'}
                    </Button>
                  </div>
                </div>
              )}

              {hasGdcIdentity && (
                <div className="space-y-4 rounded-lg border border-sky-300 bg-sky-50/40 p-4">
                  <div>
                    <h3 className="font-semibold">Preview QRIS Dinamis GDC — Sandbox</h3>
                    <p className="mt-1 text-sm text-muted-foreground">
                      Membuat QR uji Rp1.000 langsung melalui <code>qr-mpm-generate</code> sandbox. Tidak membuat order Sadesa atau mengubah status aktivasi. QR ini hanya untuk pengujian sandbox dan jangan dibayar.
                    </p>
                  </div>
                  <Button variant="outline" disabled={previewing || saving || !mappingMatchesSelected} onClick={() => void previewGdcMpm(selected)}>
                    {previewing ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <QrCode className="mr-2 h-4 w-4" />}
                    {previewing ? 'Meminta QR uji…' : 'Buat QR Uji Sandbox · Rp1.000'}
                  </Button>
                  {qrisPreview?.applicationId === selected.id && (
                    <div className="flex flex-col items-center gap-3 rounded-lg border bg-white p-4 text-center">
                      <Badge variant="destructive">QR UJI SANDBOX — JANGAN DIBAYAR</Badge>
                      <QRCodeSVG value={qrisPreview.payment.qr_content} size={240} level="M" includeMargin aria-label={`QRIS dinamis sandbox ${selected.merchant?.name || 'merchant'}`} />
                      <p className="text-sm font-semibold">Rp{qrisPreview.payment.amount.toLocaleString('id-ID')}</p>
                      <p className="text-xs text-muted-foreground">Referensi sandbox: {qrisPreview.payment.reference_no}</p>
                    </div>
                  )}
                </div>
              )}
            </CardContent>
          </Card>
        )}
      </div>
    </AdminLayout>
  );
}
