export type PilotMerchantTrack = 'marketplace_only' | 'pos';

export type PilotMilestone =
  | 'merchant_profile'
  | 'first_listing'
  | 'first_order'
  | 'first_fulfillment'
  | 'pos_setup'
  | 'first_pos_transaction';

export interface PilotMerchantEvidence {
  merchantProfileComplete: boolean;
  publishedListingCount: number;
  completedOrderCount: number;
  completedFulfillmentCount: number;
  posSetupComplete: boolean;
  completedPosTransactionCount: number;
}

export interface PilotMilestoneResult {
  milestone: PilotMilestone;
  complete: boolean;
  label: string;
}

export interface PilotReadinessResult {
  track: PilotMerchantTrack;
  readyForPilot: boolean;
  activationComplete: boolean;
  milestones: PilotMilestoneResult[];
  nextMilestone: PilotMilestone | null;
}

const MILESTONE_LABELS: Record<PilotMilestone, string> = {
  merchant_profile: 'Profil usaha lengkap',
  first_listing: 'Listing pertama terbit',
  first_order: 'Order pertama selesai',
  first_fulfillment: 'Fulfillment pertama selesai',
  pos_setup: 'Setup POS selesai',
  first_pos_transaction: 'Transaksi POS pertama selesai',
};

function positiveCount(value: number | null | undefined): number {
  return Number.isFinite(value) ? Math.max(0, value as number) : 0;
}

export function evaluatePilotReadiness(
  track: PilotMerchantTrack,
  evidence: PilotMerchantEvidence,
): PilotReadinessResult {
  const milestones: PilotMilestoneResult[] = [
    { milestone: 'merchant_profile', complete: evidence.merchantProfileComplete, label: MILESTONE_LABELS.merchant_profile },
    { milestone: 'first_listing', complete: positiveCount(evidence.publishedListingCount) >= 1, label: MILESTONE_LABELS.first_listing },
    { milestone: 'first_order', complete: positiveCount(evidence.completedOrderCount) >= 1, label: MILESTONE_LABELS.first_order },
    { milestone: 'first_fulfillment', complete: positiveCount(evidence.completedFulfillmentCount) >= 1, label: MILESTONE_LABELS.first_fulfillment },
  ];

  if (track === 'pos') {
    milestones.push(
      { milestone: 'pos_setup', complete: evidence.posSetupComplete, label: MILESTONE_LABELS.pos_setup },
      { milestone: 'first_pos_transaction', complete: positiveCount(evidence.completedPosTransactionCount) >= 1, label: MILESTONE_LABELS.first_pos_transaction },
    );
  }

  const activationMilestones = track === 'pos' ? milestones : milestones.slice(0, 4);
  const activationComplete = activationMilestones.every((milestone) => milestone.complete);
  const nextMilestone = activationMilestones.find((milestone) => !milestone.complete)?.milestone ?? null;

  return {
    track,
    readyForPilot: activationComplete,
    activationComplete,
    milestones,
    nextMilestone,
  };
}
