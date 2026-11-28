// Boss-scoped write and console read endpoints.
// Exports bossWritesRouter mounted at /api/boss before bossApiRouter.
// Depends on boss auth, access scoping, audit logging, and D1 tables.

import { Hono, type Context } from 'hono';
import type { Env, Priority } from '../types';
import { isIntegration } from '../integrations/credentials';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import { logAudit } from '../audit';
import { mintedKeySweep } from '../agent-keys/boss-access';
import { getAccessibleAgentIds } from './boss-api';
import { getBossOverview } from './boss-overview';

type BossContext = Context<{ Bindings: Env }>;
type JsonObject = Record<string, unknown>;

interface GroupRow {
  id: string;
  name: string;
  description: string | null;
  owner_id: string;
  created_at: string;
}

interface AgentConfigRow {
  default_priority: Priority;
  rate_limit: number | null;
}

const VALID_PRIORITIES: Priority[] = ['critical', 'high', 'normal', 'low'];

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', bossAuth);

routes.post('/groups', async (c) => {
  const scope = await requireWriteScope(c);
  if (!scope.ok) return scope.response;
  const payload = await c.req.json<JsonObject>();
  const ownerId = typeof payload.owner_agent_id === 'string' ? payload.owner_agent_id : '';
  if (!scope.agentIds.includes(ownerId)) return c.text('agent not accessible', 403);
  const name = typeof payload.name === 'string' ? payload.name.trim() : '';
  if (!name) return c.text('name is required', 400);
  const description = typeof payload.description === 'string' ? payload.description.trim() : null;
  const inserted = await c.env.DB
    .prepare('INSERT INTO agent_groups (name, description, owner_id) VALUES (?, ?, ?) RETURNING *')
    .bind(name, description, ownerId)
    .first<GroupRow>();
  if (!inserted) return c.text('failed to create', 500);
  audit(c, scope.bossId, 'group.create', 'agent_group', inserted.id, name);
  return c.json(inserted, 201);
});

routes.delete('/groups/:id', async (c) => {
  const scope = await requireWriteScope(c);
  if (!scope.ok) return scope.response;
  const group = await findAccessibleGroup(c.env, c.req.param('id'), scope.agentIds);
  if (!group) return c.text('not found', 404);
  await c.env.DB.prepare('DELETE FROM agent_groups WHERE id = ?').bind(group.id).run();
  audit(c, scope.bossId, 'group.delete', 'agent_group', group.id);
  return c.json({ ok: true });
});

routes.post('/groups/:id/members', async (c) => {
  const scope = await requireWriteScope(c);
  if (!scope.ok) return scope.response;
  const group = await findAccessibleGroup(c.env, c.req.param('id'), scope.agentIds);
  if (!group) return c.text('group not found', 404);
  const payload = await c.req.json<JsonObject>();
  const agentId = typeof payload.agent_id === 'string' ? payload.agent_id : '';
  if (!agentId) return c.text('agent_id is required', 400);
  if (!scope.agentIds.includes(agentId)) return c.text('agent not accessible', 403);
  if (await isIntegration(c.env, agentId)) return c.text('a webhook integration cannot join a group: it reads no messages', 400);
  await c.env.DB.prepare('INSERT OR IGNORE INTO agent_group_members (group_id, agent_id) VALUES (?, ?)').bind(group.id, agentId).run();
  audit(c, scope.bossId, 'group.add_member', 'agent_group', group.id, agentId);
  return c.json({ ok: true }, 201);
});

routes.delete('/groups/:id/members/:agentId', async (c) => {
  const scope = await requireWriteScope(c);
  if (!scope.ok) return scope.response;
  const group = await findAccessibleGroup(c.env, c.req.param('id'), scope.agentIds);
  const agentId = c.req.param('agentId');
  if (!group) return c.text('not found', 404);
  if (!scope.agentIds.includes(agentId)) return c.text('agent not accessible', 403);
  const result = await c.env.DB.prepare('DELETE FROM agent_group_members WHERE group_id = ? AND agent_id = ?').bind(group.id, agentId).run();
  if (!result.meta.changes) return c.text('not found', 404);
  audit(c, scope.bossId, 'group.remove_member', 'agent_group', group.id, agentId);
  return c.json({ ok: true });
});

