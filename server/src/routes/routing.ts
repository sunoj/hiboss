// CRUD endpoints for message routing rules.
// Exports routingRouter mounted at /api/routing-rules.
// Depends on Hono, auth middleware, and D1 bindings.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

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

const VALID_CHANNELS = ['discord', 'telegram', 'email'];

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.get('/', async (c) => {
  const agentId = getAgentId(c);
  const rows = await c.env.DB
    .prepare('SELECT * FROM routing_rules WHERE owner_id = ? ORDER BY priority DESC')
    .bind(agentId)
    .all<RoutingRuleRow>();
  return c.json({ rules: rows.results ?? [] });
});

routes.post('/', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const channel = typeof payload.channel === 'string' ? payload.channel : '';
  const pattern = typeof payload.pattern === 'string' ? payload.pattern : '';
  const targetAgentId = typeof payload.target_agent_id === 'string' ? payload.target_agent_id : '';
  const priority = typeof payload.priority === 'number' ? payload.priority : 0;
  if (!VALID_CHANNELS.includes(channel)) {
    return c.text('invalid channel', 400);
  }
  if (!pattern) {
    return c.text('pattern is required', 400);
  }
  if (!targetAgentId) {
    return c.text('target_agent_id is required', 400);
  }
  // Validate regex
  try {
    new RegExp(pattern);
  } catch {
    return c.text('invalid regex pattern', 400);
  }
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO routing_rules (owner_id, channel, pattern, target_agent_id, priority) VALUES (?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentId, channel, pattern, targetAgentId, priority)
    .first<RoutingRuleRow>();
  if (!inserted) {
    return c.text('failed to create', 500);
  }
  return c.json(inserted, 201);
});

routes.delete('/:id', async (c) => {
  const agentId = getAgentId(c);
  const ruleId = c.req.param('id');
  const result = await c.env.DB
    .prepare('DELETE FROM routing_rules WHERE id = ? AND owner_id = ?')
    .bind(ruleId, agentId)
    .run();
  if (!result.meta.changes || result.meta.changes === 0) {
    return c.text('not found', 404);
  }
  return c.json({ ok: true });
});

export const routingRouter = routes;
