export function getTimeAwareSearchPlaceholder() {
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 10) return 'Cari bubur, nasi uduk, kopi, atau roti';
  if (hour >= 10 && hour < 15) return 'Cari nasi, ayam, atau paket hemat';
  if (hour >= 15 && hour < 18) return 'Cari es kopi, jus, atau camilan';
  if (hour >= 18) return 'Cari makan malam atau menu keluarga';
  return 'Cari makanan yang masih buka';
}
