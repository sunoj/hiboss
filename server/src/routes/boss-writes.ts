// Boss-scoped write and console read endpoints.
// Exports bossWritesRouter mounted at /api/boss before bossApiRouter.
// Depends on boss auth, access scoping, audit logging, and D1 tables.

import { Hono, type Context } from 'hono';
import type { Channel, Env, Priority } from '../types';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import { logAudit } from '../audit';
import { getAccessibleAgentIds } from './boss-api';
import { getBossOverview } from './boss-overview';

type BossContext = Context<{ Bindings: Env }>;
type JsonPrimitive = string | number | boolean | null;
type JsonObject = Record<string, unknown>;
type ChannelDisplay = Record<string, JsonPrimitive>;

interface GroupRow {
  id: string;
  name: string;
  description: string | null;
  owner_id: string;
  created_at: string;
}

interface RoutingRuleRow {
  id: string;
  owner_id: string;
  channel: string;
  pattern: string;
  target_agent_id: string;
  priority: number;
  enabled: number;
  created_at: string;
}

interface AgentConfigRow {
  default_priority: Priority;
  rate_limit: number | null;
  channel_routing: string | null;
}

const VALID_PRIORITIES: Priority[] = ['critical', 'high', 'normal', 'low'];
const VALID_CHANNELS: Channel[] = ['discord', 'telegram', 'email', 'api'];
const SECRET_CONFIG_KEYS = new Set(['bot_token', 'webhook_url', 'webhook_secret', 'secret', 'token', 'password', 'api_key']);

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

routes.post('/routing-rules', async (c) => {
  const scope = await requireWriteScope(c);
  if (!scope.ok) return scope.response;
  const payload = await c.req.json<JsonObject>();
  const ruleInput = parseRuleInput(payload);
  if (!ruleInput.ok) return c.text(ruleInput.error, 400);
  if (!scope.agentIds.includes(ruleInput.ownerId) || !scope.agentIds.includes(ruleInput.targetAgentId)) {
    return c.text('agent not accessible', 403);
  }
  const inserted = await c.env.DB.prepare('INSERT INTO routing_rules (owner_id, channel, pattern, target_agent_id, priority) VALUES (?, ?, ?, ?, ?) RETURNING *')
    .bind(ruleInput.ownerId, ruleInput.channel, ruleInput.pattern, ruleInput.targetAgentId, ruleInput.priority)
    .first<RoutingRuleRow>();
  if (!inserted) return c.text('failed to create', 500);
  audit(c, scope.bossId, 'rule.create', 'routing_rule', inserted.id, JSON.stringify(ruleInput));
  return c.json(inserted, 201);
});

routes.delete('/routing-rules/:id', async (c) => {
  const scope = await requireWriteScope(c);
  if (!scope.ok) return scope.response;
  const rule = await c.env.DB.prepare('SELECT owner_id FROM routing_rules WHERE id = ?').bind(c.req.param('id')).first<{ owner_id: string }>();
  if (!rule || !scope.agentIds.includes(rule.owner_id)) return c.text('not found', 404);
  await c.env.DB.prepare('DELETE FROM routing_rules WHERE id = ?').bind(c.req.param('id')).run();
  audit(c, scope.bossId, 'rule.delete', 'routing_rule', c.req.param('id'));
  return c.json({ ok: true });
});

routes.patch('/agents/:id/config', async (c) => {
  const scope = await requireWriteScope(c);
  if (!scope.ok) return scope.response;
  const agentId = c.req.param('id');
  if (!scope.agentIds.includes(agentId)) return c.text('agent not accessible', 403);
  const parsed = parseAgentConfig(await c.req.json<JsonObject>());
  if (!parsed.ok) return c.text(parsed.error, 400);
  await c.env.DB.prepare(`UPDATE api_keys SET ${parsed.updates.join(', ')} WHERE id = ?`).bind(...parsed.binds, agentId).run();
  const updated = await c.env.DB.prepare('SELECT default_priority, rate_limit, channel_routing FROM api_keys WHERE id = ?').bind(agentId).first<AgentConfigRow>();
  audit(c, scope.bossId, 'agent.config', 'api_key', agentId, JSON.stringify(parsed.keys));
  return c.json({ ...updated, channel_routing: updated?.channel_routing ? JSON.parse(updated.channel_routing) as JsonObject : null });
});

