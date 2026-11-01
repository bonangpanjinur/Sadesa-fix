import { useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle2, Clock3, Download, FileText, Loader2, QrCode, RefreshCw, ShieldCheck, XCircle } from 'lucide-react';
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
type QrisApplication = { id: string; application_number: string; merchant_id: string; applicant_user_id: string; default_account_id: string | null; default_bank_name: string | null; default_account_number: string | null; default_account_name: string | null; business_criteria_code: string; business_age_code: string; qris_merchant_name_short: string; qris_merchant_name: string; documents: Record<string,string>; status: AppStatus; decision_note: string | null; qris_reference: string | null; qris_asset_key: string | null; gdc_merchant_id: string | null; gdc_account_number: string | null; submitted_at: string; revision_number: number; merchant?: { name: string; city: string | null } | null };
type LegacyProfile = { merchant_id: string; provider_merchant_id: string; provider_account_number: string; status: string; merchant?: { name: string } | null };
// qris_applications is a newly introduced table not yet present in generated Supabase types.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const db = supabase as any;
const labels: Record<AppStatus,string> = { SUBMITTED:'Menunggu Verifikasi', IN_REVIEW:'Sedang Diverifikasi', NEEDS_CORRECTION:'Perlu Perbaikan', REJECTED:'Ditolak', APPROVED_PENDING_ISSUANCE:'Disetujui — Menunggu Penerbitan', ISSUED_PENDING_ACTIVATION:'Menunggu Aktivasi', ACTIVE:'QRIS Aktif' };
const docLabels: Record<string,string> = { OWNER_ID:'Foto KTP Pemilik', OWNER_SELFIE:'Foto Selfie Pemilik', BUSINESS_LOCATION:'Foto Lokasi Usaha', PRODUCT:'Foto Produk' };
const requiredDocumentCodes = Object.keys(docLabels);
const maskAccountNumber = (value: string) => value.length <= 4 ? '******' + value : '******' + value.slice(-4);

