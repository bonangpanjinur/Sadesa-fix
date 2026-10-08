import { formatFullAddress, type AddressData } from '@/components/AddressSelector';
import type { CheckoutAddressData } from './CheckoutAddressForm';

export function hasCompleteRegionAddress(address: Pick<AddressData, 'province' | 'city' | 'district' | 'village'>): boolean {
  return Boolean(address.province && address.city && address.district && address.village);
}

export function createCheckoutProfileAddressPayload(userId: string, data: CheckoutAddressData) {
  const detail = data.detailAddress?.trim() || data.address.detail?.trim() || '';
  const fullAddress = formatFullAddress({ ...data.address, detail });
  const address = data.location
    ? `${fullAddress}\nGoogle Maps: https://maps.google.com/?q=${data.location.lat},${data.location.lng}`
    : fullAddress;

  return {
    user_id: userId,
    ...(data.name.trim() ? { full_name: data.name.trim() } : {}),
    ...(data.phone.trim() ? { phone: data.phone.trim() } : {}),
    address,
    province_id: data.address.province,
    province_name: data.address.provinceName,
    city_id: data.address.city,
    city_name: data.address.cityName,
    district_id: data.address.district,
    district_name: data.address.districtName,
    village_id: data.address.village,
    village_name: data.address.villageName,
    address_detail: detail || null,
  };
}
