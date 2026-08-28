import type { CartItem, LoyaltyProgram, Promotion, Voucher } from '@/components/pos/kasir/types';

export interface POSPricingInput {
  cart: CartItem[];
  orderDiscount?: number;
  promo?: Promotion | null;
  voucher?: Voucher | null;
  usePoints?: boolean;
  pointsToRedeem?: number;
  customerPoints?: number;
  loyaltyProgram?: LoyaltyProgram | null;
  paymentAmount?: number;
  paymentMethod?: string;
}

export interface POSPricingResult {
  subtotal: number;
  taxAmount: number;
  orderDiscount: number;
  promoDiscount: number;
  voucherDiscount: number;
  pointsDiscount: number;
  total: number;
  pointsEarned: number;
  change: number;
}

const nonNegative = (value: number | undefined | null) => Math.max(0, Number(value) || 0);
const cap = (value: number, maximum: number) => Math.min(nonNegative(value), Math.max(0, maximum));

export function calculatePromotionDiscount(promo: Promotion | null | undefined, subtotal: number, now = new Date()): number {
  if (!promo || subtotal < nonNegative(promo.min_purchase)) return 0;
  if (promo.type === 'happy_hour') {
    if (!promo.happy_hour_start || !promo.happy_hour_end || !(promo.happy_hour_days || []).includes(now.getDay())) return 0;
    const [startHour, startMinute] = promo.happy_hour_start.split(':').map(Number);
    const [endHour, endMinute] = promo.happy_hour_end.split(':').map(Number);
    const current = now.getHours() * 60 + now.getMinutes();
    if (current < startHour * 60 + startMinute || current > endHour * 60 + endMinute) return 0;
  }
  if (promo.type === 'discount_percent' || promo.type === 'happy_hour') {
    return cap(subtotal * nonNegative(promo.discount_percent) / 100, promo.max_discount ?? subtotal);
  }
  if (promo.type === 'discount_amount') return cap(promo.discount_amount, subtotal);
  if (promo.type === 'bundle' && promo.bundle_price !== null) return cap(subtotal - nonNegative(promo.bundle_price), subtotal);
  return 0;
}

export function calculateVoucherDiscount(voucher: Voucher | null | undefined, subtotal: number): number {
  if (!voucher || subtotal < nonNegative(voucher.min_purchase)) return 0;
  if (voucher.type === 'discount_percent') {
    return cap(subtotal * nonNegative(voucher.discount_percent) / 100, voucher.max_discount ?? subtotal);
  }
  return cap(voucher.discount_amount, subtotal);
}

export function calculatePOSPricing(input: POSPricingInput): POSPricingResult {
  const subtotal = input.cart.reduce((sum, item) => sum + Math.max(0, item.price * item.qty - nonNegative(item.discount)), 0);
  const taxAmount = input.cart.reduce((sum, item) => sum + Math.max(0, item.price * item.qty - nonNegative(item.discount)) * nonNegative(item.taxRate) / 100, 0);
  const orderDiscount = cap(input.orderDiscount, subtotal + taxAmount);
  const promoDiscount = calculatePromotionDiscount(input.promo, subtotal);
  const voucherDiscount = calculateVoucherDiscount(input.voucher, subtotal);
  const program = input.loyaltyProgram;
  const customerPoints = nonNegative(input.customerPoints);
  const requestedPoints = nonNegative(input.pointsToRedeem);
  const maxPointsDiscount = program && program.redeem_rate > 0
    ? Math.min(Math.floor(customerPoints / program.redeem_rate), Math.floor((subtotal + taxAmount) * nonNegative(program.max_redeem_percent) / 100))
    : 0;
  const pointsDiscount = input.usePoints && program && program.redeem_rate > 0
    ? Math.min(Math.floor(requestedPoints / program.redeem_rate), maxPointsDiscount)
    : 0;
  const total = Math.max(0, subtotal + taxAmount - orderDiscount - promoDiscount - voucherDiscount - pointsDiscount);
  const pointsEarned = program && program.earn_per_rupiah > 0 ? Math.floor(total / program.earn_per_rupiah) : 0;
  const change = input.paymentMethod === 'cash' ? Math.max(0, nonNegative(input.paymentAmount) - total) : 0;

  return { subtotal, taxAmount, orderDiscount, promoDiscount, voucherDiscount, pointsDiscount, total, pointsEarned, change };
}
