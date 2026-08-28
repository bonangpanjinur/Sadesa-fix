export interface POSPaymentValidationInput {
  total: number;
  paymentMethod: string;
  paymentAmount: number;
  isSplitPayment: boolean;
  splitAmount1: number;
  splitAmount2: number;
  isOnline: boolean;
  usePoints: boolean;
  pointsToRedeem: number;
  minimumRedeemPoints: number;
}

export function validatePOSPayment(input: POSPaymentValidationInput): string | null {
  if (!Number.isFinite(input.total) || input.total < 0) return 'Total transaksi tidak valid';
  if (input.isSplitPayment) {
    if (!Number.isFinite(input.splitAmount1) || !Number.isFinite(input.splitAmount2)) return 'Nominal split payment tidak valid';
    if (Math.abs(input.splitAmount1 + input.splitAmount2 - input.total) > 0.001) {
      return 'Total pembayaran split harus sama dengan total transaksi';
    }
  } else if (input.paymentMethod === 'cash' && input.paymentAmount < input.total) {
    return 'Jumlah bayar kurang dari total';
  }
  if (!input.isOnline && input.paymentMethod !== 'cash') {
    return 'Pembayaran non-tunai memerlukan koneksi internet';
  }
  if (input.usePoints && input.pointsToRedeem < input.minimumRedeemPoints) {
    return `Min. tukar ${input.minimumRedeemPoints} poin`;
  }
  return null;
}

export function getEffectivePaymentAmount(input: Pick<POSPaymentValidationInput, 'total' | 'paymentAmount' | 'isSplitPayment' | 'splitAmount1' | 'splitAmount2'>): number {
  return input.isSplitPayment
    ? input.splitAmount1 + input.splitAmount2
    : (Number.isFinite(input.paymentAmount) ? input.paymentAmount : input.total);
}
