import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = process.cwd();
const presence = readFileSync(resolve(root, 'src/hooks/chat/useChatPresence.ts'), 'utf8');
const typing = readFileSync(resolve(root, 'src/hooks/chat/useTypingIndicator.ts'), 'utf8');
const orderChat = readFileSync(resolve(root, 'src/components/chat/OrderChat.tsx'), 'utf8');

describe('chat presence and typing contract', () => {
  it('tracks only a non-sensitive online presence payload', () => {
    expect(presence).toContain('channel.track({ online: true })');
    expect(presence).not.toContain('gps');
    expect(presence).not.toContain('location');
    expect(presence).toContain('presenceState');
  });

  it('debounces typing and automatically stops after three seconds', () => {
    expect(typing).toContain('value ? 400 : 0');
    expect(typing).toContain('setTimeout(() => setIsTyping(false), 3000)');
    expect(typing).toContain("event: 'typing'");
    expect(typing).toContain('subscribedRef');
  });

  it('uses the shared hooks from the real OrderChat entry point', () => {
    expect(orderChat).toContain("useChatPresence(conversationId)");
    expect(orderChat).toContain("useTypingIndicator(conversationId)");
    expect(orderChat).toContain('typing.setIsTyping');
    expect(orderChat).toContain('Sedang mengetik');
  });
});
