import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const adminPOS = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminPOSPage.tsx'), 'utf8');
const actionHandlers = adminPOS.slice(
  adminPOS.indexOf('const openSubscriptionActionDialog ='),
  adminPOS.indexOf('const handleReactivate ='),
);

describe('Admin POS suspend/cancel dialog contract', () => {
  it('routes suspend and cancel through the accessible in-app dialog rather than native prompt/confirm', () => {
    expect(actionHandlers).not.toContain('window.prompt');
    expect(actionHandlers).not.toContain('window.confirm');
    expect(adminPOS).toContain("openSubscriptionActionDialog(sub, 'SUSPEND')");
    expect(adminPOS).toContain("openSubscriptionActionDialog(sub, 'CANCEL')");
    expect(adminPOS).toContain('<SubscriptionActionDialog');
  });

  it('submits a trimmed reason and clears the pending state only after success', () => {
    expect(actionHandlers).toContain('const reason = subscriptionActionReason.trim()');
    expect(actionHandlers).toContain("runSubscriptionAction(subscription.id, action, { reason })");
    expect(actionHandlers).toContain('if (ok) {');
    expect(adminPOS).toContain('finally {\n      setActioningId(null);');
  });
});
