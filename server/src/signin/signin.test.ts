// Tests the "Sign in with iPhone" flow end to end: a signed-out Mac opens a request, a
// signed-in boss approves it and receives the code, and the Mac completes with that code.
// Depends on cloudflare:test, test-helpers and ./test-support.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedBossToken, seedDatabase } from '../test-helpers';
import { act, approvedCode, boss, complete, open, status, view } from './test-support';

const ADMIN = 'hb_boss_signin_admin_000000000001';
const VIEWER = 'hb_boss_signin_viewer_00000000001';
const MANAGER = 'hb_boss_signin_manager_0000000001';
let adminId = '';

beforeAll(async () => {
  await seedDatabase();
  adminId = await seedBossToken('Signin Admin', 'admin', ADMIN);
  await seedBossToken('Signin Viewer', 'viewer', VIEWER);
  await seedBossToken('Signin Manager', 'manager', MANAGER);
});

describe('sign in with iPhone', () => {
  it('signs the Mac in as the approving boss with a code shown on the iPhone', async () => {
    const opened = await open('Studio Mac');
    expect(opened.request_id).toMatch(/^[0-9a-f]{32}$/);
    expect(await (await status(opened.poll_token)).json()).toMatchObject({ status: 'pending' });
    expect(await (await view(opened.request_id, ADMIN)).json()).toMatchObject({ device_label: 'Studio Mac', status: 'pending' });

    const code = await approvedCode(opened.request_id, ADMIN);
    expect(code).toMatch(/^[0-9]{6}$/);
    expect(await (await status(opened.poll_token)).json()).toMatchObject({ status: 'approved' });

    const res = await complete(opened.poll_token, { code });
    expect(res.status).toBe(200);
    const grant = await res.json() as { token: string; boss: { id: string; role: string } };
    expect(grant.boss).toMatchObject({ id: adminId, role: 'admin' });
    const clients = await SELF.fetch('http://localhost/api/boss/clients', { headers: boss(grant.token) });
    expect(clients.status).toBe(200);
    const listed = await clients.json() as { clients: { label: string; kind: string; is_current: boolean }[] };
    expect(listed.clients.find(client => client.is_current)).toMatchObject({ label: 'Studio Mac', kind: 'web' });

    expect((await complete(opened.poll_token, { code })).status).toBe(400);
    expect(await (await status(opened.poll_token)).json()).toMatchObject({ status: 'completed' });
  });

  it('stores only hashes of the poll token and the code', async () => {
    const opened = await open();
    const code = await approvedCode(opened.request_id, ADMIN);
    const row = await env.DB.prepare('SELECT * FROM signin_requests WHERE id = ?').bind(opened.request_id).first<Record<string, unknown>>();
    expect(JSON.stringify(row)).not.toContain(opened.poll_token);
    expect(JSON.stringify(row)).not.toContain(`"${code}"`);
  });

  it('lets a manager approve and refuses a viewer', async () => {
    const opened = await open();
    expect((await view(opened.request_id, VIEWER)).status).toBe(403);
    expect((await act(opened.request_id, 'approve', VIEWER)).status).toBe(403);
    expect((await act(opened.request_id, 'approve', MANAGER)).status).toBe(200);
  });

  it('refuses a second approval and completion before approval', async () => {
    const opened = await open();
    expect((await complete(opened.poll_token, { code: '000000' })).status).toBe(400);
    await approvedCode(opened.request_id, ADMIN);
    expect((await act(opened.request_id, 'approve', MANAGER)).status).toBe(409);
  });

  it('ends a request the boss rejects', async () => {
    const opened = await open();
    expect((await act(opened.request_id, 'reject', ADMIN)).status).toBe(200);
    expect(await (await status(opened.poll_token)).json()).toMatchObject({ status: 'rejected' });
    expect((await act(opened.request_id, 'approve', ADMIN)).status).toBe(409);
  });

  it('lets only the approving boss reject an approved request', async () => {
    const opened = await open();
    const code = await approvedCode(opened.request_id, ADMIN);
    expect((await act(opened.request_id, 'reject', MANAGER)).status).toBe(409);
    expect((await act(opened.request_id, 'reject', ADMIN)).status).toBe(200);
    expect((await complete(opened.poll_token, { code })).status).toBe(400);
  });

  it('validates input', async () => {
    const bad = await SELF.fetch('http://localhost/api/signin/requests', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ device_label: '<script>' }),
    });
    expect(bad.status).toBe(400);
    expect((await status('st_nope')).status).toBe(404);
    expect((await view('not-an-id', ADMIN)).status).toBe(404);
    const opened = await open();
    expect((await complete(opened.poll_token, { code: '12345' })).status).toBe(400);
  });

  it('completes once under concurrent attempts with the right code', async () => {
    const opened = await open();
    const code = await approvedCode(opened.request_id, ADMIN);
    const results = await Promise.all([1, 2, 3].map(() => complete(opened.poll_token, { code })));
    expect(results.map(res => res.status).sort()).toEqual([200, 400, 400]);
  });
});
