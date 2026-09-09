import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migrationPath = resolve(
  process.cwd(),
  'supabase/bootstrap/34_20260909110000_chat_security_pair_isolation.sql',
);
const migration = readFileSync(migrationPath, 'utf8');

describe('chat security migration contract', () => {
  it('scopes direct conversations to buyer and merchant pairs', () => {
    expect(migration).toContain('ADD COLUMN IF NOT EXISTS buyer_user_id');
    expect(migration).toContain('chat_conversations_direct_pair_uidx');
    expect(migration).toContain('ON public.chat_conversations(buyer_user_id, merchant_id, conversation_type)');
    expect(migration).toContain('DROP INDEX IF EXISTS public.chat_conversations_direct_merchant_uidx');
  });

  it('fails closed when an existing direct conversation has ambiguous buyers', () => {
    expect(migration).toContain('direct chat migration blocked');
    expect(migration).toContain('HAVING count(*) = 1');
  });

  it('removes user message update policies and validates recipients', () => {
    expect(migration).toContain('DROP POLICY IF EXISTS "Users can update own messages read status"');
    expect(migration).toContain('validate_chat_message_participants');
    expect(migration).toContain('receiver is not a different active conversation participant');
  });
});
