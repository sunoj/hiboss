// Admin preference API regression coverage for quiet hours and removed settings.
// Depends on authenticated Worker requests and isolated boss fixtures.
import { testRequest, returnsStatus } from '../test-request';
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
    const res1 = await testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { preferences: { timezone: 'UTC' } });
    expect(res1.status).toBe(200);
    // Merge additional preference
    const res2 = await testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { preferences: { quiet_hours: { start: '22:00', end: '08:00' } } });
    expect(res2.status).toBe(200);
    // Verify merge
    const getRes = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, { headers: viewerHeaders() });
    const data = await getRes.json() as { preferences: { timezone: string; quiet_hours: { start: string } } };
    expect(data.preferences.timezone).toBe('UTC');
    expect(data.preferences.quiet_hours.start).toBe('22:00');
  });

  it('rejects removed preferred_channel', returnsStatus(400, () =>
    testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { preferences: { preferred_channel: 'slack' } })));

  it('rejects removed notify_priorities', returnsStatus(400, () =>
    testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { preferences: { notify_priorities: ['invalid'] } })));

  it('clears preferences with null', returnsStatus(200, () =>
    testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { preferences: null })));

});
