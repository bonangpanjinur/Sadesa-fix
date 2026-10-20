import { describe, expect, it } from 'vitest';
import { resolveProfile } from './useBusinessProfile';
import { BUSINESS_PROFILE } from '@/config/businessProfile';

describe('resolveProfile', () => {
  it('reads direct app_settings keys over fallback values', () => {
    const profile = resolveProfile([
      { key: 'site_name', value: 'SaDesa Live' },
      { key: 'company_legal_name', value: 'PT Live Nusantara' },
      { key: 'business_address', value: 'Jl. Desa No. 1' },
      { key: 'business_phone', value: '081234567890' },
      { key: 'business_whatsapp', value: '081234567891' },
      { key: 'business_email', value: 'halo@sadesa.id' },
      { key: 'business_operating_hours', value: '08.00-21.00 WIB' },
      { key: 'business_service_area', value: 'Kabupaten Ciamis' },
    ]);

    expect(profile).toEqual({
      brandName: 'SaDesa Live',
      legalName: 'PT Live Nusantara',
      tagline: BUSINESS_PROFILE.tagline,
      address: 'Jl. Desa No. 1',
      phone: '081234567890',
      whatsapp: '081234567891',
      email: 'halo@sadesa.id',
      operatingHours: '08.00-21.00 WIB',
      serviceArea: 'Kabupaten Ciamis',
      faqs: BUSINESS_PROFILE.faqs,
    });
  });

  it('reads the existing site_info JSON object and support aliases', () => {
    const profile = resolveProfile([
      {
        key: 'site_info',
        value: {
          name: 'SaDesa Site Info',
          tagline: 'Belanja dari desa',
          address: 'Alamat site info',
          phone: '0800000000',
          support_email: 'support@site-info.id',
          service_area: 'Area site info',
        },
      },
      { key: 'support_whatsapp', value: '081111111111' },
    ]);

    expect(profile.brandName).toBe('SaDesa Site Info');
    expect(profile.tagline).toBe('Belanja dari desa');
    expect(profile.address).toBe('Alamat site info');
    expect(profile.phone).toBe('0800000000');
    expect(profile.whatsapp).toBe('081111111111');
    expect(profile.email).toBe('support@site-info.id');
    expect(profile.serviceArea).toBe('Area site info');
  });

  it('reads FAQ items from the public help setting', () => {
    const profile = resolveProfile([{ key: 'help_faq', value: { items: [{ question: 'Q baru', answer: 'A baru' }] } }]);
    expect(profile.faqs).toEqual([{ question: 'Q baru', answer: 'A baru' }]);
  });
});
