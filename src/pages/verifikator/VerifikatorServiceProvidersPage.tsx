import { useState } from 'react';
import { Check, Wrench, X } from 'lucide-react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { VerifikatorLayout } from '@/components/verifikator/VerifikatorLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

interface ProviderApplication {
  id: string;
  provider_id: string;
  provider_name: string;
  headline: string;
  bio: string | null;
  village: string | null;
  phone: string | null;
  min_price: number;
  verification_status: string;
  verifikator_code: string | null;
  created_at: string;
  service_skills?: { subcategory_id: string; service_subcategories?: { name: string } | null }[];
}

const money = (amount: number) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Number(amount || 0));

export default function VerifikatorServiceProvidersPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [notes, setNotes] = useState<Record<string, string>>({});
  const { data: applications = [], isLoading } = useQuery<ProviderApplication[]>({
    queryKey: ['verifikator-service-providers', user?.id],
    enabled: Boolean(user),
    staleTime: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase.from('service_profiles')
        .select('id,provider_id,provider_name,headline,bio,village,phone,min_price,verification_status,verifikator_code,created_at,service_skills(subcategory_id,service_subcategories(name))')
        .eq('verification_status', 'PENDING')
        .not('verifikator_code', 'is', null)
        .order('created_at', { ascending: true });
      if (error) throw error;
      return (data || []) as unknown as ProviderApplication[];
    },
  });

  const reviewMutation = useMutation({
    mutationFn: async ({ profileId, decision, note }: { profileId: string; decision: 'VERIFIED' | 'REJECTED'; note: string }) => {
      const { error } = await supabase.rpc('service_admin_review_provider', {
        p_profile_id: profileId,
        p_decision: decision,
        p_note: note.trim() || null,
      } as never);
      if (error) throw error;
    },
    onSuccess: (_data, variables) => {
      toast.success(variables.decision === 'VERIFIED' ? 'Penyedia jasa berhasil diverifikasi.' : 'Pendaftaran penyedia ditolak.');
      setNotes((current) => ({ ...current, [variables.profileId]: '' }));
      void queryClient.invalidateQueries({ queryKey: ['verifikator-service-providers', user?.id] });
      void queryClient.invalidateQueries({ queryKey: ['service-providers'] });
    },
    onError: (error: Error) => toast.error(error.message || 'Tidak dapat memproses pendaftaran. Pastikan pendaftar memakai kode referral Anda.'),
  });

  return <VerifikatorLayout title="Penyedia Jasa" subtitle="Pendaftar yang menggunakan kode referral Anda">
    <Card className="mb-4 border-primary/20 bg-primary/5"><CardContent className="flex items-start gap-3 p-4 text-sm"><Wrench className="mt-0.5 h-5 w-5 shrink-0 text-primary" /><p>Hanya pendaftar dengan kode referral aktif milik Anda yang dapat ditinjau. Keputusan akan divalidasi ulang dan dicatat oleh database.</p></CardContent></Card>
    <div className="mb-4 text-sm text-muted-foreground">{applications.length} pendaftaran menunggu</div>
    {isLoading ? <Card><CardContent className="py-12 text-center text-sm text-muted-foreground">Memuat antrean pendaftaran...</CardContent></Card> : applications.length === 0 ? <Card><CardContent className="py-12 text-center text-sm text-muted-foreground">Belum ada pendaftaran jasa yang memakai kode Anda.</CardContent></Card> : <div className="space-y-4">{applications.map((application) => <Card key={application.id}><CardContent className="space-y-4 p-4 sm:p-5">
      <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-lg font-bold">{application.provider_name}</p><p className="text-sm text-muted-foreground">{application.headline}</p></div><Badge variant="outline" className="font-mono">Kode {application.verifikator_code}</Badge></div>
      <div className="grid gap-3 text-sm sm:grid-cols-2"><div><p className="text-muted-foreground">Kontak</p><p>{application.phone || '-'}</p></div><div><p className="text-muted-foreground">Area dan tarif minimum</p><p>{application.village || '-'} · {money(application.min_price)}</p></div></div>
      <div><p className="mb-1 text-sm font-medium">Keahlian</p><div className="flex flex-wrap gap-2">{application.service_skills?.map((skill) => <Badge key={skill.subcategory_id} variant="secondary">{skill.service_subcategories?.name || 'Keahlian'}</Badge>)}</div></div>
      {application.bio && <p className="whitespace-pre-wrap text-sm text-muted-foreground">{application.bio}</p>}
      <div className="space-y-2"><label htmlFor={`review-note-${application.id}`} className="text-sm font-medium">Catatan verifikasi</label><Textarea id={`review-note-${application.id}`} value={notes[application.id] || ''} onChange={(event) => setNotes((current) => ({ ...current, [application.id]: event.target.value }))} maxLength={1000} placeholder="Opsional untuk persetujuan; wajib minimal 3 karakter jika menolak" /></div>
      <div className="flex flex-wrap justify-end gap-2"><Button variant="destructive" disabled={reviewMutation.isPending || (notes[application.id] || '').trim().length < 3} onClick={() => reviewMutation.mutate({ profileId: application.id, decision: 'REJECTED', note: notes[application.id] || '' })}><X className="mr-2 h-4 w-4" />Tolak pendaftaran</Button><Button disabled={reviewMutation.isPending} onClick={() => reviewMutation.mutate({ profileId: application.id, decision: 'VERIFIED', note: notes[application.id] || '' })}><Check className="mr-2 h-4 w-4" />Setujui & aktifkan</Button></div>
    </CardContent></Card>)}</div>}
  </VerifikatorLayout>;
}
