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
});
