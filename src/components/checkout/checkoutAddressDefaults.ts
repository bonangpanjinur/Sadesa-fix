import { createEmptyAddressData, type AddressData } from '@/components/AddressSelector';
import type { CheckoutAddressData } from './CheckoutAddressForm';

export function createEmptyCheckoutAddress(): CheckoutAddressData {
  return {
    name: '',
    phone: '',
    address: createEmptyAddressData(),
    location: null,
    fullAddress: '',
    detailAddress: '',
  };
}

export type { AddressData };