routes.get('/channels', async (c) => {
  const agentIds = await accessibleAgents(c);
  if (agentIds.length === 0) return c.json([]);
  const rows = await loadChannelRows(c.env, agentIds);
  return c.json(rows.map(mapChannelRow));
});

routes.get('/system', async (c) => {
  const agentIds = await accessibleAgents(c);
  const dbRow = await c.env.DB.prepare('SELECT 1 AS ok').first<{ ok: number }>();
  const overview = await getBossOverview(c.env, agentIds);
  return c.json({
    server_time: new Date().toISOString(),
    db_ok: dbRow?.ok === 1,
    channels: overview.channels,
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

function parseRuleInput(payload: JsonObject): { ok: true; ownerId: string; channel: Channel; pattern: string; targetAgentId: string; priority: number } | { ok: false; error: string } {
  const ownerId = typeof payload.owner_agent_id === 'string' ? payload.owner_agent_id : '';
  const channel = typeof payload.channel === 'string' ? payload.channel : '';
  const pattern = typeof payload.pattern === 'string' ? payload.pattern : '';
  const targetAgentId = typeof payload.target_agent_id === 'string' ? payload.target_agent_id : '';
  const priority = typeof payload.priority === 'number' ? payload.priority : 0;
  if (!ownerId) return { ok: false, error: 'owner_agent_id is required' };
  if (!VALID_CHANNELS.includes(channel as Channel)) return { ok: false, error: 'invalid channel' };
  if (!pattern) return { ok: false, error: 'pattern is required' };
  if (!targetAgentId) return { ok: false, error: 'target_agent_id is required' };
  try { new RegExp(pattern); } catch { return { ok: false, error: 'invalid regex pattern' }; }
  return { ok: true, ownerId, channel: channel as Channel, pattern, targetAgentId, priority };
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
  if ('channel_routing' in payload) {
    const parsed = parseChannelRouting(payload.channel_routing);
    if (!parsed.ok) return parsed;
    updates.push(parsed.sql); binds.push(parsed.value); keys.push('channel_routing');
  }
  if (updates.length === 0) return { ok: false, error: 'no valid fields to update' };
  return { ok: true, updates, binds, keys };
}

function parseChannelRouting(value: unknown): { ok: true; sql: string; value: string | null } | { ok: false; error: string } {
  if (value === null) return { ok: true, sql: 'channel_routing = ?', value: null };
  if (typeof value !== 'object' || Array.isArray(value)) return { ok: false, error: 'channel_routing must be an object or null' };
  for (const [, channel] of Object.entries(value as JsonObject)) {
    if (typeof channel !== 'string' || !VALID_CHANNELS.includes(channel as Channel)) return { ok: false, error: 'channel_routing values must be valid channels' };
  }
  return { ok: true, sql: 'channel_routing = ?', value: JSON.stringify(value) };
}

async function loadChannelRows(env: Env, agentIds: string[]) {
  const placeholders = agentIds.map(() => '?').join(', ');
  const rows = await env.DB.prepare(`SELECT cc.id, cc.agent_id, k.name AS agent_name, cc.channel, cc.config, cc.enabled, cc.created_at FROM channel_configs cc JOIN api_keys k ON k.id = cc.agent_id WHERE cc.agent_id IN (${placeholders}) ORDER BY k.name, cc.channel`)
    .bind(...agentIds)
    .all<{ id: string; agent_id: string; agent_name: string; channel: Channel; config: string; enabled: 0 | 1; created_at: string }>();
  return rows.results ?? [];
}

function mapChannelRow(row: { id: string; agent_id: string; agent_name: string; channel: Channel; config: string; enabled: 0 | 1; created_at: string }): ChannelDisplay {
  return { id: row.id, agent_id: row.agent_id, agent_name: row.agent_name, channel: row.channel, configured: row.enabled === 1, enabled: row.enabled, created_at: row.created_at, ...publicConfig(row.config) };
}

function publicConfig(raw: string): ChannelDisplay {
  const parsed = parseObject(raw);
  const display: ChannelDisplay = {};
  for (const [key, value] of Object.entries(parsed)) {
    if (SECRET_CONFIG_KEYS.has(key) || key.endsWith('_token') || key.endsWith('_secret')) continue;
    if (['string', 'number', 'boolean'].includes(typeof value) || value === null) display[key] = value as JsonPrimitive;
  }
  return display;
}

function parseObject(raw: string): JsonObject {
  try {
    const parsed = JSON.parse(raw) as unknown;
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as JsonObject : {};
  } catch {
    return {};
  }
}
