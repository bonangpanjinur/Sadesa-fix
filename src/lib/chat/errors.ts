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

function getErrorFields(error: unknown): { code?: string; message?: string; details?: string; hint?: string } {
  if (typeof error === 'string') return { message: error };
  if (!error || typeof error !== 'object') return {};
  const value = error as Record<string, unknown>;
  return {
    code: typeof value.code === 'string' ? value.code : undefined,
    message: typeof value.message === 'string' ? value.message : undefined,
    details: typeof value.details === 'string' ? value.details : undefined,
    hint: typeof value.hint === 'string' ? value.hint : undefined,
  };
}

export function toChatError(error: unknown): ChatError {
  if (error instanceof ChatError) return error;
  const fields = getErrorFields(error);
  const rawMessage = error instanceof Error ? error.message : fields.message;
  const message = rawMessage || fields.details || fields.hint || 'Operasi chat gagal';
  const searchable = [fields.code, message, fields.details, fields.hint].filter(Boolean).join(' ');
  if (/jwt|permission|forbidden|not allowed|unauthorized|42501/i.test(searchable)) return new ChatError('Anda tidak memiliki akses ke percakapan ini.', 'unauthorized');
  if (/closed|archived/i.test(message)) return new ChatError('Percakapan ini sudah ditutup.', 'closed');
  if (/expired|retention/i.test(message)) return new ChatError('Percakapan ini sudah kedaluwarsa.', 'expired');
  if (/network|fetch|offline|timeout|5\d\d|54000/i.test(searchable)) return new ChatError('Koneksi atau kapasitas server sedang bermasalah. Silakan coba lagi.', 'offline', true);
  if (/invalid|validation|22023|4000 characters|client message ID/i.test(searchable)) return new ChatError(message, 'validation', false);
  return new ChatError(message, 'unknown', true);
}
