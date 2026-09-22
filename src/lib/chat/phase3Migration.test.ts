import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/03_20260908190000_to_20260922114500.sql'),
  'utf8',
);
const repository = readFileSync(
  resolve(process.cwd(), 'src/lib/chat/repository.ts'),
  'utf8',
);
const orderChat = readFileSync(
  resolve(process.cwd(), 'src/components/chat/OrderChat.tsx'),
  'utf8',
);

describe('chat phase 3 security contract', () => {
  it('exposes only authenticated canonical RPC write paths', () => {
    expect(migration).toContain('send_chat_message');
    expect(migration).toContain('REVOKE ALL ON public.chat_messages FROM anon, authenticated');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.send_chat_message');
    expect(migration).toContain('p_client_message_id uuid');
    expect(migration).toContain('chat message must contain 1 to 4000 characters');
  });

  it('validates caller context and read cursor ownership', () => {
    expect(migration).toContain('not a chat participant');
    expect(migration).toContain('message does not belong to conversation');
    expect(migration).toContain('p_receiver_id = auth.uid()');
    expect(migration).toContain('protect_chat_message_immutability');
  });

  it('does not bypass database authorization in the client', () => {
    expect(repository).toContain("supabase.rpc('send_chat_message'");
    expect(repository).not.toContain(".from('chat_messages')\n    .insert");
    expect(orderChat).not.toContain(".from('chat_messages').insert");
    expect(orderChat).not.toContain(".from('chat_messages').update({ is_read: true })");
  });
});
