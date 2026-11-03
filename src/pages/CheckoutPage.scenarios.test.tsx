import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import type { ReactNode } from 'react';
import type { CheckoutAddressData } from '@/components/checkout/CheckoutAddressForm';
import { setLocale } from '@/lib/i18n';

const mockCheckout = vi.hoisted(() => ({
  user: { id: 'buyer-1' },
  items: [] as unknown[],
  stockRows: [] as unknown[],
  merchantRows: [] as unknown[],
  merchantIsOpen: true,
  transferEnabled: true,
  gdcMpmAvailable: false,
  gdcMpmShouldFail: false,
  xenditEnabled: true,
  quote: null as unknown,
  quoteError: null as string | null,
  checkoutError: null as string | null,
  rpc: vi.fn(),
  createPaymentInvoice: vi.fn(),
  removeFromCart: vi.fn(),
  toast: vi.fn(),
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: mockCheckout.user }),
}));

vi.mock('@/contexts/CartContext', () => ({
  useCart: () => ({
    selectedItems: mockCheckout.items,
    removeFromCart: mockCheckout.removeFromCart,
  }),
}));

vi.mock('@/hooks/useGuestCheckoutEnabled', () => ({
  useGuestCheckoutEnabled: () => ({ enabled: true, loading: false }),
}));

vi.mock('@/hooks/use-toast', () => ({ toast: mockCheckout.toast }));

vi.mock('@/lib/paymentApi', () => ({
  isXenditEnabled: () => Promise.resolve(mockCheckout.xenditEnabled),
  createPaymentInvoice: (args: { orderId: string }) => mockCheckout.createPaymentInvoice(args),
}));

vi.mock('@/lib/gdcQrisMpmApi', () => ({
  isGdcQrisMpmAvailable: () => mockCheckout.gdcMpmShouldFail
    ? Promise.reject(new Error('endpoint unavailable'))
    : Promise.resolve(mockCheckout.gdcMpmAvailable),
}));

vi.mock('@/lib/merchantOperatingHours', () => ({
  getMerchantOperatingStatus: (isOpen: boolean) => ({
    isCurrentlyOpen: isOpen,
    isManuallyOpen: isOpen,
    openTime: '00:00',
    closeTime: '23:59',
    reason: isOpen ? 'Toko sedang buka' : 'Toko sedang tutup sementara',
  }),
  formatTime: (time: string | null) => time ?? '',
}));

vi.mock('@/lib/deliveryRestriction', () => ({
  getDeliveryRestriction: () => ({ requiresExpedition: false, reasons: [] }),
  MAX_LOCAL_DELIVERY_DISTANCE_KM: 15,
}));

vi.mock('@/components/ui/radio-group', async () => {
  const React = await import('react');
  const RadioContext = React.createContext({ value: '', onValueChange: (_value: string) => {} });
  return {
    RadioGroup: ({ value, onValueChange, children, className }: {
      value: string;
      onValueChange: (value: string) => void;
      children: ReactNode;
      className?: string;
    }) => (
      <RadioContext.Provider value={{ value, onValueChange }}>
        <div role="radiogroup" className={className}>{children}</div>
      </RadioContext.Provider>
    ),
    RadioGroupItem: ({ value, id, disabled }: { value: string; id?: string; disabled?: boolean }) => {
      const group = React.useContext(RadioContext);
      return (
        <input
          type="radio"
          role="radio"
          id={id}
          value={value}
          checked={group.value === value}
          disabled={disabled}
          onChange={() => group.onValueChange(value)}
        />
      );
    },
  };
});

vi.mock('@/components/checkout/CheckoutAddressForm', () => ({
  CheckoutAddressForm: ({ value, onChange }: {
    value: CheckoutAddressData;
    onChange: (value: CheckoutAddressData) => void;
  }) => (
    <div>
      <label>
        Nama penerima
        <input
          aria-label="Nama penerima"
          value={value.name}
          onChange={(event) => onChange({ ...value, name: event.target.value })}
        />
      </label>
      <label>
        Nomor telepon
        <input
          aria-label="Nomor telepon"
          value={value.phone}
          onChange={(event) => onChange({ ...value, phone: event.target.value })}
        />
      </label>
    </div>
  ),
}));

