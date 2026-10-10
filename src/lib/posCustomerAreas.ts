export interface POSCustomerAreaProfile {
  id: string;
  district_name: string | null;
  city_name: string | null;
}

export interface POSCustomerAreaSale {
  customer_id: string | null;
  total: number;
}

export interface POSCustomerAreaStat {
  key: string;
  label: string;
  detail: string;
  customerCount: number;
  transactionCount: number;
  revenue: number;
}

function cleanArea(value: string | null | undefined): string {
  return value?.trim().replace(/\s+/g, ' ') ?? '';
}

function normalizeArea(value: string): string {
  return value.toLocaleLowerCase('id-ID');
}

/**
 * Rank regions by distinct POS customers, using their current structured profile
 * area. This intentionally returns aggregate metrics only (no customer PII/GPS).
 */
export function rankPOSCustomerAreas(
  sales: readonly POSCustomerAreaSale[],
  profiles: readonly POSCustomerAreaProfile[],
): POSCustomerAreaStat[] {
  const profileById = new Map(profiles.map((profile) => [profile.id, profile]));
  const grouped = new Map<string, POSCustomerAreaStat & { customerIds: Set<string> }>();

  for (const sale of sales) {
    if (!sale.customer_id) continue;
    const profile = profileById.get(sale.customer_id);
    if (!profile) continue;

    const district = cleanArea(profile.district_name);
    const city = cleanArea(profile.city_name);
    if (!district && !city) continue;

    const keyParts = [district, city].map(normalizeArea);
    const key = keyParts.join('|');
    const label = district || city;
    const detail = district && city ? city : '';
    let area = grouped.get(key);
    if (!area) {
      area = { key, label, detail, customerCount: 0, transactionCount: 0, revenue: 0, customerIds: new Set() };
      grouped.set(key, area);
    }
    area.customerIds.add(sale.customer_id);
    area.transactionCount += 1;
    area.revenue += Number.isFinite(Number(sale.total)) ? Number(sale.total) : 0;
  }

  return [...grouped.values()]
    .map(({ customerIds, ...area }) => ({ ...area, customerCount: customerIds.size }))
    .sort((a, b) => b.customerCount - a.customerCount || b.transactionCount - a.transactionCount || b.revenue - a.revenue || a.label.localeCompare(b.label, 'id'));
}
