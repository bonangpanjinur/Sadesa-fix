import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/03_20260908190000_to_20260922114500.sql'),
  'utf8',
);
const operationsMigration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/03_20260908190000_to_20260922114500.sql'),
  'utf8',
);
const worker = readFileSync(
  resolve(process.cwd(), 'supabase/functions/process-chat-retention/index.ts'),
  'utf8',
);

describe('chat retention implementation contract', () => {
  it('stores deterministic day 14 and day 30 expiry metadata', () => {
    expect(migration).toContain('soft_delete_at timestamptz');
    expect(migration).toContain('hard_delete_at timestamptz');
    expect(migration).toContain("created_at + interval '14 days'");
    expect(migration).toContain("created_at + interval '30 days'");
    expect(migration).toContain('chat_messages_retention_order_check');
  });

  it('provides server-only batch functions for soft and hard deletion', () => {
    expect(migration).toContain('soft_delete_expired_chat_messages');
    expect(migration).toContain('list_hard_expired_chat_messages');
    expect(migration).toContain('hard_delete_chat_messages');
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.hard_delete_chat_messages');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.hard_delete_chat_messages(uuid[]) TO service_role');
  });

  it('authenticates the scheduled worker and removes attachment objects before rows', () => {
    expect(worker).toContain('x-worker-secret');
    expect(worker).toContain('storage.from("chat-images").remove(paths)');
    expect(worker).toContain('hard_delete_chat_messages');
  });

  it('redacts soft-deleted bodies, claims hard-delete batches, and records metrics', () => {
    expect(operationsMigration).toContain("body = '[Pesan dihapus otomatis]'");
    expect(operationsMigration).toContain("message = '[Pesan dihapus otomatis]'");
    expect(operationsMigration).toContain('chat_retention_claims');
    expect(operationsMigration).toContain('FOR UPDATE OF m SKIP LOCKED');
    expect(operationsMigration).toContain('chat_retention_runs');
    expect(operationsMigration).toContain('record_chat_retention_run');
    expect(operationsMigration).toContain('legacy three-hour auto_delete_at policy is intentionally disabled');
  });

  it('validates attachment paths and never logs message content', () => {
    expect(worker).toContain('safeAttachmentPath');
    expect(worker).toContain('!path.includes("..")');
    expect(worker).toContain('RETENTION_WORKER_FAILED');
    expect(worker).not.toContain('message.body');
    expect(worker).not.toContain('message.message');
  });
});
