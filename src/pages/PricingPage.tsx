import { Link } from 'react-router-dom';
import { ArrowRight, Check, Clock3, HelpCircle, Receipt, ShieldCheck, Store, X } from 'lucide-react';
import { Header } from '@/components/layout/Header';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

const plans = [
  {
    name: 'Marketplace',
    eyebrow: 'Untuk semua merchant',
    price: 'Gratis',
    description: 'Mulai membangun etalase online tanpa biaya langganan.',
    icon: Store,
    accent: 'border-sky-200 bg-sky-50/60 dark:border-sky-900 dark:bg-sky-950/20',
    features: ['Etalase toko online', 'Katalog produk dasar', 'Pesanan marketplace', 'Statistik ringan 7/30 hari'],
    exclusions: ['Analitik operasional lanjutan', 'Mode kasir offline'],
    cta: 'Daftar sebagai merchant',
    href: '/register/merchant',
  },
  {
    name: 'POS Starter',
    eyebrow: 'Warung & toko kecil',
    price: 'Rp49–79 ribu',
    suffix: '/bulan',
    description: 'Operasional kasir dasar untuk satu outlet.',
    icon: Receipt,
    accent: 'border-emerald-200 bg-emerald-50/60 dark:border-emerald-900 dark:bg-emerald-950/20',
    features: ['1 outlet dan 2 pengguna', 'Kasir, stok, dan transaksi', 'Laporan dasar', 'Trial 14–30 hari'],
    exclusions: ['Multi-outlet luas', 'Analitik lanjutan'],
    cta: 'Pelajari POS',
    href: '/register/merchant',
  },
  {
    name: 'POS Growth',
    eyebrow: 'Toko berkembang',
    price: 'Rp129–199 ribu',
    suffix: '/bulan',
    description: 'Kontrol stok dan penjualan untuk bisnis yang mulai berkembang.',
    icon: Clock3,
    accent: 'border-amber-200 bg-amber-50/60 dark:border-amber-900 dark:bg-amber-950/20',
    features: ['1–3 outlet', 'Kasir dan pengguna lebih banyak', 'Pembelian, retur, dan loyalty', 'Offline sync dan laporan lanjutan'],
    exclusions: [],
    cta: 'Pelajari POS',
    href: '/register/merchant',
    popular: true,
  },
  {
    name: 'POS Business',
    eyebrow: 'Retail & multi-outlet',
    price: 'Rp299–499 ribu',
    suffix: '/bulan',
    description: 'Kontrol terpusat untuk operasi multi-outlet yang lebih kompleks.',
    icon: ShieldCheck,
    accent: 'border-violet-200 bg-violet-50/60 dark:border-violet-900 dark:bg-violet-950/20',
    features: ['Multi-outlet lebih luas', 'Akses granular dan audit', 'Analitik lanjutan', 'Dukungan prioritas'],
    exclusions: [],
    cta: 'Hubungi tim SaDesa',
    href: '/help',
  },
];

const faqItems = [
  {
    question: 'Apa yang tetap gratis di SaDesa?',
    answer: 'Marketplace tetap gratis untuk merchant yang memiliki role merchant dan memenuhi aturan platform. Merchant dapat membuat etalase, menampilkan katalog, menerima pesanan online, dan membangun reputasi tanpa harus berlangganan POS.',
  },
  {
    question: 'Apa fungsi POS berbayar?',
    answer: 'POS dipakai untuk operasi toko fisik: kasir, stok per outlet, pengguna staf, pembelian, retur, laporan, printer, dan penjualan offline. POS tidak menggantikan marketplace; keduanya memakai identitas katalog yang sama.',
  },
  {
    question: 'Bagaimana trial POS dan kapan mulai ditagih?',
    answer: 'Trial berlangsung 14 atau 30 hari sesuai paket/program yang diaktifkan admin. H-7 dan H-1 sistem akan mengingatkan merchant. Setelah jatuh tempo ada grace period 3–7 hari sebelum operasi POS baru dihentikan.',
  },
  {
    question: 'Apa yang terjadi saat pembayaran POS terlambat?',
    answer: 'Saat grace period merchant masih dapat bertransaksi dengan peringatan. Setelah status suspended, transaksi POS baru dihentikan, tetapi data, histori, laporan, dan export tetap dapat dibaca. Status marketplace tetap terpisah.',
  },
  {
    question: 'Apakah data POS terhapus saat langganan berhenti?',
    answer: 'Tidak. Suspend atau cancelled tidak menghapus data POS maupun marketplace. Reaktivasi harus mempertahankan tenant, outlet, produk, dan histori yang sama tanpa membuat duplikat.',
  },
  {
    question: 'Apakah harga di halaman ini sudah final?',
    answer: 'Belum. Rentang harga adalah harga uji awal untuk validasi pasar. Harga final, pajak, periode tagihan, diskon, dan add-on akan ditampilkan transparan sebelum pembelian dan dapat diubah admin untuk periode berikutnya.',
  },
  {
    question: 'Apakah POS bisa dipakai saat internet terputus?',
    answer: 'Ya, untuk operasi yang aman ditunda seperti penjualan tunai, membaca katalog cache, dan mencetak struk lokal. Transaksi diberi status pending sampai tersinkron. Pembayaran online, order marketplace, dan laporan final tetap memerlukan koneksi.',
  },
];

