export const MEAL_PERIODS = ['pagi', 'siang', 'sore', 'malam'] as const;
export type MealPeriod = (typeof MEAL_PERIODS)[number];

export interface MealRecommendation {
  title: string;
  body: string;
  suggestion: string;
  enabled: boolean;
}

export type MealRecommendations = Record<MealPeriod, MealRecommendation>;

export const MEAL_PERIOD_LABELS: Record<MealPeriod, string> = {
  pagi: 'Pagi · 07.00',
  siang: 'Siang · 12.00',
  sore: 'Sore · 16.00',
  malam: 'Malam · 19.00',
};

export const DEFAULT_MEAL_RECOMMENDATIONS: MealRecommendations = {
  pagi: {
    title: 'Pengingat makan pagi',
    body: 'Mulai hari dengan bubur ayam, nasi uduk, atau jajanan lokal.',
    suggestion: 'Bubur ayam, nasi uduk, atau kopi dan jajanan lokal cocok untuk memulai hari.',
    enabled: true,
  },
  siang: {
    title: 'Pengingat makan siang',
    body: 'Saatnya makan siang—coba menu rumahan dari warung sekitar.',
    suggestion: 'Saatnya makan siang—coba nasi dengan lauk rumahan atau menu favorit dari warung sekitar.',
    enabled: true,
  },
  sore: {
    title: 'Pengingat camilan sore',
    body: 'Temani sore dengan gorengan, camilan tradisional, atau minuman segar.',
    suggestion: 'Temani waktu santai dengan gorengan, camilan tradisional, atau minuman segar.',
    enabled: true,
  },
  malam: {
    title: 'Pengingat makan malam',
    body: 'Cari makan malam yang mengenyangkan dari merchant lokal.',
    suggestion: 'Cari makan malam yang mengenyangkan atau pesan minuman hangat dari merchant lokal.',
    enabled: true,
  },
};

export function getMealPeriod(hour: number): MealPeriod {
  if (hour >= 5 && hour < 10) return 'pagi';
  if (hour >= 10 && hour < 14) return 'siang';
  if (hour >= 14 && hour < 18) return 'sore';
  return 'malam';
}

function boundedText(value: unknown, fallback: string, maxLength: number): string {
  return typeof value === 'string' && value.trim()
    ? value.trim().slice(0, maxLength)
    : fallback;
}

export function normalizeMealRecommendations(value: unknown): MealRecommendations {
  const source = value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};

  return Object.fromEntries(MEAL_PERIODS.map((period) => {
    const candidate = source[period] && typeof source[period] === 'object' && !Array.isArray(source[period])
      ? source[period] as Record<string, unknown>
      : {};
    const fallback = DEFAULT_MEAL_RECOMMENDATIONS[period];
    return [period, {
      title: boundedText(candidate.title, fallback.title, 80),
      body: boundedText(candidate.body, fallback.body, 180),
      suggestion: boundedText(candidate.suggestion, fallback.suggestion, 240),
      enabled: typeof candidate.enabled === 'boolean' ? candidate.enabled : fallback.enabled,
    }];
  })) as MealRecommendations;
}
