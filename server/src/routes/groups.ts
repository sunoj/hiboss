// CRUD + broadcast endpoints for agent groups.
// Exports groupsRouter mounted at /api/groups.
// Depends on Hono, auth middleware, and D1 bindings.

import { Hono } from 'hono';
import type { Env, Priority } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

interface GroupRow {
  id: string;
  name: string;
  description: string | null;
  created_at: string;
}

interface MemberRow {
  agent_id: string;
  name: string;
  added_at: string;
}

const VALID_PRIORITIES: Priority[] = ['critical', 'high', 'normal', 'low'];

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.get('/', async (c) => {
  const rows = await c.env.DB
    .prepare(
      'SELECT g.*, (SELECT COUNT(*) FROM agent_group_members m WHERE m.group_id = g.id) AS member_count FROM agent_groups g ORDER BY g.name'
    )
    .all<GroupRow & { member_count: number }>();
  return c.json({ groups: rows.results ?? [] });
});

routes.post('/', async (c) => {
  const payload = await c.req.json<Record<string, unknown>>();
  const name = typeof payload.name === 'string' ? payload.name.trim() : '';
  if (!name) {
    return c.text('name is required', 400);
  }
  const description = typeof payload.description === 'string' ? payload.description.trim() : null;
  const inserted = await c.env.DB
    .prepare('INSERT INTO agent_groups (name, description) VALUES (?, ?) RETURNING *')
    .bind(name, description)
    .first<GroupRow>();
  if (!inserted) {
    return c.text('failed to create', 500);
  }
  return c.json(inserted, 201);
});

routes.get('/:id', async (c) => {
  const groupId = c.req.param('id');
  const group = await findGroup(c.env, groupId);
  if (!group) {
    return c.text('not found', 404);
  }
  const members = await c.env.DB
    .prepare(
      'SELECT m.agent_id AS id, k.name, m.added_at FROM agent_group_members m JOIN api_keys k ON k.id = m.agent_id WHERE m.group_id = ?'
    )
    .bind(group.id)
    .all<MemberRow>();
  return c.json({ ...group, members: members.results ?? [] });
});

routes.delete('/:id', async (c) => {
  const groupId = c.req.param('id');
  const result = await c.env.DB
    .prepare('DELETE FROM agent_groups WHERE id = ?')
    .bind(groupId)
    .run();
  if (!result.meta.changes || result.meta.changes === 0) {
    return c.text('not found', 404);
  }
  return c.json({ ok: true });
});

routes.post('/:id/members', async (c) => {
  const groupId = c.req.param('id');
  const group = await findGroup(c.env, groupId);
  if (!group) {
    return c.text('group not found', 404);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const agentId = typeof payload.agent_id === 'string' ? payload.agent_id : '';
  if (!agentId) {
    return c.text('agent_id is required', 400);
  }
  await c.env.DB
    .prepare('INSERT OR IGNORE INTO agent_group_members (group_id, agent_id) VALUES (?, ?)')
    .bind(group.id, agentId)
    .run();
  return c.json({ ok: true }, 201);
});

routes.delete('/:id/members/:agentId', async (c) => {
  const groupId = c.req.param('id');
  const agentId = c.req.param('agentId');
  const result = await c.env.DB
    .prepare('DELETE FROM agent_group_members WHERE group_id = ? AND agent_id = ?')
    .bind(groupId, agentId)
    .run();
  if (!result.meta.changes || result.meta.changes === 0) {
    return c.text('not found', 404);
  }
  return c.json({ ok: true });
});

routes.post('/:id/broadcast', async (c) => {
  const groupId = c.req.param('id');
  const group = await findGroup(c.env, groupId);
  if (!group) {
    return c.text('group not found', 404);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  const priority = typeof payload.priority === 'string' && VALID_PRIORITIES.includes(payload.priority as Priority)
    ? payload.priority
    : 'normal';
  const members = await c.env.DB
    .prepare('SELECT agent_id FROM agent_group_members WHERE group_id = ?')
    .bind(group.id)
    .all<{ agent_id: string }>();
  const agentIds = (members.results ?? []).map((m) => m.agent_id);
  const messages: { agent_id: string; message_id: string }[] = [];
  for (const agentId of agentIds) {
    const inserted = await c.env.DB
      .prepare(
        "INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority) VALUES (?, 'boss_to_agent', 'async', NULL, ?, 'sent', ?) RETURNING id"
      )
      .bind(agentId, body, priority)
      .first<{ id: string }>();
    if (inserted) {
      messages.push({ agent_id: agentId, message_id: inserted.id });
    }
  }
  return c.json({ messages, count: messages.length }, 201);
});

export const groupsRouter = routes;

async function findGroup(env: Env, idOrName: string): Promise<GroupRow | null> {
  const byId = await env.DB
    .prepare('SELECT * FROM agent_groups WHERE id = ?')
    .bind(idOrName)
    .first<GroupRow>();
  if (byId) return byId;
  return env.DB
    .prepare('SELECT * FROM agent_groups WHERE name = ?')
    .bind(idOrName)
    .first<GroupRow>();
}
