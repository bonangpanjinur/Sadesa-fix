export interface CartItem {
  productId: string;
  variantId?: string;
  name: string;
  variantName?: string;
  price: number;
  costPrice: number;
  unit: string;
  qty: number;
  discount: number;
  taxRate: number;
  notes: string;
}

export interface HeldBill {
  id: string;
  label: string;
  customer_name: string | null;
  items: CartItem[];
  discount_amount: number;
  notes: string;
  customer_id?: string | null;
}

export interface LastSale {
  saleId?: string;
  saleNumber: string;
  createdAt?: string;
  outletId?: string;
  printJobId?: string;
  total: number;
  change: number;
  paymentMethod: string;
  customerName: string;
  items: CartItem[];
  pointsEarned: number;
  pointsRedeemed: number;
  pointsDiscount: number;
  promoDiscount: number;
  voucherDiscount: number;
  appliedPromoName: string | null;
  appliedVoucherCode: string | null;
  newPointsBalance: number | null;
  subtotal?: number;
  taxAmount?: number;
  paidAmount?: number;
}

export interface ReceiptStore {
  name?: string;
  address?: string;
  phone?: string;
  receipt_header?: string;
  receipt_footer?: string;
}

export interface CustomerBalance {
  total_purchase: number;
  transaction_count: number;
  loyalty_points: number;
}

export interface Customer {
  id: string;
  name: string;
  phone: string | null;
  is_member: boolean;
  loyalty_points?: number;
  loyalty_tier?: string;
}

export interface LoyaltyProgram {
  id: string;
  is_active: boolean;
  earn_per_rupiah: number;
  redeem_rate: number;
  min_redeem_points: number;
  max_redeem_percent: number;
  tiers: { name: string; min_points: number; discount_percent: number; color: string }[];
}

export interface Promotion {
  id: string;
  name: string;
  type: string;
  discount_percent: number;
  discount_amount: number;
  min_purchase: number;
  max_discount: number | null;
  buy_qty: number;
  get_qty: number;
  bundle_price: number | null;
  happy_hour_start: string | null;
  happy_hour_end: string | null;
  happy_hour_days: number[];
  applies_to: string;
  used_count?: number;
}

export interface Voucher {
  id: string;
  code: string;
  name: string;
  type: string;
  discount_percent: number;
  discount_amount: number;
  min_purchase: number;
  max_discount: number | null;
  per_customer_limit: number;
  used_count: number;
  usage_limit: number | null;
  start_date?: string | null;
  end_date?: string | null;
}

export interface SaleRow {
  id: string;
}

export interface StockRow {
  id: string;
  quantity: number;
}

export interface RawMaterialRow {
  id: string;
  name: string;
  current_stock: number;
  unit: string;
}

export interface RecipeRow {
  product_id: string;
  qty_needed: number;
  pos_raw_materials: RawMaterialRow | null;
}

export interface Product {
  id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  price: number;
  cost_price: number;
  unit: string;
  tax_rate: number;
  is_stock_tracked: boolean;
  has_variants: boolean;
  image_url: string | null;
  is_active: boolean;
  pos_categories?: { name: string } | null;
  pos_stock?: { quantity: number }[];
  category_id?: string | null;
}

export interface Variant {
  id: string;
  name: string;
  price: number | null;
  cost_price: number | null;
  is_active: boolean;
}
