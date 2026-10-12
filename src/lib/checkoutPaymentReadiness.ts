export type CheckoutPaymentMethod = 'TRANSFER' | 'ONLINE';
export type CheckoutPaymentSettingsStatus = 'loading' | 'ready' | 'error';

export function isCheckoutPaymentSettingsReady(
  status: CheckoutPaymentSettingsStatus,
  loadedMerchantId: string | null,
  expectedMerchantId: string | undefined,
): boolean {
  return status === 'ready' && Boolean(expectedMerchantId) && loadedMerchantId === expectedMerchantId;
}

export function isCheckoutPaymentMethodAvailable(
  paymentMethod: CheckoutPaymentMethod,
  transferEnabled: boolean,
  onlinePaymentAvailable: boolean,
): boolean {
  return paymentMethod === 'ONLINE' ? onlinePaymentAvailable : transferEnabled;
}
