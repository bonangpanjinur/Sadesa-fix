import type { ChatContextType } from './types';

export type ChatRole = 'buyer' | 'merchant' | 'courier' | 'passenger';
export type ChatRolloutEnvironment = 'development' | 'staging' | 'production';

export interface ChatRolloutRequest {
  role: ChatRole;
  context: ChatContextType;
  environment?: ChatRolloutEnvironment;
}

export interface ChatRolloutConfig {
  enabled: boolean;
  allowedRoles: readonly ChatRole[];
  allowedContexts: readonly ChatContextType[];
  pilotUserIds: readonly string[];
}

const roles: readonly ChatRole[] = ['buyer', 'merchant', 'courier', 'passenger'];
const contexts: readonly ChatContextType[] = ['order', 'ride', 'direct'];

function csv(value: string | undefined): string[] {
  return (value ?? '').split(',').map((item) => item.trim()).filter(Boolean);
}

function envValue(key: string): string | undefined {
  return (import.meta as ImportMeta & { env?: Record<string, string | undefined> }).env?.[key];
}

function allowedValues<T extends string>(values: string[], supported: readonly T[]): T[] {
  return values.filter((value): value is T => supported.includes(value as T));
}

export function getChatRolloutConfig(environment: ChatRolloutEnvironment = 'development'): ChatRolloutConfig {
  const explicitlyEnabled = envValue('VITE_CHAT_ROLLOUT_ENABLED') === 'true';
  const enabled = environment === 'development'
    ? envValue('VITE_CHAT_ROLLOUT_ENABLED') !== 'false'
    : explicitlyEnabled;
  return {
    enabled,
    allowedRoles: allowedValues(csv(envValue('VITE_CHAT_ROLLOUT_ROLES')), roles),
    allowedContexts: allowedValues(csv(envValue('VITE_CHAT_ROLLOUT_CONTEXTS')), contexts),
    pilotUserIds: csv(envValue('VITE_CHAT_PILOT_USER_IDS')),
  };
}

export function isChatRolloutAllowed(
  request: ChatRolloutRequest,
  userId?: string,
  config = getChatRolloutConfig(request.environment ?? 'development'),
): boolean {
  if (!config.enabled || !config.allowedRoles.includes(request.role) || !config.allowedContexts.includes(request.context)) return false;
  if (request.environment === 'production' && config.pilotUserIds.length > 0 && (!userId || !config.pilotUserIds.includes(userId))) return false;
  return true;
}

export function getChatRolloutReason(
  request: ChatRolloutRequest,
  userId?: string,
  config = getChatRolloutConfig(request.environment ?? 'development'),
): 'enabled' | 'disabled' | 'role_not_allowed' | 'context_not_allowed' | 'pilot_not_allowed' {
  if (!config.enabled) return 'disabled';
  if (!config.allowedRoles.includes(request.role)) return 'role_not_allowed';
  if (!config.allowedContexts.includes(request.context)) return 'context_not_allowed';
  if (request.environment === 'production' && config.pilotUserIds.length > 0 && (!userId || !config.pilotUserIds.includes(userId))) return 'pilot_not_allowed';
  return 'enabled';
}
