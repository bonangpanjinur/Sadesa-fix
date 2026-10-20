export interface BusinessProfile {
  brandName: string;
  legalName: string;
  tagline: string;
  address: string;
  phone: string;
  whatsapp: string;
  email: string;
  operatingHours: string;
  serviceArea: string;
  faqs: HelpFaqItem[];
}

export interface HelpFaqItem {
  question: string;
  answer: string;
}

export const DEFAULT_HELP_FAQS: HelpFaqItem[] = [
  { question: 'Bagaimana cara memesan produk?', answer: 'Pilih produk yang diinginkan, tambahkan ke keranjang, lalu lanjutkan ke checkout. Isi alamat pengiriman dan pilih metode pembayaran.' },
  { question: 'Berapa lama pengiriman pesanan?', answer: 'Estimasi pengiriman tergantung jarak antara toko dan alamat Anda. Umumnya 1-3 hari untuk area lokal.' },
  { question: 'Bagaimana cara membatalkan pesanan?', answer: 'Buka halaman Pesanan Saya, pilih pesanan yang ingin dibatalkan, lalu klik tombol "Batalkan Pesanan". Pembatalan hanya bisa dilakukan sebelum pesanan diproses.' },
  { question: 'Metode pembayaran apa saja yang tersedia?', answer: 'Kami menerima transfer bank, QRIS, dan COD (bayar di tempat) untuk area tertentu.' },
  { question: 'Bagaimana cara menjadi merchant/pedagang?', answer: 'Buka menu Akun → Bergabung Bersama Kami → Daftar Sebagai Pedagang. Lengkapi data yang diperlukan dan tunggu persetujuan admin.' },
  { question: 'Bagaimana cara mengajukan refund?', answer: 'Buka detail pesanan, klik "Ajukan Pengembalian", isi alasan dan lampirkan bukti foto jika diperlukan.' },
  { question: 'Apakah semua produk halal?', answer: 'Kami mengutamakan produk halal. Cek badge sertifikat halal pada setiap produk untuk memastikan status halalnya.' },
];

/**
 * Public business details used by the About, Contact, footer and service pages.
 * These values are only a safe loading/error fallback. Runtime values are
 * loaded by useBusinessProfile from the public app_settings table.
 */
export const BUSINESS_PROFILE: BusinessProfile = {
  brandName: 'SaDesa',
  legalName: 'PT RAKA SISTEM NUSANTARA',
  tagline: 'Marketplace produk lokal, kebutuhan harian, dan layanan antar dari desa.',
  address: 'Alamat operasional belum diatur pada app_settings.',
  phone: '',
  whatsapp: '',
  email: 'support@sadesa.id',
  operatingHours: 'Setiap hari, mengikuti jam operasional merchant dan layanan.',
  serviceArea: 'Wilayah layanan lokal SaDesa dan area sekitar merchant yang terdaftar.',
  faqs: DEFAULT_HELP_FAQS,
};

export function normalizeWhatsAppNumber(value: string): string {
  const digits = value.replace(/\D/g, '');
  if (digits.startsWith('0')) return `62${digits.slice(1)}`;
  if (digits.startsWith('8')) return `62${digits}`;
  return digits;
}

export function whatsappHref(value: string): string | null {
  const normalized = normalizeWhatsAppNumber(value);
  return normalized ? `https://wa.me/${normalized}` : null;
}
