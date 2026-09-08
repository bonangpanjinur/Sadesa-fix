export type CategoryTemplateKey = 'product' | 'food' | 'service' | 'rental' | 'experience';
export type CategoryWorkflow = 'order' | 'service_request' | 'rental' | 'booking';

export interface CategoryTemplate {
  key: CategoryTemplateKey;
  label: string;
  workflow: CategoryWorkflow;
  listingFields: readonly string[];
  states: readonly string[];
  transitions: Readonly<Record<string, readonly string[]>>;
}

const ORDER_TRANSITIONS = {
  draft: ['pending', 'cancelled'],
  pending: ['accepted', 'cancelled'],
  accepted: ['preparing', 'completed', 'cancelled'],
  preparing: ['ready', 'cancelled'],
  ready: ['completed', 'cancelled'],
  completed: [],
  cancelled: [],
} as const;

const SERVICE_TRANSITIONS = {
  draft: ['pending', 'cancelled'],
  pending: ['accepted', 'cancelled'],
  accepted: ['in_progress', 'cancelled'],
  in_progress: ['completed', 'cancelled'],
  completed: [],
  cancelled: [],
} as const;

const RENTAL_TRANSITIONS = {
  draft: ['pending', 'cancelled'],
  pending: ['confirmed', 'cancelled'],
  confirmed: ['checked_out', 'cancelled'],
  checked_out: ['returned', 'cancelled'],
  returned: ['completed'],
  completed: [],
  cancelled: [],
} as const;

const BOOKING_TRANSITIONS = {
  draft: ['pending', 'cancelled'],
  pending: ['confirmed', 'cancelled'],
  confirmed: ['checked_in', 'cancelled'],
  checked_in: ['completed', 'cancelled'],
  completed: [],
  cancelled: [],
} as const;

export const CATEGORY_TEMPLATES: Readonly<Record<CategoryTemplateKey, CategoryTemplate>> = {
  product: {
    key: 'product',
    label: 'Produk fisik',
    workflow: 'order',
    listingFields: ['nama', 'harga', 'stok', 'deskripsi'],
    states: Object.keys(ORDER_TRANSITIONS),
    transitions: ORDER_TRANSITIONS,
  },
  food: {
    key: 'food',
    label: 'Makanan & minuman',
    workflow: 'order',
    listingFields: ['nama', 'harga', 'stok', 'deskripsi', 'waktu_persiapan'],
    states: Object.keys(ORDER_TRANSITIONS),
    transitions: ORDER_TRANSITIONS,
  },
  service: {
    key: 'service',
    label: 'Jasa',
    workflow: 'service_request',
    listingFields: ['nama', 'harga', 'durasi', 'deskripsi'],
    states: Object.keys(SERVICE_TRANSITIONS),
    transitions: SERVICE_TRANSITIONS,
  },
  rental: {
    key: 'rental',
    label: 'Sewa',
    workflow: 'rental',
    listingFields: ['nama', 'harga', 'ketersediaan', 'deposit', 'deskripsi'],
    states: Object.keys(RENTAL_TRANSITIONS),
    transitions: RENTAL_TRANSITIONS,
  },
  experience: {
    key: 'experience',
    label: 'Pengalaman & wisata',
    workflow: 'booking',
    listingFields: ['nama', 'harga', 'jadwal', 'kapasitas', 'deskripsi'],
    states: Object.keys(BOOKING_TRANSITIONS),
    transitions: BOOKING_TRANSITIONS,
  },
};

const CATEGORY_ALIASES: Record<string, CategoryTemplateKey> = {
  makanan: 'food',
  minuman: 'food',
  kuliner: 'food',
  jasa: 'service',
  layanan: 'service',
  sewa: 'rental',
  rental: 'rental',
  wisata: 'experience',
  pengalaman: 'experience',
  tourism: 'experience',
};

export function getCategoryTemplate(categorySlug: string | null | undefined): CategoryTemplate {
  const normalized = (categorySlug || '').trim().toLowerCase();
  const key = CATEGORY_ALIASES[normalized] || (normalized as CategoryTemplateKey);
  return CATEGORY_TEMPLATES[key] || CATEGORY_TEMPLATES.product;
}

export function canTransitionCategory(
  categorySlug: string | null | undefined,
  from: string,
  to: string,
): boolean {
  const template = getCategoryTemplate(categorySlug);
  return template.transitions[from]?.includes(to) ?? false;
}