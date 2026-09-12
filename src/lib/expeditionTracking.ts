export type ExpeditionProvider = {
  key: string;
  label: string;
  trackingUrl: (trackingNumber: string) => string;
};

const providers: ExpeditionProvider[] = [
  { key: 'jne', label: 'JNE', trackingUrl: (resi) => `https://cekresi.com/?noresi=${encodeURIComponent(resi)}` },
  { key: 'jnt', label: 'J&T Express', trackingUrl: (resi) => `https://www.jet.co.id/track?waybill=${encodeURIComponent(resi)}` },
  { key: 'sicepat', label: 'SiCepat', trackingUrl: (resi) => `https://www.sicepat.com/checkAwb?awb=${encodeURIComponent(resi)}` },
  { key: 'anteraja', label: 'AnterAja', trackingUrl: (resi) => `https://anteraja.id/tracking?awb=${encodeURIComponent(resi)}` },
  { key: 'ninja', label: 'Ninja Xpress', trackingUrl: (resi) => `https://www.ninjaxpress.co/id-id/tracking?id=${encodeURIComponent(resi)}` },
  { key: 'pos', label: 'Pos Indonesia', trackingUrl: (resi) => `https://www.posindonesia.co.id/id/tracking?barcode=${encodeURIComponent(resi)}` },
  { key: 'tiki', label: 'TIKI', trackingUrl: (resi) => `https://www.tiki.id/id/tracking?stt=${encodeURIComponent(resi)}` },
  { key: 'wahana', label: 'Wahana', trackingUrl: (resi) => `https://www.wahana.com/tracking/${encodeURIComponent(resi)}` },
  { key: 'lion', label: 'Lion Parcel', trackingUrl: (resi) => `https://lionparcel.com/track/stt/${encodeURIComponent(resi)}` },
];

const aliases: Record<string, string> = {
  jne: 'jne', 'jne express': 'jne', jnt: 'jnt', 'j&t': 'jnt', 'j&t express': 'jnt',
  sicepat: 'sicepat', 'si cepat': 'sicepat', anteraja: 'anteraja', 'anter aja': 'anteraja',
  ninja: 'ninja', 'ninja xpress': 'ninja', pos: 'pos', 'pos indonesia': 'pos', tiki: 'tiki',
  wahana: 'wahana', 'lion parcel': 'lion', lion: 'lion',
};

export function normalizeExpeditionName(value: string | null | undefined): string {
  return (value ?? '').trim().toLocaleLowerCase('id-ID').replace(/\s+/g, ' ');
}

export function getExpeditionProvider(name: string | null | undefined): ExpeditionProvider | null {
  const key = aliases[normalizeExpeditionName(name)];
  return providers.find((provider) => provider.key === key) ?? null;
}

export function getExpeditionTrackingUrl(name: string | null | undefined, trackingNumber: string | null | undefined): string | null {
  const resi = (trackingNumber ?? '').trim();
  const provider = getExpeditionProvider(name);
  return provider && resi ? provider.trackingUrl(resi) : null;
}

export function getExpeditionLabel(name: string | null | undefined): string {
  return getExpeditionProvider(name)?.label ?? (name?.trim() || 'Ekspedisi');
}
