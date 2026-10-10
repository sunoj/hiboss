// Exercises avatar-only project authorization through the Worker profile endpoint.
// Verifies boss overlap, strict mixed writes, attachment ownership and durable audit rows.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from '../../test-helpers';

const caller = getTestAgentId();
const peerA = 'avatar-peer-a';
const peerB = 'avatar-peer-b';
const outsider = 'avatar-outsider';
const avatar = 'https://test.local/api/attachments/shared-avatar.png';
const priorAvatar = 'https://test.local/api/attachments/prior-avatar.png';

beforeAll(async () => {
  await seedDatabase();
  for (const id of [peerA, peerB, outsider]) {
    await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(id, id, `hash-${id}`).run();
  }
  for (const id of ['avatar-boss-a', 'avatar-boss-b', 'avatar-boss-outside']) {
    await env.DB.prepare("INSERT INTO bosses (id, name, role) VALUES (?, ?, 'manager')")
      .bind(id, id).run();
  }
  for (const [boss, agent] of [
    ['avatar-boss-a', caller], ['avatar-boss-b', caller],
    ['avatar-boss-a', peerA], ['avatar-boss-b', peerB], ['avatar-boss-outside', outsider],
  ]) {
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(boss, agent).run();
  }
  await env.ATTACHMENTS.put('shared-avatar.png', 'image', { customMetadata: { agent_id: caller } });
});

async function seedProject(slug: string, owners: string[] = [caller, peerA]): Promise<void> {
  await env.DB.prepare(`INSERT INTO projects
    (id, slug, display_name, bio, avatar_url, created_by_agent_id, updated_at)
    VALUES (?, ?, 'Original', 'Original bio', ?, ?, '2000-01-01')`)
    .bind(slug, slug, priorAvatar, caller).run();
  for (const alias of [slug, `${slug}-checkout`]) {
    await env.DB.prepare("INSERT INTO project_aliases (alias, project_id, source) VALUES (?, ?, 'explicit')")
      .bind(alias, slug).run();
  }
  for (const owner of owners) {
    await env.DB.prepare(`INSERT INTO sessions (id, agent_id, project_id, status, last_seen_at)
      VALUES (?, ?, ?, 'completed', '2000-01-01')`).bind(`${slug}-${owner}`, owner, slug).run();
  }
}

function put(project: string, body: Record<string, unknown>): Promise<Response> {
  return SELF.fetch(`https://test.local/api/progress/teams/${encodeURIComponent(project)}`, {
    method: 'PUT', headers: authHeaders(), body: JSON.stringify(body),
  });
}

async function stored(project: string): Promise<Record<string, unknown> | null> {
  return env.DB.prepare('SELECT * FROM projects WHERE id = ?').bind(project).first();
}

async function audits(project: string): Promise<Record<string, unknown>[]> {
  const rows = await env.DB.prepare(`SELECT actor_type, actor_id, resource_type, created_at, details
    FROM audit_log WHERE action = 'project.avatar.set' AND resource_id = ?`).bind(project).all();
  return rows.results;
}

it('allows avatar-only updates when each session agent shares a boss with the caller', async () => {
  const project = 'avatar-pairwise';
  await seedProject(project, [caller, peerA, peerB]);
  const response = await put(`${project}-checkout`, { avatar_url: avatar });
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ project, avatar_url: avatar, display_name: 'Original' });
  expect(await stored(project)).toMatchObject({
    avatar_url: avatar, handle: null, display_name: 'Original', bio: 'Original bio', slug: project,
  });
  const rows = await audits(project);
  expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({ actor_type: 'agent', actor_id: caller, resource_type: 'project' });
  expect(rows[0].created_at).toMatch(/^\d{4}-\d{2}-\d{2} /);
  expect(JSON.parse(rows[0].details as string)).toEqual({ avatar_url: avatar });
  const aliases = await env.DB.prepare('SELECT alias FROM project_aliases WHERE project_id = ? ORDER BY alias')
    .bind(project).all<{ alias: string }>();
  expect(aliases.results.map(row => row.alias)).toEqual([project, `${project}-checkout`]);
});

it('allows clearing a shared avatar and records the clear', async () => {
  const project = 'avatar-clear';
  await seedProject(project);
  expect((await put(project, { avatar_url: null })).status).toBe(200);
  expect(await stored(project)).toMatchObject({ avatar_url: null, handle: null, display_name: 'Original' });
  const rows = await audits(project);
  expect(rows).toHaveLength(1);
  expect(rows[0].actor_id).toBe(caller);
  expect(JSON.parse(rows[0].details as string)).toEqual({ avatar_url: null });
});

it('rejects any session agent outside the callers bosses without identifying that agent', async () => {
  const project = 'avatar-outside';
  await seedProject(project, [caller, peerA, outsider]);
  const before = await stored(project);
  for (const avatar_url of [avatar, null]) {
    const response = await put(project, { avatar_url });
    expect(response.status).toBe(409);
    expect(await response.text()).toBe(
      'cannot set project avatar: project has data from an agent outside your bosses',
    );
  }
  expect(await stored(project)).toEqual(before);
  expect(await audits(project)).toEqual([]);
});

it('requires a caller session even when the caller created the project and shares its boss', async () => {
  const project = 'avatar-no-session';
  await seedProject(project, [peerA]);
  const before = await stored(project);
  const response = await put(project, { avatar_url: avatar });
  expect(response.status).toBe(409);
  expect(await response.text()).toBe('cannot set project avatar: you have no session on this project');
  expect(await stored(project)).toEqual(before);
  expect(await audits(project)).toEqual([]);
});

