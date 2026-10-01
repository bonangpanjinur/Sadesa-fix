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
}

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
