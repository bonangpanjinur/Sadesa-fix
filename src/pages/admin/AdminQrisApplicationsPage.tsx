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
import { ImageUpload } from '@/components/ui/ImageUpload';

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
const docLabels: Record<string, string> = {
  OWNER_ID: 'Foto KTP Pemilik',
  OWNER_SELFIE: 'Foto Selfie Pemilik',
  BUSINESS_LOCATION: 'Foto Lokasi Usaha',
  PRODUCT: 'Foto Produk',
};

export default function AdminQrisApplicationsPage() {
  const { user } = useAuth();
  const [applications, setApplications] = useState<QrisApplication[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [documentUrls, setDocumentUrls] = useState<Record<string, string>>({});
  const [correctionNote, setCorrectionNote] = useState('');
  const [qrisReference, setQrisReference] = useState('');
  const [qrisImageUrl, setQrisImageUrl] = useState<string | null>(null);
  const [gdcMerchantId, setGdcMerchantId] = useState('');
  const [gdcAccountNumber, setGdcAccountNumber] = useState('');
  const [filter, setFilter] = useState('ALL');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const selected = applications.find((item) => item.id === selectedId) || null;
  const pendingCount = useMemo(() => applications.filter((item) => ['SUBMITTED', 'IN_REVIEW'].includes(item.status)).length, [applications]);

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
      setQrisReference(selected.qris_reference || '');
      setGdcMerchantId(selected.gdc_merchant_id || '');
      setGdcAccountNumber(selected.gdc_account_number || '');
      setQrisImageUrl(null);
      setCorrectionNote('');
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

  const issue = async (application: QrisApplication) => {
    if (!user || !qrisReference.trim() || !qrisImageUrl || !gdcMerchantId.trim() || !gdcAccountNumber.trim()) {
      return toast.error('Isi referensi, unggah QRIS, dan masukkan MID serta Account Number GDC.');
    }
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_issue_qris_mpm', {
        p_application_id: application.id,
        p_qris_reference: qrisReference.trim(),
        p_qris_asset_key: qrisImageUrl,
        p_gdc_merchant_id: gdcMerchantId.trim(),
        p_gdc_account_number: gdcAccountNumber.trim(),
      });
      if (error) throw error;
      toast.success('QRIS Sadesa dicatat dan menunggu aktivasi akhir. QRIS MPM Dinamis masih nonaktif sampai admin mengaktifkannya.');
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Penerbitan QRIS gagal disimpan.');
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
      toast.success('Mapping tersimpan. QRIS MPM Dinamis tetap nonaktif sampai diaktifkan secara terpisah.');
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Mapping GDC gagal disimpan.');
    } finally {
      setSaving(false);
    }
  };

  const setGdcMpmEnabled = async (application: QrisApplication, enabled: boolean) => {
    if (!user) return;
    if (enabled && (!application.gdc_merchant_id?.trim() || !application.gdc_account_number?.trim())) {
      toast.error('Simpan dan verifikasi MID serta Account Number GDC sebelum mengaktifkan.');
      return;
    }
    if (enabled && !window.confirm(`Pastikan MID dan Account Number GDC yang tersimpan sudah dicocokkan dengan toko ${application.merchant?.name || 'ini'}. Aktifkan QRIS MPM Dinamis?`)) return;
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
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_activate_qris', { p_application_id: application.id });
      if (error) throw error;
      toast.success('QRIS Sadesa aktif untuk merchant. QRIS MPM Dinamis dapat diaktifkan setelah mapping diverifikasi.');
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Aktivasi QRIS gagal.');
    } finally {
      setSaving(false);
    }
  };

  const shown = applications.filter((item) => filter === 'ALL' || item.status === filter);
  const hasGdcIdentity = Boolean(selected?.gdc_merchant_id?.trim() && selected.gdc_account_number?.trim());
  const mappingMatchesSelected = Boolean(selected
    && gdcMerchantId.trim() === selected.gdc_merchant_id?.trim()
    && gdcAccountNumber.trim() === selected.gdc_account_number?.trim());

  return (
    <AdminLayout title="Pengajuan QRIS Sadesa" subtitle="Verifikasi data, daftarkan merchant secara manual ke Neo/GDC, unggah QRIS statis per merchant, lalu aktifkan mapping QRIS MPM secara terpisah setelah diverifikasi.">
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
              {Object.entries(labels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
            {loading ? (
              <div className="flex items-center gap-2 py-8 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />Memuat pengajuan…</div>
            ) : shown.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">Belum ada pengajuan pada status ini.</p>
            ) : shown.map((application) => (
              <button key={application.id} onClick={() => setSelectedId(application.id)} className={`w-full rounded-lg border p-3 text-left transition-colors ${selectedId === application.id ? 'border-primary bg-primary/5' : 'hover:bg-muted/60'}`}>
                <div className="flex items-start justify-between gap-2">
                  <span className="font-medium">{application.merchant?.name || 'Merchant'}</span>
                  <Badge variant={application.status === 'ACTIVE' ? 'default' : 'secondary'}>{labels[application.status]}</Badge>
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
                <p><strong>Kriteria bisnis:</strong> {selected.business_criteria_code}</p>
                <p><strong>Lama usaha:</strong> {selected.business_age_code}</p>
                <p><strong>Nama QRIS (25):</strong> {selected.qris_merchant_name_short}</p>
                <p><strong>Nama QRIS (50):</strong> {selected.qris_merchant_name}</p>
                <p><strong>Bank default:</strong> {selected.default_bank_name || '—'}</p>
                <p><strong>Nomor akun:</strong> {selected.default_account_number || '—'}</p>
                <p><strong>Atas nama:</strong> {selected.default_account_name || '—'}</p>
              </div>

              <div>
                <h3 className="mb-3 font-semibold">Dokumen Merchant</h3>
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
                    <Button disabled={saving} onClick={() => void setStatus(selected, 'APPROVED_PENDING_ISSUANCE', 'Data dan dokumen telah diverifikasi.')}><CheckCircle2 className="mr-2 h-4 w-4" />Setujui</Button>
                  </div>
                </div>
              )}

              {selected.status === 'APPROVED_PENDING_ISSUANCE' && (
                <div className="space-y-3 rounded-lg border border-primary/20 p-4">
                  <h3 className="font-semibold">Pendaftaran Neo/GDC &amp; unggah QRIS statis</h3>
                  <p className="text-sm text-muted-foreground">Cocokkan toko dan data merchant di dashboard GDC sebelum menyimpan mapping. Data GDC hanya dipakai backend. QRIS MPM Dinamis belum aktif sampai admin mengaktifkannya setelah review.</p>
                  <div className="space-y-2">
                    <Label htmlFor="qris-reference">Nomor referensi QRIS</Label>
                    <Input id="qris-reference" value={qrisReference} onChange={(event) => setQrisReference(event.target.value)} maxLength={200} />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="gdc-merchant-id">GDC Merchant ID (MID)</Label>
                    <Input id="gdc-merchant-id" value={gdcMerchantId} onChange={(event) => setGdcMerchantId(event.target.value)} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="gdc-account-number">GDC Account Number</Label>
                    <Input id="gdc-account-number" value={gdcAccountNumber} onChange={(event) => setGdcAccountNumber(event.target.value)} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="space-y-2">
                    <Label>QRIS statis untuk merchant ini</Label>
                    <ImageUpload bucket="merchant-images" path={`qris/${selected.merchant_id}`} value={qrisImageUrl} onChange={setQrisImageUrl} placeholder="Unggah QRIS statis merchant" />
                  </div>
                  <Button disabled={saving || !qrisReference.trim() || !qrisImageUrl || !gdcMerchantId.trim() || !gdcAccountNumber.trim()} onClick={() => void issue(selected)}>Simpan QRIS — Menunggu Aktivasi</Button>
                </div>
              )}

              {selected.status === 'ISSUED_PENDING_ACTIVATION' && (
                <div className="space-y-4 rounded-lg border p-4">
                  <div>
                    <h3 className="font-semibold">Aktivasi QRIS &amp; mapping GDC</h3>
                    <p className="mt-1 text-sm text-muted-foreground">Referensi: <strong>{selected.qris_reference || '—'}</strong>. Cocokkan MID dan Account Number dengan toko ini. Menyimpan mapping tidak mengaktifkan QRIS MPM Dinamis; aktivasi MPM tetap menjadi langkah terpisah setelah QRIS Sadesa aktif.</p>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="pending-gdc-merchant-id">GDC Merchant ID (MID)</Label>
                    <Input id="pending-gdc-merchant-id" value={gdcMerchantId} onChange={(event) => setGdcMerchantId(event.target.value)} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="pending-gdc-account-number">GDC Account Number</Label>
                    <Input id="pending-gdc-account-number" value={gdcAccountNumber} onChange={(event) => setGdcAccountNumber(event.target.value)} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button variant="outline" disabled={saving || !gdcMerchantId.trim() || !gdcAccountNumber.trim()} onClick={() => void saveGdcMpmIdentity(selected)}>Simpan Mapping (MPM tetap nonaktif)</Button>
                    <Button disabled={saving} onClick={() => void activate(selected)}><ShieldCheck className="mr-2 h-4 w-4" />Aktifkan QRIS Sadesa</Button>
                  </div>
                </div>
              )}

              {selected.status === 'ACTIVE' && (
                <div className="space-y-4 rounded-lg border border-emerald-300 p-4">
                  <div>
                    <h3 className="font-semibold">QRIS MPM Dinamis GDC</h3>
                    <p className="mt-1 text-sm text-muted-foreground">Status: <strong>{selected.gdc_mpm_enabled ? 'Aktif' : 'Nonaktif'}</strong>. Mengubah mapping akan menonaktifkan QRIS Dinamis hingga diverifikasi dan diaktifkan ulang. Perubahan status dan mapping dicatat tanpa menyalin nilai MID/account ke log.</p>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="active-gdc-merchant-id">GDC Merchant ID (MID)</Label>
                    <Input id="active-gdc-merchant-id" value={gdcMerchantId} onChange={(event) => setGdcMerchantId(event.target.value)} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="active-gdc-account-number">GDC Account Number</Label>
                    <Input id="active-gdc-account-number" value={gdcAccountNumber} onChange={(event) => setGdcAccountNumber(event.target.value)} maxLength={100} autoComplete="off" />
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button variant="outline" disabled={saving || !gdcMerchantId.trim() || !gdcAccountNumber.trim()} onClick={() => void saveGdcMpmIdentity(selected)}>Simpan Mapping (Dinamis Dinonaktifkan)</Button>
                    <Button disabled={saving || (!selected.gdc_mpm_enabled && (!hasGdcIdentity || !mappingMatchesSelected))} variant={selected.gdc_mpm_enabled ? 'destructive' : 'default'} onClick={() => void setGdcMpmEnabled(selected, !selected.gdc_mpm_enabled)}>
                      {selected.gdc_mpm_enabled ? 'Nonaktifkan QRIS Dinamis' : 'Aktifkan QRIS Dinamis'}
                    </Button>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        )}
      </div>
    </AdminLayout>
  );
}
