import { useNavigate } from 'react-router-dom';
import { safeGoBack } from '@/lib/utils';
import { ArrowLeft, Building2, Mail, MapPin, MessageCircle, Phone, RefreshCw } from 'lucide-react';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { whatsappHref } from '@/config/businessProfile';
import { useBusinessProfile } from '@/hooks/useBusinessProfile';

const FAQ_ITEMS = [
  {
    q: 'Bagaimana cara memesan produk?',
    a: 'Pilih produk yang diinginkan, tambahkan ke keranjang, lalu lanjutkan ke checkout. Isi alamat pengiriman dan pilih metode pembayaran.',
  },
  {
    q: 'Berapa lama pengiriman pesanan?',
    a: 'Estimasi pengiriman tergantung jarak antara toko dan alamat Anda. Umumnya 1-3 hari untuk area lokal.',
  },
  {
    q: 'Bagaimana cara membatalkan pesanan?',
    a: 'Buka halaman Pesanan Saya, pilih pesanan yang ingin dibatalkan, lalu klik tombol "Batalkan Pesanan". Pembatalan hanya bisa dilakukan sebelum pesanan diproses.',
  },
  {
    q: 'Metode pembayaran apa saja yang tersedia?',
    a: 'Kami menerima transfer bank, QRIS, dan COD (bayar di tempat) untuk area tertentu.',
  },
  {
    q: 'Bagaimana cara menjadi merchant/pedagang?',
    a: 'Buka menu Akun → Bergabung Bersama Kami → Daftar Sebagai Pedagang. Lengkapi data yang diperlukan dan tunggu persetujuan admin.',
  },
  {
    q: 'Bagaimana cara mengajukan refund?',
    a: 'Buka detail pesanan, klik "Ajukan Pengembalian", isi alasan dan lampirkan bukti foto jika diperlukan.',
  },
  {
    q: 'Apakah semua produk halal?',
    a: 'Kami mengutamakan produk halal. Cek badge sertifikat halal pada setiap produk untuk memastikan status halalnya.',
  },
];

export default function HelpPage() {
  const navigate = useNavigate();
  const { profile, loading: isLoadingContact, error: contactError, refetch: fetchContact } = useBusinessProfile();
  const whatsappUrl = whatsappHref(profile.whatsapp);

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />

      <main className="flex-1 overflow-y-auto pb-[var(--bottom-nav-space)]">
        <div className="px-4 py-4 sm:px-5 sm:py-5">
          <button
            type="button"
            onClick={() => safeGoBack(navigate)}
            className="mb-4 inline-flex min-h-11 items-center gap-2 rounded-lg px-2 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <ArrowLeft className="h-4 w-4" />
            <span>Kembali</span>
          </button>

          <header className="mb-5">
            <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-primary">Bantuan & kontak</p>
            <h1 className="mt-1 text-xl font-bold text-foreground sm:text-2xl">Pusat Bantuan</h1>
            <p className="mt-1 text-sm text-muted-foreground">Temukan jawaban atau hubungi tim SaDesa.</p>
          </header>

          <Card className="mb-5 border-emerald-200 bg-emerald-50/60 dark:border-emerald-900 dark:bg-emerald-950/20">
            <CardHeader className="pb-3"><CardTitle className="flex items-center gap-2 text-base"><Building2 className="h-5 w-5 text-primary" /> Informasi usaha</CardTitle></CardHeader>
            <CardContent className="space-y-3 text-sm">
              <div><p className="text-xs text-muted-foreground">Badan usaha</p><p className="font-semibold">{profile.legalName}</p></div>
              <div className="flex gap-2"><MapPin className="mt-0.5 h-4 w-4 shrink-0 text-primary" /><div><p className="text-xs text-muted-foreground">Alamat operasional</p><p>{profile.address}</p></div></div>
              {profile.phone && <div className="flex gap-2"><Phone className="mt-0.5 h-4 w-4 shrink-0 text-primary" /><div><p className="text-xs text-muted-foreground">Telepon</p><a href={`tel:${profile.phone}`} className="font-medium hover:underline">{profile.phone}</a></div></div>}
              <div><p className="text-xs text-muted-foreground">Jam operasional</p><p>{profile.operatingHours}</p></div>
            </CardContent>
          </Card>

          <Card className="mb-5 border-primary/15 bg-primary/[0.03]">
            <CardHeader className="pb-3">
              <CardTitle className="text-base">Butuh bantuan langsung?</CardTitle>
              <p className="text-sm text-muted-foreground">Pilih kanal yang paling nyaman untuk Anda.</p>
            </CardHeader>
            <CardContent className="space-y-3">
              {isLoadingContact ? (
                <div className="rounded-xl border border-border bg-background p-3 text-sm text-muted-foreground" aria-live="polite">Memuat kontak bantuan...</div>
              ) : contactError && !profile.whatsapp && !profile.email ? (
                <div className="rounded-xl border border-destructive/20 bg-destructive/5 p-3">
                  <p className="text-sm text-destructive">Kontak bantuan belum tersedia.</p>
                  <Button type="button" variant="outline" size="sm" onClick={() => void fetchContact()} className="mt-3 min-h-10 gap-2">
                    <RefreshCw className="h-4 w-4" /> Coba lagi
                  </Button>
                </div>
              ) : (
                <>
                  {whatsappUrl && <a
                    href={whatsappUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex min-h-14 items-center gap-3 rounded-xl border border-primary/20 bg-primary/10 p-3 transition hover:bg-primary/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                  >
                    <MessageCircle className="h-5 w-5 shrink-0 text-primary" />
                    <span className="min-w-0">
                      <span className="block text-sm font-semibold">WhatsApp</span>
                      <span className="block truncate text-xs text-muted-foreground">Chat langsung dengan CS</span>
                    </span>
                  </a>}
                  <a
                    href={`mailto:${profile.email}`}
                    className="flex min-h-14 items-center gap-3 rounded-xl border border-primary/20 bg-primary/10 p-3 transition hover:bg-primary/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                  >
                    <Mail className="h-5 w-5 shrink-0 text-primary" />
                    <span className="min-w-0">
                      <span className="block text-sm font-semibold">Email</span>
                      <span className="block truncate text-xs text-muted-foreground">{profile.email}</span>
                    </span>
                  </a>
              {contactError && <p className="text-xs text-muted-foreground">Kontak ditampilkan dari konfigurasi terakhir yang tersedia.</p>}
                </>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base">Pertanyaan Umum (FAQ)</CardTitle>
            </CardHeader>
            <CardContent className="pt-0">
              <Accordion type="single" collapsible className="w-full">
                {FAQ_ITEMS.map((item, i) => (
                  <AccordionItem key={i} value={`faq-${i}`}>
                    <AccordionTrigger className="min-h-14 text-left text-sm leading-snug">
                      {item.q}
                    </AccordionTrigger>
                    <AccordionContent className="text-sm leading-relaxed text-muted-foreground">
                      {item.a}
                    </AccordionContent>
                  </AccordionItem>
                ))}
              </Accordion>
            </CardContent>
          </Card>
        </div>
      </main>

      <BottomNav />
    </div>
  );
}
