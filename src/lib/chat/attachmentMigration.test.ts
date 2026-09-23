import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/20_20260923195000_allow_attachment_only_chat_message.sql'),
  'utf8',
);

describe('chat attachment payload migration', () => {
  it('allows an image-only message while keeping text validation for text-only messages', () => {
    expect(migration).toContain('NEW.attachment_path IS NULL');
    expect(migration).toContain("length(btrim(COALESCE(NEW.body, NEW.message, ''))) NOT BETWEEN 1 AND 4000");
    expect(migration).toContain("RAISE EXCEPTION 'invalid chat message payload'");
  });
});
