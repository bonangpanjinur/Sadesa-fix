import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { getChatRolloutReason, isChatRolloutAllowed, type ChatRolloutConfig } from './rollout';

const root = process.cwd();
const read = (file: string) => readFileSync(resolve(root, file), 'utf8');
const security = read('supabase/bootstrap/34_20260909110000_chat_security_pair_isolation.sql');
const abuse = read('supabase/bootstrap/36_20260909130000_chat_rls_rpc_abuse_control.sql');
const retention = read('supabase/bootstrap/37_20260909140000_chat_retention_operations.sql');
const notification = read('supabase/bootstrap/38_20260909150000_chat_notification_observability.sql');
const roleAwareNotification = read('supabase/bootstrap/41_20260909152000_role_aware_chat_notifications.sql');
const finalNotificationRepair = read('supabase/bootstrap/42_20260909170000_chat_notification_final_repair.sql');
const notificationDropdown = read('src/components/notifications/NotificationDropdown.tsx');
const repository = read('src/lib/chat/repository.ts');
const realtime = read('src/lib/chat/realtime.ts');
const rollout = read('src/lib/chat/rollout.ts');

const pilotConfig: ChatRolloutConfig = {
  enabled: true,
  allowedRoles: ['buyer', 'merchant', 'courier'],
  allowedContexts: ['order'],
  pilotUserIds: ['buyer-a', 'merchant-a', 'courier-a'],
};

describe('chat phase 8 acceptance matrix contract', () => {
  it('covers security and database isolation scenarios', () => {
    expect(security).toContain('chat_conversations_direct_pair_uidx');
    expect(security).toContain('validate_chat_message_participants');
    expect(abuse).toContain('REVOKE ALL ON FUNCTION public.send_chat_message');
    expect(abuse).toContain('client_message_id');
    expect(abuse).toContain('auth.uid()');
  });

  it('covers realtime and reliability scenarios', () => {
    expect(realtime).toContain("status === 'TIMED_OUT'");
    expect(realtime).toContain("status === 'CHANNEL_ERROR'");
    expect(repository).toContain('recordChatChannelStatus');
    expect(repository).toContain('recordMessageEventLatency');
    expect(repository).toContain('duplicate_retry_recovered');
    expect(repository).toContain('client_message_id');
  });

  it('covers retention, cleanup retry, and attachment safety', () => {
    expect(retention).toContain('FOR UPDATE OF m SKIP LOCKED');
    expect(retention).toContain('chat_retention_claims');
    expect(read('supabase/functions/process-chat-retention/index.ts')).toContain('safeAttachmentPath');
    expect(read('supabase/functions/process-chat-retention/index.ts')).toContain('Chat retention worker failed');
  });

  it('covers notification idempotency and operations metrics', () => {
    expect(notification).toContain('notifications_chat_idempotency_uidx');
    expect(notification).toContain('send_chat_notification');
    expect(notification).toContain('chat_observability_events');
    expect(notification).toContain('record_chat_observability');
    expect(notification).toContain('deep_link');
    expect(roleAwareNotification).not.toMatch(/FULL\s+JOIN/i);
    expect(roleAwareNotification).toContain('send_chat_notification');
    expect(roleAwareNotification).toContain('RAISE WARNING');
    expect(finalNotificationRepair).toContain('CREATE TRIGGER chat_messages_notify_recipient');
    expect(finalNotificationRepair).toContain('notifications_chat_idempotency_uidx');
    expect(finalNotificationRepair).toContain('ON CONFLICT (user_id, idempotency_key)');
    expect(finalNotificationRepair).toContain('TO service_role');
    expect(notificationDropdown).toContain("[notifications] refresh failed");
    expect(notificationDropdown).toContain('setInterval(() => void refreshNotifications(), 15000)');
    expect(notificationDropdown).toContain('prev.some(item => item.id === n.id)');
  });

  it('keeps production disabled by default and gates pilot by role/domain/user', () => {
    expect(rollout).toContain('VITE_CHAT_ROLLOUT_ENABLED');
    expect(rollout).toContain('VITE_CHAT_ROLLOUT_ROLES');
    expect(rollout).toContain('VITE_CHAT_ROLLOUT_CONTEXTS');
    expect(getChatRolloutReason({ role: 'buyer', context: 'order', environment: 'production' }, 'buyer-a', { ...pilotConfig, enabled: false })).toBe('disabled');
    expect(isChatRolloutAllowed({ role: 'buyer', context: 'order', environment: 'production' }, 'buyer-a', pilotConfig)).toBe(true);
    expect(getChatRolloutReason({ role: 'passenger', context: 'ride', environment: 'production' }, 'passenger-a', pilotConfig)).toBe('role_not_allowed');
    expect(getChatRolloutReason({ role: 'buyer', context: 'direct', environment: 'production' }, 'buyer-a', pilotConfig)).toBe('context_not_allowed');
    expect(getChatRolloutReason({ role: 'buyer', context: 'order', environment: 'production' }, 'buyer-b', pilotConfig)).toBe('pilot_not_allowed');
  });
});
