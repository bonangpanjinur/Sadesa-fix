import { z } from 'zod';

const emailDomainLabel = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i;

/**
 * Signup email policy: a syntactically valid mailbox with a real-looking
 * domain. Mailbox ownership is proven separately by Supabase's confirmation
 * email before the account can sign in.
 */
export const signupEmailSchema = z
  .string()
  .trim()
  .min(1, 'Email wajib diisi')
  .max(254, 'Email maksimal 254 karakter')
  .email('Masukkan alamat email aktif yang valid')
  .superRefine((value, context) => {
    const [localPart, domain] = value.split('@');
    const labels = domain?.split('.') ?? [];

    if (!localPart || localPart.startsWith('.') || localPart.endsWith('.') || localPart.includes('..')) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: 'Format email tidak valid' });
    }

    if (labels.length < 2 || labels.some((label) => !emailDomainLabel.test(label)) || labels.at(-1)?.length < 2) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: 'Gunakan domain email yang valid, misalnya nama@contoh.com' });
    }
  });

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}
