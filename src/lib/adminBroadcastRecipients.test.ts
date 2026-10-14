import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import { chunkArray, fetchAllPagedRows } from './adminBroadcastRecipients';

const adminBroadcastPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminBroadcastPage.tsx'), 'utf8');
const pushSender = readFileSync(resolve(process.cwd(), 'supabase/functions/send-push-notification/index.ts'), 'utf8');

describe('fetchAllPagedRows', () => {
  it('loads every page until the final short page', async () => {
    const source = ['merchant-1', 'merchant-2', 'courier-1', 'courier-2', 'courier-3'];
    const loadPage = vi.fn(async (from: number, to: number) => ({
      data: source.slice(from, to + 1),
      error: null,
    }));

    await expect(fetchAllPagedRows(loadPage, 2)).resolves.toEqual(source);
    expect(loadPage.mock.calls).toEqual([[0, 1], [2, 3], [4, 5]]);
  });

  it('does not hide a recipient-query error as an empty audience', async () => {
    const error = new Error('role query failed');
    await expect(fetchAllPagedRows(async () => ({ data: null, error }))).rejects.toBe(error);
  });
});

describe('chunkArray', () => {
  it('splits recipients into bounded non-empty batches', () => {
    expect(chunkArray([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunkArray([], 2)).toEqual([]);
  });
});

describe('admin broadcast Web Push contract', () => {
  it('pages through users, batches inbox/push sends, and makes the VAPID channel explicit', () => {
    expect(adminBroadcastPage).toContain(".eq('is_blocked', false)");
    expect(adminBroadcastPage).toContain(".in('role', rolesFilter)");
    expect(adminBroadcastPage).toContain('fetchAllPagedRows');
    expect(adminBroadcastPage).toContain('chunkArray(notifications, 500)');
    expect(adminBroadcastPage).toContain('user_ids: recipientBatch');
    expect(adminBroadcastPage).toContain('VAPID bukan email');
  });

  it('reports partial VAPID delivery as unsuccessful when any subscription fails', () => {
    expect(pushSender).toContain('success: sentCount === subscriptions.length');
  });
});
