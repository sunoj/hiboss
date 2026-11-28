// Regression probes for boss grants, viewer roles, and project lifecycle.
// Exercises public Worker routes with isolated D1 fixtures.
// Depends on shared D1 seeding and agent keys.

import { testRequest } from '../test-request';
import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { createAgent } from '../agent-keys';
import { seedBossToken, seedDatabase } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});
const base = 'https://test.local';

async function agent(name: string): Promise<{ id: string; key: string }> {
  const created = await createAgent(env.DB, name, { type: 'system', id: 'business-audit' });
  if (!created) throw new Error(`failed to create ${name}`);
  return created;
}

async function project(id: string, owner: string): Promise<void> {
  await env.DB.prepare('INSERT INTO projects (id, slug, display_name, created_by_agent_id) VALUES (?, ?, ?, ?)')
    .bind(id, id, id, owner).run();
  await env.DB.prepare("INSERT INTO project_aliases (alias, project_id, source) VALUES (?, ?, 'explicit')")
    .bind(id, id).run();
}

async function session(id: string, owner: string, projectId: string): Promise<void> {
  await env.DB.prepare('INSERT INTO sessions (id, agent_id, project_id) VALUES (?, ?, ?)')
    .bind(id, owner, projectId).run();
}

async function sessionProject(id: string): Promise<string | null> {
  const row = await env.DB.prepare('SELECT project_id FROM sessions WHERE id = ?')
    .bind(id).first<{ project_id: string | null }>();
  return row?.project_id ?? null;
}

describe('Business audit access boundaries', () => {
  it('F3 boss merge preserves sessions of agents outside its grants', async () => {
    const allowed = await agent('audit-f3-allowed');
    const hidden = await agent('audit-f3-hidden');
    const token = 'audit-f3-boss-token';
    const boss = await seedBossToken('audit-f3-boss', 'manager', token);
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, allowed.id).run();
    for (const id of ['audit-f3-good-from', 'audit-f3-good-to', 'audit-f3-mixed-from', 'audit-f3-mixed-to']) {
      await project(id, allowed.id);
    }
    await session('audit-f3-good-session', allowed.id, 'audit-f3-good-from');
    await session('audit-f3-allowed-session', allowed.id, 'audit-f3-mixed-from');
    await session('audit-f3-hidden-session', hidden.id, 'audit-f3-mixed-from');
    const merge = (from: string, into: string): Promise<Response> => testRequest('PATCH',
      `${base}/api/boss/projects/${from}`,
      { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, { merge_into: into });
    expect((await merge('audit-f3-good-from', 'audit-f3-good-to')).status).toBe(200);
    expect(await sessionProject('audit-f3-good-session')).toBe('audit-f3-good-to');
    expect(await sessionProject('audit-f3-hidden-session')).toBe('audit-f3-mixed-from');
    const attempt = await merge('audit-f3-mixed-from', 'audit-f3-mixed-to');
    expect([200, 403, 409]).toContain(attempt.status);
    expect(await sessionProject('audit-f3-hidden-session')).toBe('audit-f3-mixed-from');
  });

  it('F2 agent progress aliases cannot merge away a project containing another agent session', async () => {
    const caller = await agent('audit-f2-caller');
    const hidden = await agent('audit-f2-hidden');
    await project('audit-f2-winner', caller.id);
    await project('audit-f2-other', hidden.id);
    await session('audit-f2-other-session', hidden.id, 'audit-f2-other');
    const post = (projectIdentity: { slug: string; aliases: string[] }, body: string): Promise<Response> =>
      testRequest('POST', `${base}/api/progress`,
        { Authorization: `Bearer ${caller.key}`, 'Content-Type': 'application/json' },
        { body, project: projectIdentity });
    const control = await post({ slug: 'audit-f2-winner', aliases: [] }, 'control progress');
    expect(control.status).toBe(201);
    expect(await control.json()).toMatchObject({ project_ref: { id: 'audit-f2-winner' } });
    expect(await sessionProject('audit-f2-other-session')).toBe('audit-f2-other');
    const attempt = await post({ slug: 'audit-f2-winner', aliases: ['audit-f2-other'] }, 'alias collision');
    expect([201, 409]).toContain(attempt.status);
    expect(await sessionProject('audit-f2-other-session')).toBe('audit-f2-other');
    expect(await env.DB.prepare("SELECT id FROM projects WHERE id = 'audit-f2-other'").first()).toEqual({ id: 'audit-f2-other' });
  });

  it('F11 viewer associated agent cannot PATCH inbox status', async () => {
    const manager = await agent('audit-f11-manager-agent');
    const viewer = await agent('audit-f11-viewer-agent');
    const sub = await agent('audit-f11-sub-agent');
    for (const [id, role, associated] of [
      ['audit-f11-manager', 'manager', manager.id],
      ['audit-f11-viewer', 'viewer', viewer.id],
    ]) {
      await env.DB.prepare('INSERT INTO bosses (id, name, role, agent_id) VALUES (?, ?, ?, ?)')
        .bind(id, id, role, associated).run();
      await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
        .bind(id, sub.id).run();
    }
    await env.DB.prepare("INSERT INTO messages (id, agent_id, direction, mode, body, status) VALUES (?, ?, 'agent_to_boss', 'async', 'control', 'sent'), (?, ?, 'agent_to_boss', 'async', 'viewer attempt', 'sent')")
      .bind('audit-f11-control', sub.id, 'audit-f11-target', sub.id).run();
    const patch = (id: string, key: string): Promise<Response> => testRequest('PATCH',
      `${base}/api/boss/inbox/${id}`, { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      { status: 'read' });
    expect((await patch('audit-f11-control', manager.key)).status).toBe(200);
    expect(await env.DB.prepare("SELECT status FROM messages WHERE id = 'audit-f11-control'").first()).toEqual({ status: 'read' });
    expect(await env.DB.prepare("SELECT status FROM messages WHERE id = 'audit-f11-target'").first()).toEqual({ status: 'sent' });
    const attempt = await patch('audit-f11-target', viewer.key);
    expect(attempt.status).toBe(403);
    expect(await env.DB.prepare("SELECT status FROM messages WHERE id = 'audit-f11-target'").first()).toEqual({ status: 'sent' });
  });

});
