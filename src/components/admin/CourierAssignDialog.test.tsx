import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

const mocks = vi.hoisted(() => ({
  autoAssignCourier: vi.fn(),
  manualAssignCourier: vi.fn(),
  getAvailableCouriers: vi.fn(),
  toast: { success: vi.fn(), error: vi.fn() },
}));

vi.mock('@/lib/courierApi', () => ({
  autoAssignCourier: mocks.autoAssignCourier,
  manualAssignCourier: mocks.manualAssignCourier,
  getAvailableCouriers: mocks.getAvailableCouriers,
}));

vi.mock('sonner', () => ({ toast: mocks.toast }));

vi.mock('@/components/merchant/CourierMapSelector', () => ({
  CourierMapSelector: () => <div data-testid="courier-map" />,
}));

import { CourierAssignDialog } from './CourierAssignDialog';

const courier = {
  id: 'courier-1',
  name: 'Siti Kurir',
  vehicle_type: 'motor',
  distance_km: 0.4,
  active_orders: 0,
  current_lat: -6.2,
  current_lng: 106.8,
};

function renderDialog(onOpenChange = vi.fn()) {
  return render(
    <CourierAssignDialog
      open
      onOpenChange={onOpenChange}
      orderId="order-1"
      merchantLat={-6.21}
      merchantLng={106.81}
    />,
  );
}

describe('CourierAssignDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getAvailableCouriers.mockResolvedValue([courier]);
    mocks.manualAssignCourier.mockResolvedValue({ success: true });
    mocks.autoAssignCourier.mockResolvedValue({ success: false, error: 'Kurir tidak tersedia' });
  });

  it('keeps the dialog within the viewport and provides a scrollable content region', async () => {
    renderDialog();

    const dialog = screen.getByRole('dialog');
    const scrollRegion = screen.getByRole('region', { name: 'Konten penugasan kurir' });

    expect(dialog).toHaveClass('overflow-hidden');
    expect(dialog.className).toContain('h-[min(90dvh,44rem)]');
    expect(scrollRegion).toHaveClass('min-h-0', 'overflow-y-auto', 'overscroll-contain');
    expect(await screen.findByRole('button', { name: 'Tugaskan Siti Kurir' })).toBeInTheDocument();
  });

  it('shows a retry action instead of presenting a load failure as an empty courier list', async () => {
    mocks.getAvailableCouriers
      .mockRejectedValueOnce(new Error('network unavailable'))
      .mockResolvedValueOnce([courier]);
    renderDialog();

    fireEvent.click(await screen.findByRole('button', { name: 'Coba Lagi' }));

    expect(await screen.findByRole('button', { name: 'Tugaskan Siti Kurir' })).toBeInTheDocument();
    expect(mocks.getAvailableCouriers).toHaveBeenCalledTimes(2);
  });

  it('assigns the selected courier and closes the dialog after success', async () => {
    const onOpenChange = vi.fn();
    renderDialog(onOpenChange);

    fireEvent.click(await screen.findByRole('button', { name: 'Tugaskan Siti Kurir' }));

    await waitFor(() => {
      expect(mocks.manualAssignCourier).toHaveBeenCalledWith('order-1', 'courier-1');
      expect(onOpenChange).toHaveBeenCalledWith(false);
    });
  });
});
