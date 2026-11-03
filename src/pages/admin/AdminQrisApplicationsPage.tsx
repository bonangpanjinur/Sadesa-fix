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

type AppStatus = 'SUBMITTED' | 'IN_REVIEW' | 'NEEDS_CORRECTION' | 'REJECTED' | 'APPROVED_PENDING_ISSUANCE' | 'ISSUED_PENDING_ACTIVATION' | 'ACTIVE';
type QrisApplication = { id: string; application_number: string; merchant_id: string; applicant_user_id: string; default_bank_name: string | null; default_account_number: string | null; default_account_name: string | null; business_criteria_code: string; business_age_code: string; qris_merchant_name_short: string; qris_merchant_name: string; documents: Record<string,string>; status: AppStatus; decision_note: string | null; qris_reference: string | null; qris_asset_key: string | null; gdc_merchant_id: string | null; gdc_account_number: string | null; submitted_at: string; revision_number: number; merchant?: { name: string; city: string | null } | null };
// qris_applications is a newly introduced table not yet present in generated Supabase types.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const db = supabase as any;
const labels: Record<AppStatus,string> = { SUBMITTED:'Menunggu Verifikasi', IN_REVIEW:'Sedang Diverifikasi', NEEDS_CORRECTION:'Perlu Perbaikan', REJECTED:'Ditolak', APPROVED_PENDING_ISSUANCE:'Disetujui — Menunggu Penerbitan', ISSUED_PENDING_ACTIVATION:'Menunggu Aktivasi', ACTIVE:'QRIS Aktif' };
const docLabels: Record<string,string> = { OWNER_ID:'Foto KTP Pemilik', OWNER_SELFIE:'Foto Selfie Pemilik', BUSINESS_LOCATION:'Foto Lokasi Usaha', PRODUCT:'Foto Produk' };

