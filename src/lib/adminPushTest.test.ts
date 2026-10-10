import { describe, expect, it } from 'vitest';
import { buildAdminPushTestPayload } from './adminPushTest';

describe('buildAdminPushTestPayload', () => {
  it('targets exactly one user and never broadcasts the test notification', () => {
    const payload = buildAdminPushTestPayload('admin-user-123', 'Tes SaDesa', 'Notifikasi uji');

    expect(payload).toEqual({
      user_id: 'admin-user-123',
      title: 'Tes SaDesa',
      body: 'Notifikasi uji',
      url: '/',
    });
    expect(payload).not.toHaveProperty('user_ids');
    expect(payload).not.toHaveProperty('role');
    expect(payload).not.toHaveProperty('all');
  });
});
