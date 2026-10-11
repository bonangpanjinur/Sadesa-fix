export type CheckoutPaymentMethod = 'TRANSFER' | 'ONLINE';

export function isCheckoutPaymentMethodAvailable(
  paymentMethod: CheckoutPaymentMethod,
  transferEnabled: boolean,
  onlinePaymentAvailable: boolean,
): boolean {
  return paymentMethod === 'ONLINE' ? onlinePaymentAvailable : transferEnabled;
}
