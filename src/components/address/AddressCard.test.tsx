import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { AddressCard } from './AddressCard';
import type { SavedAddress } from '@/hooks/useSavedAddresses';

const address: SavedAddress = {
  id: 'address-1', user_id: 'user-1', label: 'Rumah', recipient_name: 'Ayu', phone: '08123456789',
  province_id: null, province_name: 'DIY', city_id: null, city_name: 'Bantul', district_id: null,
  district_name: 'Sewon', village_id: null, village_name: 'Panggungharjo', address_detail: 'Jl. Mawar 1',
  full_address: 'Jl. Mawar 1, Panggungharjo', lat: null, lng: null, is_default: false,
  created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z',
};

describe('AddressCard', () => {
  it('exposes selectable addresses as named native buttons with pressed state', () => {
    const onSelect = vi.fn();
    render(<AddressCard address={address} selectable selected onSelect={onSelect} />);

    const select = screen.getByRole('button', { name: /Rumah.*Ayu.*08123456789/s });
    expect(select).toHaveAttribute('aria-pressed', 'true');
    fireEvent.click(select);
    expect(onSelect).toHaveBeenCalledWith(address);
  });

  it('names the address overflow menu button by its target', () => {
    render(<AddressCard address={address} onEdit={vi.fn()} />);
    expect(screen.getByRole('button', { name: 'Aksi alamat Rumah: Ayu' })).toBeInTheDocument();
  });
});