it('does not create a project or aliases for an avatar-only request without a session', async () => {
  const project = 'avatar-missing';
  const response = await put(project, { avatar_url: null });
  expect(response.status).toBe(409);
  expect(await response.text()).toBe('cannot set project avatar: you have no session on this project');
  expect(await stored(project)).toBeNull();
  expect(await env.DB.prepare('SELECT alias FROM project_aliases WHERE alias = ?').bind(project).first())
    .toBeNull();
  expect(await audits(project)).toEqual([]);
});

it('keeps display name, handle and bio writes strict and rejects mixed requests in full', async () => {
  const project = 'avatar-strict';
  await seedProject(project);
  const before = await stored(project);
  for (const body of [{ display_name: 'Changed' }, { handle: 'changed' }, { bio: null }]) {
    for (const request of [body, { ...body, avatar_url: avatar }]) {
      const response = await put(project, request);
      expect(response.status).toBe(409);
      expect(await response.text()).toBe('project has sessions belonging to another agent');
      expect(await stored(project)).toEqual(before);
    }
  }
  // Extra identity fields must not turn a mixed request into an avatar-only write.
  for (const body of [{ slug: 'changed' }, { aliases: ['changed'] }]) {
    expect((await put(project, { ...body, avatar_url: null })).status).toBe(409);
    expect(await stored(project)).toEqual(before);
  }
  expect(await audits(project)).toEqual([]);
});

it('preserves avatar attachment ownership and validation', async () => {
  const project = 'avatar-attachment';
  await seedProject(project);
  await env.ATTACHMENTS.put('foreign-avatar.png', 'image', { customMetadata: { agent_id: peerA } });
  const before = await stored(project);
  for (const avatar_url of [
    'https://elsewhere.invalid/image.png', 'https://test.local/api/attachments/missing-avatar.png',
    'https://test.local/api/attachments/foreign-avatar.png',
  ]) {
    expect((await put(project, { avatar_url })).status).toBe(400);
  }
  expect(await stored(project)).toEqual(before);
  expect(await audits(project)).toEqual([]);
});

it('keeps strict single-owner combined profile writes working and audits their avatar', async () => {
  const project = 'avatar-owned';
  await seedProject(project, [caller]);
  expect((await put(project, {
    avatar_url: avatar, display_name: 'Changed', handle: 'avatar-owned', bio: 'Changed bio',
  })).status).toBe(200);
  expect(await stored(project)).toMatchObject({
    avatar_url: avatar, display_name: 'Changed', handle: 'avatar-owned', bio: 'Changed bio',
  });
  expect(await audits(project)).toHaveLength(1);
});

it('does not count an active admin as a shared boss', async () => {
  const project = 'avatar-admin';
  await seedProject(project, [caller, outsider]);
  await env.DB.prepare("INSERT INTO bosses (id, name, role) VALUES ('avatar-admin', 'Avatar admin', 'admin')")
    .run();
  expect((await put(project, { avatar_url: avatar })).status).toBe(409);
  expect(await stored(project)).toMatchObject({ avatar_url: priorAvatar });
  expect(await audits(project)).toEqual([]);
});

it('counts the project creator and progress authors as participants', async () => {
  const creatorProject = 'avatar-foreign-creator';
  await seedProject(creatorProject, [caller]);
  await env.DB.prepare('UPDATE projects SET created_by_agent_id = ? WHERE id = ?')
    .bind(outsider, creatorProject).run();
  const postProject = 'avatar-foreign-post';
  await seedProject(postProject, [caller]);
  await env.DB.prepare("INSERT INTO progress_posts (id, agent_id, project_id, body) VALUES ('avatar-post', ?, ?, 'x')")
    .bind(outsider, postProject).run();
  for (const project of [creatorProject, postProject]) {
    expect((await put(project, { avatar_url: avatar })).status).toBe(409);
    expect(await stored(project)).toMatchObject({ avatar_url: priorAvatar });
  }
});

it('rejects a caller who registers a session on another boss project', async () => {
  const project = 'avatar-joined';
  await seedProject(project, [outsider]);
  await env.DB.prepare('UPDATE projects SET created_by_agent_id = ? WHERE id = ?').bind(outsider, project).run();
  const joined = await SELF.fetch('https://test.local/api/sessions', {
    method: 'POST', headers: authHeaders(), body: JSON.stringify({ id: 'avatar-joined-caller', project }),
  });
  expect(joined.status).toBe(201);
  expect((await put(project, { avatar_url: avatar })).status).toBe(409);
  expect(await stored(project)).toMatchObject({ avatar_url: priorAvatar });
});

it('does not count archived admins or archived explicit grants as shared bosses', async () => {
  const project = 'avatar-archived';
  await seedProject(project, [caller, outsider]);
  for (const role of ['admin', 'manager']) {
    const boss = `avatar-archived-${role}`;
    await env.DB.prepare(`INSERT INTO bosses (id, name, role, archived_at)
      VALUES (?, ?, ?, '2000-01-01')`).bind(boss, boss, role).run();
    for (const agent of [caller, outsider]) {
      await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
        .bind(boss, agent).run();
    }
  }
  expect((await put(project, { avatar_url: avatar })).status).toBe(409);
  expect(await stored(project)).toMatchObject({ avatar_url: priorAvatar });
  expect(await audits(project)).toEqual([]);
});

it('requires a resolved boss even when the caller is the only session agent', async () => {
  const project = 'avatar-no-boss';
  await seedProject(project, [caller]);
  await env.DB.prepare('DELETE FROM boss_agent_access WHERE agent_id = ?').bind(caller).run();
  expect((await put(project, { avatar_url: null })).status).toBe(409);
  expect(await stored(project)).toMatchObject({ avatar_url: priorAvatar });
  expect(await audits(project)).toEqual([]);
});
