// Sends boss-authenticated group broadcasts with authoritative API provenance.
// Exports a focused router mounted before the broader boss write API.
// Depends on boss access scope, audit logging, and message provenance builders.

import { Hono } from 'hono';
import type { Env, Priority } from '../types';
import {
  bossAuth, getBossId, getBossName, getBossRole, getBossTokenId,
} from '../middleware/auth';
import { bearerApiMetadata } from '../message-security';
import { logAudit } from '../audit';
import { getAccessibleAgentIds } from './boss-api';

const PRIORITIES: Priority[] = ['critical', 'high', 'normal', 'low'];
const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', bossAuth);

routes.post('/groups/:id/broadcast', async (c) => {
  const role = getBossRole(c);
  if (role === 'viewer') return c.text('viewer cannot write', 403);
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, role);
  const group = await c.env.DB.prepare(
    'SELECT id, owner_id FROM agent_groups WHERE id = ?',
  ).bind(c.req.param('id')).first<{ id: string; owner_id: string }>();
  if (!group || !agentIds.includes(group.owner_id)) return c.text('group not found', 404);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) return c.text('body is required', 400);
  const priority = parsePriority(payload.priority);
  const members = await c.env.DB.prepare(
    'SELECT agent_id FROM agent_group_members WHERE group_id = ?',
  ).bind(group.id).all<{ agent_id: string }>();
  const metadata = bearerApiMetadata(
    { id: bossId, name: getBossName(c) }, getBossTokenId(c),
  );
  const messages: { agent_id: string; message_id: string }[] = [];
  for (const member of members.results ?? []) {
    if (!agentIds.includes(member.agent_id)) continue;
    const id = await insertBroadcast(c.env, member.agent_id, body, priority, metadata);
    if (id) messages.push({ agent_id: member.agent_id, message_id: id });
  }
  c.executionCtx.waitUntil(logAudit(
    c.env, 'boss', bossId, 'group.broadcast', 'agent_group', group.id,
    JSON.stringify({ count: messages.length, priority }),
  ));
  return c.json({ messages, count: messages.length }, 201);
});

function parsePriority(value: unknown): Priority {
  return typeof value === 'string' && PRIORITIES.includes(value as Priority)
    ? value as Priority
    : 'normal';
}

async function insertBroadcast(
  env: Env,
  agentId: string,
  body: string,
  priority: Priority,
  metadata: Record<string, unknown>,
): Promise<string | null> {
  const row = await env.DB.prepare(
    "INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, 'boss_to_agent', 'async', 'api', ?, 'sent', ?, ?) RETURNING id",
  ).bind(agentId, body, priority, JSON.stringify(metadata)).first<{ id: string }>();
  return row?.id ?? null;
}

export const bossGroupBroadcastRouter = routes;
