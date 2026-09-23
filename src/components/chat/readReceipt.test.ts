import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (file: string) => readFileSync(resolve(process.cwd(), file), 'utf8');

describe('chat read receipt contract', () => {
  it('renders one check for sent and two checks for read messages', () => {
    const status = read('src/components/chat/MessageStatus.tsx');
    expect(status).toContain("isRead ? '✓✓' : '✓'");
    expect(status).toContain("aria-label={isRead ? 'Dibaca' : 'Terkirim'}");
  });

  it('uses the other participant read cursor for both chat implementations', () => {
    const repository = read('src/lib/chat/repository.ts');
    const legacy = read('src/components/chat/OrderChat.tsx');
    const canonical = read('src/hooks/chat/useConversation.ts');
    expect(repository).toContain('getConversationReadAt');
    expect(repository).toContain(".neq('user_id', auth.user.id)");
    expect(legacy).toContain('getConversationReadAt(conversationId)');
    expect(canonical).toContain('getConversationReadAt(result.conversationId!)');
  });

  it('resolves the send recipient from canonical conversation membership', () => {
    const repository = read('src/lib/chat/repository.ts');
    expect(repository).toContain(".from('chat_participants')");
    expect(repository).toContain(".neq('user_id', request.senderId)");
    expect(repository).toContain('p_receiver_id: receiverId');
  });
});
