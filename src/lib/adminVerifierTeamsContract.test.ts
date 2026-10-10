import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const page = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminVerifikatorTeamsPage.tsx'), 'utf8');

describe('admin verifier team management contract', () => {
  it('provides team creation when the team list is empty and creates an active lead membership', () => {
    expect(page).toContain('Buat tim');
    expect(page).toContain('Belum ada tim. Buat tim terlebih dahulu');
    expect(page).toContain(".from('verifikator_teams').insert({");
    expect(page).toContain("role: 'LEAD'");
    expect(page).toContain('verifikator_team_members').toContain('cleanupError');
  });

  it('restricts selectable members and coordinators to users with the verifier application role', () => {
    expect(page).toContain(".from('user_roles').select('user_id').eq('role', 'verifikator')");
    expect(page).toContain('verifikatorIds.includes(selectedUserId)');
    expect(page).toContain('const verifikators = useMemo');
  });

  it('reports query failures instead of silently presenting failed data as an empty team', () => {
    expect(page).toContain('if (error) throw error');
    expect(page).toContain("toast.error(error instanceof Error ? error.message : 'Data tim gagal dimuat')");
    expect(page).toContain('Memuat data...');
  });
});
