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
 * Keep these values identical to the legal documents and the Xendit dashboard.
 * Production deployments should provide the address and phone through Vite env.
 */
export const BUSINESS_PROFILE: BusinessProfile = {
  brandName: import.meta.env.VITE_BUSINESS_BRAND_NAME || 'SaDesa',
  legalName: import.meta.env.VITE_BUSINESS_LEGAL_NAME || 'PT RAKA SISTEM NUSANTARA',
  tagline: 'Marketplace produk lokal, kebutuhan harian, dan layanan antar dari desa.',
  address: import.meta.env.VITE_BUSINESS_ADDRESS || 'Alamat operasional diatur pada konfigurasi bisnis SaDesa.',
  phone: import.meta.env.VITE_BUSINESS_PHONE || '',
  whatsapp: import.meta.env.VITE_BUSINESS_WHATSAPP || '',
  email: import.meta.env.VITE_BUSINESS_EMAIL || 'support@sadesa.id',
  operatingHours: import.meta.env.VITE_BUSINESS_OPERATING_HOURS || 'Setiap hari, mengikuti jam operasional merchant dan layanan.',
  serviceArea: import.meta.env.VITE_BUSINESS_SERVICE_AREA || 'Wilayah layanan lokal SaDesa dan area sekitar merchant yang terdaftar.',
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
