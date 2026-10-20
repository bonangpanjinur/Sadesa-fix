import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');

describe('help center navigation and dynamic settings contract', () => {
  it('exposes both help and contact shortcuts from the account menu', () => {
    const account = read('src/pages/AccountPage.tsx');
    expect(account).toContain("path: '/help'");
    expect(account).toContain("path: '/contact'");
    expect(account).toContain("label: 'Pusat Bantuan'");
    expect(account).toContain("label: 'Kontak'");
  });

  it('keeps both public routes mapped to the help page', () => {
    const app = read('src/App.tsx');
    expect(app).toContain('<Route path="/help" element={<HelpPage />} />');
    expect(app).toContain('<Route path="/contact" element={<HelpPage />} />');
  });

  it('reads public FAQ content from app settings and exposes admin save keys', () => {
    const hook = read('src/hooks/useBusinessProfile.ts');
    const helpPage = read('src/pages/HelpPage.tsx');
    const admin = read('src/pages/admin/AdminSettingsPage.tsx');
    expect(hook).toContain("settings.get('help_faq')");
    expect(helpPage).toContain('profile.faqs.map');
    expect(admin).toContain("['help_faq', { items: values.faqs }]");
    expect(admin).toContain("['business_whatsapp'");
    expect(admin).toContain("['business_email'");
  });
});
