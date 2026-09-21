export type NotificationRole = 'admin' | 'admin_desa' | 'merchant' | 'courier' | 'verifikator' | string;

export interface NotificationRouteInput {
  link?: string | null;
  deep_link?: string | null;
  type?: string | null;
  data?: unknown;
  conversation_id?: string | null;
  message_id?: string | null;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!value) return {};
  if (typeof value === 'object') return value as Record<string, unknown>;
  if (typeof value !== 'string') return {};
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' ? parsed as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

function firstString(...values: unknown[]): string | null {
  return values.find((value): value is string => typeof value === 'string' && value.trim().length > 0)?.trim() || null;
}

function withChatContext(path: string, input: NotificationRouteInput): string {
  const params = new URLSearchParams(path.split('?')[1] || '');
  const data = asRecord(input.data);
  const conversationId = firstString(
    params.get('conversationId'),
    params.get('conversation'),
    input.conversation_id,
    data.conversation_id,
    data.conversationId,
  );
  const orderId = firstString(params.get('orderId'), data.order_id, data.orderId);
  const rideRequestId = firstString(params.get('rideRequestId'), data.ride_request_id, data.rideRequestId);
  params.delete('conversation');
  if (conversationId) params.set('conversationId', conversationId);
  if (orderId) params.set('orderId', orderId);
  if (rideRequestId) params.set('rideRequestId', rideRequestId);
  const query = params.toString();
  return `${path.split('?')[0]}${query ? `?${query}` : ''}`;
}

/**
 * Resolves notification links without letting a multi-role account silently
 * switch context. Producers should include an explicit role-scoped link.
 */
export function resolveNotificationLink(input: NotificationRouteInput, roles: NotificationRole[] = []): string {
  const rawLink = firstString(input.deep_link, input.link) || '';
  const data = asRecord(input.data);
  const explicitTarget = firstString(data.target_path, data.targetPath, data.route);
  let link = explicitTarget || rawLink;

  if (input.type === 'order' && !explicitTarget) {
    const orderId = firstString(asRecord(input.data).order_id, asRecord(input.data).orderId, link.match(/orderId[=:]([\w-]+)/)?.[1], link.match(/\/orders?\/([\w-]+)/)?.[1]);
    if (orderId && !/^\/(merchant|courier|admin|desa|verifikator)\//.test(link)) {
      link = roles.includes('merchant') ? `/merchant/orders?orderId=${orderId}`
        : roles.includes('courier') ? `/courier?orderId=${orderId}`
          : roles.includes('admin') ? `/admin/orders?orderId=${orderId}`
            : roles.includes('admin_desa') ? `/desa?orderId=${orderId}`
              : roles.includes('verifikator') ? `/verifikator?orderId=${orderId}`
                : `/orders?orderId=${orderId}`;
    }
  }

  if (input.type === 'chat' || input.conversation_id || /(^|\/)chat(\/|\?|$)/.test(link)) {
    // Older database triggers stored every chat notification as /buyer/chat.
    // For a merchant+buyer account that legacy target must open the merchant
    // inbox; canonical role-scoped links remain untouched below.
    if (link.startsWith('/buyer/chat') && roles.includes('merchant')) {
      link = link.replace(/^\/buyer\/chat/, '/merchant/chat');
    } else if (link.startsWith('/buyer/chat') && roles.includes('courier')) {
      link = link.replace(/^\/buyer\/chat/, '/courier/chat');
    } else if (link.startsWith('/buyer/chat') && roles.includes('admin_desa')) {
      link = link.replace(/^\/buyer\/chat/, '/desa/chat');
    }
    if (/^\/chat(?:\/|\?|$)/.test(link)) {
      link = roles.includes('merchant') ? `/merchant${link}`
        : roles.includes('courier') ? `/courier${link}`
          : roles.includes('admin') ? `/admin${link}`
            : roles.includes('admin_desa') ? `/desa${link}`
              : '/buyer' + link;
    } else if (!link || link === '/') {
      link = roles.includes('merchant') ? '/merchant/chat'
        : roles.includes('courier') ? '/courier/chat'
          : roles.includes('admin') ? '/admin/chat'
            : roles.includes('admin_desa') ? '/desa/chat'
              : '/buyer/chat';
    }
    return withChatContext(link, input);
  }

  return link || '/';
}

export function isChatNotification(input: NotificationRouteInput): boolean {
  return input.type === 'chat'
    || Boolean(input.conversation_id)
    || /(^|\/)chat(\/|\?|$)/.test(input.link || '')
    || Boolean(asRecord(input.data).conversation_id || asRecord(input.data).conversationId);
}