vi.mock('@/components/AddressSelector', () => ({
  createEmptyAddressData: () => ({
    province: '', provinceName: '', city: '', cityName: '', district: '', districtName: '',
    village: '', villageName: '', postalCode: '',
  }),
  formatFullAddress: () => 'Alamat pickup',
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (table: string) => {
      const query = {
        select: () => query,
        eq: () => query,
        maybeSingle: async () => {
          if (table === 'merchants') {
            const merchantRows = mockCheckout.merchantRows as Array<Record<string, unknown>>;
            return {
              data: merchantRows[0]
                ? { ...merchantRows[0], payment_transfer_enabled: mockCheckout.transferEnabled }
                : null,
              error: null,
            };
          }
          return { data: null, error: null };
        },
        in: async () => {
          if (table === 'merchants') {
            const merchantRows = mockCheckout.merchantRows as Array<Record<string, unknown>>;
            return { data: merchantRows.map((merchant) => ({
              ...merchant,
              is_open: mockCheckout.merchantIsOpen && Boolean(merchant.is_open),
            })), error: null };
          }
          if (table === 'products') return { data: mockCheckout.stockRows, error: null };
          return { data: [], error: null };
        },
      };
      return query;
    },
    rpc: (functionName: string, args: unknown) => mockCheckout.rpc(functionName, args),
  },
}));

import CheckoutPage from './CheckoutPage';

function renderCheckout() {
  return render(
    <MemoryRouter initialEntries={['/checkout']}>
      <CheckoutPage />
    </MemoryRouter>,
  );
}

function submitForm() {
  const form = document.getElementById('checkout-form');
  if (!form) throw new Error('Checkout form was not rendered');
  fireEvent.submit(form);
}

function cartItem(id = 'product-1', merchantId = 'merchant-1', price = 10_000) {
  return {
    product: {
      id,
      merchantId,
      merchantName: merchantId === 'merchant-1' ? 'Toko Demo' : 'Toko Lain',
      name: id === 'product-1' ? 'Produk Demo' : `Produk ${id}`,
      description: '',
      price,
      stock: 10,
      image: 'https://example.com/product.jpg',
      category: 'Makanan',
      isActive: true,
    },
    quantity: 1,
  };
}