export default function PricingPage() {
  return (
    <div className="min-h-screen bg-background">
      <Header />
      <main className="mx-auto max-w-7xl px-4 pb-12 pt-8 sm:px-6 lg:px-8">
        <section className="mx-auto max-w-3xl text-center">
          <Badge variant="secondary" className="mb-4">Fase 0 · Aturan produk</Badge>
          <h1 className="text-3xl font-bold tracking-tight sm:text-5xl">
            Marketplace gratis, POS yang membantu usaha tumbuh
          </h1>
          <p className="mt-4 text-base text-muted-foreground sm:text-lg">
            Mulai dari etalase online tanpa biaya. Aktifkan POS ketika bisnis membutuhkan kontrol kasir, stok, dan operasional yang lebih rapi.
          </p>
          <div className="mt-6 flex flex-wrap justify-center gap-3">
            <Button asChild>
              <Link to="/register/merchant">Mulai gratis <ArrowRight className="ml-2 h-4 w-4" /></Link>
            </Button>
            <Button variant="outline" asChild>
              <a href="#faq">Lihat FAQ</a>
            </Button>
          </div>
        </section>

        <section className="mt-12 grid gap-5 sm:grid-cols-2 xl:grid-cols-4" aria-label="Paket SaDesa">
          {plans.map((plan) => {
            const Icon = plan.icon;
            return (
              <Card key={plan.name} className={`relative flex h-full flex-col ${plan.accent}`}>
                {plan.popular && (
                  <Badge className="absolute right-4 top-4">Paling populer</Badge>
                )}
                <CardHeader>
                  <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-xl bg-background/80">
                    <Icon className="h-5 w-5 text-primary" />
                  </div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{plan.eyebrow}</p>
                  <CardTitle>{plan.name}</CardTitle>
                  <CardDescription>{plan.description}</CardDescription>
                </CardHeader>
                <CardContent className="flex-1">
                  <div className="mb-5">
                    <span className="text-2xl font-bold">{plan.price}</span>
                    {plan.suffix && <span className="ml-1 text-sm text-muted-foreground">{plan.suffix}</span>}
                  </div>
                  <ul className="space-y-3 text-sm">
                    {plan.features.map((feature) => (
                      <li key={feature} className="flex gap-2">
                        <Check className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
                        <span>{feature}</span>
                      </li>
                    ))}
                    {plan.exclusions.map((feature) => (
                      <li key={feature} className="flex gap-2 text-muted-foreground">
                        <X className="mt-0.5 h-4 w-4 shrink-0" />
                        <span>{feature}</span>
                      </li>
                    ))}
                  </ul>
                </CardContent>
                <CardFooter>
                  <Button variant={plan.popular ? 'default' : 'outline'} className="w-full" asChild>
                    <Link to={plan.href}>{plan.cta}</Link>
                  </Button>
                </CardFooter>
              </Card>
            );
          })}
        </section>

        <section className="mx-auto mt-12 max-w-5xl rounded-2xl border bg-card p-5 sm:p-8">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-primary">Aturan yang transparan</p>
              <h2 className="mt-1 text-2xl font-bold">Marketplace dan POS punya peran berbeda</h2>
            </div>
            <Badge variant="outline" className="w-fit">Harga uji · bukan harga final</Badge>
          </div>
          <Separator className="my-6" />
          <div className="grid gap-6 sm:grid-cols-2">
            <div>
              <h3 className="font-semibold">Marketplace tetap terbuka</h3>
              <p className="mt-2 text-sm leading-6 text-muted-foreground">
                Batas marketplace fokus pada kualitas, kuota katalog, dan perlindungan abuse. Order sukses tidak dibatasi keras hanya untuk mendorong upgrade.
              </p>
            </div>
            <div>
              <h3 className="font-semibold">POS melindungi operasi usaha</h3>
              <p className="mt-2 text-sm leading-6 text-muted-foreground">
                Saat POS suspended, data tidak dihapus. Merchant tetap bisa membaca dan mengekspor histori, sementara akses transaksi POS baru mengikuti entitlement.
              </p>
            </div>
          </div>
        </section>

        <section id="faq" className="mx-auto mt-12 max-w-5xl scroll-mt-24">
          <div className="mb-5 flex items-center gap-3">
            <HelpCircle className="h-6 w-6 text-primary" />
            <div>
              <h2 className="text-2xl font-bold">FAQ paket dan aturan penggunaan</h2>
              <p className="text-sm text-muted-foreground">Jawaban singkat tentang marketplace, POS, trial, dan status langganan.</p>
            </div>
          </div>
          <Card>
            <CardContent className="pt-2">
              <Accordion type="single" collapsible className="w-full">
                {faqItems.map((item, index) => (
                  <AccordionItem key={item.question} value={`pricing-faq-${index}`}>
                    <AccordionTrigger className="text-left">{item.question}</AccordionTrigger>
                    <AccordionContent className="leading-6 text-muted-foreground">{item.answer}</AccordionContent>
                  </AccordionItem>
                ))}
              </Accordion>
            </CardContent>
          </Card>
        </section>
      </main>
    </div>
  );
}