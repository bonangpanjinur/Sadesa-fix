export interface CourierDeliveryCommissionPolicy {
  feePercent: number;
  enabled: boolean;
  chargeCourierDelivery: boolean;
}

export interface CourierDeliveryEarningBreakdown {
  gross: number;
  platformFee: number | null;
  net: number | null;
  available: boolean;
}

function nonNegativeMoney(value: number | null | undefined): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
}

export function getCourierDeliveryEarningBreakdown({
  shippingCost,
  earningEstimate,
  savedPlatformFee,
  policy,
}: {
  shippingCost: number | null | undefined;
  earningEstimate: number | null | undefined;
  savedPlatformFee?: number | null;
  policy: CourierDeliveryCommissionPolicy | null | undefined;
}): CourierDeliveryEarningBreakdown {
  const savedEstimate = nonNegativeMoney(earningEstimate);
  // Customer shipping is not a courier payout. If the server did not provide
  // the courier earning estimate, keep the amount unavailable instead of
  // presenting the full customer charge as courier income.
  if (savedEstimate <= 0) {
    return { gross: 0, platformFee: null, net: null, available: false };
  }
  const gross = savedEstimate;

  // Completed orders carry the authoritative fee snapshot. Never recalculate it
  // with today's policy: an admin rate change must not rewrite payout history.
  if (savedPlatformFee != null && Number.isFinite(savedPlatformFee)) {
    const platformFee = Math.min(gross, nonNegativeMoney(savedPlatformFee));
    return { gross, platformFee, net: gross - platformFee, available: true };
  }

  if (!policy || !Number.isFinite(policy.feePercent) || policy.feePercent < 0 || policy.feePercent > 100) {
    return { gross, platformFee: null, net: null, available: true };
  }

  const platformFee = policy.enabled && policy.chargeCourierDelivery
    ? Math.min(gross, Math.round(gross * policy.feePercent / 100))
    : 0;

  return {
    gross,
    platformFee,
    net: gross - platformFee,
    available: true,
  };
}
