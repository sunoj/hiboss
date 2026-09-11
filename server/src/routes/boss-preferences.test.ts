// Admin preference API regression coverage for quiet hours and removed settings.
// Depends on authenticated Worker requests and isolated boss fixtures.
import { SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
const createdBossId = 'preference-target';
beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Admin', 'admin', 'pref-admin', 'pref-admin');
  await seedBossToken('Viewer', 'viewer', 'pref-viewer', 'pref-viewer');
  await seedBossToken('Target', 'manager', 'pref-target', createdBossId);
});
function adminHeaders(): Record<string, string> { return { Authorization: 'Bearer pref-admin', 'Content-Type': 'application/json' }; }
function viewerHeaders(): Record<string, string> { return { Authorization: 'Bearer pref-viewer' }; }
describe('Admin preferences', () => {
  it('sets and merges preferences', async () => {
    const res1 = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: { timezone: 'UTC' } }),
    });
    expect(res1.status).toBe(200);
    // Merge additional preference
    const res2 = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: { quiet_hours: { start: '22:00', end: '08:00' } } }),
    });
    expect(res2.status).toBe(200);
    // Verify merge
    const getRes = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, { headers: viewerHeaders() });
    const data = await getRes.json() as { preferences: { timezone: string; quiet_hours: { start: string } } };
    expect(data.preferences.timezone).toBe('UTC');
    expect(data.preferences.quiet_hours.start).toBe('22:00');
  });

  it('rejects removed preferred_channel', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: { preferred_channel: 'slack' } }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects removed notify_priorities', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: { notify_priorities: ['invalid'] } }),
    });
    expect(res.status).toBe(400);
  });

  it('clears preferences with null', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: null }),
    });
    expect(res.status).toBe(200);
  });

});
