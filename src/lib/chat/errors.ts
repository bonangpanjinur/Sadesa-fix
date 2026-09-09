export type ChatErrorCode = 'unauthorized' | 'closed' | 'expired' | 'offline' | 'validation' | 'unknown';

export class ChatError extends Error {
  readonly code: ChatErrorCode;
  readonly retryable: boolean;

  constructor(message: string, code: ChatErrorCode = 'unknown', retryable = false) {
    super(message);
    this.name = 'ChatError';
    this.code = code;
    this.retryable = retryable;
  }
}

export function toChatError(error: unknown): ChatError {
  if (error instanceof ChatError) return error;
  const message = error instanceof Error ? error.message : 'Operasi chat gagal';
  if (/jwt|permission|forbidden|not allowed|unauthorized/i.test(message)) return new ChatError('Anda tidak memiliki akses ke percakapan ini.', 'unauthorized');
  if (/closed|archived/i.test(message)) return new ChatError('Percakapan ini sudah ditutup.', 'closed');
  if (/expired|retention/i.test(message)) return new ChatError('Percakapan ini sudah kedaluwarsa.', 'expired');
  if (/network|fetch|offline|timeout/i.test(message)) return new ChatError('Koneksi terputus. Silakan coba lagi.', 'offline', true);
  return new ChatError(message, 'unknown', true);
}
