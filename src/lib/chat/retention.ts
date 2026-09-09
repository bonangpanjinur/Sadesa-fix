import type { ConversationMessage } from './types';

export const CHAT_RETENTION_DAYS = 14;
export const CHAT_HARD_DELETE_DAYS = 30;
export const CHAT_MAX_MESSAGE_LENGTH = 4000;

export function isSoftDeleted(message: Pick<ConversationMessage, 'deleted_at' | 'soft_delete_at'>, now = Date.now()): boolean {
  return Boolean(message.deleted_at || (message.soft_delete_at && new Date(message.soft_delete_at).getTime() <= now));
}

export function messageDisplayBody(message: ConversationMessage): string {
  return isSoftDeleted(message) ? 'Pesan dihapus otomatis' : (message.body || message.message || '');
}

export function validateMessageBody(value: string): string | null {
  const body = value.trim();
  if (!body) return 'Pesan tidak boleh kosong';
  if (body.length > CHAT_MAX_MESSAGE_LENGTH) return `Pesan maksimal ${CHAT_MAX_MESSAGE_LENGTH.toLocaleString('id-ID')} karakter`;
  return null;
}