export default function AdminQrisApplicationsPage() {
  const { user } = useAuth();
  const [applications, setApplications] = useState<QrisApplication[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [documentUrls, setDocumentUrls] = useState<Record<string,string>>({});
  const [correctionNote, setCorrectionNote] = useState('');
  const [qrisReference, setQrisReference] = useState('');
  const [gdcMerchantId, setGdcMerchantId] = useState('');
  const [gdcAccountNumber, setGdcAccountNumber] = useState('');
  const [filter, setFilter] = useState('ALL');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const selected = applications.find((item) => item.id === selectedId) || null;
  const pendingCount = useMemo(() => applications.filter((item) => ['SUBMITTED','IN_REVIEW'].includes(item.status)).length, [applications]);

  const load = async () => {
    setLoading(true);
    try {
      const { data, error } = await db.from('qris_applications').select('*, merchant:merchants(name,city)').order('submitted_at', { ascending: false });
      if (error) throw error;
      setApplications((data || []) as QrisApplication[]);
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Daftar pengajuan QRIS gagal dimuat.'); }
    finally { setLoading(false); }
  };
  useEffect(() => { void load(); }, []);
  useEffect(() => {
    let active = true;
    const loadDocuments = async () => {
      if (!selected) { setDocumentUrls({}); return; }
      const pairs = await Promise.all(Object.entries(selected.documents || {}).map(async ([type,path]) => {
        const { data } = await supabase.storage.from('qris-applications').createSignedUrl(path, 300);
        return [type, data?.signedUrl || ''] as const;
      }));
      if (active) setDocumentUrls(Object.fromEntries(pairs));
      setQrisReference(selected.qris_reference || '');
      setGdcMerchantId(selected.gdc_merchant_id || '');
      setGdcAccountNumber(selected.gdc_account_number || '');
      setCorrectionNote('');
    };
    void loadDocuments();
    return () => { active = false; };
  }, [selected]);

  const setStatus = async (application: QrisApplication, status: AppStatus, action: string, note?: string) => {
    if (!user) return;
    setSaving(true);
    try {
      const patch: Record<string,unknown> = { status, updated_at: new Date().toISOString() };
      if (['REJECTED','NEEDS_CORRECTION'].includes(status)) patch.decision_note = note?.trim();
      if (status === 'IN_REVIEW') patch.assigned_admin_id = user.id;
      if (status === 'REJECTED' || status === 'APPROVED_PENDING_ISSUANCE') { patch.decision_by_admin_id = user.id; patch.decision_note = note?.trim() || null; }
      const { error } = await db.from('qris_applications').update(patch).eq('id', application.id);
      if (error) throw error;
      toast.success(`Status diperbarui: ${labels[status]}`);
      await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Perubahan status gagal disimpan.'); }
    finally { setSaving(false); }
  };

  const issue = async (application: QrisApplication) => {
    if (!user || !gdcMerchantId.trim() || !gdcAccountNumber.trim()) return toast.error('Masukkan NMID/Merchant ID dan Account Number GDC. Referensi pendaftaran bersifat opsional.');
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_issue_qris_mpm', { p_application_id: application.id, p_qris_reference: qrisReference.trim() || null, p_qris_asset_key: null, p_gdc_merchant_id: gdcMerchantId.trim(), p_gdc_account_number: gdcAccountNumber.trim() });
      if (error) throw error;
      toast.success('QRIS Sadesa dicatat dan menunggu aktivasi akhir.');
      await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Penerbitan QRIS gagal disimpan.'); }
    finally { setSaving(false); }
  };

  const saveActiveMpmIdentity = async (application: QrisApplication) => {
    if (!user || !gdcMerchantId.trim() || !gdcAccountNumber.trim()) return toast.error('Merchant ID dan Account Number GDC wajib diisi.');
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_configure_qris_mpm', {
        p_application_id: application.id,
        p_gdc_merchant_id: gdcMerchantId.trim(),
        p_gdc_account_number: gdcAccountNumber.trim(),
      });
      if (error) throw error;
      toast.success('Identitas GDC tersimpan untuk QRIS MPM dinamis.');
      await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Identitas GDC gagal disimpan.'); }
    finally { setSaving(false); }
  };

  const activate = async (application: QrisApplication) => {
    if (!user) return;
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_activate_qris', { p_application_id: application.id });
      if (error) throw error;
      toast.success('QRIS Sadesa aktif untuk merchant.');
      await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Aktivasi QRIS gagal.'); }
    finally { setSaving(false); }
  };

  const shown = applications.filter((item) => filter === 'ALL' || item.status === filter);
  return <AdminLayout title="Pengajuan QRIS Sadesa" subtitle="Verifikasi data merchant Neo/GDC lalu aktifkan QRIS MPM dinamis; unggahan QRIS statis tidak diperlukan.">
    <div className="grid gap-4 xl:grid-cols-[minmax(300px,0.9fr)_minmax(0,1.5fr)]">
      <Card className="h-fit"><CardHeader><div className="flex items-center justify-between gap-2"><div><CardTitle className="flex items-center gap-2"><QrCode className="h-5 w-5" />Antrean Pengajuan</CardTitle><CardDescription>{pendingCount} pengajuan perlu ditangani</CardDescription></div><Button variant="outline" size="icon" onClick={() => void load()} aria-label="Muat ulang"><RefreshCw className="h-4 w-4" /></Button></div></CardHeader><CardContent className="space-y-3">
        <select className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={filter} onChange={(event) => setFilter(event.target.value)}><option value="ALL">Semua status</option>{Object.entries(labels).map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select>
        {loading ? <div className="flex items-center gap-2 py-8 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />Memuat pengajuan…</div> : shown.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Belum ada pengajuan pada status ini.</p> : shown.map((application) => <button key={application.id} onClick={() => setSelectedId(application.id)} className={`w-full rounded-lg border p-3 text-left transition-colors ${selectedId === application.id ? 'border-primary bg-primary/5' : 'hover:bg-muted/60'}`}><div className="flex items-start justify-between gap-2"><span className="font-medium">{application.merchant?.name || 'Merchant'}</span><Badge variant={application.status === 'ACTIVE' ? 'default' : 'secondary'}>{labels[application.status]}</Badge></div><p className="mt-1 text-xs text-muted-foreground">{application.application_number} · {new Date(application.submitted_at).toLocaleDateString('id-ID')}</p><p className="mt-1 text-xs text-muted-foreground">{application.business_criteria_code} · {application.qris_merchant_name}</p></button>)}
      </CardContent></Card>
      {!selected ? <Card><CardContent className="flex min-h-64 flex-col items-center justify-center gap-3 text-center text-muted-foreground"><FileText className="h-8 w-8" /><p>Pilih pengajuan untuk melihat data dan melakukan verifikasi.</p></CardContent></Card> : <Card><CardHeader><CardTitle>{selected.merchant?.name || 'Merchant'} <span className="text-sm font-normal text-muted-foreground">· {selected.application_number}</span></CardTitle><CardDescription>Revisi {selected.revision_number} · Diajukan {new Date(selected.submitted_at).toLocaleString('id-ID')}</CardDescription></CardHeader><CardContent className="space-y-5">
        <div className="grid gap-3 rounded-lg bg-muted/50 p-4 text-sm sm:grid-cols-2"><p><strong>Kriteria bisnis:</strong> {selected.business_criteria_code}</p><p><strong>Lama usaha:</strong> {selected.business_age_code}</p><p><strong>Nama QRIS (25):</strong> {selected.qris_merchant_name_short}</p><p><strong>Nama QRIS (50):</strong> {selected.qris_merchant_name}</p><p><strong>Bank default:</strong> {selected.default_bank_name || '—'}</p><p><strong>Nomor akun:</strong> {selected.default_account_number || '—'}</p><p><strong>Atas nama:</strong> {selected.default_account_name || '—'}</p></div>
        <div><h3 className="mb-3 font-semibold">Dokumen Merchant</h3><div className="grid gap-3 sm:grid-cols-2">{Object.entries(docLabels).map(([type,label]) => <div key={type} className="rounded-lg border p-3"><p className="mb-2 text-sm font-medium">{label}</p>{documentUrls[type] ? <a href={documentUrls[type]} target="_blank" rel="noreferrer" className="text-sm text-primary underline">Lihat dokumen (tautan berlaku 5 menit)</a> : <p className="text-xs text-destructive">Dokumen tidak ditemukan</p>}</div>)}</div></div>
        {selected.decision_note && <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm"><strong>Catatan sebelumnya:</strong> {selected.decision_note}</div>}
        {['SUBMITTED','IN_REVIEW'].includes(selected.status) && <div className="space-y-3 rounded-lg border p-4"><h3 className="font-semibold">Keputusan Verifikasi</h3><Textarea value={correctionNote} onChange={(event) => setCorrectionNote(event.target.value)} placeholder="Catatan untuk merchant, wajib untuk permintaan perbaikan atau penolakan" /><div className="flex flex-wrap gap-2"><Button variant="outline" disabled={saving} onClick={() => void setStatus(selected, 'IN_REVIEW', 'REVIEW_STARTED')}><Clock3 className="mr-2 h-4 w-4" />Mulai Verifikasi</Button><Button variant="outline" disabled={saving || correctionNote.trim().length < 8} onClick={() => void setStatus(selected, 'NEEDS_CORRECTION', 'CORRECTION_REQUESTED', correctionNote)}><FileText className="mr-2 h-4 w-4" />Minta Perbaikan</Button><Button variant="destructive" disabled={saving || correctionNote.trim().length < 8} onClick={() => void setStatus(selected, 'REJECTED', 'APPLICATION_REJECTED', correctionNote)}><XCircle className="mr-2 h-4 w-4" />Tolak</Button><Button disabled={saving} onClick={() => void setStatus(selected, 'APPROVED_PENDING_ISSUANCE', 'APPLICATION_APPROVED', 'Data dan dokumen telah diverifikasi.')}><CheckCircle2 className="mr-2 h-4 w-4" />Setujui</Button></div></div>}
        {selected.status === 'APPROVED_PENDING_ISSUANCE' && <div className="space-y-3 rounded-lg border border-primary/20 p-4"><h3 className="font-semibold">Aktivasi merchant Neo/GDC untuk QRIS MPM dinamis</h3><p className="text-sm text-muted-foreground">Tim Desa mendaftarkan merchant ini secara manual ke Neo/GDC. Masukkan NMID/Merchant ID dan Account Number yang diberikan Neo/GDC (bukan nomor rekening bank default). QR unik untuk setiap pesanan akan dibuat backend; Anda tidak perlu mengunggah QRIS statis.</p><div className="space-y-2"><Label htmlFor="gdc-merchant-id">NMID / Merchant ID Neo-GDC</Label><Input id="gdc-merchant-id" value={gdcMerchantId} onChange={(event) => setGdcMerchantId(event.target.value)} autoComplete="off" placeholder="Masukkan NMID / Merchant ID dari GDC" /></div><div className="space-y-2"><Label htmlFor="gdc-account-number">Account Number GDC</Label><Input id="gdc-account-number" value={gdcAccountNumber} onChange={(event) => setGdcAccountNumber(event.target.value)} autoComplete="off" placeholder="Nomor akun collection yang diberikan GDC" /></div><div className="space-y-2"><Label>Referensi pendaftaran Neo/GDC (opsional)</Label><Input value={qrisReference} onChange={(event) => setQrisReference(event.target.value)} placeholder="Masukkan referensi jika diberikan Neo/GDC" /></div><Button disabled={saving} onClick={() => void issue(selected)}>Simpan Identitas GDC — Menunggu Aktivasi</Button></div>}
        {selected.status === 'ISSUED_PENDING_ACTIVATION' && <div className="rounded-lg border p-4"><p className="mb-3 text-sm">Periksa NMID/Merchant ID dan Account Number Neo/GDC sebelum aktivasi. Referensi pendaftaran: <strong>{selected.qris_reference || '—'}</strong>. QRIS statis tidak diperlukan untuk MPM dinamis.</p><Button disabled={saving} onClick={() => void activate(selected)}><ShieldCheck className="mr-2 h-4 w-4" />Aktifkan QRIS</Button></div>}
        {selected.status === 'ACTIVE' && <div className="space-y-3 rounded-lg border border-emerald-300 bg-emerald-50 p-4"><p className="text-sm font-medium text-emerald-800">QRIS MPM dinamis aktif. Identitas berikut digunakan backend untuk membuat QR setiap pesanan; konfigurasi ini terpisah dari nomor rekening bank default merchant.</p><div className="space-y-2"><Label htmlFor="gdc-merchant-id">NMID / Merchant ID Neo-GDC</Label><Input id="gdc-merchant-id" value={gdcMerchantId} onChange={(event) => setGdcMerchantId(event.target.value)} autoComplete="off" placeholder="Masukkan NMID / Merchant ID dari GDC" /></div><div className="space-y-2"><Label htmlFor="gdc-account-number">Account Number GDC</Label><Input id="gdc-account-number" value={gdcAccountNumber} onChange={(event) => setGdcAccountNumber(event.target.value)} autoComplete="off" placeholder="Nomor akun collection yang diberikan GDC" /></div><Button disabled={saving} onClick={() => void saveActiveMpmIdentity(selected)}>Simpan Identitas QR MPM</Button></div>}
      </CardContent></Card>}
    </div>
  </AdminLayout>;
}
