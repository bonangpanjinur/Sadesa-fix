export const posFixture = {
  tenant: {
    id: 'tenant-fixture-001',
    name: 'Toko Fixture',
  },
  outlet: {
    id: 'outlet-fixture-001',
    tenant_id: 'tenant-fixture-001',
    name: 'Outlet Utama',
  },
  products: [
    {
      id: 'product-coffee-001',
      name: 'Kopi Arabika',
      price: 18000,
      cost_price: 9000,
      stock: 20,
      tax_rate: 0,
    },
    {
      id: 'product-cake-001',
      name: 'Pisang Cokelat',
      price: 12000,
      cost_price: 6000,
      stock: 10,
      tax_rate: 0,
    },
  ],
  sale: {
    id: 'sale-fixture-001',
    sale_number: 'TRX-FIXTURE-001',
    created_at: '2026-08-28T10:00:00.000Z',
    subtotal: 30000,
    discount_amount: 0,
    tax_amount: 0,
    total: 30000,
    payment_amount: 50000,
    change_amount: 20000,
    payment_method: 'cash',
  },
} as const;

export type PosFixture = typeof posFixture;
