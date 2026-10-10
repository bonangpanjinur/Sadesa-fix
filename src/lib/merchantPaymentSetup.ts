export interface MerchantPaymentSetupFields {
  bank_name: string | null;
  bank_account_number: string | null;
  bank_account_name: string | null;
  qris_image_url: string | null;
}

export function hasMerchantPaymentSetup(fields: MerchantPaymentSetupFields): boolean {
  const hasCompleteBankAccount = [
    fields.bank_name,
    fields.bank_account_number,
    fields.bank_account_name,
  ].every((value) => typeof value === 'string' && value.trim().length > 0);
  const hasQris = typeof fields.qris_image_url === 'string' && fields.qris_image_url.trim().length > 0;
  return hasCompleteBankAccount || hasQris;
}
