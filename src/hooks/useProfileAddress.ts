import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import type { SavedAddress } from '@/hooks/useSavedAddresses';

interface ProfileAddressRow {
  user_id: string;
  full_name: string;
  phone: string | null;
  address: string | null;
  province_id: string | null;
  province_name: string | null;
  city_id: string | null;
  city_name: string | null;
  district_id: string | null;
  district_name: string | null;
  village_id: string | null;
  village_name: string | null;
  village: string | null;
  address_detail: string | null;
  updated_at: string;
}

function toProfileAddress(profile: ProfileAddressRow): SavedAddress | null {
  const addressFromProfile = profile.address?.split(/\nGoogle Maps:/i)[0].trim() || '';
  const fullAddress = [
    profile.address_detail,
    profile.village_name || profile.village,
    profile.district_name,
    profile.city_name,
    profile.province_name,
  ].filter(Boolean).join(', ') || addressFromProfile;

  if (!fullAddress) return null;

  const mapsUrl = profile.address?.match(/https?:\/\/[^\s]+/i)?.[0];
  const coordinates = mapsUrl?.match(/[?&]q=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/i);

  return {
    id: 'profile',
    user_id: profile.user_id,
    label: 'Profil',
    recipient_name: profile.full_name || 'Pengguna SaDesa',
    phone: profile.phone || '',
    province_id: profile.province_id,
    province_name: profile.province_name,
    city_id: profile.city_id,
    city_name: profile.city_name,
    district_id: profile.district_id,
    district_name: profile.district_name,
    village_id: profile.village_id,
    village_name: profile.village_name || profile.village,
    address_detail: profile.address_detail,
    full_address: fullAddress,
    lat: coordinates ? Number(coordinates[1]) : null,
    lng: coordinates ? Number(coordinates[2]) : null,
    is_default: false,
    created_at: profile.updated_at,
    updated_at: profile.updated_at,
  };
}

export function useProfileAddress() {
  const { user } = useAuth();
  const [address, setAddress] = useState<SavedAddress | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchProfileAddress = useCallback(async () => {
    if (!user) {
      setAddress(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('user_id, full_name, phone, address, province_id, province_name, city_id, city_name, district_id, district_name, village_id, village_name, village, address_detail, updated_at')
        .eq('user_id', user.id)
        .order('updated_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (error) throw error;
      setAddress(data ? toProfileAddress(data as ProfileAddressRow) : null);
    } catch (error) {
      console.error('Error fetching profile delivery address:', error);
      setAddress(null);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    void fetchProfileAddress();
    window.addEventListener('sadesa-profile-address-updated', fetchProfileAddress);
    return () => window.removeEventListener('sadesa-profile-address-updated', fetchProfileAddress);
  }, [fetchProfileAddress]);

  return { address, loading, refetch: fetchProfileAddress };
}
