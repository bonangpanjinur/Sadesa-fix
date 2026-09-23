import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = process.cwd();
const read = (file: string) => readFileSync(resolve(root, file), 'utf8');

describe('buyer admin chat contract', () => {
  const page = read('src/pages/buyer/BuyerChatPage.tsx');
  const orderChat = read('src/components/chat/OrderChat.tsx');

  it('keeps admin direct messages in the buyer inbox', () => {
    expect(page).toContain("'admin_user'");
    expect(page).toMatch(/\.in\('chat_type', \[[^\]]*'admin_user'/s);
  });

  it('opens the selected admin thread using its existing conversation', () => {
    expect(page).toContain('conversationId={selectedThread.conversationId}');
    expect(orderChat).toContain("| 'admin_user';");
    expect(orderChat).toContain("chatType === 'admin_user'");
  });

  it('resolves the admin name from the other conversation participant', () => {
    expect(page).toContain(".from('chat_participants')");
    expect(page).toContain('otherUserByConversation');
    expect(page).toContain("profile?.full_name?.trim() || 'Admin SaDesa'");
    expect(orderChat).toContain("senderNames[msg.sender_id] || otherUserName || 'Admin SaDesa'");
  });
});
