export const CHAT_PRODUCT_POLICY = {
  contexts: {
    order: ['buyer_merchant', 'buyer_courier', 'merchant_courier'],
    ride: ['passenger_courier'],
    direct: ['buyer_merchant'],
  },
  retention: {
    softDeleteAfterDays: 14,
    hardDeleteAfterDays: 30,
  },
  limits: {
    maxBodyLength: 4000,
    messagesPerMinute: 30,
  },
  attachments: {
    enabled: false,
  },
} as const;

export type ChatContext = keyof typeof CHAT_PRODUCT_POLICY.contexts;
export type ChatConversationType =
  (typeof CHAT_PRODUCT_POLICY.contexts)[ChatContext][number];

export function isConversationTypeAllowed(
  context: ChatContext,
  conversationType: string,
): boolean {
  return (CHAT_PRODUCT_POLICY.contexts[context] as readonly string[]).includes(
    conversationType,
  );
}

export function isValidChatBody(body: string): boolean {
  const trimmed = body.trim();
  return trimmed.length >= 1 && trimmed.length <= CHAT_PRODUCT_POLICY.limits.maxBodyLength;
}

export function getRetentionDates(createdAt: Date): {
  softDeleteAt: Date;
  hardDeleteAt: Date;
} {
  const softDeleteAt = new Date(createdAt);
  softDeleteAt.setUTCDate(softDeleteAt.getUTCDate() + CHAT_PRODUCT_POLICY.retention.softDeleteAfterDays);

  const hardDeleteAt = new Date(createdAt);
  hardDeleteAt.setUTCDate(hardDeleteAt.getUTCDate() + CHAT_PRODUCT_POLICY.retention.hardDeleteAfterDays);

  return { softDeleteAt, hardDeleteAt };
}