export default function AdminQrisApplicationsPage() {
  const { user } = useAuth();
  const [applications, setApplications] = useState<QrisApplication[]>([]);
  const [legacyProfiles, setLegacyProfiles] = useState<LegacyProfile[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [documentUrls, setDocumentUrls] = useState<Record<string,string>>({});
  const [correctionNote, setCorrectionNote] = useState('');
  const [qrisReference, setQrisReference] = useState('');
  const [qrisImageUrl, setQrisImageUrl] = useState<string | null>(null);
  const [gdcMerchantId, setGdcMerchantId] = useState('');
  const [gdcAccountNumber, setGdcAccountNumber] = useState('');
  const [businessCriteria, setBusinessCriteria] = useState('');
  const [businessAge, setBusinessAge] = useState('');
  const [qrisMerchantNameShort, setQrisMerchantNameShort] = useState('');
  const [qrisMerchantName, setQrisMerchantName] = useState('');
  const [defaultBankName, setDefaultBankName] = useState('');
  const [defaultAccountNumber, setDefaultAccountNumber] = useState('');
  const [defaultAccountName, setDefaultAccountName] = useState('');
  const [defaultAccountId, setDefaultAccountId] = useState('');
  const [merchantName, setMerchantName] = useState('');
  const [filter, setFilter] = useState('ALL');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [selectedLegacyMerchantIds, setSelectedLegacyMerchantIds] = useState<string[]>([]);
  const selected = applications.find((item) => item.id === selectedId) || null;
  const pendingCount = useMemo(() => applications.filter((item) => ['SUBMITTED','IN_REVIEW'].includes(item.status)).length, [applications]);

  const load = async () => {
    setLoading(true);
    try {
      const { data, error } = await db.rpc('admin_list_qris_applications');
      if (error) throw error;
      const nextApplications = (data || []) as QrisApplication[];
      setApplications(nextApplications);
      const applicationMerchantIds = new Set(nextApplications.map((item) => item.merchant_id));
      try {
        const { data: legacyData, error: legacyError } = await db.from('gdc_payment_profiles')
          .select('merchant_id,provider_merchant_id,provider_account_number,status,merchant:merchants(name)')
          .eq('provider', 'GDC')
          .order('updated_at', { ascending: false });
        if (legacyError) throw legacyError;
        setLegacyProfiles(((legacyData || []) as LegacyProfile[]).filter((item) => !applicationMerchantIds.has(item.merchant_id)));
      } catch (legacyError) {
        setLegacyProfiles([]);
        toast.error(`Daftar pengajuan sudah dimuat, tetapi profil GDC legacy gagal dimuat: ${legacyError instanceof Error ? legacyError.message : 'kesalahan tidak diketahui'}`);
      }
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
      setBusinessCriteria(selected.business_criteria_code || '');
      setBusinessAge(selected.business_age_code || '');
      setQrisMerchantNameShort(selected.qris_merchant_name_short || '');
      setQrisMerchantName(selected.qris_merchant_name || '');
      setDefaultBankName(selected.default_bank_name || '');
      setDefaultAccountNumber(selected.default_account_number || '');
      setDefaultAccountName(selected.default_account_name || '');
      setDefaultAccountId(selected.default_account_id || '');
      setMerchantName(selected.merchant?.name || '');
      setGdcMerchantId(selected.gdc_merchant_id || '');
      setGdcAccountNumber(selected.gdc_account_number || '');
      setQrisImageUrl(null);
      setCorrectionNote('');
    };
    void loadDocuments();
    return () => { active = false; };
  }, [selected]);

  const downloadDocument = async (path: string, label: string) => {
    try {
      const { data, error } = await supabase.storage.from('qris-applications').download(path);
      if (error || !data) throw error || new Error('File dokumen tidak tersedia.');
      const url = URL.createObjectURL(data);
      const link = document.createElement('a');
      const originalName = path.split('/').pop() || 'dokumen';
      link.href = url;
      link.download = `${label.toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${originalName}`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Dokumen gagal diunduh.');
    }
  };

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

  const saveApplicationDetails = async (application: QrisApplication) => {
    if (!user) return;
    const accountId = defaultAccountId.trim();
    if (accountId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(accountId)) {
      return toast.error('ID akun default harus UUID yang valid atau dikosongkan.');
    }
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_update_qris_application_details', {
        p_application_id: application.id,
        p_merchant_name: merchantName.trim(),
        p_default_account_id: accountId || null,
        p_business_criteria_code: businessCriteria,
        p_business_age_code: businessAge,
        p_qris_merchant_name_short: qrisMerchantNameShort,
        p_qris_merchant_name: qrisMerchantName,
        p_default_bank_name: defaultBankName,
        p_default_account_number: defaultAccountNumber,
        p_default_account_name: defaultAccountName,
        p_reason: 'Perubahan data dilakukan admin dari panel QRIS Merchant.',
      });
      if (error) throw error;
      toast.success('Data pengajuan QRIS diperbarui dan dicatat di aktivitas.');
      await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Data pengajuan QRIS gagal diperbarui.'); }
    finally { setSaving(false); }
  };

  const issue = async (application: QrisApplication) => {
    if (!user || !qrisReference.trim() || !qrisImageUrl || !gdcMerchantId.trim() || !gdcAccountNumber.trim()) return toast.error('Isi referensi, unggah file QRIS, dan masukkan Merchant ID serta Account Number GDC.');
    setSaving(true);
    try {
      const { error } = await db.rpc('admin_issue_qris_mpm', { p_application_id: application.id, p_qris_reference: qrisReference.trim(), p_qris_asset_key: qrisImageUrl, p_gdc_merchant_id: gdcMerchantId.trim(), p_gdc_account_number: gdcAccountNumber.trim() });
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
      toast.success('Identitas GDC tersimpan untuk QRIS merchant aktif.');
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

  const runLegacyImport = async (profile: LegacyProfile) => {
    const { data, error } = await db.rpc('admin_import_legacy_qris_application', {
      p_merchant_id: profile.merchant_id,
      p_gdc_merchant_id: profile.provider_merchant_id,
      p_gdc_account_number: profile.provider_account_number,
    });
    if (error) throw error;
    return data as { application_id?: string; created?: boolean } | null;
  };

  const importLegacyProfile = async (profile: LegacyProfile) => {
    if (!user) return;
    const confirmed = window.confirm(`Impor profil GDC legacy milik ${profile.merchant?.name || profile.merchant_id}?\n\nData akan dibuat sebagai pengajuan QRIS NEEDS_CORRECTION dan memerlukan kelengkapan serta review dokumen.`);
    if (!confirmed) return;
    setSaving(true);
    try {
      const data = await runLegacyImport(profile);
      toast.success(data?.created === false ? 'Merchant sudah memiliki pengajuan QRIS.' : 'Profil GDC legacy diimpor sebagai pengajuan QRIS. Lengkapi dokumen sebelum persetujuan.');
      await load();
      if (data?.application_id) setSelectedId(data.application_id);
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Import profil GDC legacy gagal.'); }
    finally { setSaving(false); }
  };

  const importSelectedLegacyProfiles = async () => {
    if (!user || selectedLegacyMerchantIds.length === 0) return;
    const selectedProfiles = legacyProfiles.filter((profile) => selectedLegacyMerchantIds.includes(profile.merchant_id));
    const confirmed = window.confirm(`Impor ${selectedProfiles.length} profil GDC legacy terpilih?\n\nSemua data akan dibuat sebagai pengajuan QRIS NEEDS_CORRECTION dan tetap memerlukan kelengkapan serta review dokumen.`);
    if (!confirmed) return;
    setSaving(true);
    let created = 0;
    let alreadyExists = 0;
    let failed = 0;
    const applicationIds: string[] = [];
    try {
      for (const profile of selectedProfiles) {
        try {
          const result = await runLegacyImport(profile);
          if (result?.created === false) alreadyExists += 1;
          else created += 1;
          if (result?.application_id) applicationIds.push(result.application_id);
        } catch {
          failed += 1;
        }
      }
      setSelectedLegacyMerchantIds([]);
      await load();
      if (applicationIds.length > 0) {
        setFilter('ALL');
        setSelectedId(applicationIds[0]);
      }
      toast.success(`Import selesai: ${created} berhasil, ${alreadyExists} sudah memiliki aplikasi, ${failed} gagal.`);
    } finally { setSaving(false); }
  };

  const shown = applications.filter((item) => filter === 'ALL' || item.status === filter);
  const missingDocuments = selected ? requiredDocumentCodes.filter((code) => !selected.documents?.[code]?.trim()) : [];
  const isLegacyImport = selected?.business_age_code === 'LEGACY_IMPORT_REQUIRES_REVIEW';
  return <AdminLayout title="QRIS Merchant" subtitle="Kelola pengajuan, penerbitan, aktivasi, dan kesiapan QRIS MPM dalam satu alur.">
    <div className="grid gap-4 xl:grid-cols-[minmax(300px,0.9fr)_minmax(0,1.5fr)]">
      <Card className="h-fit"><CardHeader><div className="flex items-center justify-between gap-2"><div><CardTitle className="flex items-center gap-2"><QrCode className="h-5 w-5" />Antrean Pengajuan</CardTitle><CardDescription>{pendingCount} pengajuan perlu ditangani</CardDescription></div><Button variant="outline" size="icon" onClick={() => void load()} aria-label="Muat ulang"><RefreshCw className="h-4 w-4" /></Button></div></CardHeader><CardContent className="space-y-3">
        {legacyProfiles.length > 0 && <div className="space-y-3 rounded-lg border border-amber-300 bg-amber-50 p-3"><div><p className="font-semibold text-amber-950">Profil GDC legacy perlu diimpor</p><p className="mt-1 text-xs text-amber-900">Import membuat pengajuan berstatus NEEDS_CORRECTION dan menyalin identifier GDC. Dokumen, review, penerbitan, dan aktivasi tetap wajib dilakukan.</p></div><div className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-amber-200 bg-white p-2"><label className="flex items-center gap-2 text-sm font-medium"><input type="checkbox" checked={selectedLegacyMerchantIds.length === legacyProfiles.length} onChange={(event) => setSelectedLegacyMerchantIds(event.target.checked ? legacyProfiles.map((profile) => profile.merchant_id) : [])} />Pilih semua ({legacyProfiles.length})</label><Button size="sm" disabled={saving || selectedLegacyMerchantIds.length === 0} onClick={() => void importSelectedLegacyProfiles()}>Impor terpilih ({selectedLegacyMerchantIds.length})</Button></div>{legacyProfiles.map((profile) => <div key={profile.merchant_id} className="flex items-center justify-between gap-2 rounded-md border border-amber-200 bg-white p-2"><label className="flex min-w-0 items-center gap-2"><input type="checkbox" checked={selectedLegacyMerchantIds.includes(profile.merchant_id)} onChange={(event) => setSelectedLegacyMerchantIds((current) => event.target.checked ? [...new Set([...current, profile.merchant_id])] : current.filter((id) => id !== profile.merchant_id))} /><span className="min-w-0"><span className="block truncate text-sm font-medium">{profile.merchant?.name || profile.merchant_id}</span><span className="block truncate text-[11px] text-muted-foreground">{profile.provider_merchant_id} · {maskAccountNumber(profile.provider_account_number)}</span></span></label><Button size="sm" variant="outline" disabled={saving} onClick={() => void importLegacyProfile(profile)}>Impor</Button></div>)}</div>}
        <select className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={filter} onChange={(event) => setFilter(event.target.value)}><option value="ALL">Semua status</option>{Object.entries(labels).map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select>
        {loading ? <div className="flex items-center gap-2 py-8 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />Memuat pengajuan…</div> : shown.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Belum ada pengajuan pada status ini.</p> : shown.map((application) => { const mpmReady = application.status === 'ACTIVE' && Boolean(application.gdc_merchant_id?.trim() && application.gdc_account_number?.trim()); return <button key={application.id} onClick={() => setSelectedId(application.id)} className={`w-full rounded-lg border p-3 text-left transition-colors ${selectedId === application.id ? 'border-primary bg-primary/5' : 'hover:bg-muted/60'}`}><div className="flex items-start justify-between gap-2"><span className="font-medium">{application.merchant?.name || 'Merchant'}</span><div className="flex flex-wrap justify-end gap-1"><Badge variant={application.status === 'ACTIVE' ? 'default' : 'secondary'}>{labels[application.status]}</Badge>{application.business_age_code === 'LEGACY_IMPORT_REQUIRES_REVIEW' && <Badge variant="outline">Legacy import</Badge>}{application.status === 'ACTIVE' && <Badge variant={mpmReady ? 'default' : 'destructive'}>{mpmReady ? 'MPM siap' : 'MPM belum siap'}</Badge>}</div></div><p className="mt-1 text-xs text-muted-foreground">{application.application_number} · {new Date(application.submitted_at).toLocaleDateString('id-ID')}</p><p className="mt-1 text-xs text-muted-foreground">{application.business_criteria_code} · {application.qris_merchant_name}</p></button>; })}
      </CardContent></Card>
      {!selected ? <Card><CardContent className="flex min-h-64 flex-col items-center justify-center gap-3 text-center text-muted-foreground"><FileText className="h-8 w-8" /><p>Pilih pengajuan untuk melihat data dan melakukan verifikasi.</p></CardContent></Card> : <Card><CardHeader><CardTitle>{selected.merchant?.name || 'Merchant'} <span className="text-sm font-normal text-muted-foreground">· {selected.application_number}</span></CardTitle><CardDescription>Revisi {selected.revision_number} · Diajukan {new Date(selected.submitted_at).toLocaleString('id-ID')}</CardDescription></CardHeader><CardContent className="space-y-5">
        {isLegacyImport && <div className="flex gap-3 rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950"><AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" /><div><p className="font-semibold">Legacy import — perlu dokumen</p><p className="mt-1">Aplikasi ini dibuat dari <code>gdc_payment_profiles</code>. Identifier GDC sudah disalin, tetapi dokumen merchant belum tersedia atau belum lengkap.</p></div></div>}
        {!['ACTIVE', 'ISSUED_PENDING_ACTIVATION'].includes(selected.status) && <div className="space-y-3 rounded-lg border border-primary/20 p-4"><div><h3 className="font-semibold">Edit data pengajuan</h3><p className="text-xs text-muted-foreground">Admin dapat membantu mengoreksi data sebelum QRIS diterbitkan. Semua perubahan dicatat.</p></div><div className="grid gap-3 sm:grid-cols-2"><div className="space-y-2"><Label>Nama merchant (profil toko)</Label><Input value={merchantName} onChange={(event) => setMerchantName(event.target.value)} maxLength={150} /></div><div className="space-y-2"><Label>ID akun default (UUID internal, opsional)</Label><Input value={defaultAccountId} onChange={(event) => setDefaultAccountId(event.target.value)} placeholder="Kosongkan jika belum ada" /></div><div className="space-y-2"><Label>Kriteria bisnis</Label><select className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={businessCriteria} onChange={(event) => setBusinessCriteria(event.target.value)}><option value="">Pilih kriteria</option><option value="UMI">UMI</option><option value="UME">UME</option><option value="UBE">UBE</option></select></div><div className="space-y-2"><Label>Lama usaha</Label><Input value={businessAge} onChange={(event) => setBusinessAge(event.target.value)} maxLength={80} /></div><div className="space-y-2"><Label>Nama QRIS pendek (maks. 25)</Label><Input value={qrisMerchantNameShort} onChange={(event) => setQrisMerchantNameShort(event.target.value)} maxLength={25} /></div><div className="space-y-2"><Label>Nama QRIS (maks. 50)</Label><Input value={qrisMerchantName} onChange={(event) => setQrisMerchantName(event.target.value)} maxLength={50} /></div><div className="space-y-2"><Label>Bank</Label><Input value={defaultBankName} onChange={(event) => setDefaultBankName(event.target.value)} /></div><div className="space-y-2"><Label>Nomor rekening</Label><Input value={defaultAccountNumber} onChange={(event) => setDefaultAccountNumber(event.target.value)} /></div><div className="space-y-2 sm:col-span-2"><Label>Nama pemilik rekening</Label><Input value={defaultAccountName} onChange={(event) => setDefaultAccountName(event.target.value)} /></div></div><Button variant="outline" disabled={saving} onClick={() => void saveApplicationDetails(selected)}>Simpan koreksi data</Button></div>}
        <div className="grid gap-3 rounded-lg bg-muted/50 p-4 text-sm sm:grid-cols-2"><p><strong>Nama merchant:</strong> {selected.merchant?.name || '—'}</p><p><strong>ID akun default:</strong> {selected.default_account_id || '—'}</p><p><strong>Kriteria bisnis:</strong> {selected.business_criteria_code}</p><p><strong>Lama usaha:</strong> {selected.business_age_code}</p><p><strong>Nama QRIS (25):</strong> {selected.qris_merchant_name_short}</p><p><strong>Nama QRIS (50):</strong> {selected.qris_merchant_name}</p><p><strong>Bank default:</strong> {selected.default_bank_name || '—'}</p><p><strong>Nomor akun:</strong> {selected.default_account_number || '—'}</p><p><strong>Atas nama:</strong> {selected.default_account_name || '—'}</p><p><strong>Kesiapan QRIS MPM:</strong> {selected.status === 'ACTIVE' && selected.gdc_merchant_id?.trim() && selected.gdc_account_number?.trim() ? <span className="font-semibold text-emerald-700">Siap digunakan</span> : <span className="font-semibold text-amber-700">Belum siap — lengkapi aktivasi dan identitas GDC</span>}</p></div>
        <div><h3 className="mb-3 font-semibold">Dokumen Merchant</h3><div className="grid gap-3 sm:grid-cols-2">{Object.entries(docLabels).map(([type,label]) => <div key={type} className="rounded-lg border p-3"><p className="mb-2 text-sm font-medium">{label}</p>{documentUrls[type] ? <div className="flex flex-wrap items-center gap-3"><a href={documentUrls[type]} target="_blank" rel="noreferrer" className="text-sm text-primary underline">Lihat dokumen</a><Button type="button" variant="outline" size="sm" onClick={() => void downloadDocument(selected.documents[type], label)}><Download className="mr-2 h-4 w-4" />Unduh</Button></div> : <p className="text-xs text-destructive">Dokumen tidak ditemukan</p>}</div>)}</div></div>
        {selected.decision_note && <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm"><strong>Catatan sebelumnya:</strong> {selected.decision_note}</div>}
        {selected.status === 'SUBMITTED' && missingDocuments.length > 0 && <p className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">Setujui dinonaktifkan. Lengkapi dokumen wajib: {missingDocuments.map((code) => docLabels[code]).join(', ')}.</p>}
        {['SUBMITTED','IN_REVIEW'].includes(selected.status) && <div className="space-y-3 rounded-lg border p-4"><h3 className="font-semibold">Keputusan Verifikasi</h3><Textarea value={correctionNote} onChange={(event) => setCorrectionNote(event.target.value)} placeholder="Catatan untuk merchant, wajib untuk permintaan perbaikan atau penolakan" /><div className="flex flex-wrap gap-2"><Button variant="outline" disabled={saving} onClick={() => void setStatus(selected, 'IN_REVIEW', 'REVIEW_STARTED')}><Clock3 className="mr-2 h-4 w-4" />Mulai Verifikasi</Button><Button variant="outline" disabled={saving || correctionNote.trim().length < 8} onClick={() => void setStatus(selected, 'NEEDS_CORRECTION', 'CORRECTION_REQUESTED', correctionNote)}><FileText className="mr-2 h-4 w-4" />Minta Perbaikan</Button><Button variant="destructive" disabled={saving || correctionNote.trim().length < 8} onClick={() => void setStatus(selected, 'REJECTED', 'APPLICATION_REJECTED', correctionNote)}><XCircle className="mr-2 h-4 w-4" />Tolak</Button><Button disabled={saving || missingDocuments.length > 0} title={missingDocuments.length > 0 ? `Lengkapi dokumen: ${missingDocuments.map((code) => docLabels[code]).join(', ')}` : undefined} onClick={() => void setStatus(selected, 'APPROVED_PENDING_ISSUANCE', 'APPLICATION_APPROVED', 'Data dan dokumen telah diverifikasi.')}><CheckCircle2 className="mr-2 h-4 w-4" />Setujui</Button></div></div>}
        {selected.status === 'APPROVED_PENDING_ISSUANCE' && <div className="space-y-3 rounded-lg border border-primary/20 p-4"><h3 className="font-semibold">Penerbitan QRIS dan identitas GDC</h3><p className="text-sm text-muted-foreground">Identitas ini digunakan server untuk membuat QR MPM dinamis dan tidak ditampilkan kepada pembeli.</p><div className="space-y-2"><Label>Nomor referensi QRIS</Label><Input value={qrisReference} onChange={(event) => setQrisReference(event.target.value)} placeholder="Masukkan ID/referensi penerbitan" /></div><div className="grid gap-3 sm:grid-cols-2"><div className="space-y-2"><Label>GDC Merchant ID</Label><Input value={gdcMerchantId} onChange={(event) => setGdcMerchantId(event.target.value)} autoComplete="off" /></div><div className="space-y-2"><Label>GDC Account Number</Label><Input value={gdcAccountNumber} onChange={(event) => setGdcAccountNumber(event.target.value)} autoComplete="off" /></div></div><div className="space-y-2"><Label>Gambar QRIS referensi</Label><ImageUpload bucket="merchant-images" path={`qris/${selected.merchant_id}`} value={qrisImageUrl} onChange={setQrisImageUrl} placeholder="Unggah QRIS referensi" /></div><Button disabled={saving} onClick={() => void issue(selected)}>Simpan Penerbitan — Menunggu Aktivasi</Button></div>}
        {selected.status === 'ISSUED_PENDING_ACTIVATION' && <div className="rounded-lg border p-4"><p className="mb-3 text-sm">Referensi: <strong>{selected.qris_reference || '—'}</strong>. Pastikan QRIS tertaut ke merchant yang benar sebelum aktivasi.</p><p className="mb-3 text-sm">GDC Merchant ID: <strong>{selected.gdc_merchant_id || '—'}</strong> · Account Number: <strong>{selected.gdc_account_number ? 'Tersimpan' : '—'}</strong></p><Button disabled={saving} onClick={() => void activate(selected)}><ShieldCheck className="mr-2 h-4 w-4" />Aktifkan QRIS</Button></div>}
        {selected.status === 'ACTIVE' && <div className="space-y-3 rounded-lg border border-emerald-300 bg-emerald-50 p-4"><p className="text-sm font-medium text-emerald-800">QRIS sudah aktif. Penetapan QRIS tetap dikelola oleh admin.</p><div className="grid gap-3 sm:grid-cols-2"><div className="space-y-2"><Label>GDC Merchant ID</Label><Input value={gdcMerchantId} onChange={(event) => setGdcMerchantId(event.target.value)} autoComplete="off" /></div><div className="space-y-2"><Label>GDC Account Number</Label><Input value={gdcAccountNumber} onChange={(event) => setGdcAccountNumber(event.target.value)} autoComplete="off" /></div></div><p className="text-xs text-emerald-900">{selected.gdc_merchant_id && selected.gdc_account_number ? 'Identitas GDC sudah disiapkan.' : 'Belum ada identitas GDC; simpan data yang diberikan acquirer agar QRIS dinamis tersedia.'}</p><Button disabled={saving} onClick={() => void saveActiveMpmIdentity(selected)}>Simpan Identitas GDC</Button></div>}
      </CardContent></Card>}
    </div>
  </AdminLayout>;
}