async function preparePickupCheckout() {
  renderCheckout();
  fireEvent.change(screen.getByLabelText('Nama penerima'), { target: { value: 'Budi Santoso' } });
  fireEvent.change(screen.getByLabelText('Nomor telepon'), { target: { value: '081234567890' } });
  const pickup = document.getElementById('pickup');
  if (!pickup) throw new Error('Pickup option was not rendered');
  fireEvent.click(pickup);
  await waitFor(() => {
    expect(mockCheckout.rpc.mock.calls.some(([name]) => name === 'quote_marketplace_checkout')).toBe(true);
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, 'error').mockImplementation(() => {});
  Object.defineProperty(globalThis, 'ResizeObserver', {
    configurable: true,
    value: class {
      observe() {}
      unobserve() {}
      disconnect() {}
    },
  });
  setLocale('id');
  mockCheckout.items = [cartItem()];
  mockCheckout.stockRows = [{ id: 'product-1', name: 'Produk Demo', stock: 10 }];
  mockCheckout.merchantIsOpen = true;
  mockCheckout.gdcMpmAvailable = false;
  mockCheckout.gdcMpmShouldFail = false;
  mockCheckout.merchantRows = [{
    id: 'merchant-1',
    name: 'Toko Demo',
    is_open: true,
    open_time: '00:00',
    close_time: '23:59',
    location_lat: null,
    location_lng: null,
    province: 'Jawa Timur',
    city: 'Kota Demo',
    district: 'Kecamatan Demo',
    payment_transfer_enabled: true,
    bank_name: 'Bank SaDesa',
    bank_account_number: '1234567890',
    bank_account_name: 'Toko Demo',
    qris_image_url: 'https://example.com/merchant-qris.png',
  }];
  mockCheckout.transferEnabled = true;
  mockCheckout.xenditEnabled = true;
  mockCheckout.quote = {
    subtotal: 10_000,
    shipping_cost: 0,
    voucher_discount: 0,
    total: 10_000,
    distance_km: 0,
    quoted_at: '2026-10-13T00:00:00.000Z',
  };
  mockCheckout.quoteError = null;
  mockCheckout.checkoutError = null;
  mockCheckout.rpc.mockImplementation(async (functionName: string) => {
    if (functionName === 'quote_marketplace_checkout') {
      return mockCheckout.quoteError
        ? { data: null, error: { message: mockCheckout.quoteError } }
        : { data: mockCheckout.quote, error: null };
    }
    if (functionName === 'create_marketplace_checkout') {
      return mockCheckout.checkoutError
        ? { data: null, error: { message: mockCheckout.checkoutError } }
        : { data: { primary_order_id: 'order-1' }, error: null };
    }
    return { data: null, error: null };
  });
  mockCheckout.createPaymentInvoice.mockResolvedValue({ invoice_url: 'https://pay.example.test/invoice' });
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('CheckoutPage scenario regressions', () => {
  it('blocks order creation when the merchant is closed, even after pickup and a valid server quote', async () => {
    mockCheckout.merchantIsOpen = false;
    renderCheckout();
    fireEvent.change(screen.getByLabelText('Nama penerima'), { target: { value: 'Budi Santoso' } });
    fireEvent.change(screen.getByLabelText('Nomor telepon'), { target: { value: '081234567890' } });
    expect(await screen.findByText('Beberapa toko sedang tutup')).toBeInTheDocument();

    const pickup = document.getElementById('pickup');
    if (!pickup) throw new Error('Pickup option was not rendered');
    fireEvent.click(pickup);
    await waitFor(() => {
      expect(mockCheckout.rpc.mock.calls.some(([name]) => name === 'quote_marketplace_checkout')).toBe(true);
    });
    submitForm();

    await waitFor(() => expect(mockCheckout.toast).toHaveBeenCalledWith(expect.objectContaining({
      title: 'Toko sedang tutup',
      variant: 'destructive',
    })));
    expect(mockCheckout.rpc.mock.calls.some(([name]) => name === 'create_marketplace_checkout')).toBe(false);
  });

  it('does not request a quote or enable submission for a cart spanning multiple merchants', async () => {
    mockCheckout.items = [cartItem(), cartItem('product-2', 'merchant-2')];
    mockCheckout.stockRows = [
      { id: 'product-1', name: 'Produk Demo', stock: 10 },
      { id: 'product-2', name: 'Produk product-2', stock: 10 },
    ];
    mockCheckout.merchantRows = [
      mockCheckout.merchantRows[0],
      {
        id: 'merchant-2',
        name: 'Toko Lain',
        is_open: true,
        open_time: '00:00',
        close_time: '23:59',
      },
    ];
    renderCheckout();

    const multiMerchantAlert = await screen.findByRole('alert');
    expect(multiMerchantAlert).toBeInTheDocument();
    const submitButton = document.querySelector('button[type="submit"]') as HTMLButtonElement | null;
    expect(submitButton?.disabled).toBe(true);
    expect(mockCheckout.rpc.mock.calls.some(([name]) => name === 'quote_marketplace_checkout')).toBe(false);
    expect(mockCheckout.rpc.mock.calls.some(([name]) => name === 'create_marketplace_checkout')).toBe(false);
  });

  it('displays the authoritative server quote when its price differs from the cart price', async () => {
    mockCheckout.quote = {
      subtotal: 8_500,
      shipping_cost: 0,
      voucher_discount: 0,
      total: 8_500,
      distance_km: 0,
      quoted_at: '2026-10-13T00:00:00.000Z',
    };
    await preparePickupCheckout();

    await waitFor(() => expect(screen.getAllByText(/8\.500/).length).toBeGreaterThan(0));
    expect(mockCheckout.rpc).toHaveBeenCalledWith('quote_marketplace_checkout', expect.objectContaining({
      p_delivery_type: 'PICKUP',
    }));
  });

  it('surfaces a server price-change rejection and keeps the cart after the quote becomes stale', async () => {
    mockCheckout.quote = {
      subtotal: 8_500,
      shipping_cost: 0,
      voucher_discount: 0,
      total: 8_500,
      distance_km: 0,
      quoted_at: '2026-10-13T00:00:00.000Z',
    };
    await preparePickupCheckout();
    await waitFor(() => expect(screen.getAllByText(/8\.500/).length).toBeGreaterThan(0));
    mockCheckout.checkoutError = 'Harga produk berubah; perbarui quote sebelum checkout';

    submitForm();

    await waitFor(() => expect(mockCheckout.toast).toHaveBeenCalledWith(expect.objectContaining({
      title: 'Gagal membuat pesanan',
      description: 'Harga produk berubah; perbarui quote sebelum checkout',
      variant: 'destructive',
    })));
    expect(mockCheckout.removeFromCart).not.toHaveBeenCalled();
    expect(screen.queryByText('Pesanan Berhasil!')).not.toBeInTheDocument();
  });

  it('shows only the active merchant QRIS and never renders bank account details', async () => {
    await preparePickupCheckout();

    expect(screen.getByText('QRIS toko')).toBeInTheDocument();
    expect(screen.getByAltText('QRIS Toko Demo')).toHaveAttribute('src', 'https://example.com/merchant-qris.png');
    expect(screen.queryByText('1234567890')).not.toBeInTheDocument();
    expect(screen.queryByText('Bank SaDesa')).not.toBeInTheDocument();
    expect(screen.queryByRole('radio', { name: /online/i })).not.toBeInTheDocument();
  });

  it('enables server-generated QR MPM only when the logged-in merchant is configured', async () => {
    mockCheckout.gdcMpmAvailable = true;
    await preparePickupCheckout();

    const dynamicQris = screen.getByRole('radio', { name: /QRIS MPM dinamis/ });
    expect(dynamicQris).toBeEnabled();
    fireEvent.click(dynamicQris);
    expect(dynamicQris).toBeChecked();
    expect(document.querySelector('button[type="submit"]')).toBeEnabled();
  });

  it('allows QR MPM checkout without any static QR image', async () => {
    mockCheckout.merchantRows = [{ ...(mockCheckout.merchantRows[0] as Record<string, unknown>), qris_image_url: null }];
    mockCheckout.gdcMpmAvailable = true;
    await preparePickupCheckout();

    expect(screen.queryByRole('radio', { name: /QRIS statis merchant/i })).not.toBeInTheDocument();
    const dynamicQris = screen.getByRole('radio', { name: /QRIS MPM dinamis/ });
    expect(dynamicQris).toBeEnabled();
    fireEvent.click(dynamicQris);
    expect(document.querySelector('button[type="submit"]')).toBeEnabled();
  });
  it('shows a service verification error and retries availability without calling it unconfigured', async () => {
    mockCheckout.gdcMpmShouldFail = true;
    await preparePickupCheckout();
    expect(await screen.findByRole('alert')).toHaveTextContent('Ketersediaan QR MPM gagal diverifikasi');
    expect(screen.queryByText(/QRIS MPM belum tersedia/)).not.toBeInTheDocument();
    mockCheckout.gdcMpmShouldFail = false;
    mockCheckout.gdcMpmAvailable = true;
    fireEvent.click(screen.getByRole('button', { name: 'Coba lagi' }));
    await waitFor(() => expect(screen.getByRole('radio', { name: /QRIS MPM dinamis/ })).toBeEnabled());
  });

  it('blocks checkout when neither dynamic MPM nor static QR is configured', async () => {
    mockCheckout.merchantRows = [{ ...(mockCheckout.merchantRows[0] as Record<string, unknown>), qris_image_url: null }];
    await preparePickupCheckout();

    expect(screen.queryByRole('radio', { name: /QRIS statis merchant/i })).not.toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /QRIS MPM dinamis/ })).toBeDisabled();
    const submitButton = document.querySelector('button[type="submit"]') as HTMLButtonElement | null;
    expect(submitButton?.disabled).toBe(true);
    expect(mockCheckout.rpc.mock.calls.some(([name]) => name === 'create_marketplace_checkout')).toBe(false);
  });

  it('rejects checkout when current server stock is lower than the cart demand', async () => {
    mockCheckout.stockRows = [{ id: 'product-1', name: 'Produk Demo', stock: 0 }];
    await preparePickupCheckout();

    submitForm();

    await waitFor(() => expect(mockCheckout.toast).toHaveBeenCalledWith(expect.objectContaining({
      title: 'Stok tidak mencukupi',
      variant: 'destructive',
    })));
    expect(mockCheckout.rpc.mock.calls.some(([name]) => name === 'create_marketplace_checkout')).toBe(false);
    expect(mockCheckout.removeFromCart).not.toHaveBeenCalled();
  });
});