routes.patch('/agents/:id/config', async (c) => {
  const scope = await requireWriteScope(c);
  if (!scope.ok) return scope.response;
  const agentId = c.req.param('id');
  if (!scope.agentIds.includes(agentId)) return c.text('agent not accessible', 403);
  const payload = await c.req.json<JsonObject>();
  if ('admin' in payload) {
    if (getBossRole(c) !== 'admin') return c.text('admin required', 403);
    if (typeof payload.admin !== 'boolean') return c.text('admin must be a boolean', 400);
    if (Object.keys(payload).length !== 1) return c.text('admin must be updated separately', 400);
    await c.env.DB.batch([
      c.env.DB.prepare('UPDATE api_keys SET is_admin = ? WHERE id = ?').bind(Number(payload.admin), agentId),
      ...mintedKeySweep(c.env.DB),
    ]);
    audit(c, scope.bossId, 'agent.admin', 'api_key', agentId, JSON.stringify({ admin: payload.admin }));
    return c.json({ admin: payload.admin });
  }
  const parsed = parseAgentConfig(payload);
  if (!parsed.ok) return c.text(parsed.error, 400);
  await c.env.DB.prepare(`UPDATE api_keys SET ${parsed.updates.join(', ')} WHERE id = ?`).bind(...parsed.binds, agentId).run();
  const updated = await c.env.DB.prepare('SELECT default_priority, rate_limit FROM api_keys WHERE id = ?').bind(agentId).first<AgentConfigRow>();
  audit(c, scope.bossId, 'agent.config', 'api_key', agentId, JSON.stringify(parsed.keys));
  return c.json(updated);
});

routes.get('/system', async (c) => {
  const agentIds = await accessibleAgents(c);
  const dbRow = await c.env.DB.prepare('SELECT 1 AS ok').first<{ ok: number }>();
  const overview = await getBossOverview(c.env, agentIds);
  return c.json({
    server_time: new Date().toISOString(),
    db_ok: dbRow?.ok === 1,
    active_sessions: overview.kpis.activeSessions,
    pending_decisions: overview.kpis.pendingDecisions,
  });
});

export const bossWritesRouter = routes;

async function accessibleAgents(c: BossContext): Promise<string[]> {
  return getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c));
}

async function requireWriteScope(c: BossContext): Promise<{ ok: true; bossId: string; agentIds: string[] } | { ok: false; response: Response }> {
  const role = getBossRole(c);
  if (role === 'viewer') return { ok: false, response: c.text('viewer cannot write', 403) };
  const bossId = getBossId(c);
  return { ok: true, bossId, agentIds: await getAccessibleAgentIds(c.env, bossId, role) };
}

function audit(c: BossContext, bossId: string, action: string, resourceType: string, resourceId: string, details?: string): void {
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, action, resourceType, resourceId, details));
}

async function findAccessibleGroup(env: Env, groupId: string, agentIds: string[]): Promise<GroupRow | null> {
  if (agentIds.length === 0) return null;
  const row = await env.DB.prepare('SELECT * FROM agent_groups WHERE id = ?').bind(groupId).first<GroupRow>();
  if (!row || !agentIds.includes(row.owner_id)) return null;
  return row;
}

function parsePriority(value: unknown, fallback: Priority): Priority {
  return typeof value === 'string' && VALID_PRIORITIES.includes(value as Priority) ? value as Priority : fallback;
}

function parseAgentConfig(payload: JsonObject): { ok: true; updates: string[]; binds: (string | number | null)[]; keys: string[] } | { ok: false; error: string } {
  const updates: string[] = [];
  const binds: (string | number | null)[] = [];
  const keys: string[] = [];
  if ('default_priority' in payload) {
    const value = payload.default_priority;
    if (typeof value !== 'string' || !VALID_PRIORITIES.includes(value as Priority)) return { ok: false, error: 'invalid default_priority' };
    updates.push('default_priority = ?'); binds.push(value); keys.push('default_priority');
  }
  if ('rate_limit' in payload) {
    const value = payload.rate_limit;
    if (value !== null && (typeof value !== 'number' || value < 0 || !Number.isInteger(value))) return { ok: false, error: 'rate_limit must be a positive integer or null' };
    updates.push('rate_limit = ?'); binds.push(value as number | null); keys.push('rate_limit');
  }
  if (updates.length === 0) return { ok: false, error: 'no valid fields to update' };
  return { ok: true, updates, binds, keys };
}
